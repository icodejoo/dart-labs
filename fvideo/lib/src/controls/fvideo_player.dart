import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../core/fvideo_config.dart';
import '../core/fvideo_controller.dart';
import 'gesture_layer.dart';

/// Which transient HUD indicator is currently shown.
///
/// 当前显示的瞬时 HUD 指示器种类。
enum _Hud { none, volume, brightness, seek }

/// How long the HUD stays visible after the last update.
///
/// 最后一次更新后 HUD 保持可见的时长。
const Duration _kHudLinger = Duration(milliseconds: 700);

/// The fvideo player widget: video surface + zoom + gesture control layer.
///
/// Renders a media_kit [Video] with its built-in controls disabled and
/// overlays fvideo's own gestures (left=volume, right=brightness,
/// horizontal=seek, double-tap=seek, pinch=zoom) with HUD feedback. The
/// VOD/live control bars land in a later milestone (P3).
///
/// fvideo 播放器组件：视频画面 + 缩放 + 手势控制层。
///
/// 渲染 media_kit 的 [Video]（关闭其内置控制条），叠加 fvideo 自己的手势
/// （左音量/右亮度/横滑进度/双击快进退/双指缩放）并带 HUD 反馈。点播/直播
/// 控制条在后续里程碑（P3）实现。
class FvideoPlayer extends StatefulWidget {
  /// The playback controller to render and drive.
  ///
  /// 用于渲染和驱动的播放控制器。
  final FvideoController controller;

  /// Gesture enable/side configuration.
  ///
  /// 手势开关与侧别配置。
  final FvideoGestureConfig gestureConfig;

  /// Maximum pinch-zoom scale factor.
  ///
  /// 双指缩放的最大倍数。
  final double maxZoom;

  /// Creates a player bound to [controller].
  ///
  /// 创建绑定到 [controller] 的播放器。
  ///
  /// Example / 示例:
  /// ```dart
  /// FvideoPlayer(controller: myController);
  /// ```
  const FvideoPlayer({
    super.key,
    required this.controller,
    this.gestureConfig = const FvideoGestureConfig(),
    this.maxZoom = 3.0,
  });

  @override
  State<FvideoPlayer> createState() => _FvideoPlayerState();
}

/// State for [FvideoPlayer]; owns zoom, brightness cache and HUD timing.
///
/// [FvideoPlayer] 的状态；持有缩放、亮度缓存与 HUD 计时。
class _FvideoPlayerState extends State<FvideoPlayer> {
  final ScreenBrightness _brightnessPlugin = ScreenBrightness();
  double _zoom = 1.0;
  double _baseZoom = 1.0;
  double _brightness = 1.0;

  _Hud _hud = _Hud.none;
  String _hudText = '';
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();
    _loadBrightness();
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    super.dispose();
  }

  /// Reads the current screen brightness into the local cache.
  ///
  /// 读取当前屏幕亮度到本地缓存。
  Future<void> _loadBrightness() async {
    try {
      _brightness = await _brightnessPlugin.application;
    } catch (_) {
      _brightness = 1.0; // unsupported platform / 平台不支持时兜底
    }
  }

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
    _showHud(_Hud.seek, '${_fmt(target)}  $sign${_fmt(Duration(seconds: seconds.abs().round()))}');
  }

  /// Commits the accumulated horizontal seek.
  ///
  /// 提交累计的横向进度调整。
  void _onSeekCommit(double seconds) {
    widget.controller.seek(_clampedTarget(seconds));
  }

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

  @override
  Widget build(BuildContext context) {
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
              ),
            ),
          ),
          FvideoGestureDetector(
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
          ),
          if (_hud != _Hud.none) _buildHud(),
        ],
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
