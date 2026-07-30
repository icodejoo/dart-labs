import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'api.dart';
import 'bus/bus.dart';
import 'events/events.dart';
import 'interceptor/interceptor.dart';
import 'kernel/kernel.dart';
import 'kernel/mpv_kernel.dart';
import 'model/fit.dart';
import 'model/quality.dart';
import 'model/source.dart';
import 'options/options.dart';
import 'platform/ports.dart';
import 'state/progress.dart';
import 'state/state.dart';
import 'state/ui_state.dart';

/// The production [VmApi] implementation: reduces a [VmKernel]'s raw streams
/// into public state/event/progress streams and implements every capability
/// method (playback, quality switching + ABR, live-seek gating, HUD/controls
/// timers, platform ports).
///
/// This is the only class in `lib/src/core/**` that wires everything else in
/// this layer together; it never imports `package:flutter` or
/// `package:media_kit` directly (those live behind [VmKernel]/[VmOptions]/
/// the ports).
///
/// 生产环境的 [VmApi] 实现：把 [VmKernel] 的原始流归约为公开的状态/事件/进度
/// 流，并实现全部能力方法（播放、清晰度切换 + ABR、直播拖动门控、HUD/控制条
/// 计时器、平台端口）。
///
/// 这是 `lib/src/core/**` 中唯一把该层其余部分粘合在一起的类；它本身不直接
/// 引入 `package:flutter` 或 `package:media_kit`（这些依赖被隔离在
/// [VmKernel]/[VmOptions]/各 Port 之后）。
class VmEngine implements VmApi {
  /// The kernel this engine drives.
  ///
  /// 该 engine 驱动的内核。
  final VmKernel _kernel;

  /// The configuration this instance was constructed with.
  ///
  /// 构造该实例时使用的配置。
  @override
  final VmOptions options;

  /// Interceptor chain consulted before open/seek/play and on every error.
  ///
  /// 在 open/seek/play 前及每次出错时咨询的拦截链。
  final VmInterceptorChain _chain;

  /// Reads/writes device screen brightness.
  ///
  /// 读写设备屏幕亮度。
  final VmBrightnessPort _brightness;

  /// Enters system picture-in-picture.
  ///
  /// 进入系统画中画。
  final VmPipPort _pip;

  /// Applies/resets fullscreen orientation and system UI.
  ///
  /// 应用/重置全屏方向与系统 UI。
  final VmOrientationPort _orientation;

  /// The ABR downshift policy in effect; defaults to a [VmBufferingAbr]
  /// seeded from [VmAbrConfig.stallThreshold] when [VmAbrConfig.policy] is
  /// null.
  ///
  /// 当前生效的 ABR 降档策略；[VmAbrConfig.policy] 为空时默认用
  /// [VmAbrConfig.stallThreshold] 构造的 [VmBufferingAbr]。
  late final VmAbrPolicy _abrPolicy;

  /// Reentrancy guard for [_handleAbrBuffering]: true while a downshift
  /// triggered by a previous threshold-crossing is still in flight (its
  /// async `open()`/`seek()` hasn't settled yet). Prevents two overlapping
  /// [downshiftQuality] calls from racing on [_kernel] and corrupting the
  /// "from" quality snapshot or double/under-firing [VmAbrDownshift].
  ///
  /// [_handleAbrBuffering] 的重入保护：为真时表示上一次阈值触发的降档仍在
  /// 进行中（其异步 `open()`/`seek()` 尚未完成）。防止两次
  /// [downshiftQuality] 调用并发争用 [_kernel]，破坏"from"清晰度快照或
  /// 导致 [VmAbrDownshift] 重复/漏发。
  bool _abrDownshiftInFlight = false;

  final VmBus<VmState> _state = VmBus<VmState>(const VmState());
  final VmBus<VmUiState> _ui = VmBus<VmUiState>(const VmUiState());
  final StreamController<VmEvent> _events = StreamController<VmEvent>.broadcast();
  final StreamController<VmProgress> _progressRaw = StreamController<VmProgress>.broadcast();
  late final Stream<VmProgress> _progress;

  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<bool> _completedSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;
  late final StreamSubscription<Duration> _bufferSub;
  late final StreamSubscription<VmSize> _sizeSub;
  late final StreamSubscription<Object> _errorSub;

  /// The most recently opened source, or null before [open] has ever been
  /// called.
  ///
  /// 最近一次打开的源；[open] 从未被调用过时为 null。
  VmSource? _source;

