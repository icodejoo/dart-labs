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
  }) =>
      _startWarm(source, at: at, trigger: _config.effectiveTrigger, cue: cue);

  /// Shared shadow-creation path for [prepare] and [swapTo]; [trigger] is
  /// injected so [swapTo] can force eager warming regardless of the
  /// configured trigger.
  ///
  /// [prepare]、[swapTo] 共用的影子创建路径；[trigger] 由调用方注入，使
  /// [swapTo] 能无视已配置的触发策略、强制立即预热。
  Future<void> _startWarm(
    MovaSource source, {
    required Duration at,
    required MovaWarmTrigger trigger,
    required MovaWarmCue cue,
  }) async {
    if (!swapEnabled) return;
    if (_shadow != null) return;
    if (!trigger.shouldWarm(cue)) return;

    final shadow = _engineFactory();
    _shadow = shadow;
    _warmAt = at;
    _warmLive = source.type == MovaStreamType.live;
    _policy = _config.newReadyPolicy();
    _warmClock = Stopwatch()..start();

    if (_config.muteWhileWarm) unawaited(shadow.setVolume(0));
    await shadow.open(source, autoPlay: true);
    if (!_warmLive) await shadow.seek(at);

    if (_disposed || !identical(_shadow, shadow)) return;

    _shadowBuffering = false;
    _shadowStateSub = shadow.states.listen((s) => _shadowBuffering = s.buffering);
    _shadowProgressSub = shadow.progress.listen((p) => _evaluate(shadow, p.position, p.buffer));

    _setPhase(MovaSwapPhase.warming);
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
    await shadow.setVolume(old.state.volume);
    await shadow.play();

    await _detach();
    await _shadowStateSub?.cancel();
    await _shadowProgressSub?.cancel();
    _shadowStateSub = null;
    _shadowProgressSub = null;

    _active = shadow;
    _shadow = null;
    _epoch++;
    _attach(_active);

    _policy = null;
    _warmClock = null;
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
    await _shadowStateSub?.cancel();
    await _shadowProgressSub?.cancel();
    _shadowStateSub = null;
    _shadowProgressSub = null;
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

    await _startWarm(source, at: at, trigger: const MovaEagerWarm(), cue: const MovaWarmCue());
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
