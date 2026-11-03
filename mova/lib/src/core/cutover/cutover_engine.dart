import 'dart:collection';
import '../playback_commands.dart';
import '../kernel/restart_observer.dart';
import 'dart:async';

import '../api.dart';
import '../bus/bus.dart';
import '../events/events.dart';
import '../feed/engine_pool.dart' show MovaEngineFactory;
import '../kernel/player_mute.dart';
import '../model/fit.dart';
import '../model/orientation.dart';
import '../model/quality.dart';
import '../model/source.dart';
import '../options/options.dart';
import '../preview/api.dart';
import '../report/report.dart';
import '../keep_alive/keep_alive.dart';
import '../state/progress.dart';
import '../platform/brightness_lease.dart';
import '../state/state.dart';
import '../state/ui_state.dart';
import '../stt/api.dart';
import 'ctl.dart';
import 'acceptance.dart';
import 'plan.dart';
import 'retirable.dart';
import 'trigger.dart';
import 'warm.dart';

/// Chooses a safe fallback when player mute is unavailable or cannot restore.
///
/// 播放器静音不可用或无法还原时，选择安全降级。
class _WarmMuteFailurePolicy {
  /// Creates the default policy.
  ///
  /// 创建默认策略。
  const _WarmMuteFailurePolicy();

  /// Allows audible warming, but rejects a hand-off that would remain muted.
  ///
  /// 允许有声预热，但拒绝仍被预热静音的引擎接管。
  bool giveUp({required bool releasing}) => releasing;
}

/// 一次预热的状态与资源；机械收拢后仍沿用原有生命周期。
class _WarmSlot {
  /// 创建空的预热槽。
  _WarmSlot();

  /// 本槽是否已达到就绪判据。
  bool ready = false;
  MovaWarmTicket? ticket;
  MovaSourceChange? lastSource;
  MovaReady? lastReady;
  MovaFirstFrame? lastFirstFrame;

  /// 包内调用方指定的起播意图，用户新命令到达后失效。
  bool? play;

  /// 指定意图时的用户命令代际。
  int playCommand = 0;

  /// 宿主是否拒绝本槽的打开请求；槽释放后仍供原调用者读取。
  bool rejected = false;

  /// 后台预热的引擎。
  MovaApi? engine;

  /// 本槽对应的源。
  MovaSource? source;

  /// 预热目标位置。
  Duration at = Duration.zero;

  /// 本次预热计划。
  MovaWarmPlan plan = const MovaWarmPlan();

  /// 本次就绪判据。
  MovaWarmPolicy? policy;

  /// 本次预热耗时。
  Stopwatch? clock;

  /// 在途的目标帧暂停操作。
  Future<void>? holding;

  /// 是否已执行目标帧暂停。
  bool heldAtTarget = false;

  /// 是否为直播源。
  bool live = false;

  /// 影子的缓冲状态。
  bool buffering = false;

  /// 等待就绪的调用者。
  Completer<bool>? readyCompleter;

  /// 独立就绪期限计时器。
  Timer? readyTimer;

  /// 影子状态订阅。
  StreamSubscription<MovaState>? stateSub;

  /// 影子进度订阅。
  StreamSubscription<MovaProg>? progressSub;

  /// 影子错误订阅。
  StreamSubscription<MovaEvent>? eventSub;

  /// 成功获取预热静音的影子。
  MovaApi? muteOwner;
}