  /// Latest known playback position, tracked synchronously from every
  /// kernel `position` callback (independent of the throttled [progress]
  /// stream) so [switchQuality]/[downshiftQuality]/[seekBy] can read it
  /// without waiting on throttling.
  ///
  /// 最近已知的播放位置，从内核每次 `position` 回调同步更新（与节流后的
  /// [progress] 流无关），使 [switchQuality]/[downshiftQuality]/[seekBy]
  /// 无需等待节流即可读取。
  Duration _lastPosition = Duration.zero;

  /// Latest known playing/paused flag, tracked synchronously from every
  /// kernel `playing` callback; see [_lastPosition] for why this is kept
  /// outside the throttled/deduplicated public streams.
  ///
  /// 最近已知的播放/暂停标志，从内核每次 `playing` 回调同步更新；保持在
  /// 公开节流/去重流之外的原因见 [_lastPosition]。
  bool _lastPlaying = false;

  Timer? _hudTimer;
  Timer? _autoHideTimer;

  /// Creates an engine over [kernel] (defaults to a new [MpvKernel]),
  /// [options], [interceptors], and platform [brightness]/[pip]/[orientation]
  /// ports (each defaults to a zero-dependency fallback/noop).
  ///
  /// 基于 [kernel]（省略时默认新建 [MpvKernel]）、[options]、[interceptors]
  /// 及平台 [brightness]/[pip]/[orientation] 端口（各自省略时默认使用零依赖
  /// 兜底/空实现）创建一个 engine。
  VmEngine({
    VmKernel? kernel,
    this.options = const VmOptions(),
    List<VmInterceptor> interceptors = const [],
    VmBrightnessPort? brightness,
    VmPipPort? pip,
    VmOrientationPort? orientation,
  })  : _kernel = kernel ?? MpvKernel(),
        _chain = VmInterceptorChain(interceptors),
        _brightness = brightness ?? FallbackBrightnessPort(),
        _pip = pip ?? NoopPipPort(),
        _orientation = orientation ?? NoopOrientationPort() {
    _abrPolicy = options.abr.policy ?? VmBufferingAbr(threshold: options.abr.stallThreshold);
    _progress = throttleStream(_progressRaw.stream, const Duration(milliseconds: 200))
        .asBroadcastStream();

    _playingSub = _kernel.playing.listen((v) {
      _lastPlaying = v;
      _state.emit(state.copyWith(playing: v));
      _events.add(v ? const VmPlay() : const VmPause());
    });
    _bufferingSub = _kernel.buffering.listen((v) {
      _state.emit(state.copyWith(buffering: v));
      _events.add(VmBufferingChanged(v));
      _handleAbrBuffering(v);
    });
    _completedSub = _kernel.completed.listen((v) {
      _state.emit(state.copyWith(completed: v));
      if (v) _events.add(const VmCompleted());
    });
    _positionSub = _kernel.position.listen((v) {
      _lastPosition = v;
      _progressRaw.add(VmProgress(position: v, buffer: _lastBuffer));
    });
    _bufferSub = _kernel.buffer.listen((v) {
      _lastBuffer = v;
      _progressRaw.add(VmProgress(position: _lastPosition, buffer: v));
    });
    _durationSub = _kernel.duration.listen((v) {
      _state.emit(state.copyWith(duration: v));
      _events.add(VmDurationChanged(v));
      _recomputeLiveSeekable();
    });
    _sizeSub = _kernel.size.listen((v) {
      _state.emit(state.copyWith(width: v.width, height: v.height));
      _events.add(VmSizeChanged(v.width, v.height));
    });
    _errorSub = _kernel.error.listen((e) {
      _state.emit(state.copyWith(error: e));
      _events.add(VmErrorEvent(e));
      _chain.onError(e, StackTrace.current);
    });
  }

  /// Latest known buffered position, tracked alongside [_lastPosition] so a
  /// `buffer` callback doesn't clobber the last known `position` (and vice
  /// versa) when pushing a combined [VmProgress] snapshot.
  ///
  /// 与 [_lastPosition] 一并维护的最近已知缓冲位置，避免 `buffer` 回调覆盖
  /// 最近的 `position`（反之亦然）——用于推送合并后的 [VmProgress] 快照。
  Duration _lastBuffer = Duration.zero;

  /// One-time global engine init; forwards to [MpvKernel.ensureInitialized].
  /// Call before constructing any [VmEngine].
  ///
  /// 全局一次性 engine 初始化；转发给 [MpvKernel.ensureInitialized]。创建任何
  /// [VmEngine] 前调用。
  static void ensureInitialized() => MpvKernel.ensureInitialized();

