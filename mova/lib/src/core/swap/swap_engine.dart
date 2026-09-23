import 'dart:async';

import '../api.dart';
import '../bus/bus.dart';
import '../events/events.dart';
import '../feed/engine_pool.dart' show MovaEngineFact;
import '../model/fit.dart';
import '../model/orientation.dart';
import '../model/quality.dart';
import '../model/source.dart';
import '../options/options.dart';
import '../preview/api.dart';
import '../state/progress.dart';
import '../state/state.dart';
import '../state/ui_state.dart';
import '../stt/api.dart';
import 'ctl.dart';
import 'plan.dart';
import 'trigger.dart';
import 'warm.dart';

/// A [MovaApi] that owns a live engine plus, briefly, a warming shadow one,
/// and presents a single stable surface in front of both.
///
/// The UI holds *this* object, never the engines behind it: its streams,
/// state snapshot and render handle stay addressable across a swap, so
/// components that subscribe once in `initState` keep working and
/// `MovaPlayer`'s `ValueKey(api)` never remounts the tree mid-swap.
///
/// With [MovaSwapConfig.enabled] false this is a pure pass-through: no shadow
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
/// [MovaSwapConfig.enabled] 为 false 时它是纯直通代理：永不创建影子引擎，
/// 每个方法都原样转发给工厂产出的那唯一一个引擎。
class MovaSwapEngine implements MovaApi, MovaSwapCtl {
  /// Creates a swap engine over [engineFactory].
  ///
  /// 基于 [engineFactory] 创建一个切换引擎。
  ///
  /// - [engineFactory]: creates each underlying engine; hosts pass
  ///   `createMovaEngine` / 创建每个底层引擎；宿主传 `createMovaEngine`
  ///
  /// Example / 示例:
  /// ```dart
  /// final api = MovaSwapEngine(engineFactory: createMovaEngine);
  /// runApp(MovaPlayer(api: api));
  /// ```
  MovaSwapEngine({required this._engineFactory}) {
    _active = _engineFactory();
    _state = MovaBus<MovaState>(_active.state.copyWith(renderEpoch: _epoch));
    _uiState = MovaBus<MovaUiState>(_active.uiState);
    _attach(_active);
  }

  /// Creates each underlying engine.
  ///
  /// 创建每个底层引擎。
  final MovaEngineFact _engineFactory;

  /// The engine currently driving the render surface.
  ///
  /// 当前驱动渲染面的引擎。
  MovaApi get active => _active;
  late MovaApi _active;

  /// The engine warming up in the background, if any.
  ///
  /// 后台正在预热的引擎（若有）。
  MovaApi? _shadow;

  late final MovaBus<MovaState> _state;
  late final MovaBus<MovaUiState> _uiState;
  final StreamController<MovaProg> _progress = StreamController<MovaProg>.broadcast();
  final StreamController<MovaEvent> _events = StreamController<MovaEvent>.broadcast();
  final StreamController<MovaSwapPhase> _swapPhases = StreamController<MovaSwapPhase>.broadcast();

  StreamSubscription<MovaState>? _activeStateSub;
  StreamSubscription<MovaProg>? _activeProgressSub;
  StreamSubscription<MovaEvent>? _activeEventSub;
  StreamSubscription<MovaUiState>? _activeUiSub;

  StreamSubscription<MovaState>? _shadowStateSub;
  StreamSubscription<MovaProg>? _shadowProgressSub;

  /// Watches the shadow engine's own event stream so a load failure there ends
  /// the warm-up instead of silently warming forever.
  ///
  /// 监听影子引擎自身的事件流，使其加载失败时结束预热，而不是悄悄地一直预热。
  StreamSubscription<MovaEvent>? _shadowEventSub;

  /// Render-epoch counter merged into every forwarded state; bumped once per
  /// committed swap so the render surface always re-reads [renderHandle].
  ///
  /// 合并进每次转发状态的渲染纪元计数器；每次提交切换后加一，使渲染面每次都
  /// 重新读取 [renderHandle]。
  int _epoch = 0;

  MovaSwapPhase _phase = MovaSwapPhase.idle;
  MovaWarmPolicy? _policy;
  Stopwatch? _warmClock;
  Duration _warmAt = Duration.zero;
  bool _warmLive = false;
  bool _shadowBuffering = false;
  Completer<bool>? _readyCompleter;
  bool _disposed = false;

  /// The plan driving the warm-up currently in flight.
  ///
  /// 驱动当前在途预热的计划。
  MovaWarmPlan _warmPlan = const MovaWarmPlan();

