import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import 'api.dart';
import 'bus/bus.dart';
import 'events/events.dart';
import 'interceptor/interceptor.dart';
import 'kernel/kernel.dart';
import 'kernel/mpv_kernel.dart';
import 'kernel/standby_kernel.dart';
import 'live/timeshift.dart';
import 'model/fit.dart';
import 'model/orientation.dart';
import 'model/quality.dart';
import 'model/source.dart';
import 'options/options.dart';
import 'platform/ports.dart';
import 'preview/api.dart';
import 'preview/cache.dart';
import 'preview/dir_provider.dart';
import 'preview/disk_cache.dart';
import 'preview/extractor.dart';
import 'preview/fetcher.dart';
import 'preview/net_probe.dart';
import 'preview/platform_kind.dart';
import 'preview/service.dart';
import 'preview/source.dart';
import 'preview/two_level_cache.dart';
import 'preview/vtt_source.dart';
import 'recovery/fail.dart';
import 'recovery/watchdog.dart';
import 'render/first_frame.dart';
import 'report/collector.dart';
import 'report/report.dart';
import 'report/stats_probe.dart';
import 'standby/plan.dart';
import 'standby/standby.dart';
import 'state/progress.dart';
import 'state/state.dart';
import 'state/ui_state.dart';
import 'stt/api.dart';
import 'stt/service.dart';

/// The production [MovaApi] implementation: reduces a [MovaKernel]'s raw streams
/// into public state/event/progress streams and implements every capability
/// method (playback, quality switching + ABR, live-seek gating, HUD/controls
/// timers, platform ports).
///
/// This is the only class in `lib/src/core/**` that wires everything else in
/// this layer together; it never imports `package:flutter` or
/// `package:media_kit` directly (those live behind [MovaKernel]/[MovaOpts]/
/// the ports).
///
/// 生产环境的 [MovaApi] 实现：把 [MovaKernel] 的原始流归约为公开的状态/事件/进度
/// 流，并实现全部能力方法（播放、清晰度切换 + ABR、直播拖动门控、HUD/控制条
/// 计时器、平台端口）。
///
/// 这是 `lib/src/core/**` 中唯一把该层其余部分粘合在一起的类；它本身不直接
/// 引入 `package:flutter` 或 `package:media_kit`（这些依赖被隔离在
/// [MovaKernel]/[MovaOpts]/各 Port 之后）。
class MovaEngine implements MovaApi, MovaStandbyController {
  /// The kernel this engine drives.
  ///
  /// 该 engine 驱动的内核。
  final MovaKernel _kernel;

  /// The configuration this instance was constructed with.
  ///
  /// 构造该实例时使用的配置。
  @override
  final MovaOpts options;

  /// The kernel's render handle (a media_kit `VideoController` for
  /// [MovaMpvKernel]), forwarded verbatim so `MovaPlayer` can feed it to the
  /// `Video` widget.
  ///
  /// 内核的渲染句柄（[MovaMpvKernel] 场景下是 media_kit 的 `VideoController`），
  /// 原样转发，供 `MovaPlayer` 传给 `Video` 组件。
  @override
  Object? get renderHandle => _kernel.renderHandle;

  @override
  bool get pipSupported => state.pipSupported;

  /// Interceptor chain consulted before open/seek/play and on every error.
  ///
  /// 在 open/seek/play 前及每次出错时咨询的拦截链。
  final MovaHookChain _chain;

  /// Reads/writes device screen brightness.
  ///
  /// 读写设备屏幕亮度。
  final MovaBrightPort _brightness;

  /// Reads/writes system media volume; `null` means the volume gesture drives
  /// the player's own volume via [_kernel] instead of any system volume.
  ///
  /// 读写系统媒体音量；为 `null` 时音量手势经 [_kernel] 驱动播放器自身音量，
  /// 而非任何系统音量。
  final MovaVolumePort? _volume;

  /// Enters system picture-in-picture.
  ///
  /// 进入系统画中画。
  final MovaPipPort _pip;

  /// Applies/resets fullscreen orientation and system UI.
  ///
  /// 应用/重置全屏方向与系统 UI。
  final MovaOrientationPort _orientation;

  /// Pulls single frames for the scrub-preview fallback; `null` when no
  /// frame-extraction fallback is wired (an audio-only engine, among others).
  ///
  /// 为拖动预览兜底抽取单帧；未接线时为 `null`（仅音频引擎即是其中一种情形）。
  final MovaFramePuller? _extractor;

  /// HTTP fetcher shared by the preview pipeline (VTT/sprites) and
  /// [loadQualities]'s HLS master-playlist fetch; defaults to
  /// [MovaIoHttpFetcher] when the host injects none.
  ///
  /// 预览流水线（VTT/雪碧图）与 [loadQualities] 拉取 HLS 主播放列表共用的 HTTP
  /// 客户端；宿主未注入时默认使用 [MovaIoHttpFetcher]。
  final MovaHttpFetch _fetcher;

  /// Unified reporting sink; `null` means reporting is off — no translator is
  /// created and [report] is a no-op, so the whole feature costs nothing when
  /// unused (mirrors [MovaSwapConfig.enabled]'s pass-through-when-off design).
  ///
  /// 统一上报出口；为 `null` 表示上报关闭——不创建转换器，[report] 也是空操作，
  /// 未使用时整个功能零开销（与 [MovaSwapConfig.enabled] 关闭时纯直通的设计
  /// 一致）。
  final MovaReporter? _reporter;

  /// Owns this engine's QoE state and forwards standardized report events to
  /// [_reporter]; `null` when [_reporter] is `null`.
  ///
  /// 持有本 engine 的 QoE 状态，把标准化后的上报事件转发给 [_reporter]；
  /// [_reporter] 为 `null` 时本字段也是 `null`。
  MovaQoeCollector? _qoe;

  /// This engine's constructor-time `audioOnly` decision, forwarded to
  /// [_qoe] as a per-session constant; see the [MovaEngine.new] doc comment
  /// for why this isn't a [MovaState] field.
  ///
  /// 该 engine 构造期的 `audioOnly` 决策，作为每会话常量转发给 [_qoe]；为何
  /// 不是 [MovaState] 字段见 [MovaEngine.new] 的文档注释。
  final bool _audioOnly;

  /// The scrub-preview service assembled from [MovaOpts.preview].
  ///
  /// 依据 [MovaOpts.preview] 装配出来的拖动预览服务。
  late final MovaPreviewService _previewService;
  late final MovaSttService _sttService;

  /// The ABR downshift policy in effect; defaults to a [MovaBufferAbr]
  /// seeded from [MovaAbrConfig.stallThreshold] when [MovaAbrConfig.policy] is
  /// null.
  ///
  /// 当前生效的 ABR 降档策略；[MovaAbrConfig.policy] 为空时默认用
  /// [MovaAbrConfig.stallThreshold] 构造的 [MovaBufferAbr]。
  late final MovaAbrPolicy _abrPolicy;

  /// Reentrancy guard for [_handleAbrBuffering]: true while a downshift
  /// triggered by a previous threshold-crossing is still in flight (its
  /// async `open()`/`seek()` hasn't settled yet). Prevents two overlapping
  /// [downshiftQuality] calls from racing on [_kernel] and corrupting the
  /// "from" quality snapshot or double/under-firing [MovaAbrDownShift].
  ///
  /// [_handleAbrBuffering] 的重入保护：为真时表示上一次阈值触发的降档仍在
  /// 进行中（其异步 `open()`/`seek()` 尚未完成）。防止两次
  /// [downshiftQuality] 调用并发争用 [_kernel]，破坏"from"清晰度快照或
  /// 导致 [MovaAbrDownShift] 重复/漏发。
  bool _abrDownshiftInFlight = false;

  /// Reentrancy guard for [_maybeAutoBackToLive]: true while an automatic
  /// back-to-edge jump is still in flight. Buffering can flap several times
  /// per second, and each overlapping jump would issue another kernel
  /// `seek()`/`open()` on top of the previous one.
  ///
  /// [_maybeAutoBackToLive] 的重入保护：为真表示一次自动回边缘仍在进行中。
  /// 缓冲状态每秒可能翻转数次，若不加保护，每次翻转都会在上一次未完成时再向
  /// 内核发一次 `seek()`/`open()`。
  bool _autoBackToLiveInFlight = false;

  /// Decides when the current playback attempt has really started presenting
  /// media; feeds [MovaState.rendered] and [MovaFirstFrame].
  ///
  /// 判定当前播放尝试何时真正开始呈现媒体；驱动 [MovaState.rendered] 与
  /// [MovaFirstFrame]。
  final MovaFirstFrameGate _frameGate = MovaFirstFrameGate();

  /// Subscription to the kernel's native restart signal, when it has one.
  ///
  /// 内核原生 RESTART 信号的订阅（内核提供时才有）。
  StreamSubscription<void>? _restartSub;

  /// Pending grace timer: a fallback landed while the native signal was live.
  ///
  /// 宽限计时器：原生信号在工作时兜底信号先到，等待 RESTART。
  Timer? _graceTimer;

  /// When the current source's `open()` call began, for [MovaFirstFrame.sinceOpen].
  ///
  /// 当前源的 `open()` 调用开始时刻，用于 [MovaFirstFrame.sinceOpen]。
  DateTime? _openedAt;

  /// In-flight kernel `open()` calls; gate observations are dropped while > 0.
  ///
  /// 在途的内核 `open()` 调用数；大于 0 时丢弃一切闸门观测。
  int _kernelOpening = 0;

  /// Set synchronously at the start of [dispose] so late callbacks never
  /// re-arm timers on a dying engine.
  ///
  /// 在 [dispose] 开头同步置位，使迟到的回调不会在濒死引擎上重新起计时器。
  bool _disposed = false;

  /// How long a fallback may wait for a native restart before landing anyway.
  ///
  /// 兜底信号先到后，最多等原生 RESTART 多久再自行落地。
  static const Duration _firstFrameGrace = Duration(milliseconds: 1500);

  /// Start/stall watchdog; non-null only when [MovaRecoveryConfig.enabled], so
  /// a disabled engine owns no recovery timer and subscribes to nothing extra.
  ///
  /// 起播/卡顿看门狗；仅在 [MovaRecoveryConfig.enabled] 时非空，因此关闭态的引擎
  /// 不持有任何恢复计时器，也不多订阅任何流。
  MovaPlayWatchdog? _watchdog;

  /// Subscription to the kernel's native end-of-file reasons (recovery only).
  ///
  /// 内核原生文件结束原因的订阅（仅 recovery 开启时存在）。
  StreamSubscription<MovaEndFileReason>? _endFileSub;

  /// Pending retry/failover delay.
  ///
  /// 等待中的重试/切换延迟。
  Timer? _recoverTimer;

  /// Bumped for every armed attempt (open, retry, reload).
  ///
  /// 每武装一次尝试（打开、重试、重载）就自增。
  int _attemptId = 0;

  /// The attempt id already handled as a failure, so one attempt fails once.
  ///
  /// 已作为失败处理过的尝试编号，保证一次尝试只失败一次。
  int _failedAttemptId = -1;

  /// Consecutive failures across all addresses since the last first frame.
  ///
  /// 自上次出首帧以来跨所有地址的连续失败次数。
  int _streak = 0;

  /// Consecutive failures per address index since the last first frame.
  ///
  /// 自上次出首帧以来每个地址下标的连续失败次数。
  final Map<int, int> _addrFailures = <int, int>{};

  /// Whether this session already announced [MovaSourceChange]/[MovaReady].
  ///
  /// 本会话是否已发过 [MovaSourceChange]/[MovaReady]。
  bool _readyAnnounced = false;

  /// Index into the source's addresses currently playing.
  ///
  /// 当前正在播放的地址下标。
  int _sourceIndex = 0;