/// A [MovaApi] that owns a live engine plus, briefly, a warming shadow one,
/// and presents a single stable surface in front of both.
///
/// The UI holds *this* object, never the engines behind it: its streams,
/// state snapshot and render handle stay addressable across a cutover, so
/// components that subscribe once in `initState` keep working and
/// `MovaPlayer`'s `ValueKey(api)` never remounts the tree mid-cutover.
///
/// With [MovaCutoverConfig.enabled] false this is a pure pass-through: no shadow
/// engine is ever created and every method forwards verbatim to the single
/// engine the factory produced.
///
/// 一个持有生效引擎、并在短暂窗口内同时持有预热中影子引擎的 [MovaApi]，
/// 在两者之前呈现唯一一份稳定的对外面。
///
/// UI 持有的是*本对象*，而非它背后的引擎：它的流、状态快照与渲染句柄在切换
/// 前后始终可寻址，因此在 `initState` 里订阅一次的组件继续有效，
/// `MovaPlayer` 的 `ValueKey(api)` 也不会在切换途中重挂整棵树。
///
/// [MovaCutoverConfig.enabled] 为 false 时它是纯直通代理：永不创建影子引擎，
/// 每个方法都原样转发给工厂产出的那唯一一个引擎。
/// 换指按旧引擎的 playbackIntent 决定是否开播；自写引擎须维护该字段。
/// 意图恒为假时，影子换指后保持暂停。
class MovaCutoverEngine
    implements
        MovaRestartObserver,
        MovaApi,
        MovaProgressSource,
        MovaCutover,
        MovaKeepAlive,
        MovaWarmOwner {
  /// Creates a cutover engine over [engineFactory].
  ///
  /// 基于 [engineFactory] 创建一个切换引擎。
  ///
  /// - [engineFactory]: creates each underlying engine; hosts pass
  ///   `createMovaEngine` / 创建每个底层引擎；宿主传 `createMovaEngine`
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = MovaCutoverEngine(engineFactory: createMovaEngine);
  /// runApp(MovaPlayer(api: api));
  /// ```
  MovaCutoverEngine({required this._engineFactory}) {
    _active = _engineFactory();
    _state = MovaBus<MovaState>(_active.state.copyWith(renderEpoch: _epoch));
    _uiState = MovaBus<MovaUiState>(_active.uiState);
    _attach(_active);
  }

  /// Creates each underlying engine.
  ///
  /// 创建每个底层引擎。
  final MovaEngineFactory _engineFactory;

  /// 封面要求的精确首帧意图，在换指及预热时继续传递。
  bool _observeRestartRequested = false;

  /// 启用当前及影子引擎的精确首帧能力，无返回值。
  /// 示例：`engine.observeRestarts()`。
  @override
  void observeRestarts() {
    _observeRestartRequested = true;
    _requestRestarts(_active);
    final shadow = _slot.engine;
    if (shadow != null) _requestRestarts(shadow);
  }

  /// 将封面观察意图传给支持能力的 [engine]。
  void _requestRestarts(MovaApi engine) {
    if (_observeRestartRequested && engine is MovaRestartObserver) {
      (engine as MovaRestartObserver).observeRestarts();
    }
  }

  /// 当前驱动渲染面的引擎。
  MovaApi get active => _active;

  /// 当前生效的底层引擎。
  late MovaApi _active;

  /// 当前预热的全部状态与资源。
  _WarmSlot _slot = _WarmSlot();

  /// 打开、重载、一次性切换和销毁共用的操作代际。
  int _op = 0;

  /// 跨过期提交保留用户意图，内部暂停不能污染后继事务。
  bool? _intentSnapshot;

  /// 已认领提交的串行尾闩；完成后后继才可重新校验并认领槽。
  Future<void> _commitTail = Future<void>.value();

  late final MovaBus<MovaState> _state;
  late final MovaBus<MovaUiState> _uiState;
  final StreamController<MovaProg> _progress =
      StreamController<MovaProg>.broadcast();
  final StreamController<MovaEvent> _events =
      StreamController<MovaEvent>.broadcast(sync: true);

  /// 状态与事件同一次投递携带相同纪元；重入通知排在本次通知之后。
  final Queue<({MovaState state, MovaEvent? event, int epoch, int op})> _deliveries =
      Queue();
  bool _delivering = false;
  ({MovaApi engine, bool playing})? _handoff;

  void _publish({MovaState? snapshot, MovaEvent? event}) {
    if (_events.isClosed) return;
    var next = snapshot ?? _active.state;
    // 原引擎的 state 流与 event 流可有不同的微任务深度，事件载荷才是本次变化的值。
    next = switch (event) {
      MovaBufferChange e => next.copyWith(buffering: e.buffering),
      MovaDurationChange e => next.copyWith(duration: e.duration),
      MovaSizeChange e => next.copyWith(width: e.width, height: e.height),
      MovaVolumeChange e => next.copyWith(volume: e.value),
      MovaBrightChange e => next.copyWith(brightness: e.value),
      MovaRateChange e => next.copyWith(rate: e.value),
      MovaQualityListChange e => next.copyWith(qualities: e.qualities),
      MovaQualityChange e => next.copyWith(currentQuality: e.quality),
      MovaFitChange e => next.copyWith(fit: e.fit),
      MovaZoomChange e => next.copyWith(zoom: e.zoom),
      MovaLockChange e => next.copyWith(locked: e.value),
      MovaFullScreenChange e => next.copyWith(fullscreen: e.value),
      MovaOrientationChange e => next.copyWith(orientation: e.orientation),
      MovaPipChange e => next.copyWith(pip: e.value),
      MovaMiniChange e => next.copyWith(mini: e.mini),
      MovaTimeShiftChange e => next.copyWith(timeshiftBehind: e.behind),
      MovaPlay() => next.copyWith(playing: true),
      MovaPause() => next.copyWith(playing: false),
      MovaFirstFrame() => next.copyWith(rendered: true),
      _ => next,
    };
    final handoff = _handoff;
    if (handoff != null && identical(_active, handoff.engine)) {
      next = next.copyWith(playing: handoff.playing);
    }
    _deliveries.add((
      state: next.copyWith(renderEpoch: _epoch),
      event: event,
      epoch: _epoch,
      op: _op,
    ));
    if (_delivering) return;
    _delivering = true;
    try {
      while (_deliveries.isNotEmpty) {
        final delivery = _deliveries.removeFirst();
        if (delivery.epoch != _epoch || delivery.op != _op) continue;
        _state.emit(delivery.state);
        if (delivery.epoch != _epoch || delivery.op != _op) continue;
        if (delivery.event != null) _events.add(delivery.event!);
      }
    } finally {
      _delivering = false;
    }
  }

  final StreamController<MovaCutoverPhase> _cutoverPhases =
      StreamController<MovaCutoverPhase>.broadcast();

  StreamSubscription<MovaState>? _activeStateSub;
  StreamSubscription<MovaProg>? _activeProgressSub;
  StreamSubscription<MovaEvent>? _activeEventSub;
  StreamSubscription<MovaUiState>? _activeUiSub;

  /// Render-epoch counter merged into every forwarded state; bumped once per
  /// committed cutover so the render surface always re-reads [renderHandle].
  ///
  /// 合并进每次转发状态的渲染纪元计数器；每次提交切换后加一，使渲染面每次都
  /// 重新读取 [renderHandle]。
  int _epoch = 0;

  MovaCutoverPhase _phase = MovaCutoverPhase.idle;
  bool _disposed = false;

  /// Cancels [_slot.readyTimer] if it is armed.
  ///
  /// 若 [_slot.readyTimer] 已武装则取消它。
  void _cancelReadyTimer([_WarmSlot? owned]) {
    final slot = owned ?? _slot;
    slot.readyTimer?.cancel();
    slot.readyTimer = null;
  }

  /// Pauses the shadow and rewinds it to the warm-up target so the cutover starts
  /// exactly there.
  ///
  /// The rewind also runs for a zero target. By the time a policy reports
  /// ready the shadow has been decoding for a while and has drifted past frame
  /// zero (measured on device: ~300ms for an ad), so skipping the rewind here
  /// would deliver exactly the headless ad [MovaWarmPlan.pauseWhenReady]
  /// exists to prevent. This is not the `seek(0)` that [_startWarm]
  /// deliberately avoids: that one fires before the first frame lands, this
  /// one only after the readiness policy has seen buffered, playing frames.
  ///
  /// 暂停影子引擎并回绕到预热目标点，使切换恰好从该处开始。
  ///
  /// 目标为零时同样回绕。判据报告就绪时影子已经解码了一会儿、早漂过第 0 帧
  /// （真机实测广告约 300ms），此时省掉回绕，交付出去的正是
  /// [MovaWarmPlan.pauseWhenReady] 要防的那条缺头广告。这与 [_startWarm] 刻意
  /// 回避的那次 `seek(0)` 不是一回事：那次发生在首帧落地之前，这次发生在就绪
  /// 判据已经看到缓冲充足、正常播放的帧之后。
  Future<void> _holdAtTarget(_WarmSlot slot) async {
    final shadow = slot.engine!;
    try {
      await shadow.pause();
      if (_disposed || !identical(slot.engine, shadow)) return;
      if (!slot.live) await shadow.seek(slot.at);
    } catch (_) {
      // 保持目标帧是尽力操作，立即观察异常，不能阻断提交或资源释放。
    }
  }

  /// The cutover configuration in effect, taken from the active engine's options.
  ///
  /// 生效中的切换配置，取自当前生效引擎的选项。
  MovaCutoverConfig get _config => _active.options.cutover;

  /// Subscribes to [engine]'s streams and forwards them onto this proxy's own
  /// streams, merging the current [_epoch] into every forwarded state.
  ///
  /// 订阅 [engine] 的流并转发到本代理自己的流上，把当前 [_epoch] 合并进每个
  /// 转发出的状态。
  void _attach(MovaApi engine) {
    _lastProgress = engine is MovaProgressSource
        ? (engine as MovaProgressSource).progressValue
        : const MovaProg();
    _progress.add(_lastProgress);
    final attachedEpoch = _epoch;
    bool current() =>
        !_disposed && identical(engine, _active) && attachedEpoch == _epoch;
    _publish(snapshot: engine.state);
    _activeStateSub = engine.states.listen((s) {
      if (current()) _publish(snapshot: s);
    });
    _activeProgressSub = engine.progress.listen((p) {
      _lastProgress = p;
      _progress.add(p);
    });
    _activeEventSub = engine.events.listen((event) {
      if (!current()) return;
      if (event is MovaPause && identical(_handoff?.engine, engine)) return;
      _publish(snapshot: engine.state, event: event);
    });
    _activeUiSub = engine.uiStates.listen(_uiState.emit);
  }

  /// Cancels the forwarding subscriptions set up by [_attach].
  ///
  /// 取消 [_attach] 建立的转发订阅。
  Future<void> _detach() async {
    final subscriptions = [
      _activeStateSub,
      _activeProgressSub,
      _activeEventSub,
      _activeUiSub,
    ];
    _activeStateSub = null;
    _activeProgressSub = null;
    _activeEventSub = null;
    _activeUiSub = null;
    await Future.wait(
      subscriptions.whereType<StreamSubscription<dynamic>>().map(
        (s) => s.cancel(),
      ),
    );
  }

  /// Cancels the shadow-observing subscriptions set up in [_startWarm].
  /// Shared by [dispose], [_commitNow] and [abandon] — every path that ends
  /// a warm-up must tear these down the same way, or a stale subscription
  /// keeps firing against a shadow that path is about to drop or dispose.
  ///
  /// 取消 [_startWarm] 里建立的影子观测订阅。供 [dispose]、[_commitNow]、
  /// [abandon] 共用——每条结束预热的路径都必须以同样的方式拆掉它们，否则一个
  /// 陈旧订阅会继续对着即将被丢弃或释放的影子触发。
  Future<void> _detachShadow(_WarmSlot slot) async {
    final subscriptions = [slot.stateSub, slot.progressSub, slot.eventSub];
    slot.stateSub = null;
    slot.progressSub = null;
    slot.eventSub = null;
    await Future.wait(
      subscriptions.whereType<StreamSubscription<dynamic>>().map(
        (s) => s.cancel(),
      ),
    );
  }

  @override
  Stream<MovaEvent> get events => _events.stream;

  @override
  Stream<MovaState> get states => _state.stream;

  @override
  Stream<MovaProg> get progress => _replayedProgress;

  /// 保持流身份稳定，并在每次订阅时播种最新快照。
  late final Stream<MovaProg> _replayedProgress = Stream<MovaProg>.multi((
    controller,
  ) {
    controller.add(progressValue);
    final sub = _progress.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  }, isBroadcast: true);

  /// 不支持同步快照的宿主引擎使用最近一次转发的进度。
  MovaProg _lastProgress = const MovaProg();

  /// 返回当前生效引擎的快照，换指后立即跟随新引擎。
  @override
  MovaProg get progressValue => _active is MovaProgressSource
      ? (_active as MovaProgressSource).progressValue
      : _lastProgress;

  @override
  Stream<MovaUiState> get uiStates => _uiState.stream;

  @override
  MovaState get state => _state.value;

  @override
  MovaUiState get uiState => _uiState.value;

  @override
  MovaOpts get options => _active.options;

  @override
  Object? get renderHandle => _active.renderHandle;

  @override
  bool get pipSupported => _active.pipSupported;

  @override
  MovaPreviewApi get preview => _active.preview;

  @override
  MovaSttApi get stt => _active.stt;

  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) {
    if (_disposed) return Future<bool>.value(false);
    _intentSnapshot = null;
    _op++;
    unawaited(_abandonWarm(reason: MovaCutoverEndReason.superseded));
    return _active.open(source, autoPlay: autoPlay);
  }

  /// 播放命令清除内部暂停快照，并转发给当前引擎。
  @override
  Future<void> play() {
    if (_disposed) return Future<void>.value();
    _intentSnapshot = null;
    movaRecordPlaybackCommand(this);
    return _active.play();
  }

  /// 暂停命令清除事务快照，后继切换必须尊重暂停。
  @override
  Future<void> pause() {
    if (_disposed) return Future<void>.value();
    _intentSnapshot = null;
    movaRecordPlaybackCommand(this);
    return _active.pause();
  }

  /// The host's latest keepAlive wish, re-applied to whichever engine becomes
  /// active.
  ///
  /// 宿主最近一次的待机意愿，会重新施加到成为生效引擎的那一个上。
  bool _keepAliveWanted = false;

  @override
  Future<MovaKeepAlivePhase> setKeepAlive(bool on) async {
    // Disposed: no-op, and the wish is no longer recorded.
    //
    // 已销毁：空操作，也不再记录意愿。
    if (_disposed) return MovaKeepAlivePhase.off;
    _keepAliveWanted = on;
    final a = _active;
    if (a is MovaKeepAlive) {
      return (a as MovaKeepAlive).setKeepAlive(on);
    }
    // An engine without the capability can only pause and play.
    //
    // 不具备该能力的引擎只能暂停/播放。
    if (on) {
      await a.pause();
    } else {
      await a.play();
    }
    return MovaKeepAlivePhase.off;
  }

  /// 切换播放意图时清除事务快照。
  @override
  Future<void> playOrPause() {
    if (_disposed) return Future<void>.value();
    _intentSnapshot = null;
    movaRecordPlaybackCommand(this);
    return _active.playOrPause();
  }

  @override
  Future<void> seek(Duration to) =>
      _disposed ? Future<void>.value() : _active.seek(to);

  @override
  Future<void> seekBy(Duration delta) =>
      _disposed ? Future<void>.value() : _active.seekBy(delta);

  @override
  Future<void> setVolume(double v) =>
      _disposed ? Future<void>.value() : _active.setVolume(v);

  @override
  Future<void> setBrightness(double v) =>
      _disposed ? Future<void>.value() : _active.setBrightness(v);

  @override
  Future<void> setRate(double r) =>
      _disposed ? Future<void>.value() : _active.setRate(r);

  @override
  Future<void> setFit(MovaFit f) =>
      _disposed ? Future<void>.value() : _active.setFit(f);

  @override
  Future<void> setZoom(double z) =>
      _disposed ? Future<void>.value() : _active.setZoom(z);

  @override
  Future<void> setLocked(bool v) =>
      _disposed ? Future<void>.value() : _active.setLocked(v);

  @override
  Future<void> setFullscreen(bool v) =>
      _disposed ? Future<void>.value() : _active.setFullscreen(v);

  @override
  Future<void> setMini(bool v) =>
      _disposed ? Future<void>.value() : _active.setMini(v);

  @override
  Future<void> setOrientation(MovaOrientation o) =>
      _disposed ? Future<void>.value() : _active.setOrientation(o);

  @override
  Future<void> loadQualities() =>
      _disposed ? Future<void>.value() : _active.loadQualities();

  @override
  Future<void> switchQuality(MovaQuality q) =>
      _disposed ? Future<void>.value() : _active.switchQuality(q);

  @override
  Future<bool> enterPip() =>
      _disposed ? Future<bool>.value(false) : _active.enterPip();

  @override
  Future<void> reload() {
    if (_disposed) return Future<void>.value();
    _intentSnapshot = null;
    _op++;
    unawaited(_abandonWarm(reason: MovaCutoverEndReason.superseded));
    return _active.reload();
  }

  @override
  Future<void> backToLiveEdge() =>
      _disposed ? Future<void>.value() : _active.backToLiveEdge();

  @override
  void showControls({bool sticky = false}) {
    if (!_disposed) _active.showControls(sticky: sticky);
  }

  @override
  void hideControls() {
    if (!_disposed) _active.hideControls();
  }

  @override
  void showHud(MovaHud hud, {String? text}) {
    if (!_disposed) _active.showHud(hud, text: text);
  }

  @override
  void setDragging(bool v, {Duration? previewAt}) {
    if (!_disposed) _active.setDragging(v, previewAt: previewAt);
  }

  @override
  void report(MovaReportName name, {Map<String, dynamic>? params}) {
    if (!_disposed) _active.report(name, params: params);
  }

  @override
  Future<void> dispose() async {
    // 幂等：重复 dispose 直接返回。
    if (_disposed) return;
    _disposed = true;
    _intentSnapshot = null;
    _op++;
    final cleanup = _abandonWarm(reason: MovaCutoverEndReason.disposed);
    try {
      // 同时观察两个清理任务，避免一个挂起时另一个先报出未观察异常。
      await Future.wait([_detach(), cleanup]);
    } finally {
      try {
        await _active.dispose();
      } finally {
        await Future.wait([
          _state.close(),
          _uiState.close(),
          _progress.close(),
          _events.close(),
          _cutoverPhases.close(),
        ]);
      }
    }
  }

  @override
  bool get cutoverEnabled => _config.enabled;

  @override
  MovaCutoverPhase get cutoverPhase => _phase;

  @override
  Stream<MovaCutoverPhase> get cutoverPhases => _cutoverPhases.stream;

  @override
  Future<void> prepare(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
  }) async {
    await prepareAccepted(source, at: at, cue: cue, plan: plan);
  }

  /// 包内调用方可区分预热失败与宿主拒绝。
  @override
  Future<bool> prepareAccepted(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
  }) async {
    final slot = await _startWarm(source, at: at, cue: cue, plan: plan);
    return slot?.rejected != true;
  }

  /// 按 [source]、位置 [at]、提示 [cue] 与 [plan] 预热，返回只认本槽的凭据。
  /// [play] 可指定起播意图，后续用户命令优先；未触发时返回 null。
  /// 示例：`final ticket = await engine.prepareOwned(source);`。
  @override
  Future<MovaWarmTicket?> prepareOwned(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
    bool? play,
  }) async {
    final op = _op;
    final command = movaPlaybackCommand(this);
    final slot = await _startWarm(source, at: at, cue: cue, plan: plan);
    // 即使 prepare 尚未返回槽，旧操作也必须能报告 superseded，禁止硬切抢回宿主源。
    if (_disposed || op != _op) return MovaWarmTicket(null, op);
    if (slot == null) return null;
    if (play != null) {
      slot.play = play;
      slot.playCommand = command;
    }
    if (slot.ticket?.operation != op) {
      slot.ticket = MovaWarmTicket(slot, op, rejected: slot.rejected);
    }
    return slot.ticket;
  }

  /// 只提交 [ticket] 的槽，[waitForReady] 控制等待；返回已提交、未就绪或被取代。
  /// 示例：`await engine.commitOwned(ticket, waitForReady: true);`。
  @override
  Future<MovaWarmCommit> commitOwned(
    MovaWarmTicket ticket, {
    bool waitForReady = false,
  }) async {
    if (_disposed || ticket.operation != _op) return MovaWarmCommit.superseded;
    final slot = ticket.slot;
    if (slot is! _WarmSlot) return MovaWarmCommit.notReady;
    final ok = await _commitSlot(
      slot,
      ticket.operation,
      waitForReady: waitForReady,
    );
    if (_disposed || ticket.operation != _op) return MovaWarmCommit.superseded;
    if (ok) return MovaWarmCommit.committed;
    return _disposed || ticket.operation != _op
        ? MovaWarmCommit.superseded
        : MovaWarmCommit.notReady;
  }

  /// Shared shadow-creation path for [prepare] and [cutoverTo]; [plan] is
  /// injected so [cutoverTo] can force eager warming regardless of the
  /// configured trigger, and so an ad warm-up can hold at frame zero.
  ///
  /// [prepare]、[cutoverTo] 共用的影子创建路径；[plan] 由调用方注入，使
  /// [cutoverTo] 能无视已配置的触发策略、强制立即预热，也使广告方向的预热能停在
  /// 第 0 帧。
  Future<_WarmSlot?> _startWarm(
    MovaSource source, {
    required Duration at,
    required MovaWarmCue cue,
    required MovaWarmPlan plan,
  }) async {
    // A disposed proxy must not build a shadow engine nobody would release.
    //
    // 已销毁的代理不能再造一个没人释放的影子引擎。
    if (_disposed || !cutoverEnabled) return null;
    final op = _op;
    final trigger = plan.trigger ?? _config.effectiveTrigger;
    if (!trigger.shouldWarm(cue)) return null;
    if (_slot.engine != null) {
      // A shadow for the same source is already warming; a different source
      // means the old shadow is stale and must go before the new one starts.
      //
      // 同一源的影子已在预热则沿用；源不同说明旧影子已过期，须先放弃再新建。
      if (_slot.source?.sameAs(source) ?? false) return _slot;
      await _abandonWarm(reason: MovaCutoverEndReason.superseded);
      if (_disposed || op != _op || _slot.engine != null) return null;
    }

    final slot = _WarmSlot();
    _slot = slot;
    final shadow = _engineFactory();
    _requestRestarts(shadow);
    // 影子引擎要在挂界面之前就解码出画面，读一次 renderHandle 让懒创建的视频管线
    // 提前建好（否则预热期间 vid=no，切换时仍要黑屏等首帧）。
    shadow.renderHandle;
    slot.engine = shadow;
    slot.source = source;
    slot.at = at;
    slot.plan = plan;
    slot.heldAtTarget = false;
    slot.live = source.type == MovaStreamType.live;
    // An injected policy is the *same instance* on every warm-up, so it must
    // be reset before use — otherwise the second warm-up inherits the first
    // one's consecutive-tick counter and a single lucky tick commits a cutover.
    //
    // 注入的判据在每次预热时都是*同一个实例*，因此使用前必须重置——否则第二次
    // 预热会继承第一次的连续 tick 计数，一次侥幸的 tick 就能把切换提交出去。
    slot.policy = (plan.policy ?? _config.newReadyPolicy())..reset();
    slot.clock = Stopwatch()..start();
    _cancelReadyTimer(slot);
    final policy = slot.policy;
    final timeout = policy is MovaBufferWarm
        ? policy.timeout
        : _config.readyTimeout;
    slot.readyTimer = Timer(timeout, () {
      if (_disposed || !identical(_slot, slot)) return;
      slot.readyTimer = null;
      final c = slot.readyCompleter;
      slot.readyCompleter = null;
      unawaited(_abandonWarm(reason: MovaCutoverEndReason.timeout));
      c?.complete(false);
    });

    slot.eventSub = shadow.events.listen((event) {
      // 提交认领后槽已让出，但直到断开影子订阅前仍须记录生命周期。
      if (!identical(slot.engine, shadow) || _disposed) return;
      if (event is MovaSourceChange) slot.lastSource = event;
      if (event is MovaReady) slot.lastReady = event;
      if (event is MovaFirstFrame) slot.lastFirstFrame = event;
      if (event is MovaErrorEvent && event.fatal) _onShadowError(slot);
    });
    _setPhase(MovaCutoverPhase.warming);
    if (_disposed || op != _op || !identical(_slot, slot)) return null;

    // Unsupported kernels warm audibly rather than changing system volume.
    //
    // 不支持的内核允许预热出声，避免改动系统音量。
    if (_config.muteWhileWarm && shadow is MovaPlayerMute) {
      await _setWarmMute(slot, true);
      if (_disposed || !identical(_slot, slot)) return null;
    }
    try {
      final accepted = await shadow.open(source, autoPlay: true);
      // The ready timer may have abandoned (and disposed) this shadow while
      // open() was pending; the owner already cleaned up, so just bail out.
      //
      // open() 挂起期间就绪计时器可能已放弃（并销毁）该影子；善后已由处理方完成，
      // 直接退出。
      if (_disposed || !identical(_slot, slot)) return null;
      if (!accepted) {
        slot.rejected = true;
        await _abandonWarm(reason: MovaCutoverEndReason.notReady);
        return slot;
      }
      // Seeking to zero right after open() buys nothing and is pure risk: a seek
      // issued before the first frame lands has been observed to wedge the
      // player on device. The pre-roll→content and content→ad directions both
      // warm at zero, so this guard covers the common case.
      //
      // 刚 open() 完就 seek(0) 毫无收益、纯属风险敞口：首帧落地前下发的 seek 在
      // 真机上被观测到会把播放器卡死。前贴片→正片与正片→广告两个方向都在 0 处
      // 预热，因此这道守卫覆盖的正是常见情形。
      if (!slot.live && at > Duration.zero) await shadow.seek(at);
    } catch (_) {
      // Recoverable and handled internally: clean the shadow up and let the
      // caller fall back to a normal open. No MovaErrorEvent on the main stream
      // — a background warm-up failure must not be mistaken for a failure of
      // the healthy engine that is on screen (e.g. an ad being played).
      //
      // 可恢复且内部处理：清理影子，由调用方回落为普通打开。不往主事件流发
      // MovaErrorEvent——后台预热失败不能被误判成在屏健康引擎（如在播广告）的失败。
      if (_disposed || !identical(_slot, slot)) return null;
      await _abandonWarm(reason: MovaCutoverEndReason.shadowError);
      return null;
    }

    if (_disposed || !identical(_slot, slot)) return null;

    slot.buffering = false;
    slot.stateSub = shadow.states.listen((s) => slot.buffering = s.buffering);
    slot.progressSub = shadow.progress.listen(
      (p) => _evaluate(slot, p.position, p.buffer),
    );
    return slot;
  }

  /// Ends the warm-up the same way a [MovaWarmVerdict.giveUp] does when the
  /// shadow engine itself reports a playback error.
  ///
  /// 影子引擎自身报告播放错误时，以与 [MovaWarmVerdict.giveUp] 完全相同的方式
  /// 结束本次预热。
  void _onShadowError(_WarmSlot slot) {
    if (_disposed || !identical(_slot, slot)) return;
    final c = slot.readyCompleter;
    slot.readyCompleter = null;
    unawaited(_abandonWarm(reason: MovaCutoverEndReason.shadowError));
    c?.complete(false);
  }

  /// Feeds one warm-up observation to the readiness policy and reacts to its
  /// verdict.
  ///
  /// 把一次预热观测喂给就绪判据并对其裁决作出反应。
  void _evaluate(_WarmSlot slot, Duration position, Duration buffer) {
    if (_disposed || !identical(_slot, slot)) return;
    final policy = slot.policy;
    final clock = slot.clock;
    if (policy == null || clock == null) return;

    final verdict = policy.onSignal(
      MovaWarmSignal(
        position: position,
        buffer: buffer,
        target: slot.at,
        buffering: slot.buffering,
        elapsed: clock.elapsed,
        live: slot.live,
      ),
    );

    switch (verdict) {
      case MovaWarmVerdict.waiting:
        break;
      case MovaWarmVerdict.ready:
        // Hold the shadow at the warm-up target the first time it reports
        // ready, so the cutover starts from that exact frame instead of wherever
        // the shadow has silently played on to. The rewind lands inside the
        // already-buffered range and never goes near the media's end.
        //
        // 在首次报告就绪时把影子停在预热目标点，使切换从那一帧开始，而不是从
        // 影子悄悄播到的位置开始。这次回绕落在已缓冲区间内，绝不靠近素材尾部。
        if (slot.plan.pauseWhenReady && !slot.heldAtTarget) {
          slot.heldAtTarget = true;
          slot.holding = _holdAtTarget(slot);
        }
        slot.ready = true;
        _cancelReadyTimer(slot);
        if (_phase != MovaCutoverPhase.ready) _setPhase(MovaCutoverPhase.ready);
        final c = slot.readyCompleter;
        if (c != null) {
          slot.readyCompleter = null;
          c.complete(true);
        }
      case MovaWarmVerdict.giveUp:
        final c = slot.readyCompleter;
        slot.readyCompleter = null;
        unawaited(_abandonWarm(reason: MovaCutoverEndReason.notReady));
        c?.complete(false);
    }
  }

  @override
  Future<bool> commit({bool waitForReady = false}) async {
    return _commitSlot(_slot, _op, waitForReady: waitForReady);
  }

  /// 等待就绪与前序事务后，只认领调用者指定的槽。
  Future<bool> _commitSlot(
    _WarmSlot slot,
    int op, {
    required bool waitForReady,
  }) async {
    if (slot.engine == null || _disposed) return false;
    if (!slot.ready) {
      if (!waitForReady) return false;
      final completer = slot.readyCompleter ??= Completer<bool>();
      if (!await completer.future) return false;
    }
    if (_disposed ||
        op != _op ||
        !identical(_slot, slot) ||
        slot.engine == null) {
      return false;
    }
    final previous = _commitTail;
    final done = Completer<void>();
    _commitTail = done.future;
    await previous;
    try {
      if (_disposed ||
          op != _op ||
          !identical(_slot, slot) ||
          slot.engine == null) {
        return false;
      }
      // 同步认领整个槽；后续 prepare 可独立占用新的空槽。
      _slot = _WarmSlot();
      _cancelReadyTimer(slot);
      return await _commitNow(slot, op);
    } finally {
      done.complete();
    }
  }

  /// 提交仅操作已认领的槽；每次异步返回后校验操作代际。
  Future<bool> _commitNow(_WarmSlot slot, int op) async {
    final shadow = slot.engine!;
    final old = _active;
    // 在内部暂停前保存用户意图；自然播完的 playing 不能代表续播意愿。
    _intentSnapshot ??= old.state.playbackIntent;

    /// 显式起播仅在没有后续用户命令时有效。
    bool wantPlay() =>
        (slot.playCommand == movaPlaybackCommand(this) ? slot.play : null) ??
        _intentSnapshot ??
        old.state.playbackIntent;
    var detached = false;
    final handoff = (engine: old, playing: old.state.playing);
    _handoff = handoff;
    var endReason = MovaCutoverEndReason.notReady;

    /// 判断本次提交是否仍拥有换指权限。
    bool current() => !_disposed && op == _op && identical(_active, old);

    /// 只释放本事务资源；过期时恢复仍生效引擎的转发订阅。
    Future<bool> bail() async {
      await _releaseSlot(slot);
      if (_handoff == handoff) _handoff = null;
      if (!_disposed && identical(_active, old)) _publish(snapshot: old.state);
      if (current() && _slot.engine == null) {
        _setPhase(MovaCutoverPhase.idle, reason: endReason);
      }
      if (detached && !_disposed && identical(_active, old)) _attach(old);
      return false;
    }

    try {
      await old.pause();
      if (!current()) return await bail();
      await slot.holding;
      if (!current()) return await bail();
      if (_keepAliveWanted && wantPlay() && shadow is MovaKeepAlive) {
        await (shadow as MovaKeepAlive).setKeepAlive(true);
        if (!current()) return await bail();
      }
      await _inheritViewSettings(
        old.state,
        shadow,
        rate: slot.plan.rate,
        current: current,
      );
      if (!current()) return await bail();
      if (_config.muteWhileWarm && shadow is MovaPlayerMute) {
        final released = await _setWarmMute(slot, false, op: op);
        if (!current()) return await bail();
        if (!released) {
          endReason = MovaCutoverEndReason.muteRestoreFailed;
          await bail();
          if (current() && wantPlay()) await old.play();
          return false;
        }
      }
      if (wantPlay()) {
        await shadow.play();
      } else {
        await shadow.pause();
      }
      if (!current()) return await bail();
      detached = true;
      await _detach();
      if (!current()) return await bail();
      await _detachShadow(slot);
      if (!current()) return await bail();
      _intentSnapshot = null;
      _handoff = null;
      _active = shadow;
      slot.engine = null;
      MovaBrightnessLease.transfer(old, shadow);
      _epoch++;
      _attach(shadow);
      bool promotedCurrent() => !_disposed && op == _op && identical(_active, shadow);
      for (final event in [
        slot.lastSource,
        slot.lastReady,
        slot.lastFirstFrame,
      ]) {
        if (!promotedCurrent()) break;
        if (event != null) _publish(snapshot: shadow.state, event: event);
        if (!promotedCurrent()) break;
      }
      // 新 prepare 的槽及相位归新操作所有，提交收尾不得覆盖。
      if (promotedCurrent() && _slot.engine == null) {
        _setPhase(
          MovaCutoverPhase.idle,
          reason: MovaCutoverEndReason.committed,
        );
      }
      if (old is MovaHandoffRetirable) {
        (old as MovaHandoffRetirable).markRetired();
      }
      unawaited(old.dispose());
      return promotedCurrent();
    } catch (_) {
      await bail();
      rethrow;
    }
  }

  /// Carries the user's view settings from [from] (the outgoing engine's state)
  /// onto [shadow] before it plays, so a hand-off never snaps rate/fit/zoom/
  /// volume/locked/orientation/fullscreen/mini back to defaults. Only values that differ
  /// from the shadow's are written; a failing setter is skipped, not fatal.
  ///
  /// Rate is inherited unless the warm plan states one ([MovaWarmPlan.rate]):
  /// the cutover layer cannot tell the cutover direction, so an ad-aware caller (see
  /// `MovaAds`) declares the rate it wants instead.
  ///
  /// 在影子开播前，把用户的视图设置从 [from]（旧引擎状态）迁到 [shadow]，使换指
  /// 不会让倍速/适配/缩放/音量/锁定/方向/全屏/小窗回到默认。只写与影子不同的值；
  /// 某个 setter 失败则跳过，不致命。
  ///
  /// 换指方向在这一层分辨不出（预热计划里没有这个字段），所以倍速也一并继承；
  /// 不允许广告变速的调用方（见 `MovaAds`）在换指后自行复位。
  Future<void> _inheritViewSettings(
    MovaState from,
    MovaApi shadow, {
    double? rate,
    required bool Function() current,
  }) async {
    final to = shadow.state;
    Future<void> apply(bool differs, Future<void> Function() call) async {
      if (!differs || !current()) return;
      try {
        await call();
      } catch (_) {
        // 迁移失败不阻断换指。
      }
    }

    final wantRate = rate ?? from.rate;
    await apply(wantRate != to.rate, () => shadow.setRate(wantRate));
    await apply(from.fit != to.fit, () => shadow.setFit(from.fit));
    await apply(from.zoom != to.zoom, () => shadow.setZoom(from.zoom));
    await apply(from.volume != to.volume, () => shadow.setVolume(from.volume));
    await apply(
      from.brightness != to.brightness,
      () => shadow.setBrightness(from.brightness),
    );
    await apply(from.locked != to.locked, () => shadow.setLocked(from.locked));
    await apply(
      from.orientation != to.orientation,
      () => shadow.setOrientation(from.orientation),
    );
    await apply(
      from.fullscreen != to.fullscreen,
      () => shadow.setFullscreen(from.fullscreen),
    );
    await apply(from.mini != to.mini, () => shadow.setMini(from.mini));
  }

  /// Applies local mute; policy allows unavailable acquisition, reports failed
  /// restoration and gives up rather than activating a permanently muted player.
  ///
  /// 应用局部静音；策略允许获取不可用，恢复失败则上报并放弃，避免激活永久静音的播放器。
  Future<bool> _setWarmMute(_WarmSlot slot, bool on, {int? op}) async {
    final shadow = slot.engine!;
    final ok = await (shadow as MovaPlayerMute).setWarmMute(on);
    if (on) {
      if (ok && !_disposed && identical(_slot, slot)) slot.muteOwner = shadow;
      return !const _WarmMuteFailurePolicy().giveUp(releasing: false);
    }
    if (!identical(slot.muteOwner, shadow)) return true;
    if (ok) {
      slot.muteOwner = null;
      return true;
    }
    if (!_disposed && (op == null || op == _op)) {
      _publish(
        event: MovaErrorEvent(
          StateError('Could not restore player warm-up mute'),
        ),
      );
    }
    return !const _WarmMuteFailurePolicy().giveUp(releasing: true);
  }

  /// 释放指定槽的订阅与引擎；引擎同步取走以保证恰好释放一次。
  Future<void> _releaseSlot(_WarmSlot slot) async {
    final shadow = slot.engine;
    slot.engine = null;
    _cancelReadyTimer(slot);
    final c = slot.readyCompleter;
    slot.readyCompleter = null;
    c?.complete(false);
    try {
      await slot.holding;
    } finally {
      try {
        await _detachShadow(slot);
      } finally {
        await shadow?.dispose();
      }
    }
  }

  /// 显式放弃同时清除事务意图。
  @override
  Future<void> abandon() {
    _intentSnapshot = null;
    return _abandonWarm();
  }

  /// 内部换槽只释放预热资源，保留仍在途事务的用户意图。
  Future<void> _abandonWarm({
    MovaCutoverEndReason reason = MovaCutoverEndReason.abandoned,
  }) {
    final slot = _slot;
    _slot = _WarmSlot();
    if (_phase != MovaCutoverPhase.idle) {
      _setPhase(MovaCutoverPhase.idle, reason: reason);
    }
    return _releaseSlot(slot);
  }

  @override
  Future<bool> cutoverTo(
    MovaSource source, {
    Duration at = Duration.zero,
    double? rate,
  }) async {
    return (await cutoverToAccepted(source, at: at, rate: rate)).seamless;
  }

  /// 一次性切换单独返回接受结果；拒绝不重试，也不对旧媒体 seek。
  @override
  Future<({bool seamless, bool accepted})> cutoverToAccepted(
    MovaSource source, {
    Duration at = Duration.zero,
    double? rate,
    bool? play,
  }) async {
    if (_disposed) return (seamless: false, accepted: false);
    final command = movaPlaybackCommand(this);
    final op = ++_op;
    if (cutoverEnabled) {
      final owned = await _startWarm(
        source,
        at: at,
        cue: const MovaWarmCue(),
        plan: MovaWarmPlan(trigger: const MovaEagerWarm(), rate: rate),
      );
      if (_disposed || op != _op || owned?.rejected == true) {
        return (seamless: false, accepted: false);
      }
      if (owned != null && play != null) {
        owned.play = play;
        owned.playCommand = command;
      }
      final ok =
          owned != null && await _commitSlot(owned, op, waitForReady: true);
      if (ok) return (seamless: true, accepted: true);
    }
    if (_disposed || op != _op) return (seamless: false, accepted: false);
    final active = _active;
    _intentSnapshot = null;
    // 公开切换保留默认起播；包内显式意图让位于等待期间的用户命令。
    final autoPlay = play == null
        ? true
        : command == movaPlaybackCommand(this)
        ? play
        : active.state.playbackIntent;
    final accepted = await active.open(source, autoPlay: autoPlay);
    if (_disposed || op != _op || !accepted) {
      return (seamless: false, accepted: false);
    }
    // 零点不提前 seek，避免首帧落地前卡住媒体管线；直播不 seek。
    if (source.type != MovaStreamType.live && at > Duration.zero) {
      await active.seek(at);
    }
    return (seamless: false, accepted: true);
  }

  /// Records a phase transition and announces it on [cutoverPhases]/[events].
  ///
  /// 记录一次阶段迁移，并在 [cutoverPhases]/[events] 上宣告。
  void _setPhase(MovaCutoverPhase phase, {MovaCutoverEndReason? reason}) {
    if (_phase == phase) return;
    _phase = phase;
    if (_disposed && reason != MovaCutoverEndReason.disposed) return;
    _cutoverPhases.add(phase);
    _publish(event: MovaCutoverChange(phase, reason: reason));
  }
}