  /// Whether [MovaWarmPlan.pauseWhenReady] has already been honoured for this
  /// warm-up, so a policy that keeps reporting ready only pauses once.
  ///
  /// 本次预热是否已经执行过 [MovaWarmPlan.pauseWhenReady]，使持续报告就绪的
  /// 判据只触发一次暂停。
  bool _heldAtTarget = false;

  /// The in-flight hold-at-target operation, awaited before a commit plays the
  /// shadow so a late `pause()` can never land after that `play()`.
  ///
  /// 在途的"停在目标帧"操作；提交切换在播放影子引擎前会先等待它，使迟到的
  /// `pause()` 不可能落在那次 `play()` 之后。
  Future<void>? _holding;

  /// Pauses the shadow and rewinds it to the warm-up target so the swap starts
  /// exactly there.
  ///
  /// 暂停影子引擎并回绕到预热目标点，使切换恰好从该处开始。
  Future<void> _holdAtTarget(MovaApi shadow) async {
    await shadow.pause();
    if (_disposed || !identical(_shadow, shadow)) return;
    if (_warmAt > Duration.zero) await shadow.seek(_warmAt);
  }

  /// The swap configuration in effect, taken from the active engine's options.
  ///
  /// 生效中的切换配置，取自当前生效引擎的选项。
  MovaSwapConfig get _config => _active.options.swap;

  /// Subscribes to [engine]'s streams and forwards them onto this proxy's own
  /// streams, merging the current [_epoch] into every forwarded state.
  ///
  /// 订阅 [engine] 的流并转发到本代理自己的流上，把当前 [_epoch] 合并进每个
  /// 转发出的状态。
  void _attach(MovaApi engine) {
    _activeStateSub = engine.states.listen((s) => _state.emit(s.copyWith(renderEpoch: _epoch)));
    _activeProgressSub = engine.progress.listen(_progress.add);
    _activeEventSub = engine.events.listen(_events.add);
    _activeUiSub = engine.uiStates.listen(_uiState.emit);
  }

  /// Cancels the forwarding subscriptions set up by [_attach].
  ///
  /// 取消 [_attach] 建立的转发订阅。
  Future<void> _detach() async {
    await _activeStateSub?.cancel();
    await _activeProgressSub?.cancel();
    await _activeEventSub?.cancel();
    await _activeUiSub?.cancel();
    _activeStateSub = null;
    _activeProgressSub = null;
    _activeEventSub = null;
    _activeUiSub = null;
  }

  @override
  Stream<MovaEvent> get events => _events.stream;

  @override
  Stream<MovaState> get states => _state.stream;

  @override
  Stream<MovaProg> get progress => _progress.stream;

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
  MovaPrevApi get preview => _active.preview;

  @override
  MovaSttApi get stt => _active.stt;

  @override
  Future<void> open(MovaSource source, {bool autoPlay = true}) => _active.open(source, autoPlay: autoPlay);

  @override
  Future<void> play() => _active.play();

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> playOrPause() => _active.playOrPause();

  @override
  Future<void> seek(Duration to) => _active.seek(to);

  @override
  Future<void> seekBy(Duration delta) => _active.seekBy(delta);

  @override
  Future<void> setVolume(double v) => _active.setVolume(v);

  @override
  Future<void> setBrightness(double v) => _active.setBrightness(v);

  @override
  Future<void> setRate(double r) => _active.setRate(r);

  @override
  Future<void> setFit(MovaFit f) => _active.setFit(f);

  @override
  Future<void> setZoom(double z) => _active.setZoom(z);

  @override
  Future<void> setLocked(bool v) => _active.setLocked(v);

  @override
  Future<void> setFullscreen(bool v) => _active.setFullscreen(v);

  @override
  Future<void> setMini(bool v) => _active.setMini(v);

  @override
  Future<void> setOrientation(MovaOrient o) => _active.setOrientation(o);

  @override
  Future<void> loadQualities() => _active.loadQualities();

  @override
  Future<void> switchQuality(MovaQual q) => _active.switchQuality(q);

  @override
  Future<bool> enterPip() => _active.enterPip();

  @override
  Future<void> reload() => _active.reload();

  @override
  Future<void> backToLiveEdge() => _active.backToLiveEdge();

  @override
  void showControls({bool sticky = false}) => _active.showControls(sticky: sticky);

  @override
  void hideControls() => _active.hideControls();

  @override
  void showHud(MovaHud hud, {String? text}) => _active.showHud(hud, text: text);