  /// The address currently playing, or empty before any [open].
  ///
  /// 当前正在播放的地址；尚未 [open] 时为空串。
  String get _activeUri {
    final src = _source;
    if (src == null) return '';
    return _sourceIndex < src.uris.length ? src.uris[_sourceIndex] : src.uri;
  }

  final MovaBus<MovaState> _state;
  final MovaBus<MovaUiState> _ui = MovaBus<MovaUiState>(const MovaUiState());
  final StreamController<MovaEvent> _events =
      StreamController<MovaEvent>.broadcast();
  final StreamController<MovaProg> _progressRaw =
      StreamController<MovaProg>.broadcast();
  late final Stream<MovaProg> _progress;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<Duration> _bufferSub;
  late final StreamSubscription<MovaSize> _sizeSub;
  late final StreamSubscription<Object> _errorSub;

  /// The most recently opened source, or null before [open] has ever been
  /// called.
  ///
  /// 最近一次打开的源；[open] 从未被调用过时为 null。
  MovaSource? _source;

  /// Bumped at the start of every [open] call; a call whose generation no
  /// longer matches after an `await` has been superseded by a later [open]
  /// and bails out instead of clobbering `_source`/firing stale events for a
  /// source the kernel has already moved past.
  ///
  /// 每次 [open] 调用开始时自增；某次调用在 `await` 之后发现自己的世代号已
  /// 落后，说明已被更晚的一次 [open] 取代，就此收手，不再覆写 `_source`
  /// 或为一个内核早已翻篇的源发出陈旧事件。
  int _openGen = 0;

  // Accepted session and recovery position survive rejected open requests.
  //
  // 已接受会话与恢复位置不受被拒绝的打开请求影响。
  int _sessionGen = 0;
  Duration? _recoveryPosition;
  bool get _playIntent => state.playbackIntent;

  // ---- standby (see doc/plans/2026-10-23-standby-mode.md) ----
  // ---- 待机（见 doc/plans/2026-10-23-standby-mode.md）----

  /// Clock for standby timing; tests swap it because `DateTime.now()` does not
  /// follow `fakeAsync`.
  ///
  /// 待机计时用的时钟；测试里替换它，因为 `DateTime.now()` 不跟随 `fakeAsync`。
  @visibleForTesting
  DateTime Function() debugClock = DateTime.now;

  /// The mode of the current hold; null unless [MovaStandbyPhase.holding].
  ///
  /// 当前待机的组合；仅在 [MovaStandbyPhase.holding] 时非空。
  MovaStandbyMode? _standbyMode;

  /// When the current phase began (measures how long a fallback pause lasted).
  ///
  /// 当前阶段开始的时刻（用来计算 fallback 暂停持续了多久）。
  DateTime? _standbySince;

  /// Why the engine is in [MovaStandbyPhase.fallback]; null in other phases.
  ///
  /// 引擎处于 [MovaStandbyPhase.fallback] 的原因；其他阶段为 null。
  MovaStandbyReason? _fallbackCause;

  /// True from `setStandby(true)` until `setStandby(false)` or `pause()`: the
  /// host wants this picture hidden, so a later `play()` starts in standby.
  ///
  /// 从 `setStandby(true)` 起到 `setStandby(false)` 或 `pause()` 为止为 true：宿主希望
  /// 这块画面保持隐藏，之后的 `play()` 因此直接以待机态开播。
  bool _standbyRequested = false;

  /// Fires when a hold reaches [MovaStandbyConfig.maxDuration].
  ///
  /// 待机达到 [MovaStandbyConfig.maxDuration] 时触发。
  Timer? _standbyTimer;

  /// Serializes every standby transition so they never interleave.
  ///
  /// 串行化所有待机迁移，使其永不交错。
  Future<void> _standbyQueue = Future<void>.value();

  /// Fires when waking waited [MovaStandbyConfig.resumeTimeout] for a fresh frame.
  ///
  /// 唤醒后等新画面等满 [MovaStandbyConfig.resumeTimeout] 时触发。
  Timer? _resumeTimer;

  /// When the wake-up call began (the start of [MovaStandbyResume.elapsed]).
  ///
  /// 唤醒调用开始的时刻（[MovaStandbyResume.elapsed] 的起点）。
  DateTime? _resumeAt;

  /// The hold mode being woken from; null when woken from a fallback pause.
  ///
  /// 正在从哪种待机组合唤醒；从 fallback 暂停唤醒时为 null。
  MovaStandbyMode? _resumeFrom;

  /// Whether the first-frame gate is currently armed in resume mode.
  ///
  /// 首帧闸门当前是否处于恢复武装。
  bool _resumeGateArmed = false;

  /// The kernel's standby capability, or null when it has none.
  ///
  /// 内核的待机能力；内核不具备时为 null。
  MovaStandbyKernel? get _standbyKernel {
    final k = _kernel;
    return k is MovaStandbyKernel ? k as MovaStandbyKernel : null;
  }

  /// Whether a recovery retry/failover is waiting to run.
  ///
  /// 是否有重试/切换正在等待执行。
  bool get _recoveryPending => _recoverTimer != null;

  /// Drops a waiting recovery retry (it would load with the play intent and
  /// make a hidden card audible).
  ///
  /// 丢弃正在等待的恢复重试（它会按播放意图加载，让看不见的卡片出声）。
  void _cancelRecovery() {
    _recoverTimer?.cancel();
    _recoverTimer = null;
  }

