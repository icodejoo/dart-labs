import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../core/controller.dart';
import '../core/model/fit.dart';
import '../core/options/options.dart';
import '../ui/fit_ext.dart';
import 'gesture_layer.dart';
import 'live_controls.dart';
import 'vod_controls.dart';

/// Which transient HUD indicator is currently shown.
///
/// 当前显示的瞬时 HUD 指示器种类。
enum _Hud { none, volume, brightness, seek, fit, quality }

/// How long the HUD stays visible after the last update.
///
/// 最后一次更新后 HUD 保持可见的时长。
const Duration _kHudLinger = Duration(milliseconds: 700);

/// How long the control bars stay up before auto-hiding during playback.
///
/// 播放中控制条自动隐藏前的停留时长。
const Duration _kControlsLinger = Duration(seconds: 4);

/// Chooses the fullscreen orientations that match a video's aspect ratio.
///
/// Landscape (both directions) when width ≥ height, else portrait.
///
/// 按视频宽高比选择全屏方向：宽≥高用横屏（双向），否则竖屏。
///
/// - [width], [height]: video pixel dimensions / 视频像素宽高
/// - returns the preferred orientation list / 返回首选方向列表
List<DeviceOrientation> preferredOrientationsFor(int width, int height) {
  return width >= height
      ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
      : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];
}

/// The videoman player widget: video surface + gestures + control bars + lock.
///
/// Renders a media_kit [Video] (built-in controls disabled) and overlays
/// videoman's gestures (left=volume, right=brightness, horizontal=seek,
/// double-tap=seek, pinch=zoom), a VOD/live control bar, fill-mode switching
/// (contain/cover/fill), fullscreen with aspect-based orientation, and a
/// lock mode that blocks all interaction (anti-mistouch, immersive).
///
/// videoman 播放器组件：视频画面 + 手势 + 控制条 + 锁定。
///
/// 渲染 media_kit 的 [Video]（关内置控制条），叠加 videoman 手势（左音量/右亮度/
/// 横滑进度/双击/双指缩放）、点播或直播控制条、填充模式切换（contain/cover/fill）、
/// 基于宽高比定向的全屏，以及屏蔽全部交互的锁定模式（防误触、沉浸式）。
class VmPlayer extends StatefulWidget {
  /// The playback controller to render and drive.
  ///
  /// 用于渲染和驱动的播放控制器。
  final VmController controller;

  /// Gesture enable/side configuration.
  ///
  /// 手势开关与侧别配置。
  final VmGestureConfig gestureConfig;

  /// Initial fill mode.
  ///
  /// 初始填充模式。
  final VmFit fit;

  /// Maximum pinch-zoom scale factor.
  ///
  /// 双指缩放的最大倍数。
  final double maxZoom;

  /// Auto-detect the video aspect ratio and lock orientation accordingly
  /// while fullscreen. When false, fullscreen keeps device auto-rotate.
  ///
  /// 全屏时自动检测视频宽高比并据此锁定方向。为 false 时全屏保持设备自动旋转。
  final bool autoOrientation;

  /// Creates a player bound to [controller].
  ///
  /// 创建绑定到 [controller] 的播放器。
  ///
  /// Example / 示例:
  /// ```dart
  /// VmPlayer(controller: myController, fit: VmFit.cover);
  /// ```
  const VmPlayer({
    super.key,
    required this.controller,
    this.gestureConfig = const VmGestureConfig(),
    this.fit = VmFit.contain,
    this.maxZoom = 3.0,
    this.autoOrientation = true,
  });

  @override
  State<VmPlayer> createState() => _VmPlayerState();
}

/// State for [VmPlayer]; owns zoom, brightness, fit, lock and fullscreen.
///
/// [VmPlayer] 的状态；持有缩放、亮度、填充模式、锁定与全屏。
class _VmPlayerState extends State<VmPlayer> {
  final ScreenBrightness _brightnessPlugin = ScreenBrightness();
  double _zoom = 1.0;
  double _baseZoom = 1.0;
  double _brightness = 1.0;

  late VmFit _fit;
  bool _locked = false;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _showUnlock = false;

  _Hud _hud = _Hud.none;
  String _hudText = '';
  Timer? _hudTimer;
  Timer? _controlsTimer;