  @override
  void setDragging(bool v, {Duration? previewAt}) => _active.setDragging(v, previewAt: previewAt);

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _detach();
    await _shadowStateSub?.cancel();
    await _shadowProgressSub?.cancel();
    await _shadowEventSub?.cancel();
    await _active.dispose();
    final shadow = _shadow;
    _shadow = null;
    if (shadow != null) await shadow.dispose();
    await _state.close();
    await _uiState.close();
    await _progress.close();
    await _events.close();
    await _swapPhases.close();
  }

  @override
  bool get swapEnabled => _config.enabled;

  @override
  MovaSwapPhase get swapPhase => _phase;

  @override
  Stream<MovaSwapPhase> get swapPhases => _swapPhases.stream;

  @override
  Future<void> prepare(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
  }) =>
      _startWarm(source, at: at, cue: cue, plan: plan);

  /// Shared shadow-creation path for [prepare] and [swapTo]; [plan] is
  /// injected so [swapTo] can force eager warming regardless of the
  /// configured trigger, and so an ad warm-up can hold at frame zero.
  ///
  /// [prepare]、[swapTo] 共用的影子创建路径；[plan] 由调用方注入，使
  /// [swapTo] 能无视已配置的触发策略、强制立即预热，也使广告方向的预热能停在
  /// 第 0 帧。
  Future<void> _startWarm(
    MovaSource source, {
    required Duration at,
    required MovaWarmCue cue,
    required MovaWarmPlan plan,
  }) async {
    if (!swapEnabled) return;
    if (_shadow != null) return;
    final trigger = plan.trigger ?? _config.effectiveTrigger;
    if (!trigger.shouldWarm(cue)) return;

    final shadow = _engineFactory();
    _shadow = shadow;
    _warmAt = at;
    _warmPlan = plan;
    _heldAtTarget = false;
    _warmLive = source.type == MovaStreamType.live;
    // An injected policy is the *same instance* on every warm-up, so it must
    // be reset before use — otherwise the second warm-up inherits the first
    // one's consecutive-tick counter and a single lucky tick commits a swap.
    //
    // 注入的判据在每次预热时都是*同一个实例*，因此使用前必须重置——否则第二次
    // 预热会继承第一次的连续 tick 计数，一次侥幸的 tick 就能把切换提交出去。
    _policy = (plan.policy ?? _config.newReadyPolicy())..reset();
    _warmClock = Stopwatch()..start();

    if (_config.muteWhileWarm) unawaited(shadow.setVolume(0));
    await shadow.open(source, autoPlay: true);
    // Seeking to zero right after open() buys nothing and is pure risk: a seek
    // issued before the first frame lands has been observed to wedge the
    // player on device. The pre-roll→content and content→ad directions both
    // warm at zero, so this guard covers the common case.
    //
    // 刚 open() 完就 seek(0) 毫无收益、纯属风险敞口：首帧落地前下发的 seek 在
    // 真机上被观测到会把播放器卡死。前贴片→正片与正片→广告两个方向都在 0 处
    // 预热，因此这道守卫覆盖的正是常见情形。
    if (!_warmLive && at > Duration.zero) await shadow.seek(at);

    if (_disposed || !identical(_shadow, shadow)) return;

    _shadowBuffering = false;
    _shadowStateSub = shadow.states.listen((s) => _shadowBuffering = s.buffering);
    _shadowProgressSub = shadow.progress.listen((p) => _evaluate(shadow, p.position, p.buffer));
    _shadowEventSub = shadow.events.listen((e) {
      if (e is MovaErrorEvent) _onShadowError(shadow);
    });

    _setPhase(MovaSwapPhase.warming);
  }

  /// Ends the warm-up the same way a [MovaWarmVerdict.giveUp] does when the
  /// shadow engine itself reports a playback error.
  ///
  /// 影子引擎自身报告播放错误时，以与 [MovaWarmVerdict.giveUp] 完全相同的方式
  /// 结束本次预热。
  void _onShadowError(MovaApi shadow) {
    if (_disposed || !identical(_shadow, shadow)) return;
    final c = _readyCompleter;
    _readyCompleter = null;
    unawaited(abandon());
    c?.complete(false);
  }

  /// Feeds one warm-up observation to the readiness policy and reacts to its
  /// verdict.
  ///
  /// 把一次预热观测喂给就绪判据并对其裁决作出反应。
  void _evaluate(MovaApi shadow, Duration position, Duration buffer) {
    if (_disposed || !identical(_shadow, shadow)) return;
    final policy = _policy;
    final clock = _warmClock;
    if (policy == null || clock == null) return;

    final verdict = policy.onSignal(MovaWarmSignal(
      position: position,
      buffer: buffer,
      target: _warmAt,
      buffering: _shadowBuffering,
      elapsed: clock.elapsed,
    ));

    switch (verdict) {
      case MovaWarmVerdict.waiting:
        break;
      case MovaWarmVerdict.ready:
        // Hold the shadow at the warm-up target the first time it reports
        // ready, so the swap starts from that exact frame instead of wherever
        // the shadow has silently played on to. The rewind lands inside the
        // already-buffered range and never goes near the media's end.
        //
        // 在首次报告就绪时把影子停在预热目标点，使切换从那一帧开始，而不是从
        // 影子悄悄播到的位置开始。这次回绕落在已缓冲区间内，绝不靠近素材尾部。
        if (_warmPlan.pauseWhenReady && !_heldAtTarget) {
          _heldAtTarget = true;
          _holding = _holdAtTarget(shadow);
        }
        if (_phase != MovaSwapPhase.ready) _setPhase(MovaSwapPhase.ready);
        final c = _readyCompleter;
        if (c != null) {
          _readyCompleter = null;
          c.complete(true);
        }
      case MovaWarmVerdict.giveUp:
        final c = _readyCompleter;
        _readyCompleter = null;
        unawaited(abandon());
        c?.complete(false);
    }
  }

  @override
  Future<bool> commit({bool waitForReady = false}) async {
    final shadow = _shadow;
    if (shadow == null) return false;

    if (_phase != MovaSwapPhase.ready) {
      if (!waitForReady) return false;
      final completer = Completer<bool>();
      _readyCompleter = completer;
      final ok = await completer.future;
      if (!ok) return false;
    }

    if (!identical(_shadow, shadow)) return false;
    return _commitNow(shadow);
  }

  /// Performs the atomic hand-off from [_active] to [shadow]: pause the old
  /// engine, unmute and play the shadow, re-point the forwarding
  /// subscriptions, bump [_epoch], then dispose the old engine without
  /// blocking the swap on that (slow, native) call.
  ///
  /// 执行从 [_active] 到 [shadow] 的原子换指：暂停旧引擎、给影子取消静音并
  /// 播放、把转发订阅重新接到影子上、推进 [_epoch]，再释放旧引擎——释放调用
  /// （慢速原生调用）不阻塞切换本身。
  Future<bool> _commitNow(MovaApi shadow) async {
    final old = _active;

    await old.pause();
    await _holding;
    await shadow.setVolume(old.state.volume);
    await shadow.play();

    await _detach();
    await _shadowStateSub?.cancel();
    await _shadowProgressSub?.cancel();
    await _shadowEventSub?.cancel();
    _shadowStateSub = null;
    _shadowProgressSub = null;
    _shadowEventSub = null;

    _active = shadow;
    _shadow = null;
    _epoch++;
    _attach(_active);

    _policy = null;
    _warmClock = null;
    _holding = null;
    _warmPlan = const MovaWarmPlan();
    _heldAtTarget = false;
    _setPhase(MovaSwapPhase.idle);

    unawaited(old.dispose());
    return true;
  }

  @override
  Future<void> abandon() async {
    final shadow = _shadow;
    if (shadow == null) return;
    _shadow = null;
    _policy = null;
    _warmClock = null;
    _holding = null;
    _warmPlan = const MovaWarmPlan();
    _heldAtTarget = false;
    await _shadowStateSub?.cancel();
    await _shadowProgressSub?.cancel();
    await _shadowEventSub?.cancel();
    _shadowStateSub = null;
    _shadowProgressSub = null;
    _shadowEventSub = null;
    await shadow.dispose();
    if (_phase != MovaSwapPhase.idle) _setPhase(MovaSwapPhase.idle);
    // Unblock any commit(waitForReady: true) still awaiting this shadow —
    // it must resolve to false rather than hang forever.
    //
    // 唤醒任何仍在等待该影子引擎的 commit(waitForReady: true)——它必须解析为
    // false，而不是永远挂起。
    final c = _readyCompleter;
    if (c != null) {
      _readyCompleter = null;
      c.complete(false);
    }
  }

  @override
  Future<bool> swapTo(MovaSource source, {Duration at = Duration.zero}) async {
    if (!swapEnabled) {
      await _active.open(source);
      if (source.type != MovaStreamType.live) await _active.seek(at);
      return false;
    }

    await _startWarm(
      source,
      at: at,
      cue: const MovaWarmCue(),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    final ok = _shadow != null && await commit(waitForReady: true);
    if (!ok) {
      await _active.open(source);
      if (source.type != MovaStreamType.live) await _active.seek(at);
    }
    return ok;
  }

  /// Records a phase transition and announces it on [swapPhases]/[events].
  ///
  /// 记录一次阶段迁移，并在 [swapPhases]/[events] 上宣告。
  void _setPhase(MovaSwapPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    if (_disposed) return;
    _swapPhases.add(phase);
    _events.add(MovaSwapChg(phase));
  }
}