  /// Runs [step] after every earlier standby transition has settled.
  ///
  /// 在之前所有待机迁移落定后执行 [step]。
  Future<T> _enqueueStandby<T>(Future<T> Function() step) {
    final next = _standbyQueue.then((_) => step());
    _standbyQueue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Moves to [phase] and announces it.
  ///
  /// 切到 [phase] 并对外宣布。
  void _setStandbyPhase(
    MovaStandbyPhase phase,
    MovaStandbyReason reason, {
    MovaStandbyMode? mode,
  }) {
    if (_disposed || _events.isClosed) return;
    _standbySince = debugClock();
    _fallbackCause = phase == MovaStandbyPhase.fallback ? reason : null;
    _state.emit(state.copyWith(standby: phase));
    _events.add(MovaStandbyChange(phase: phase, reason: reason, mode: mode));
  }

  /// Latest known playback position, tracked synchronously from every
  /// kernel `position` callback (independent of the throttled [progress]
  /// stream) so [switchQuality]/[downshiftQuality]/[seekBy] can read it
  /// without waiting on throttling.
  ///
  /// 最近已知的播放位置，从内核每次 `position` 回调同步更新（与节流后的
  /// [progress] 流无关），使 [switchQuality]/[downshiftQuality]/[seekBy]
  /// 无需等待节流即可读取。
  Duration _lastPosition = Duration.zero;

  /// How close a kernel-reported position must land to [_pendingSeekTarget]
  /// before it is trusted again after a seek.
  ///
  /// [_pendingSeekTarget] 结算后重新信任内核上报位置所需的接近程度。
  static const Duration _seekSettleTolerance = Duration(milliseconds: 500);

  /// The position a seek is currently settling toward, or null when no seek
  /// is in flight. Set by every seek path ([seek]) so the *first*
  /// post-seek [progress] update already reports the target instead of a
  /// stale pre-seek position — this is what makes a tap-to-seek, a
  /// horizontal-swipe seek and a double-tap fast-forward/rewind all behave
  /// identically: they are the exact same code path.
  ///
  /// 当前正在结算的 seek 目标位置；无进行中的 seek 时为 null。由每条 seek 路径
  /// （[seek]）设置，使 seek 之后**第一个** [progress] 更新就直接报告目标位置，
  /// 而不是一个陈旧的 seek 前位置——这正是"点击进度条 seek"、"横滑 seek"、
  /// "双击快进退"三者行为完全一致的原因：它们本就是同一段代码。
  Duration? _pendingSeekTarget;

  /// A VOD seek requested before the media reported a duration. The kernel
  /// (mpv) silently drops a seek issued that early, so it is parked here and
  /// replayed once [duration] first arrives — this is what makes an
  /// open-then-resume-to-position land instead of vanishing.
  ///
  /// 在媒体尚未报告时长前就发起的点播 seek。内核（mpv）会静默丢弃这么早的
  /// seek，因此先寄存在此，待 duration 首次到达时补发——这正是"打开后续播到
  /// 某位置"能落地而非石沉大海的原因。若媒体始终不报告时长（畸形源），寄存的
  /// seek 不会执行——但这与内核原本的行为一致（无时长的源本就无法 seek）。
  Duration? _parkedSeek;

  /// Whether the parked seek in [_parkedSeek] should emit [MovaSeeked] once
  /// replayed — carries the `notify` flag [_seekOrPark] was called with
  /// across the park, so [switchQuality]'s "must not emit seek events"
  /// contract still holds even when its resume seek gets parked rather than
  /// sent immediately.
  ///
  /// [_parkedSeek] 补发时是否应发出 [MovaSeeked]——把 [_seekOrPark] 调用时的
  /// `notify` 标志带过寄存期，使 [switchQuality] 的"不得发出 seek 事件"契约
  /// 在其续播 seek 被寄存而非立即下发时依然成立。
  bool _parkedNotify = false;

  Timer? _hudTimer;
  Timer? _autoHideTimer;

  /// Creates an engine over [kernel] (defaults to a new [MovaMpvKernel]),
  /// [options], [interceptors], and platform [brightness]/[pip]/[orientation]
  /// ports (each defaults to a zero-dependency fallback/noop).
  ///
  /// 基于 [kernel]（省略时默认新建 [MovaMpvKernel]）、[options]、[interceptors]
  /// 及平台 [brightness]/[pip]/[orientation] 端口（各自省略时默认使用零依赖
  /// 兜底/空实现）创建一个 engine。
  ///
  /// [thumbDir]/[extractor]/[fetcher] supply the platform-side pieces of the
  /// preview pipeline; each may be omitted, in which case the corresponding
  /// capability degrades (no disk cache / no frame extraction / a `dart:io`
  /// HTTP client) rather than failing.
  ///
  /// [thumbDir]/[extractor]/[fetcher] 提供预览流水线的平台侧零件；三者均可
  /// 省略，省略时对应能力降级（无磁盘缓存 / 无抽帧兜底 / 使用 `dart:io`
  /// 的 HTTP 客户端）而不是报错。
  ///
  /// [audioOnly] is forwarded to the default [MovaMpvKernel] so no video pipeline
  /// is built; it has no effect when [kernel] is supplied, since an injected
  /// kernel is used exactly as given. There is deliberately no
  /// `MovaState.audioOnly` and no `MovaOpts` section for it: this is a
  /// construction-time resource decision (the kernel's render handle is bound
  /// once and never re-bound), and the observable runtime signal is simply
  /// `renderHandle == null`.
  ///
  /// [audioOnly] 会透传给默认构造的 [MovaMpvKernel]，使其不建立视频管线；当显式
  /// 传入 [kernel] 时它不起作用——注入的内核一律原样使用。这里刻意不提供
  /// `MovaState.audioOnly`，也不为它新增 `MovaOpts` 配置节：这是构造期的资源
  /// 决策（内核的渲染句柄一次绑定、永不重绑），而运行期可观测的信号就是
  /// `renderHandle == null` 本身。
  ///
  /// [fit] is the initial `MovaState.fit`, [MovaFit.contain] by default. It is a
  /// starting value, not a lock — `setFit()` and the fit button still change it
  /// at runtime, and no [MovaFitChange] is emitted for it.
  ///
  /// [fit] 是初始的 `MovaState.fit`，默认 [MovaFit.contain]。只是初值不是锁定——
  /// 运行时 `setFit()` 与 fit 按钮照常可改，也不会为它发 [MovaFitChange]。
  MovaEngine({
    MovaKernel? kernel,
    bool audioOnly = false,
    this.options = const MovaOpts(),
    List<MovaHook> interceptors = const [],
    MovaBrightPort? brightness,
    MovaVolumePort? volume,
    MovaPipPort? pip,
    MovaOrientationPort? orientation,
    MovaThumbDirProvider? thumbDir,
    MovaFramePuller? extractor,
    MovaHttpFetch? fetcher,
    MovaReporter? reporter,
    MovaFit fit = MovaFit.contain,
  }) : _state = MovaBus<MovaState>(MovaState(fit: fit)),
       _kernel =
           kernel ??
           MovaMpvKernel(
             audioOnly: audioOnly,
             lazyVideo: true,
             observeQoeSignals: reporter != null,
           ),
       _audioOnly = audioOnly,
       _extractor = extractor, // ignore: prefer_initializing_formals
       _fetcher = fetcher ?? MovaIoHttpFetcher(),
       _chain = MovaHookChain(interceptors),
       _brightness = brightness ?? MovaFallbackBrightnessPort(),
       _volume = volume, // ignore: prefer_initializing_formals
       _pip = pip ?? MovaNoopPipPort(),
       _orientation = orientation ?? MovaNoopOrientationPort(),
       _reporter =
           reporter // ignore: prefer_initializing_formals
           {
    _abrPolicy =
        options.abr.policy ??
        MovaBufferAbr(threshold: options.abr.stallThreshold);
    // throttleStream's own controller is already broadcast (see its doc
    // comment for why that matters), so no further wrapping is needed here.
    //
    // throttleStream 内部的 controller 本身就是广播型（原因见其文档注释），
    // 这里不需要再包一层。
    _progress = throttleStream(
      _progressRaw.stream,
      const Duration(milliseconds: 200),
    );
    _sttService = MovaSttService(config: options.stt, onBlocked: _onSttBlocked);
    final rec = options.recovery;
    if (rec.enabled) {
      rec.assertValid();
      _watchdog = MovaPlayWatchdog(
        startTimeout: rec.startTimeout,
        stallTimeout: rec.stallTimeout,
        onTimeout: (kind, waited) => _onPlayFail(kind, waited: waited),
      );
    }

    options.standby.assertValid();

    _playingSub = _kernel.playing.listen((v) {
      _state.emit(state.copyWith(playing: v));
      _events.add(v ? const MovaPlay() : const MovaPause());
    });
    _bufferingSub = _kernel.buffering.listen((v) {
      _state.emit(state.copyWith(buffering: v));
      _events.add(MovaBufferChange(v));
      _handleAbrBuffering(v);
      _maybeAutoBackToLive(v);
      _watchdog?.onBuffering(v);
      _feedGate(() => _frameGate.onBuffering(v, nativeLive: _nativeLive));
    });
    _completedSub = _kernel.completed.listen((v) {
      _state.emit(state.copyWith(completed: v));
      if (v) _events.add(const MovaDone());
      if (v &&
          state.type == MovaStreamType.live &&
          options.recovery.liveEndIsFailure) {
        _onPlayFail(MovaPlayFailKind.liveEnded);
      }
    });
    _positionSub = _kernel.position.listen((v) {
      // While a seek is settling, the kernel keeps echoing stale
      // pre-seek positions for a moment before it actually catches up —
      // reporting those would flash the UI back to the old spot right after
      // a seek, then snap forward once the real position lands. Suppress
      // anything that isn't yet close to the pending target; the first
      // update that is releases the suppression, so a second seek fired
      // before the first settles is never blocked.
      //
      // seek 结算期间，内核会先回声几次旧位置才真正追上——原样上报会导致刚
      // seek 完 UI 先闪回旧位置，等真实位置到达才猛地跳过去。在到达目标附近
      // 之前，一律抑制上报；第一次足够接近目标的更新会解除抑制，因此在前一次
      // 尚未结算时又发起的第二次 seek 不会被卡住。
      final target = _pendingSeekTarget;
      if (target != null) {
        if ((v - target).abs() > _seekSettleTolerance) return;
        _pendingSeekTarget = null;
      }
      _lastPosition = v;
      _updateTimeshift(v);
      _sttService.updatePosition(v);
      _qoe?.onPosition(v);
      _progressRaw.add(MovaProg(position: v, buffer: _lastBuffer));
      _feedGate(() => _frameGate.onProgress(v, nativeLive: _nativeLive));
    });
    _bufferSub = _kernel.buffer.listen((v) {
      _lastBuffer = v;
      _progressRaw.add(MovaProg(position: _lastPosition, buffer: v));
    });
    _durationSub = _kernel.duration.listen((v) {
      _state.emit(state.copyWith(duration: v));
      _events.add(MovaDurationChange(v));
      _recomputeLiveSeekable();
      unawaited(_applyParkedSeek(v));
    });
    _sizeSub = _kernel.size.listen((v) {
      _state.emit(state.copyWith(width: v.width, height: v.height));
      _events.add(MovaSizeChange(v.width, v.height));
      // Re-derive/apply fullscreen orientation if dimensions arrive (or
      // change) while already fullscreen — e.g. a network/HLS source whose
      // real size wasn't known yet when fullscreen was entered.
      //
      // 若在已处于全屏状态下尺寸才到达（或发生变化）——例如打开全屏时网络/
      // HLS 源的真实尺寸尚未知晓——则重新推导并应用全屏方向。
      if (state.fullscreen) {
        unawaited(_applyOrientation());
      }
      _feedGate(
        () => _frameGate.onSize(v.width, v.height, nativeLive: _nativeLive),
      );
    });
    _errorSub = _kernel.error.listen((e) {
      _state.emit(state.copyWith(error: e));
      _events.add(MovaErrorEvent(e));
      _chain.onError(e, StackTrace.current);
    });
    final restartKernel = _kernel;
    if (restartKernel is MovaStatsProbe) {
      _restartSub = (restartKernel as MovaStatsProbe).playbackRestarts.listen((
        _,
      ) {
        _feedGate(_frameGate.onRestart);
      });
      if (rec.enabled) {
        _endFileSub = (restartKernel as MovaStatsProbe).endFiles.listen((r) {
          if (r == MovaEndFileReason.error) {
            _onPlayFail(MovaPlayFailKind.nativeEndError);
          }
        });
      }
    }
    _previewService = _buildPreview(
      thumbDir: thumbDir,
      extractor: _extractor,
      fetcher: _fetcher,
    );
    final reporterPort = _reporter;
    if (reporterPort != null) {
      final probe = _kernel;
      _qoe = MovaQoeCollector(
        events: _events.stream,
        reporter: reporterPort,
        config: options.report,
        probe: probe is MovaStatsProbe ? probe as MovaStatsProbe : null,
      );
    }
    // Probe pip support once. The UI hides the pip button until this answers,
    // which is why a failed probe must resolve to false rather than throw.
    //
    // 探测一次画中画支持情况。UI 在它返回前隐藏画中画按钮，因此探测失败必须
    // 归约为 false，而不能抛出。
    unawaited(
      _pip
          .isSupported()
          .then((ok) {
            if (_events.isClosed) return;
            _state.emit(state.copyWith(pipSupported: ok));
          })
          .catchError((Object _) {}),
    );
    // Seed state.volume from the real system volume so the volume gesture's
    // baseline is accurate (and has headroom above the default 100). No-op
    // when no volume port is wired (player-volume path keeps the 100 default).
    //
    // 从真实系统音量播种 state.volume，使音量手势基线准确（且在默认 100 之上
    // 留出上调空间）。未接音量端口时空操作（播放器音量路径保持 100 默认）。
    final volumePort = _volume;
    if (volumePort != null) {
      unawaited(
        volumePort
            .get()
            .then((v) {
              if (_events.isClosed) return;
              _state.emit(state.copyWith(volume: v.clamp(0, 100)));
            })
            .catchError((Object _) {}),
      );
    }
  }

  /// Whether the kernel's native restart subscription is live right now.
  ///
  /// 内核的原生 RESTART 订阅此刻是否在工作。
  bool get _nativeLive {
    final k = _kernel;
    return k is MovaStatsProbe && (k as MovaStatsProbe).nativeRestartAvailable;
  }

  /// Wraps every kernel open so the gate ignores stale signals meanwhile.
  ///
  /// 包住每一次内核 open，使闸门在途期间忽略陈旧信号。
  Future<bool> _loadKernel(String uri, {required bool play}) async {
    final session = _sessionGen;
    final attempt = _attemptId;
    bool current() =>
        !_disposed && session == _sessionGen && attempt == _attemptId;
    _kernelOpening++;
    _watchdog?.disarm();
    Object? failure;
    try {
      await _kernel.open(uri, play: play);
    } catch (e) {
      if (_watchdog == null) rethrow;
      failure = e;
    } finally {
      _kernelOpening--;
    }
    if (!current()) return false;
    if (failure != null) {
      _onPlayFail(MovaPlayFailKind.openThrew, error: failure);
      return false;
    }
    if (!_playIntent && play) {
      await _kernel.pause();
      if (!current()) return false;
    }
    if (_kernelOpening == 0) _watchdog?.armStart(playing: _playIntent);
    // A paused load's size signal may arrive before open returns. Re-feed
    // known dimensions defensively; real-device confirmation is Task 16.
    //
    // 暂停加载的尺寸信号可能早于 open 返回；防御性补喂已知尺寸，真机待 Task 16 验证。
    if (!play) {
      _feedGate(
        () => _frameGate.onSize(
          state.width,
          state.height,
          nativeLive: _nativeLive,
        ),
      );
    }
    return true;
  }

  /// Arms a fresh first-frame attempt without touching [MovaState.rendered].
  ///
  /// 武装一次新的首帧尝试，不动 [MovaState.rendered]。
  void _armAttempt({required bool autoPlay}) {
    _recoverTimer?.cancel();
    _recoverTimer = null;
    _attemptId++;
    _graceTimer?.cancel();
    _graceTimer = null;
    _frameGate.arm(autoPlay: autoPlay);
  }

  /// Feeds one observation to the gate, starting the grace timer if asked to.
  ///
  /// 向闸门喂一次观测；闸门要求时起宽限计时器。
  void _feedGate(MovaFirstFrameSignal? Function() observe) {
    if (_disposed || _kernelOpening > 0 || _events.isClosed) return;
    final landed = observe();
    if (landed != null) return _onAttemptLanded(landed);
    if (_frameGate.awaitingGrace && _graceTimer == null) {
      _graceTimer = Timer(_firstFrameGrace, () {
        _graceTimer = null;
        _feedGate(_frameGate.onGraceExpired);
      });
    }
  }

  /// Marks the source as rendered (once per `open()`) and announces it.
  ///
  /// 把当前源标记为已呈现（每次 `open()` 一次）并对外宣布。
  void _onAttemptLanded(MovaFirstFrameSignal signal) {
    _graceTimer?.cancel();
    _graceTimer = null;
    if (state.standby == MovaStandbyPhase.resuming) _finishResume(signal);
    // A landing that arrives for an attempt already declared failed (the retry
    // is pending) must not reset the failure counters.
    //
    // 对已被判失败的尝试（重试正在等待）才姗姗来迟的落地，不能清零失败计数。
    if (_watchdog != null && _failedAttemptId != _attemptId) {
      _recoveryPosition = null;
      _watchdog!.onLanded();
      if (_streak > 0) {
        _events.add(MovaRecovered(_streak));
        _streak = 0;
        _addrFailures.clear();
      }
    }
    if (state.rendered) return;
    _state.emit(state.copyWith(rendered: true));
    final at = _openedAt;
    _events.add(
      MovaFirstFrame(
        sinceOpen: at == null ? Duration.zero : DateTime.now().difference(at),
        signal: signal,
      ),
    );
  }

  /// Latest known buffered position, tracked alongside [_lastPosition] so a
  /// `buffer` callback doesn't clobber the last known `position` (and vice
  /// versa) when pushing a combined [MovaProg] snapshot.
  ///
  /// 与 [_lastPosition] 一并维护的最近已知缓冲位置，避免 `buffer` 回调覆盖
  /// 最近的 `position`（反之亦然）——用于推送合并后的 [MovaProg] 快照。
  Duration _lastBuffer = Duration.zero;

  /// One-time global engine init; forwards to [MovaMpvKernel.ensureInitialized].
  /// Call before constructing any [MovaEngine].
  ///
  /// 全局一次性 engine 初始化；转发给 [MovaMpvKernel.ensureInitialized]。创建任何
  /// [MovaEngine] 前调用。
  static void ensureInitialized() => MovaMpvKernel.ensureInitialized();

  @override
  Stream<MovaEvent> get events => _events.stream;

  @override
  Stream<MovaState> get states => _state.stream;

  @override
  Stream<MovaProg> get progress => _progress;

  @override
  Stream<MovaUiState> get uiStates => _ui.stream;

  @override
  MovaState get state => _state.value;

  @override
  MovaUiState get uiState => _ui.value;

  @override
  MovaPreviewApi get preview => _previewService;

  @override
  MovaSttApi get stt => _sttService;

  /// Assembles the preview service from [MovaOpts.preview] plus the
  /// platform-side pieces the host injected.
  ///
  /// Every injection point in [MovaPreviewConfig] wins over the built-in
  /// default; a missing platform piece degrades that one capability instead of
  /// disabling preview outright.
  ///
  /// 依据 [MovaOpts.preview] 与宿主注入的平台侧零件装配预览服务。
  ///
  /// [MovaPreviewConfig] 里的每个注入点都优先于内置默认；缺失某个平台零件只会
  /// 让该项能力降级，而不会整体关闭预览。
  ///
  /// - [thumbDir]: disk-cache directory resolver / 磁盘缓存目录解析器
  /// - [extractor]: frame extractor / 抽帧器
  /// - [fetcher]: HTTP fetcher for VTT tracks and sprites / 拉取 VTT 轨与
  ///   雪碧图的 HTTP 客户端
  ///
  /// Returns the assembled service.
  ///
  /// 返回装配好的服务。
  MovaPreviewService _buildPreview({
    MovaThumbDirProvider? thumbDir,
    MovaFramePuller? extractor,
    MovaHttpFetch? fetcher,
  }) {
    final cfg = options.preview;
    final dir =
        cfg.dirProvider ??
        (cfg.diskDir != null
            ? MovaFixedThumbDirProvider(cfg.diskDir!)
            : thumbDir);
    final cache =
        cfg.cache ??
        (dir == null
            ? MovaMemoryThumbCache(maxEntries: cfg.memMaxEntries)
            : MovaTwoLevelCache(
                memory: MovaMemoryThumbCache(maxEntries: cfg.memMaxEntries),
                disk: MovaDiskThumbCache(dir: dir, maxBytes: cfg.diskMaxBytes),
              ));
    return MovaPreviewService(
      config: cfg,
      cache: cache,
      probe: cfg.probe ?? MovaAlwaysAllowNetProbe(),
      sources: cfg.sources ?? _defaultThumbSources(cfg, extractor, fetcher),
      onBlocked: _onPreviewBlocked,
    );
  }

  /// Builds the built-in `[vtt, extract]` source chain, honouring
  /// [MovaPreviewConfig.vttEnabled], [MovaPreviewConfig.extractFallback] and
  /// [MovaPreviewConfig.extractPlatforms].
  ///
  /// 构建内置的 `[vtt, extract]` 来源链，遵循 [MovaPreviewConfig.vttEnabled]、
  /// [MovaPreviewConfig.extractFallback] 与 [MovaPreviewConfig.extractPlatforms]。
  ///
  /// - [cfg]: the preview configuration / 预览配置
  /// - [extractor]: host-injected frame extractor / 宿主注入的抽帧器
  /// - [fetcher]: host-injected HTTP fetcher / 宿主注入的 HTTP 客户端
  ///
  /// Returns the ordered source chain, possibly empty.
  ///
  /// 返回有序的来源链，可能为空。
  List<MovaThumbSource> _defaultThumbSources(
    MovaPreviewConfig cfg,
    MovaFramePuller? extractor,
    MovaHttpFetch? fetcher,
  ) {
    final chain = <MovaThumbSource>[];
    if (cfg.vttEnabled) {
      final fixed = cfg.vttUrl;
      chain.add(
        MovaVttThumbSource(
          fetcher: fetcher ?? MovaIoHttpFetcher(),
          resolveUrl:
              cfg.vttUrlResolver ??
              (fixed == null ? defaultVttUrl : (_) => Uri.tryParse(fixed)),
        ),
      );
    }
    final ex = cfg.extractor ?? extractor;
    if (cfg.extractFallback &&
        ex != null &&
        cfg.extractPlatforms.contains(currentPlatformKind())) {
      chain.add(
        MovaPullerThumbSource(
          extractor: ex,
          width: cfg.frameWidth,
          hwdec: cfg.hwdec,
        ),
      );
    }
    return chain;
  }

  /// Publishes a preview refusal on [events] and forwards it to the
  /// host callback.
  ///
  /// 把一次预览拒绝发布到 [events] 上，并转发给宿主回调。
  ///
  /// - [reason]: why the request was refused / 被拒原因
  void _onPreviewBlocked(MovaPreviewBlockReason reason) {
    if (!_events.isClosed) _events.add(MovaPreviewBlock(reason));
    final cb = options.preview.onBlocked;
    if (cb == null) return;
    try {
      cb(reason);
    } on Object {
      // A host callback must never break the engine.
      //
      // 宿主回调绝不能打断 engine。
    }
  }

  /// Publishes an STT start refusal on [events] and forwards it to the host
  /// callback.
  ///
  /// 把一次 STT 启动拒绝发布到 [events] 上，并转发给宿主回调。
  ///
  /// - [reason]: why the request was refused / 被拒原因
  void _onSttBlocked(MovaSttBlockReason reason) {
    if (!_events.isClosed) _events.add(MovaSttBlock(reason));
    final cb = options.stt.onBlocked;
    if (cb == null) return;
    try {
      cb(reason);
    } on Object {
      // A host callback must never break the engine.
      //
      // 宿主回调绝不能打断 engine。
    }
  }

  @override
  Future<void> open(MovaSource source, {bool autoPlay = true}) async {
    // Claim this call's generation before the first await: if another open()
    // call is made while this one is suspended below, that later call bumps
    // _openGen again and this call notices it has been superseded the moment
    // it wakes up.
    //
    // 在第一个 await 之前认领本次调用的世代号：若本次调用在下面挂起期间又有
    // 另一次 open() 被调用，那次调用会再次推进 _openGen，本次调用一醒来就能
    // 察觉自己已被取代。
    final gen = ++_openGen;
    final allowed = await _chain.beforeOpen(source);
    if (!allowed || gen != _openGen) return;
    _recoverTimer?.cancel();
    _recoverTimer = null;
    final session = ++_sessionGen;
    _recoveryPosition = null;
    _state.emit(state.copyWith(playbackIntent: autoPlay));
    _addrFailures.clear();
    _streak = 0;
    _readyAnnounced = false;
    _failedAttemptId = -1;
    _sourceIndex = 0;
    // 通过 beforeOpen 门禁、且未被更晚一次 open() 取代之后才标记 QoE 会话
    // 边界——否则被拒绝/被取代的 open() 调用会污染上报，产生从未真正播放过
    // 的幽灵 sessionStart/sessionEnd。
    _qoe?.onTeardown();
    _qoe?.onOpen(
      source,
      autoPlay: autoPlay,
      audioOnly: _audioOnly,
      swapEnabled: options.swap.enabled,
    );
    _source = source;
    // Forget everything the *previous* media reported, so [seek]'s "park or
    // send now" decision is deterministic: a seek issued right after open()
    // must always park, or mpv wedges the player — real-device measured on
    // STG AL00 (position never leaves 0, even dispose() hangs). Full
    // real-device investigation notes: CLAUDE.md's seamless-swap verification
    // section.
    //
    // 把*上一条*素材报告过的一切忘掉，使 [seek] 里"寄存还是立刻下发"的判断
    // 变确定：紧跟 open() 之后的 seek 必须一律寄存，否则 mpv 会把播放器卡死
    // ——真机实测 STG AL00（position 永远停在 0，连 dispose() 都挂住）。完整
    // 真机排查记录见 CLAUDE.md 的无缝切换真机验证一节。
    _forgetMediaProgress();
    _previewService.attach(source);
    _sttService.attach(source);
    _abrPolicy.reset();
    _state.emit(
      state.copyWith(
        qualities: const [],
        type: source.type,
        sourceTitle: source.title,
        duration: Duration.zero,
        clearQuality: true,
        clearError: true,
        clearSourceTitle: source.title == null,
        rendered: false,
        width: 0,
        height: 0,
        sourceIndex: 0,
      ),
    );
    _openedAt = DateTime.now();
    _armAttempt(autoPlay: autoPlay);
    if (!await _loadKernel(source.uri, play: _playIntent)) return;
    if (session != _sessionGen || _disposed) return;
    _announceReady();
  }

  /// Finishes a session's first successful kernel load: recomputes live
  /// seekability, settles the control bar, and announces [MovaSourceChange] +
  /// [MovaReady] — once per `open()`, however many retries it took.
  ///
  /// 完成一次会话中第一次成功的内核加载：重算直播可拖动性、安顿控制条，并发出
  /// [MovaSourceChange] + [MovaReady]——每次 `open()` 只发一次，不论中间重试了几次。
  void _announceReady() {
    if (_readyAnnounced) return;
    _readyAnnounced = true;
    _recomputeLiveSeekable();
    // `MovaCtrlsConfig.showOnStart` previously had no effect: nothing ever
    // called `showControls()` on load, so the auto-hide timer never armed and
    // the bar just sat visible until a first tap (which, since
    // `controlsVisible` already defaulted to true, immediately hid it instead
    // of arming the timer). Routing through `showControls()`/`hideControls()`
    // here — instead of emitting `uiState` directly — makes sure the timer is
    // armed exactly the same way a manual show would.
    //
    // `MovaCtrlsConfig.showOnStart`此前形同虚设：加载时从没人调过
    // `showControls()`,自动隐藏计时器压根没启动过,栏就一直显示到用户第一次
    // 点击（而由于 `controlsVisible` 默认已是 true,那一下点击是直接隐藏,而非
    // 启动计时器）。这里改走 `showControls()`/`hideControls()`（而非直接
    // emit `uiState`）,确保计时器的启动方式与手动 show 完全一致。
    if (options.controls.showOnStart) {
      showControls();
    } else {
      hideControls();
    }
    // dispose() may close `_events` while this coroutine was suspended on the
    // awaits above — never add to a closed controller.
    //
    // 本协程挂起在上面这些 await 期间，dispose() 可能已经关闭了 `_events`——
    // 绝不能向已关闭的 controller 添加事件。
    if (_events.isClosed) return;
    final source = _source;
    if (source == null) return;
    _events.add(MovaSourceChange(source));
    _events.add(const MovaReady());
  }

  /// Handles one failed attempt: asks the policy, announces the decision, then
  /// schedules the retry/failover or gives up. No-op unless recovery is on.
  ///
  /// 处理一次失败的尝试：询问策略、宣布决策，再安排重试/切换或放弃。recovery 未开启时
  /// 为空操作。
  ///
  /// - [kind]: what failed / 失败的是什么
  /// - [error]: the underlying error, if any / 底层错误（若有）
  /// - [waited]: how long the attempt or stall lasted / 这次尝试或卡顿持续了多久
  void _onPlayFail(
    MovaPlayFailKind kind, {
    Object? error,
    Duration waited = Duration.zero,
  }) {
    final wd = _watchdog;
    final src = _source;
    if (wd == null || src == null || _disposed || _events.isClosed) return;
    if (_kernelOpening > 0) return;
    // One attempt fails once: a timeout may be followed by a native error for
    // the very same attempt.
    //
    // 一次尝试只失败一次：超时之后同一次尝试可能还会收到原生错误。
    if (_failedAttemptId == _attemptId) return;
    _recoveryPosition ??= state.type == MovaStreamType.vod && state.rendered
        ? _lastPosition
        : Duration.zero;
    _failedAttemptId = _attemptId;
    wd.disarm();
    final idx = _sourceIndex;
    final fail = MovaPlayFail(
      kind: kind,
      sourceIndex: idx,
      uri: _activeUri,
      sourceCount: src.uris.length,
      attempt: _addrFailures[idx] = (_addrFailures[idx] ?? 0) + 1,
      streak: ++_streak,
      afterFirstFrame: state.rendered,
      waited: waited,
      error: error,
    );
    var d = _decide(fail);
    if (d.action == MovaRecoveryAction.failover && !fail.hasNextSource) {
      d = const MovaRecoveryDecision.giveUp();
    }
    _events.add(MovaPlayFailure(fail, d.action));
    switch (d.action) {
      case MovaRecoveryAction.retry:
        _scheduleRecover(idx, d.delay, fail);
      case MovaRecoveryAction.failover:
        _scheduleRecover(idx + 1, d.delay, fail);
      case MovaRecoveryAction.giveUp:
        _giveUp(fail);
    }
  }

  /// Asks the effective policy; a throwing host policy counts as give-up so it
  /// can never break the engine.
  ///
  /// 询问生效的策略；宿主策略抛异常按放弃处理，绝不打断引擎。
  MovaRecoveryDecision _decide(MovaPlayFail fail) {
    try {
      return options.recovery.effectivePolicy.onFailure(fail);
    } on Object {
      return const MovaRecoveryDecision.giveUp();
    }
  }

  /// Schedules [_recover] after [delay], replacing any pending one.
  ///
  /// 延迟 [delay] 后执行 [_recover]，替换已有的待执行项。
  void _scheduleRecover(int index, Duration delay, MovaPlayFail cause) {
    final gen = _sessionGen;
    final attempt = _attemptId;
    _recoverTimer?.cancel();
    _recoverTimer = Timer(delay, () {
      _recoverTimer = null;
      if (attempt == _attemptId) unawaited(_recover(index, cause, gen));
    });
  }

  /// Reloads the kernel for a retry/failover. Not a new session: no
  /// interceptor, no [MovaSourceChange], QoE session untouched; a VOD source
  /// that had shown a frame resumes where it failed via [_seekOrPark].
  ///
  /// 为重试/切换重载内核。不是新会话：不过拦截器、不发 [MovaSourceChange]、不动 QoE
  /// 会话；失败前出过画面的点播源经 [_seekOrPark] 续播到失败位置。
  ///
  /// - [index]: address index to load / 要加载的地址下标
  /// - [cause]: the failure being recovered from / 正在恢复的那次失败
  /// - [gen]: the accepted session this recovery belongs to / 本次恢复所属的已接受会话世代
  Future<void> _recover(int index, MovaPlayFail cause, int gen) async {
    if (gen != _sessionGen || _disposed || _events.isClosed) return;
    final resumeAt = _recoveryPosition ?? Duration.zero;
    if (index != _sourceIndex) {
      // Switching address: the quality list belonged to the old address's
      // master playlist.
      //
      // 切换地址：清晰度列表属于旧地址的 master 播放列表。
      final from = _sourceIndex;
      _sourceIndex = index;
      _state.emit(
        state.copyWith(
          sourceIndex: index,
          qualities: const [],
          clearQuality: true,
        ),
      );
      _events.add(MovaFailover(from: from, to: index, uri: _activeUri));
    }
    _forgetMediaProgress();
    _abrPolicy.reset();
    _state.emit(state.copyWith(duration: Duration.zero));
    _armAttempt(autoPlay: _playIntent);
    if (!await _loadKernel(_activeUri, play: _playIntent)) return;
    if (gen != _sessionGen || _disposed || _events.isClosed) return;
    _announceReady();
    if (resumeAt > Duration.zero) await _seekOrPark(resumeAt);
  }

  /// Recovery is exhausted: surface [MovaGiveUpError] through state, the event
  /// stream and the interceptor chain, and pause the kernel so a dead live
  /// source does not keep reconnecting in the background.
  ///
  /// recovery 已耗尽：经 state、事件流与拦截链暴露 [MovaGiveUpError]，并暂停内核，
  /// 避免失效的直播源在后台一直重连。
  void _giveUp(MovaPlayFail fail) {
    final err = MovaGiveUpError(fail);
    _state.emit(state.copyWith(error: err));
    _events.add(MovaErrorEvent(err));
    _chain.onError(err, StackTrace.current);
    unawaited(_kernel.pause().catchError((Object _) {}));
  }

  @override
  Future<MovaStandbyPhase> setStandby(bool on) {
    // Recorded synchronously so a play()/open() queued behind this call sees it.
    //
    // 同步记下，使排在本调用之后的 play()/open() 能看到。
    _standbyRequested = on;
    return _enqueueStandby(() => on ? _enterStandby(viaPlay: false) : _leaveStandby());
  }

  /// Tries to enter standby. [viaPlay] means it was triggered by `play()` (or a
  /// reloaded source landing) while a request stands: decide as if the intent
  /// were true, and never pause — the caller plays only when this returns
  /// [MovaStandbyPhase.holding].
  ///
  /// 尝试进入待机。[viaPlay] 表示请求存在期间由 `play()`（或换源落地）触发：按意图为
  /// true 判定，且从不暂停——只有返回 [MovaStandbyPhase.holding] 时调用方才播放。
  Future<MovaStandbyPhase> _enterStandby({required bool viaPlay}) async {
    if (_disposed || !_standbyRequested) return state.standby;
    final k = _standbyKernel;
    MovaStandbyMedia? media;
    if (k != null) {
      try {
        media = await k.inspectStandby();
      } on Object {
        media = null;
      }
      if (_disposed || !_standbyRequested) return state.standby;
    }
    final current = state.standby;
    final entry = decideStandbyEntry(
      phase: viaPlay ? MovaStandbyPhase.off : current,
      intent: viaPlay || _playIntent,
      exempt: state.pip || state.mini,
      type: state.type,
      recovering: _recoveryPending,
      kernelCapable: k != null,
      media: media,
      config: options.standby,
    );
    switch (entry.kind) {
      case MovaStandbyEntryKind.skip:
        return state.standby;
      case MovaStandbyEntryKind.fallback:
        _cancelRecovery();
        _cancelResume();
        if (viaPlay && current == MovaStandbyPhase.fallback) return current;
        if (!viaPlay) await _kernel.pause();
        _setStandbyPhase(MovaStandbyPhase.fallback, entry.reason);
        return state.standby;
      case MovaStandbyEntryKind.hold:
        _cancelRecovery();
        _cancelResume();
        final ok = await k!.enterStandby(entry.mode!);
        if (_disposed) return MovaStandbyPhase.off;
        if (!ok) {
          if (!viaPlay) await _kernel.pause();
          _setStandbyPhase(MovaStandbyPhase.fallback, MovaStandbyReason.unsupported);
          return state.standby;
        }
        _standbyMode = entry.mode;
        _watchdog?.disarm();
        _standbyTimer?.cancel();
        _standbyTimer = Timer(options.standby.maxDuration, _expireStandby);
        _setStandbyPhase(
          MovaStandbyPhase.holding,
          MovaStandbyReason.requested,
          mode: entry.mode,
        );
        return state.standby;
    }
  }

  /// `maxDuration` elapsed: stop first, then restore properties while paused.
  ///
  /// 到了 `maxDuration`：先停播，再在暂停态还原属性。
  void _expireStandby() {
    _standbyTimer = null;
    unawaited(
      _enqueueStandby(() => _degradeStandby(MovaStandbyReason.maxDuration)),
    );
  }

  /// holding -> fallback([reason]): pause, then undo the kernel hold. No-op in
  /// any other phase.
  ///
  /// holding -> fallback([reason])：先暂停，再撤销内核待机。其他阶段为空操作。
  Future<void> _degradeStandby(MovaStandbyReason reason) async {
    if (_disposed || state.standby != MovaStandbyPhase.holding) return;
    _standbyTimer?.cancel();
    _standbyTimer = null;
    await _kernel.pause();
    await _standbyKernel?.exitStandby();
    _standbyMode = null;
    _setStandbyPhase(MovaStandbyPhase.fallback, reason);
  }

  /// Drops a pending resume measurement (hidden again, or the host took over).
  ///
  /// 丢弃待完成的恢复测量（又被隐藏，或宿主接管）。
  void _cancelResume() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (_resumeGateArmed) _frameGate.reset();
    _resumeGateArmed = false;
  }