  int? _videoWidth;
  int? _videoHeight;
  StreamSubscription<int?>? _widthSub;
  StreamSubscription<int?>? _heightSub;

  final VmBufferingAbr _abr = VmBufferingAbr();
  StreamSubscription<bool>? _bufferingSub;
  bool _pipSupported = false;

  @override
  void initState() {
    super.initState();
    _fit = widget.fit;
    _loadBrightness();
    _scheduleControlsHide();
    _initQualities();
    _initPip();
    // Downshift when the network stalls repeatedly on a pinned quality.
    // 锁定某清晰度时网络反复卡顿则降档。
    _bufferingSub = widget.controller.player.stream.buffering.listen((b) {
      if (_abr.onBuffering(b)) _autoDownshift();
    });
    // Track video dimensions so fullscreen orientation follows the aspect.
    // 跟踪视频尺寸，使全屏方向跟随宽高比。
    _widthSub = widget.controller.player.stream.width.listen((w) {
      _videoWidth = w;
      _onDimsChanged();
    });
    _heightSub = widget.controller.player.stream.height.listen((h) {
      _videoHeight = h;
      _onDimsChanged();
    });
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    _controlsTimer?.cancel();
    _widthSub?.cancel();
    _heightSub?.cancel();
    _bufferingSub?.cancel();
    // Restore system UI on the way out. / 退出时恢复系统 UI。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  /// Reads the current screen brightness into the local cache.
  ///
  /// 读取当前屏幕亮度到本地缓存。
  Future<void> _loadBrightness() async {
    try {
      _brightness = await _brightnessPlugin.application;
    } catch (_) {
      _brightness = 1.0;
    }
  }

  // ---- PiP --------------------------------------------------------------

  /// Detects PiP support so the button only shows where it works.
  ///
  /// 探测画中画支持，仅在可用平台显示按钮。
  Future<void> _initPip() async {
    final ok = await widget.controller.isPipSupported();
    if (mounted) setState(() => _pipSupported = ok);
  }

  // ---- Quality / ABR ----------------------------------------------------

  /// Resolves HLS quality variants, then refreshes to show the picker.
  ///
  /// 解析 HLS 清晰度档位，随后刷新以显示选择入口。
  Future<void> _initQualities() async {
    await widget.controller.loadQualities();
    if (mounted) setState(() {});
  }

  /// Steps down one quality on repeated stalls and flashes a HUD.
  ///
  /// 反复卡顿时降一档清晰度并闪一次 HUD。
  Future<void> _autoDownshift() async {
    final cur = widget.controller.currentQuality;
    if (cur == null || cur.isAuto) return;
    await widget.controller.downshiftQuality();
    if (!mounted) return;
    setState(() {});
    _showHud(_Hud.quality, '网络波动 · ${widget.controller.currentQuality?.label ?? ''}');
  }

  /// Opens a bottom sheet to pick a quality; auto delegates ABR to the engine.
  ///
  /// 打开底部选择器切换清晰度；"自动"把 ABR 交给内核。
  void _showQualityMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xEE1A1A1A),
      builder: (ctx) {
        final qs = widget.controller.qualities;
        final cur = widget.controller.currentQuality;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final q in qs)
                ListTile(
                  title: Text(q.label, style: const TextStyle(color: Colors.white)),
                  trailing: (cur?.uri == q.uri && cur?.isAuto == q.isAuto)
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _abr.reset();
                    widget.controller.switchQuality(q).then((_) {
                      if (mounted) setState(() {});
                    });
                    _showHud(_Hud.quality, q.label);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ---- HUD --------------------------------------------------------------

  /// Shows a HUD with [text] for [kind] and schedules auto-hide.
  ///
  /// 显示 [kind] 类型、内容为 [text] 的 HUD 并安排自动隐藏。
  void _showHud(_Hud kind, String text) {
    setState(() {
      _hud = kind;
      _hudText = text;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(_kHudLinger, () {
      if (mounted) setState(() => _hud = _Hud.none);
    });
  }

  // ---- Controls visibility ---------------------------------------------

  /// Toggles the control bars (or reveals the unlock button when locked).
  ///
  /// 切换控制条显隐（锁定时改为显示解锁按钮）。
  void _onTap() {
    if (_locked) {
      setState(() => _showUnlock = true);
      _controlsTimer?.cancel();
      _controlsTimer = Timer(_kControlsLinger, () {
        if (mounted) setState(() => _showUnlock = false);
      });
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    _scheduleControlsHide();
  }

  /// Auto-hides the control bars after a delay while playing.
  ///
  /// 播放中延迟自动隐藏控制条。
  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (!_controlsVisible || _locked) return;
    _controlsTimer = Timer(_kControlsLinger, () {
      if (mounted && widget.controller.player.state.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  // ---- Lock / fit / fullscreen -----------------------------------------

  /// Toggles the lock mode (blocks gestures + controls, goes immersive).
  ///
  /// 切换锁定模式（屏蔽手势与控制条，进入沉浸式）。
  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      _controlsVisible = !_locked;
      _showUnlock = false;
    });
    _applySystemUi();
    _scheduleControlsHide();
  }

  /// Cycles the fill mode (contain → cover → fill) and flashes a HUD.
  ///
  /// 循环切换填充模式（contain → cover → fill）并闪一次 HUD。
  void _cycleFit() {
    setState(() => _fit = _fit.next);
    _showHud(_Hud.fit, vmFitLabel(_fit));
  }

  /// Toggles fullscreen and applies aspect-based orientation + immersion.
  ///
  /// 切换全屏并应用基于宽高比的方向与沉浸式。
  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    _applySystemUi();
    _applyOrientation();
  }

  /// Applies immersive system UI when locked or fullscreen, else edge-to-edge.
  ///
  /// 锁定或全屏时进入沉浸式系统 UI，否则恢复 edge-to-edge。
  void _applySystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      (_fullscreen || _locked) ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Re-applies fullscreen orientation when the video dimensions change.
  ///
  /// 视频尺寸变化时重新应用全屏方向。
  void _onDimsChanged() {
    if (_fullscreen && widget.autoOrientation) _applyOrientation();
  }

  /// Locks orientation to match the video aspect ratio in fullscreen.
  ///
  /// 全屏时按视频宽高比锁定方向。
  void _applyOrientation() {
    if (!_fullscreen || !widget.autoOrientation) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      return;
    }
    final w = _videoWidth ?? widget.controller.player.state.width ?? 16;
    final h = _videoHeight ?? widget.controller.player.state.height ?? 9;
    SystemChrome.setPreferredOrientations(preferredOrientationsFor(w, h));
  }

  // ---- Gesture intents --------------------------------------------------

  /// Applies a volume intent (0–100) and shows the volume HUD.
  ///
  /// 应用音量意图（0–100）并显示音量 HUD。
  void _onVolume(double v) {
    widget.controller.setVolume(v);
    _showHud(_Hud.volume, '${v.round()}%');
  }

  /// Applies a brightness intent (0–1) and shows the brightness HUD.
  ///
  /// 应用亮度意图（0–1）并显示亮度 HUD。
  void _onBrightness(double b) {
    _brightness = b;
    _brightnessPlugin.setApplicationScreenBrightness(b);
    _showHud(_Hud.brightness, '${(b * 100).round()}%');
  }

  /// Shows the live seek preview while dragging horizontally.
  ///
  /// 横向拖动时显示实时进度预览。
  void _onSeekPreview(double seconds) {
    final target = _clampedTarget(seconds);
    final sign = seconds >= 0 ? '+' : '-';
    _showHud(
      _Hud.seek,
      '${_fmt(target)}  $sign${_fmt(Duration(seconds: seconds.abs().round()))}',
    );
  }

  /// Commits the accumulated horizontal seek.
  ///
  /// 提交累计的横向进度调整。
  void _onSeekCommit(double seconds) => widget.controller.seek(_clampedTarget(seconds));

  /// Applies a double-tap seek [step] relative to the current position.
  ///
  /// 应用相对当前位置的双击进度步长 [step]。
  void _onDoubleTapSeek(Duration step) {
    final target = widget.controller.player.state.position + step;
    widget.controller.seek(_clamp(target));
    final sign = step.isNegative ? '-' : '+';
    _showHud(_Hud.seek, '$sign${_fmt(Duration(seconds: step.inSeconds.abs()))}');
  }

  /// Updates the live zoom scale during a pinch.
  ///
  /// 捏合过程中更新实时缩放系数。
  void _onZoomUpdate(double scale) {
    setState(() => _zoom = (_baseZoom * scale).clamp(1.0, widget.maxZoom));
  }

  /// Persists the zoom scale after a pinch ends.
  ///
  /// 捏合结束后固化缩放系数。
  void _onZoomEnd() => _baseZoom = _zoom;

  // ---- Helpers ----------------------------------------------------------

  /// Computes the clamped seek target from a signed [seconds] delta.
  ///
  /// 根据带符号的 [seconds] 增量计算钳制后的进度目标。
  Duration _clampedTarget(double seconds) {
    final pos = widget.controller.player.state.position;
    return _clamp(pos + Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Clamps [t] to the [0, duration] range.
  ///
  /// 将 [t] 钳制到 [0, 时长] 区间。
  Duration _clamp(Duration t) {
    final dur = widget.controller.player.state.duration;
    if (t < Duration.zero) return Duration.zero;
    if (dur > Duration.zero && t > dur) return dur;
    return t;
  }

  /// Formats a duration as mm:ss (or h:mm:ss).
  ///
  /// 将时长格式化为 mm:ss（或 h:mm:ss）。
  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---- Build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final showControls = _controlsVisible && !_locked;
    return ColoredBox(
      color: const Color(0xFF000000),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: Transform.scale(
              scale: _zoom,
              child: Video(
                controller: widget.controller.videoController,
                controls: NoVideoControls,
                fit: vmBoxFit(_fit),
              ),
            ),
          ),
          if (!_locked)
            VmGestureDetector(
              config: widget.gestureConfig,
              isLive: widget.controller.isLive,
              volumeGetter: () => widget.controller.player.state.volume,
              brightnessGetter: () => _brightness,
              onVolume: _onVolume,
              onBrightness: _onBrightness,
              onSeekPreview: _onSeekPreview,
              onSeekCommit: _onSeekCommit,
              onZoomUpdate: _onZoomUpdate,
              onZoomEnd: _onZoomEnd,
              onDoubleTapSeek: _onDoubleTapSeek,
              onTap: _onTap,
            ),
          if (_locked) GestureDetector(behavior: HitTestBehavior.opaque, onTap: _onTap),
          AnimatedOpacity(
            opacity: showControls ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(ignoring: !showControls, child: _buildControls()),
          ),
          if (_locked && _showUnlock) _buildUnlockButton(),
          if (_hud != _Hud.none) _buildHud(),
        ],
      ),
    );
  }