  @override
  Stream<VmEvent> get events => _events.stream;

  @override
  Stream<VmState> get states => _state.stream;

  @override
  Stream<VmProgress> get progress => _progress;

  @override
  Stream<VmUiState> get uiStates => _ui.stream;

  @override
  VmState get state => _state.value;

  @override
  VmUiState get uiState => _ui.value;

  @override
  Future<void> open(VmSource source, {bool autoPlay = true}) async {
    final allowed = await _chain.beforeOpen(source);
    if (!allowed) return;
    _source = source;
    _abrPolicy.reset();
    _state.emit(state.copyWith(
      qualities: const [],
      type: source.type,
      clearQuality: true,
      clearError: true,
    ));
    await _kernel.open(source.uri, play: autoPlay);
    _recomputeLiveSeekable();
    _events.add(VmSourceChanged(source));
    _events.add(const VmReady());
  }

  @override
  Future<void> play() async {
    final allowed = await _chain.beforePlay();
    if (!allowed) return;
    await _kernel.play();
  }

  @override
  Future<void> pause() => _kernel.pause();

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration to) async {
    final gate = state.type == VmStreamType.vod || state.liveSeekable;
    if (!gate) return;
    final t = await _chain.beforeSeek(to);
    if (t == null) return;
    final clamped = state.duration > Duration.zero
        ? Duration(milliseconds: t.inMilliseconds.clamp(0, state.duration.inMilliseconds))
        : t;
    _events.add(VmSeeking(clamped));
    await _kernel.seek(clamped);
    _events.add(VmSeeked(clamped));
  }

  @override
  Future<void> seekBy(Duration delta) => seek(_lastPosition + delta);

  @override
  Future<void> setVolume(double v) async {
    await _kernel.setVolume(v);
    _state.emit(state.copyWith(volume: v));
    _events.add(VmVolumeChanged(v));
  }

  @override
  Future<void> setBrightness(double v) async {
    await _brightness.set(v);
    _state.emit(state.copyWith(brightness: v));
    _events.add(VmBrightnessChanged(v));
  }

  @override
  Future<void> setRate(double r) async {
    await _kernel.setRate(r);
    _state.emit(state.copyWith(rate: r));
    _events.add(VmRateChanged(r));
  }

  @override
  Future<void> setFit(VmFit f) async {
    _state.emit(state.copyWith(fit: f));
    _events.add(VmFitChanged(f));
  }

  @override
  Future<void> setZoom(double z) async {
    _state.emit(state.copyWith(zoom: z));
    _events.add(VmZoomChanged(z));
  }

  @override
  Future<void> setLocked(bool v) async {
    _state.emit(state.copyWith(locked: v));
    _events.add(VmLockChanged(v));
  }

  @override
  Future<void> setFullscreen(bool v) async {
    if (v) {
      await _orientation.apply(
        fullscreen: true,
        immersive: true,
        width: state.width,
        height: state.height,
      );
    } else {
      await _orientation.reset();
    }
    _state.emit(state.copyWith(fullscreen: v));
    _events.add(VmFullscreenChanged(v));
  }

  @override
  Future<void> loadQualities() async {
    final s = _source;
    if (s == null || !s.uri.toLowerCase().contains('.m3u8')) {
      _state.emit(state.copyWith(qualities: const [], clearQuality: true));
      return;
    }
    try {
      final content = await _httpGetString(s.uri);
      final qs = parseHlsMasterPlaylist(content, base: Uri.parse(s.uri));
      final cur = qs.isNotEmpty ? qs.first : null;
      _state.emit(state.copyWith(
        qualities: qs,
        currentQuality: cur,
        clearQuality: cur == null,
      ));
      _events.add(VmQualityListChanged(qs));
      if (cur != null) _events.add(VmQualityChanged(cur));
    } catch (_) {
      _state.emit(state.copyWith(qualities: const [], clearQuality: true));
    }
  }

  @override
  Future<void> switchQuality(VmQuality q) async {
    final playUri = q.isAuto ? (_source?.uri ?? '') : q.uri;
    if (playUri.isEmpty) return;
    final pos = _lastPosition;
    final wasPlaying = _lastPlaying;
    await _kernel.open(playUri, play: wasPlaying);
    if (state.type != VmStreamType.live) await _kernel.seek(pos);
    _state.emit(state.copyWith(currentQuality: q));
    _events.add(VmQualityChanged(q));
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
    final ok = await _pip.enter(width: state.width, height: state.height);
    _state.emit(state.copyWith(pip: ok));
    _events.add(VmPipChanged(ok));
    return ok;
  }

  @override
  Future<void> reload() async {
    final s = _source;
    if (s != null) await open(s, autoPlay: true);
  }

  @override
  Future<void> backToLiveEdge() async {
    if (state.type != VmStreamType.live) return;
    await reload();
    _events.add(const VmLiveEdgeReached());
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
  void showHud(VmHud hud) {
    _hudTimer?.cancel();
    _ui.emit(uiState.copyWith(hud: hud));
    _hudTimer = Timer(const Duration(milliseconds: 800), () {
      _ui.emit(uiState.copyWith(hud: VmHud.none));
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

  /// Directly injects quality variants into [state] without any HTTP fetch
  /// or kernel interaction; only for use by tests that need to seed ABR
  /// downshift scenarios without a real HLS master playlist.
  ///
  /// 直接向 [state] 注入清晰度档位，不发起任何 HTTP 请求或内核调用；仅供测试
  /// 在无需真实 HLS master playlist 的情况下构造 ABR 降档场景使用。
  @visibleForTesting
  void debugSetQualities(List<VmQuality> qs, {VmQuality? current}) {
    _state.emit(state.copyWith(
      qualities: qs,
      currentQuality: current,
      clearQuality: current == null,
    ));
  }

  @override
  Future<void> dispose() async {
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
    await _state.close();
    await _ui.close();
    await _events.close();
    await _progressRaw.close();
    await _kernel.dispose();
  }

  /// Recomputes [VmState.liveSeekable]/[VmState.seekableWindow] from the
  /// current stream type, [VmLiveConfig.seekMode], and the resolved DVR/
  /// time-shift window (see [_resolveWindow]).
  ///
  /// 根据当前流类型、[VmLiveConfig.seekMode] 及解析出的 DVR/时移窗口（见
  /// [_resolveWindow]）重算 [VmState.liveSeekable]/[VmState.seekableWindow]。
  void _recomputeLiveSeekable() {
    final window = _resolveWindow();
    final seekable = state.type == VmStreamType.live &&
        options.live.seekMode != VmLiveSeekMode.off &&
        window > Duration.zero;
    _state.emit(state.copyWith(liveSeekable: seekable, seekableWindow: window));
  }

  /// Resolves the effective DVR/time-shift window: an explicit
  /// [VmLiveConfig.dvrWindow] if configured, otherwise the kernel-reported
  /// [VmState.duration] (common for a live HLS stream whose "duration" is
  /// its DVR window length).
  ///
  /// 解析生效的 DVR/时移窗口：若配置了 [VmLiveConfig.dvrWindow] 则用之，否则
  /// 用内核报告的 [VmState.duration]（常见于直播 HLS 流，其"时长"即 DVR
  /// 窗口长度）。
  Duration _resolveWindow() => options.live.dvrWindow ?? state.duration;

  /// Feeds a buffering-state observation to [_abrPolicy] and, when it signals
  /// a downshift and [VmAbrConfig.enabled] is true, downshifts the current
  /// quality — emitting [VmAbrDownshift] only if the quality actually
  /// changed (i.e. not a no-op auto-mode/lowest-variant downshift attempt).
  ///
  /// 把一次缓冲状态观测喂给 [_abrPolicy]；当它发出降档信号且
  /// [VmAbrConfig.enabled] 为真时执行降档——仅当清晰度确实发生变化时（即非
  /// 自动模式/已是最低档的无操作降档）才发出 [VmAbrDownshift]。
  void _handleAbrBuffering(bool buffering) {
    final shouldDownshift = _abrPolicy.onBuffering(buffering);
    if (!shouldDownshift || !options.abr.enabled) return;
    if (_abrDownshiftInFlight) return;
    final from = state.currentQuality;
    if (from == null) return;
    _abrDownshiftInFlight = true;
    unawaited(downshiftQuality().then((_) {
      final to = state.currentQuality;
      if (to != null && to != from) {
        _events.add(VmAbrDownshift(from, to));
      }
    }).whenComplete(() => _abrDownshiftInFlight = false));
  }

  /// GETs [url] as a UTF-8 string via a one-shot HTTP client.
  ///
  /// 用一次性 HTTP 客户端以 UTF-8 拉取 [url] 文本。
  Future<String> _httpGetString(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      return await resp.transform(const Utf8Decoder()).join();
    } finally {
      client.close();
    }
  }
}