  /// Wakes from standby: undoes a hold, or resumes/reconnects a fallback pause,
  /// as [decideStandbyWake] decides.
  ///
  /// 从待机唤醒：撤销待机，或续播/重连 fallback 暂停——由 [decideStandbyWake] 决定。
  Future<MovaStandbyPhase> _leaveStandby() async {
    final phase = state.standby;
    final since = _standbySince;
    final wake = decideStandbyWake(
      phase: phase,
      intent: _playIntent,
      type: state.type,
      cause: _fallbackCause,
      pausedFor: since == null ? Duration.zero : debugClock().difference(since),
      config: options.standby,
    );
    switch (wake) {
      case MovaStandbyWake.none:
        return phase;
      case MovaStandbyWake.restore:
        _standbyTimer?.cancel();
        _standbyTimer = null;
        final from = _standbyMode;
        _standbyMode = null;
        _beginResume(from: from);
        // Arm before writing properties: the size event can arrive while the
        // `mute` write is still awaited.
        //
        // 先武装、再写属性：尺寸事件可能在 `mute` 写入的 await 期间就到达。
        if (from == MovaStandbyMode.muted) _armResumeGate();
        final restarted = await (_standbyKernel?.exitStandby() ?? Future<bool>.value(false));
        if (_disposed) return MovaStandbyPhase.off;
        _resumeWatch();
        if (!restarted) _finishResume(null);
        return state.standby;
      case MovaStandbyWake.settle:
        _setStandbyPhase(MovaStandbyPhase.off, MovaStandbyReason.woke);
        return state.standby;
      case MovaStandbyWake.resumePlay:
        _setStandbyPhase(MovaStandbyPhase.off, MovaStandbyReason.woke);
        await _kernel.play();
        _resumeWatch();
        return state.standby;
      case MovaStandbyWake.reloadEdge:
        _beginResume(from: null);
        _armAttempt(autoPlay: true);
        final reopened = await _backToLiveEdge();
        if (_disposed) return MovaStandbyPhase.off;
        if (!state.playing) await _kernel.play();
        if (!reopened) _resumeWatch();
        _state.emit(state.copyWith(clearTimeshift: true));
        _events.add(const MovaLiveEdgeReach());
        return state.standby;
      case MovaStandbyWake.reopen:
        _beginResume(from: null);
        await _reopenLiveSource();
        return state.standby;
    }
  }