  /// Builds the VOD or live control bar depending on the source type.
  ///
  /// 按源类型构建点播或直播控制条。
  Widget _buildControls() {
    final hasQualities = widget.controller.qualities.isNotEmpty;
    final onQuality = hasQualities ? _showQualityMenu : null;
    final qualityLabel = widget.controller.currentQuality?.label;
    final onPip = _pipSupported ? widget.controller.enterPip : null;
    if (widget.controller.isLive) {
      return LiveControls(
        controller: widget.controller,
        fit: _fit,
        isFullscreen: _fullscreen,
        onLock: _toggleLock,
        onCycleFit: _cycleFit,
        onToggleFullscreen: _toggleFullscreen,
        onQuality: onQuality,
        qualityLabel: qualityLabel,
        onPip: onPip,
      );
    }
    return VodControls(
      controller: widget.controller,
      fit: _fit,
      isFullscreen: _fullscreen,
      onLock: _toggleLock,
      onCycleFit: _cycleFit,
      onToggleFullscreen: _toggleFullscreen,
      onQuality: onQuality,
      qualityLabel: qualityLabel,
      onPip: onPip,
    );
  }

  /// Builds the centered unlock button shown while locked.
  ///
  /// 构建锁定态下居中显示的解锁按钮。
  Widget _buildUnlockButton() {
    return Center(
      child: InkResponse(
        onTap: _toggleLock,
        radius: 32,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Color(0xB3000000), shape: BoxShape.circle),
          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  /// Builds the centered transient HUD pill.
  ///
  /// 构建居中的瞬时 HUD 胶囊。
  Widget _buildHud() {
    const iconFor = {
      _Hud.volume: Icons.volume_up_rounded,
      _Hud.brightness: Icons.brightness_6_rounded,
      _Hud.seek: Icons.fast_forward_rounded,
      _Hud.fit: Icons.aspect_ratio_rounded,
      _Hud.quality: Icons.high_quality_rounded,
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor[_hud], color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(_hudText, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