  /// Enters [MovaStandbyPhase.resuming] and starts the [MovaStandbyConfig.resumeTimeout]
  /// clock.
  ///
  /// 进入 [MovaStandbyPhase.resuming] 并起 [MovaStandbyConfig.resumeTimeout] 计时。
  ///
  /// - [from]: the hold mode woken from, null for a fallback pause / 从哪种待机组合醒来，fallback 暂停为 null
  void _beginResume({required MovaStandbyMode? from}) {
    _resumeAt = debugClock();
    _resumeFrom = from;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(options.standby.resumeTimeout, () {
      _resumeTimer = null;
      if (_resumeGateArmed) _frameGate.reset();
      _finishResume(MovaFirstFrameSignal.grace);
    });
    _setStandbyPhase(MovaStandbyPhase.resuming, MovaStandbyReason.woke, mode: from);
  }

  /// Arms the first-frame gate in resume mode (a fresh frame, nothing else).
  ///
  /// 以恢复模式武装首帧闸门（只认新画面，别的都不算）。
  void _armResumeGate() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _frameGate.arm(autoPlay: true, resume: true);
    _resumeGateArmed = true;
  }

  /// Ends a wake-up: reports how long it took and returns to off. No-op unless
  /// resuming.
  ///
  /// 结束一次唤醒：报告耗时并回到 off。不在 resuming 时为空操作。
  ///
  /// - [signal]: what landed it; null when decoding never stopped / 由什么落地；解码从未停过为 null
  void _finishResume(MovaFirstFrameSignal? signal) {
    if (state.standby != MovaStandbyPhase.resuming) return;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _resumeGateArmed = false;
    final at = _resumeAt;
    if (!_events.isClosed) {
      _events.add(
        MovaStandbyResume(
          elapsed: at == null ? Duration.zero : debugClock().difference(at),
          signal: signal,
          from: _resumeFrom,
        ),
      );
    }
    _setStandbyPhase(MovaStandbyPhase.off, MovaStandbyReason.resumed);
  }

  /// Back to normal monitoring after standby: the stall watch, with no start
  /// deadline, and a fresh ABR tally.
  ///
  /// 待机之后回到常规监视：卡顿看门狗、不再计起播期限，ABR 计数清零。
  void _resumeWatch() {
    _abrPolicy.reset();
    final wd = _watchdog;
    if (wd == null) return;
    wd
      ..armStart(playing: _playIntent)
      ..onLanded()
      ..onBuffering(state.buffering);
  }

  @override
  Future<void> play() async {
    final allowed = await _chain.beforePlay();
    if (!allowed) return;
    _state.emit(state.copyWith(playbackIntent: true));
    _watchdog?.onPlaying(true);
    // Standby: a held stream is already playing (muted, no picture), and while
    // a request stands a play() starts in standby instead of making a hidden
    // card audible. Untouched when standby was never requested.
    //
    // 待机：被待机的流本来就在播（静音无画）；请求存在期间 play() 以待机态开播，而不是让
    // 看不见的卡片出声。从未请求待机时这里一行都不走。
    final standbyPhase = state.standby;
    if (standbyPhase == MovaStandbyPhase.holding) return;
    if (_standbyRequested && standbyPhase != MovaStandbyPhase.resuming) {
      final p = await _enqueueStandby(() => _enterStandby(viaPlay: true));
      if (p == MovaStandbyPhase.holding) {
        await _kernel.play();
        return;
      }
      if (p == MovaStandbyPhase.fallback) return;
    }
    // A VOD source that has already reached the end sits paused on its last
    // frame; calling the kernel's `play()` alone leaves it there (there is
    // nothing left downstream of the current position to play), so the
    // progress bar looked frozen and nothing visibly "replayed". Live has no
    // meaningful end-of-stream position to rewind to, so this only applies
    // to VOD.
    //
    // 点播源播放到头后停在最后一帧；只调内核的 `play()` 什么都不会变（当前
    // 位置往后已经没有内容可播），进度条看起来就是卡死、也没有任何"重新
    // 播放"的可见效果。直播没有可回退的"播放完"位置，因此只对点播生效。
    if (state.completed && state.type == MovaStreamType.vod) {
      await _kernel.seek(Duration.zero);
    }
    await _kernel.play();
  }

  @override
  Future<void> pause() {
    _state.emit(state.copyWith(playbackIntent: false));
    _watchdog?.onPlaying(false);
    return _kernel.pause();
  }

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration to) async {
    final gate = state.type == MovaStreamType.vod || state.liveSeekable;
    if (!gate) return;
    final t = await _chain.beforeSeek(to);
    if (t == null) return;
    // For a seekable live stream the meaningful upper bound is the DVR
    // window, not `duration` — with an explicit dvrWindow/windowResolver the
    // kernel may report no duration at all.
    //
    // 对可拖动的直播流，有意义的上界是 DVR 窗口而非 `duration`——配置了显式
    // dvrWindow/windowResolver 时，内核可能根本不报告时长。
    final limit = state.type == MovaStreamType.live && state.liveSeekable
        ? state.seekableWindow
        : state.duration;
    final clamped = limit > Duration.zero
        ? Duration(
            milliseconds: t.inMilliseconds.clamp(0, limit.inMilliseconds),
          )
        : t;
    if (state.type == MovaStreamType.live &&
        options.live.seekMode == MovaLiveSeekMode.timeshift) {
      await _seekTimeshift(clamped);
      return;
    }
    // Every UI seek trigger — slider tap/drag, horizontal swipe, double-tap
    // step — funnels through here, so all of them share the same
    // park-or-seek decision and pinned-until-settled reporting.
    //
    // 所有 UI 触发 seek 的入口——进度条点击/拖动、横滑、双击步进——都汇入此处，
    // 因此共用同一套"寄存还是直发"判据与"钉住直到结算"的上报行为。
    await _seekOrPark(clamped, notify: true);
  }

  /// Issues a seek, or parks it when the media can't service one yet.
  ///
  /// The park branch is the whole point: a VOD source whose duration hasn't
  /// arrived cannot be sought — mpv not only drops the request, it wedges
  /// (measured on STG AL00, see [open]). Parking hands the target to
  /// [_applyParkedSeek], which replays it the moment the duration lands.
  /// Either way the target position is reported optimistically first, and
  /// [_pendingSeekTarget] suppresses the stale echoes that follow (see
  /// `_positionSub`).
  ///
  /// This is the single decision point shared by [seek] (the UI path, which
  /// wants [MovaSeek]/[MovaSeeked] events) and [switchQuality] (the
  /// resume-after-variant-reload path, which must not emit seek events).
  ///
  /// 下发一次 seek；若媒体尚无法服务 seek 则先寄存。
  ///
  /// 寄存分支才是重点：时长尚未到达的点播源无法 seek——mpv 不只是丢弃请求，
  /// 还会卡死（STG AL00 实测，见 [open]）。寄存把目标交给 [_applyParkedSeek]，
  /// 待时长到达即刻补发。两条分支都会先乐观上报目标位置，并由
  /// [_pendingSeekTarget] 抑制随后的陈旧回声（见 `_positionSub`）。
  ///
  /// 这是 [seek]（UI 路径，需要 [MovaSeek]/[MovaSeeked] 事件）与
  /// [switchQuality]（换档后续播路径，不该发 seek 事件）共用的唯一判据落点。
  ///
  /// - [to]: already-clamped target position / 已 clamp 的目标位置
  /// - [notify]: whether to emit [MovaSeek]/[MovaSeeked] / 是否发 seek 事件
  Future<void> _seekOrPark(Duration to, {bool notify = false}) async {
    final park =
        state.type == MovaStreamType.vod && state.duration <= Duration.zero;
    if (park) {
      _parkedSeek = to;
      _parkedNotify = notify;
    } else {
      _pendingSeekTarget = to;
    }
    _lastPosition = to;
    _progressRaw.add(MovaProg(position: to, buffer: _lastBuffer));
    if (notify) _events.add(MovaSeek(to));
    if (park) return;
    await _kernel.seek(to);
    if (notify) _events.add(MovaSeeked(to));
  }

  /// Forgets everything the *previous* media reported, so the park-or-seek
  /// decision in [_seekOrPark] is deterministic right after a kernel reload.
  /// Shared by [open] (new source) and [switchQuality] (same title, new
  /// variant).
  ///
  /// 把*上一条*素材报告过的一切忘掉，使内核重新加载后 [_seekOrPark] 的
  /// "寄存还是直发"判据是确定的。由 [open]（换源）与 [switchQuality]
  /// （同一部片换档）共用。
  void _forgetMediaProgress() {
    _pendingSeekTarget = null;
    _parkedSeek = null;
    _parkedNotify = false;
    _lastPosition = Duration.zero;
    _lastBuffer = Duration.zero;
  }

  /// Replays a [_parkedSeek] once the media first reports a real duration.
  /// Clears the park, clamps the target into the freshly known duration, and
  /// arms [_pendingSeekTarget] so the first post-seek position echo is trusted
  /// the same way a normal seek's is. No-op when nothing is parked.
  ///
  /// 在媒体首次报告真实时长后补发被寄存的 [_parkedSeek]。清空寄存，把目标钳入
  /// 刚知晓的时长，并布防 [_pendingSeekTarget]，使 seek 后第一个位置回声与普通
  /// seek 一样被信任。无寄存时为空操作。
  ///
  /// - [duration]: the just-reported media duration / 刚上报的媒体时长
  Future<void> _applyParkedSeek(Duration duration) async {
    final parked = _parkedSeek;
    if (parked == null || duration <= Duration.zero) return;
    _parkedSeek = null;
    final notify = _parkedNotify;
    _parkedNotify = false;
    final clamped = parked > duration ? duration : parked;
    _pendingSeekTarget = clamped;
    _lastPosition = clamped;
    _progressRaw.add(MovaProg(position: clamped, buffer: _lastBuffer));
    await _kernel.seek(clamped);
    // Same disposal race as [open]: dispose() may have run while the await
    // above was in flight.
    //
    // 与 [open] 同样的销毁竞态：上面的 await 期间 dispose() 可能已经跑过。
    if (_events.isClosed) return;
    if (notify) _events.add(MovaSeeked(clamped));
  }

  /// Performs a time-shift seek by reopening the stream at a host-built URL.
  ///
  /// Unlike DVR mode there is nothing to seek within: the live URL only ever
  /// serves the edge, so the only way to replay is to open a different URL
  /// carrying the desired start time. [MovaLiveConfig.urlBuilder] is the sole
  /// source of that URL — without it the mode is inert and this is a no-op,
  /// because guessing a server's time-shift parameter would silently open a
  /// wrong (or 404) stream.
  ///
  /// 通过用宿主构造的 URL 重开流来完成一次时移拖动。
  ///
  /// 与 DVR 模式不同，这里没有可供 seek 的内容：直播地址永远只提供边缘内容，
  /// 想回看就只能打开另一个携带目标起播时间的地址。[MovaLiveConfig.urlBuilder]
  /// 是该地址的唯一来源——没有它本模式不生效、本方法为空操作，因为猜测服务端
  /// 的时移参数只会静默打开一个错误（或 404）的流。
  ///
  /// - [target]: the clamped in-window target position / 已 clamp 的窗口内目标位置
  Future<void> _seekTimeshift(Duration target) async {
    final src = _source;
    final builder = options.live.urlBuilder;
    if (src == null || builder == null) return;
    final window = state.seekableWindow;
    final raw = window > target ? window - target : Duration.zero;
    final behind = Duration(seconds: raw.inSeconds);
    // Unlike _seekOrPark, this path doesn't fall through it, so it must set
    // _lastPosition itself — otherwise a seekBy() landing in the gap between
    // this call and the reopened stream's first real position tick computes
    // its delta from the stale pre-timeshift position instead of `target`.
    //
    // 与 _seekOrPark 不同，本路径不会经过它，因此必须自己设置
    // _lastPosition——否则 seekBy() 若落在本次调用与重开的流首个真实位置回调
    // 之间的空档，算出的增量会基于陈旧的时移前位置，而非 `target`。
    _lastPosition = target;
    _events.add(MovaSeek(target));
    _armAttempt(autoPlay: _playIntent);
    if (!await _loadKernel(
      builder(_activeUri, behind, DateTime.now()),
      play: _playIntent,
    )) {
      return;
    }
    if (behind <= options.live.edgeThreshold) {
      _state.emit(state.copyWith(clearTimeshift: true));
      _events.add(const MovaLiveEdgeReach());
    } else {
      _state.emit(state.copyWith(timeshiftBehind: behind));
      _events.add(MovaTimeShiftChange(behind));
    }
    _events.add(MovaSeeked(target));
  }

  @override
  Future<void> seekBy(Duration delta) => seek(_lastPosition + delta);

  @override
  Future<void> setVolume(double v) async {
    // Route to the volume port when wired (system media volume / host callback),
    // otherwise to the player's own volume via the kernel. Either way the
    // percentage is mirrored into state.volume for the HUD.
    //
    // 接了音量端口就走端口（系统媒体音量 / 宿主回调），否则经内核走播放器
    // 自身音量。无论哪条路，百分比都镜像进 state.volume 供 HUD 显示。
    final volumePort = _volume;
    if (volumePort != null) {
      await volumePort.set(v);
    } else {
      await _kernel.setVolume(v);
    }
    _state.emit(state.copyWith(volume: v));
    _events.add(MovaVolumeChange(v));
  }

  @override
  Future<void> setBrightness(double v) async {
    await _brightness.set(v);
    _state.emit(state.copyWith(brightness: v));
    _events.add(MovaBrightChange(v));
  }

  @override
  Future<void> setRate(double r) async {
    await _kernel.setRate(r);
    _state.emit(state.copyWith(rate: r));
    _events.add(MovaRateChange(r));
  }

  @override
  Future<void> setFit(MovaFit f) async {
    _state.emit(state.copyWith(fit: f));
    _events.add(MovaFitChange(f));
  }

  @override
  Future<void> setZoom(double z) async {
    _state.emit(state.copyWith(zoom: z));
    _events.add(MovaZoomChange(z));
  }

  @override
  Future<void> setLocked(bool v) async {
    _state.emit(state.copyWith(locked: v));
    _events.add(MovaLockChange(v));
  }

  @override
  Future<void> setFullscreen(bool v) async {
    _state.emit(state.copyWith(fullscreen: v));
    await _applyOrientation();
    _events.add(MovaFullScreenChange(v));
  }

  @override
  Future<void> setMini(bool v) async {
    if (state.mini == v) return; // 幂等，避免无谓事件
    if (v && state.fullscreen) await setFullscreen(false);
    _state.emit(state.copyWith(mini: v));
    _events.add(MovaMiniChange(v));
  }

  @override
  Future<void> setOrientation(MovaOrientation o) async {
    _state.emit(state.copyWith(orientation: o));
    await _applyOrientation();
    _events.add(MovaOrientationChange(o));
  }

  /// Applies the current fullscreen + forced-orientation state to the platform
  /// via [_orientation]. Immersive UI is tied to fullscreen; the forced
  /// [MovaState.orientation] overrides the aspect-ratio derivation.
  ///
  /// 把当前全屏 + 强制方向状态经 [_orientation] 应用到平台。沉浸式 UI 与全屏
  /// 绑定；强制的 [MovaState.orientation] 覆盖按宽高比的推导。
  Future<void> _applyOrientation() {
    return _orientation.apply(
      fullscreen: state.fullscreen,
      immersive: state.fullscreen,
      width: state.width,
      height: state.height,
      orientation: state.orientation,
    );
  }

  @override
  Future<void> loadQualities() async {
    final s = _source;
    final base = _activeUri;
    final session = _sessionGen;
    final index = _sourceIndex;
    bool current() =>
        !_disposed && session == _sessionGen && index == _sourceIndex;
    if (s == null || !base.toLowerCase().contains('.m3u8')) {
      _state.emit(state.copyWith(qualities: const [], clearQuality: true));
      return;
    }
    try {
      final bytes = await _fetcher.get(Uri.parse(base));
      if (!current()) return;
      if (bytes == null) {
        _state.emit(state.copyWith(qualities: const [], clearQuality: true));
        return;
      }
      final content = const Utf8Decoder().convert(bytes);
      final qs = parseHlsMasterPlaylist(content, base: Uri.parse(base));
      final cur = qs.isNotEmpty ? qs.first : null;
      _state.emit(
        state.copyWith(
          qualities: qs,
          currentQuality: cur,
          clearQuality: cur == null,
        ),
      );
      _events.add(MovaQualityListChange(qs));
      if (cur != null) _events.add(MovaQualityChange(cur));
    } catch (_) {
      if (!current()) return;
      _state.emit(state.copyWith(qualities: const [], clearQuality: true));
    }
  }

  /// Seamless variant switching is *not* wired here on purpose: swapping
  /// engines mid-stream is [MovaSwapEngine]'s job, and this method's
  /// semantics already map onto `swapTo(MovaSource(uri), at: position)`
  /// one-to-one. The only piece still missing when that day comes is
  /// carrying [MovaState.currentQuality] across the swap — the shadow engine
  /// starts with an empty quality list, so the promoted engine must be
  /// re-seeded with it. See doc/plans/2026-09-16-seamless-swap.md Task 8.
  ///
  /// 此处刻意*不*接无缝换档：流中途换引擎是 [MovaSwapEngine] 的职责，且本方法
  /// 的语义已与 `swapTo(MovaSource(uri), at: position)` 一一对应。真要做那天
  /// 唯一还缺的一块，是把 [MovaState.currentQuality] 带过切换——影子引擎起步时
  /// 清晰度列表为空，转正后必须重新播种。见
  /// doc/plans/2026-09-16-seamless-swap.md Task 8。
  @override
  Future<void> switchQuality(MovaQuality q) async {
    final playUri = q.isAuto ? _activeUri : q.uri;
    if (playUri.isEmpty) return;
    final pos = _lastPosition;
    final live = state.type == MovaStreamType.live;
    // Reloading a variant is a kernel `open()` just like a source change, so
    // it carries the exact same hazard: the resume seek that follows must
    // *not* go straight to `_kernel.seek()`, or mpv wedges (see [open]).
    // Forget the old media's progress and zero out `duration` first, which
    // makes [_seekOrPark] below deterministically park the resume position
    // until the new variant reports its own duration. Deliberately narrow:
    // no hook notification, no qualities/sourceTitle clearing, no
    // MovaSourceChange — this is the same title at another bitrate, not a new
    // source.
    //
    // 换档在内核侧同样是一次 `open()`，因此隐患完全相同：随后的续播 seek
    // 绝不能直接走 `_kernel.seek()`，否则 mpv 会卡死（见 [open]）。先忘掉旧
    // 素材的进度并把 `duration` 归零，使下面的 [_seekOrPark] 确定性地寄存续播
    // 位置，直到新档位报告自己的时长。刻意只做这么多：不通知 hook、不清空
    // qualities/sourceTitle、不发 MovaSourceChange——这是同一部片的另一个码率，
    // 不是换了一部新片。
    _forgetMediaProgress();
    // Drop the stall tally: the buffering burst a variant reload causes is
    // the reload's own cost, not evidence the network can't sustain the
    // current variant — without this a manual switch can trigger a
    // back-to-back ABR `open()` that discards the just-parked resume seek.
    // Safe for ABR's own path too (downshiftQuality → here): the default
    // [MovaBufferAbr] already zeroes its counter on a downshift signal, so
    // this only clears extra rising-edge memory, never swallows a downshift.
    // Real-device measurement (STG AL00, mux x36xhzz): CLAUDE.md's
    // seamless-swap verification section.
    //
    // 清掉卡顿计数：换档重载引起的那阵缓冲是重载自身的代价，不能当成"网络扛
    // 不住当前档位"的证据——不清的话手动换档可能触发 ABR 背靠背再发一次
    // `open()`，把刚寄存的续播 seek 冲掉。对 ABR 自己那条路径
    // （downshiftQuality → 本方法）也安全：默认 [MovaBufferAbr] 在发出降档
    // 信号时已把计数归零，这里只是额外清掉上升沿记忆，不会吞掉本该发生的降档。
    // 真机实测数据（STG AL00，mux x36xhzz）见 CLAUDE.md 的无缝切换真机验证一节。
    _abrPolicy.reset();
    _state.emit(state.copyWith(duration: Duration.zero, currentQuality: q));
    _armAttempt(autoPlay: _playIntent);
    if (!await _loadKernel(playUri, play: _playIntent)) return;
    // Announce the new variant as soon as the load command is issued: the
    // resume seek may be parked until the duration arrives, and delaying the
    // event until then would leave the UI showing the old label for seconds.
    //
    // 加载命令一下发就宣布新档位：续播 seek 可能要寄存到时长到达才生效，把
    // 事件拖到那时才发会让 UI 上的档位标签滞后好几秒。
    _events.add(MovaQualityChange(q));
    if (!live && pos > Duration.zero) await _seekOrPark(pos);
  }

  /// Steps down one variant (used by the ABR monitor). No-op in auto mode,
  /// at the lowest variant, or with fewer than two variants.
  ///
  /// 下降一档（供 ABR 监测调用）。自动模式、已是最低档或档位不足两个时无操作。
  Future<void> downshiftQuality() async {
    final cur = state.currentQuality;
    if (cur == null || cur.isAuto) return;
    final variants = state.qualities.where((q) => !q.isAuto).toList();
    final idx = variants.indexWhere((q) => q.uri == cur.uri);
    if (idx < 0 || idx + 1 >= variants.length) return;
    await switchQuality(variants[idx + 1]);
  }

  @override
  Future<bool> enterPip() async {
    // Mirrors setMini's fullscreen guard: system PiP and the in-app mini
    // window must never be active at the same time, or their surfaces
    // overlap.
    //
    // 与 setMini 的全屏守卫对称：系统 PiP 与 App 内小窗不能同时生效，否则两个
    // 渲染面会叠在一起。
    if (state.mini) await setMini(false);
    final ok = await _pip.enter(width: state.width, height: state.height);
    _state.emit(state.copyWith(pip: ok));
    _events.add(MovaPipChange(ok));
    return ok;
  }

  @override
  Future<void> reload() async {
    final s = _source;
    if (s != null) await open(s, autoPlay: _playIntent);
  }

  @override
  Future<void> backToLiveEdge() async {
    if (state.type != MovaStreamType.live) return;
    await _backToLiveEdge();
    _state.emit(state.copyWith(clearTimeshift: true));
    _events.add(const MovaLiveEdgeReach());
  }

  /// Moves to the live edge by the configured strategy. Returns whether it
  /// went through [_reopenLiveSource] (a full kernel reload) rather than a seek.
  ///
  /// 按配置的策略回到直播边缘。返回是否走了 [_reopenLiveSource]（完整的内核重载）而不是 seek。
  Future<bool> _backToLiveEdge() async {
    var reopened = false;
    switch (options.live.effectiveBackToLive) {
      case MovaBackToLive.seekEnd:
        final window = state.seekableWindow;
        if (state.liveSeekable && window > Duration.zero) {
          await _kernel.seek(window);
        } else {
          await _reopenLiveSource();
          reopened = true;
        }
      case MovaBackToLive.reopen:
        await _reopenLiveSource();
        reopened = true;
    }
    return reopened;
  }

  /// Reopens the original live URL on the kernel, bypassing [open].
  ///
  /// [open] would clear the quality list and emit
  /// [MovaSourceChange]/[MovaReady], telling the UI the source changed — but
  /// returning to the edge is a position change, not a source change. It also
  /// matters in [MovaLiveSeekMode.timeshift]: [_source] still holds the
  /// *original* live URL while the kernel currently has a time-shifted one
  /// open, so this is what actually catches back up.
  ///
  /// 绕过 [open]，直接让内核重新打开原始直播地址。
  ///
  /// 走 [open] 会清空清晰度列表并发出 [MovaSourceChange]/[MovaReady]，告诉 UI
  /// 源变了——但回到边缘只是位置变化，不是换源。这一点在
  /// [MovaLiveSeekMode.timeshift] 下尤其关键：[_source] 里存的仍是**原始**直播
  /// 地址，而内核当前打开的是带时间参数的时移地址，重开原始地址才能真正追上。
  Future<void> _reopenLiveSource() async {
    final s = _source;
    if (s == null) return;
    // Same kernel-reload hazard as [open]/[switchQuality]: forget the old
    // stream's parked/pending seek bookkeeping before reloading, or a stale
    // [_parkedSeek]/[_pendingSeekTarget] from before this reopen can misfire
    // against the freshly reopened stream.
    //
    // 与 [open]/[switchQuality] 同样的内核重载隐患：重开前必须忘掉旧流的
    // 寄存/待结算 seek 簿记，否则重开前遗留的 [_parkedSeek]/
    // [_pendingSeekTarget] 可能在刚重开的流上误触发。
    _forgetMediaProgress();
    _armAttempt(autoPlay: _playIntent);
    await _loadKernel(_activeUri, play: _playIntent);
  }

  /// Jumps back to the live edge on a stall, when configured to.
  ///
  /// Only fires on a rising stall while actually time-shifted: a stall at the
  /// edge has nowhere to jump to, and jumping while the user is deliberately
  /// replaying would silently discard their chosen position — which is why
  /// [MovaLiveConfig.autoBackToLiveOnStall] defaults to off.
  ///
  /// 在配置开启时，卡顿则跳回直播边缘。
  ///
  /// 仅在**确实处于时移状态**且卡顿发生时触发：在边缘卡顿无处可跳；而用户正在
  /// 主动回看时跳走会悄悄丢掉他选定的位置——这正是
  /// [MovaLiveConfig.autoBackToLiveOnStall] 默认关闭的原因。
  ///
  /// - [buffering]: the latest buffering flag / 最新的缓冲标志
  void _maybeAutoBackToLive(bool buffering) {
    if (!buffering) return;
    if (!options.live.autoBackToLiveOnStall) return;
    if (state.type != MovaStreamType.live) return;
    if (state.timeshiftBehind == null) return;
    if (_autoBackToLiveInFlight) return;
    _autoBackToLiveInFlight = true;
    unawaited(
      backToLiveEdge().whenComplete(() => _autoBackToLiveInFlight = false),
    );
  }

  @override
  void showControls({bool sticky = false}) {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _ui.emit(uiState.copyWith(controlsVisible: true));
    if (!sticky && options.controls.autoHide) {
      _autoHideTimer = Timer(options.controls.autoHideDelay, hideControls);
    }
  }

  @override
  void hideControls() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _ui.emit(uiState.copyWith(controlsVisible: false));
  }

  @override
  void showHud(MovaHud hud, {String? text}) {
    _hudTimer?.cancel();
    _ui.emit(
      uiState.copyWith(hud: hud, hudText: text, clearHudText: text == null),
    );
    _hudTimer = Timer(const Duration(milliseconds: 800), () {
      _ui.emit(uiState.copyWith(hud: MovaHud.none, clearHudText: true));
    });
  }

  @override
  void setDragging(bool v, {Duration? previewAt}) {
    if (v) {
      _ui.emit(uiState.copyWith(dragging: true, previewAt: previewAt));
    } else {
      _ui.emit(uiState.copyWith(dragging: false, clearPreview: true));
    }
  }

  /// The brightness port this engine was constructed with; only for use by
  /// tests that need to assert which concrete [MovaBrightPort] a given
  /// construction path (e.g. [MovaEngine.new] vs. `createMovaEngine`) wired up.
  ///
  /// 该 engine 构造时使用的亮度端口；仅供测试断言某条构造路径（如
  /// [MovaEngine.new] 与 `createMovaEngine`）接入的具体 [MovaBrightPort]。
  @visibleForTesting
  MovaBrightPort get debugBrightnessPort => _brightness;

  /// The volume port this engine was constructed with (`null` = player-volume
  /// path); see [debugBrightnessPort] for why this is exposed only for tests.
  ///
  /// 该 engine 构造时使用的音量端口（`null` = 播放器音量路径）；暴露原因同
  /// [debugBrightnessPort]，仅供测试使用。
  @visibleForTesting
  MovaVolumePort? get debugVolumePort => _volume;

  /// The PiP port this engine was constructed with; see
  /// [debugBrightnessPort] for why this is exposed only for tests.
  ///
  /// 该 engine 构造时使用的画中画端口；暴露原因同 [debugBrightnessPort]，
  /// 仅供测试使用。
  @visibleForTesting
  MovaPipPort get debugPipPort => _pip;

  /// The frame extractor this engine was constructed with (`null` = no
  /// frame-extraction fallback); see [debugBrightnessPort] for why this is
  /// exposed only for tests.
  ///
  /// 该 engine 构造时使用的抽帧器（`null` 表示没有抽帧兜底）；为何只对测试暴露
  /// 见 [debugBrightnessPort]。
  @visibleForTesting
  MovaFramePuller? get debugExtractor => _extractor;

  /// The orientation port this engine was constructed with; see
  /// [debugBrightnessPort] for why this is exposed only for tests.
  ///
  /// 该 engine 构造时使用的方向端口；暴露原因同 [debugBrightnessPort]，
  /// 仅供测试使用。
  @visibleForTesting
  MovaOrientationPort get debugOrientationPort => _orientation;

  /// Directly injects quality variants into [state] without any HTTP fetch
  /// or kernel interaction; only for use by tests that need to seed ABR
  /// downshift scenarios without a real HLS master playlist.
  ///
  /// 直接向 [state] 注入清晰度档位，不发起任何 HTTP 请求或内核调用；仅供测试
  /// 在无需真实 HLS master playlist 的情况下构造 ABR 降档场景使用。
  @visibleForTesting
  void debugSetQualities(List<MovaQuality> qs, {MovaQuality? current}) {
    _state.emit(
      state.copyWith(
        qualities: qs,
        currentQuality: current,
        clearQuality: current == null,
      ),
    );
  }

  @override
  void report(MovaReportName name, {Map<String, dynamic>? params}) {
    final reporterPort = _reporter;
    if (reporterPort == null) return;
    reporterPort.onReport(
      MovaReportEvent(
        kind: MovaReportKind.action,
        name: name,
        params: params ?? const {},
        priority: MovaReportPriority.batched,
        at: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    // Disposing while the mini window still renders this engine leaves the
    // host painting a dead texture — almost always a page that disposed the
    // engine it had just handed off. Debug-only, zero release cost.
    //
    // 小窗仍在渲染本引擎时 dispose，会让宿主继续绘制一个已死的纹理——几乎总是
    // 某个页面把刚交接出去的引擎顺手销毁了。仅 debug 生效，release 零成本。
    assert(
      !state.mini,
      'dispose() while MovaState.mini is true — see MovaMiniController docs',
    );
    // Synchronous prefix on purpose: hosts call `unawaited(dispose())` from
    // State.dispose(), and a pending Timer after the tree is torn down fails
    // widget tests.
    //
    // 刻意放在同步前缀里：宿主在 State.dispose() 里 `unawaited(dispose())`，
    // 拆树后若还有挂起的 Timer，会让 widget 测试失败。
    _disposed = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    _recoverTimer?.cancel();
    _recoverTimer = null;
    _standbyTimer?.cancel();
    _standbyTimer = null;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _watchdog?.dispose();
    await _restartSub?.cancel();
    await _endFileSub?.cancel();
    await _playingSub.cancel();
    await _bufferingSub.cancel();
    await _completedSub.cancel();
    await _positionSub.cancel();
    await _durationSub.cancel();
    await _bufferSub.cancel();
    await _sizeSub.cancel();
    await _errorSub.cancel();
    _hudTimer?.cancel();
    _autoHideTimer?.cancel();
    _qoe?.onTeardown();
    await _qoe?.cancel();
    await _state.close();
    await _ui.close();
    await _events.close();
    await _progressRaw.close();
    await _previewService.dispose();
    await _sttService.dispose();
    await _kernel.dispose();
  }

  /// Recomputes [MovaState.liveSeekable]/[MovaState.seekableWindow] from the
  /// current stream type, [MovaLiveConfig.seekMode], and the resolved DVR/
  /// time-shift window (see [resolveWindow]).
  ///
  /// 根据当前流类型、[MovaLiveConfig.seekMode] 及解析出的 DVR/时移窗口（见
  /// [resolveWindow]）重算 [MovaState.liveSeekable]/[MovaState.seekableWindow]。
  void _recomputeLiveSeekable() {
    final window = resolveWindow(state, options.live);
    final seekable =
        state.type == MovaStreamType.live &&
        options.live.seekMode != MovaLiveSeekMode.off &&
        window > Duration.zero;
    _state.emit(state.copyWith(liveSeekable: seekable, seekableWindow: window));
    _updateTimeshift(_lastPosition);
  }

  /// Recomputes [MovaState.timeshiftBehind] from [position] and announces the
  /// transition on the event stream.
  ///
  /// The lag is quantised to whole seconds before comparison: position ticks
  /// arrive several times a second, and emitting a new [MovaState] for every
  /// sub-second change would turn the deduplicated [states] stream into a
  /// high-frequency one — exactly what phase A avoided by keeping position out
  /// of [MovaState]. Second-level precision is all the `-MM:SS` indicator needs.
  ///
  /// 依据 [position] 重算 [MovaState.timeshiftBehind]，并在事件流上广播其变化。
  ///
  /// 落后量在比较前先量化到整秒：position 每秒到达数次，若每次亚秒级变化都发一个
  /// 新的 [MovaState]，去重后的 [states] 流就会退化成高频流——这正是阶段 A 把
  /// position 排除在 [MovaState] 之外所要避免的。`-MM:SS` 指示器也只需要秒级精度。
  ///
  /// - [position]: latest known playhead position / 最近已知的播放位置
  void _updateTimeshift(Duration position) {
    final live = state.type == MovaStreamType.live && state.liveSeekable;
    final raw = live
        ? behindOf(position, state.seekableWindow, options.live.edgeThreshold)
        : null;
    final behind = raw == null ? null : Duration(seconds: raw.inSeconds);
    if (behind == state.timeshiftBehind) return;
    if (behind == null) {
      _state.emit(state.copyWith(clearTimeshift: true));
      if (live) _events.add(const MovaLiveEdgeReach());
    } else {
      _state.emit(state.copyWith(timeshiftBehind: behind));
      _events.add(MovaTimeShiftChange(behind));
    }
  }

  /// Feeds a buffering-state observation to [_abrPolicy] and, when it signals
  /// a downshift and [MovaAbrConfig.enabled] is true, downshifts the current
  /// quality — emitting [MovaAbrDownShift] only if the quality actually
  /// changed (i.e. not a no-op auto-mode/lowest-variant downshift attempt).
  ///
  /// 把一次缓冲状态观测喂给 [_abrPolicy]；当它发出降档信号且
  /// [MovaAbrConfig.enabled] 为真时执行降档——仅当清晰度确实发生变化时（即非
  /// 自动模式/已是最低档的无操作降档）才发出 [MovaAbrDownShift]。
  void _handleAbrBuffering(bool buffering) {
    final shouldDownshift = _abrPolicy.onBuffering(buffering);
    if (!shouldDownshift || !options.abr.enabled) return;
    if (_abrDownshiftInFlight) return;
    final from = state.currentQuality;
    if (from == null) return;
    _abrDownshiftInFlight = true;
    unawaited(
      downshiftQuality()
          .then((_) {
            final to = state.currentQuality;
            if (to != null && to != from) {
              _events.add(MovaAbrDownShift(from, to));
            }
          })
          .whenComplete(() => _abrDownshiftInFlight = false),
    );
  }
}
