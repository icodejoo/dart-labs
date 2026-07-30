import 'package:flutter/widgets.dart';

import '../core/options/gesture_config.dart';

/// Full-width horizontal swipe maps to this many seconds of seek.
///
/// 一次满屏宽度的横向滑动对应的快进/快退秒数。
const double _kFullWidthSeekSeconds = 90;

/// Movement (px) before a one-finger drag locks into an axis.
///
/// 单指拖动锁定方向前需要移动的像素阈值。
const double _kAxisLockThreshold = 8;

/// Which adjustment a one-finger vertical/horizontal drag is driving.
///
/// 单指拖动当前正在驱动哪种调节。
enum _DragMode {
  /// Not yet decided.
  ///
  /// 尚未判定。
  undecided,

  /// Horizontal drag → seek.
  ///
  /// 横向拖动 → 进度。
  seek,

  /// Left-half vertical drag → volume.
  ///
  /// 左半屏竖向拖动 → 音量。
  volume,

  /// Right-half vertical drag → brightness.
  ///
  /// 右半屏竖向拖动 → 亮度。
  brightness,

  /// Two-finger pinch → zoom.
  ///
  /// 双指捏合 → 缩放。
  zoom,
}

/// Raw gesture recognizer for the video surface.
///
/// Emits high-level *intents* (seek/volume/brightness/zoom/tap) and never
/// touches playback state directly, so it stays UI- and controller-agnostic.
/// Side mapping honors [VmGestureConfig] (left=volume, right=brightness).
///
/// 视频画面的原始手势识别层。
///
/// 只发出高层*意图*（进度/音量/亮度/缩放/点击），不直接操作播放状态，
/// 因此与具体 UI、控制器解耦。侧别映射遵循 [VmGestureConfig]（左音量/右亮度）。
class VmGestureDetector extends StatefulWidget {
  /// Gesture enable/side config.
  ///
  /// 手势开关与侧别配置。
  final VmGestureConfig config;

  /// Whether the current source is live (disables seek gestures).
  ///
  /// 当前源是否直播（禁用进度类手势）。
  final bool isLive;

  /// Snapshots current volume (0–100) at drag start.
  ///
  /// 拖动开始时读取当前音量（0–100）。
  final double Function() volumeGetter;

  /// Snapshots current brightness (0–1) at drag start.
  ///
  /// 拖动开始时读取当前亮度（0–1）。
  final double Function() brightnessGetter;

  /// Emits target volume (0–100) during a left-side vertical drag.
  ///
  /// 左侧竖滑过程中发出目标音量（0–100）。
  final ValueChanged<double> onVolume;

  /// Emits target brightness (0–1) during a right-side vertical drag.
  ///
  /// 右侧竖滑过程中发出目标亮度（0–1）。
  final ValueChanged<double> onBrightness;

  /// Emits the live seek delta (seconds) during a horizontal drag.
  ///
  /// 横滑过程中发出实时进度增量（秒）。
  final ValueChanged<double> onSeekPreview;

  /// Fires when a horizontal seek drag ends, with the final delta (seconds).
  ///
  /// 横滑结束时触发，携带最终进度增量（秒）。
  final ValueChanged<double> onSeekCommit;

  /// Emits the accumulated zoom scale (relative to drag start) during a pinch.
  ///
  /// 捏合过程中发出累计缩放系数（相对拖动起点）。
  final ValueChanged<double> onZoomUpdate;

  /// Fires when a pinch ends, so the parent can persist the zoom.
  ///
  /// 捏合结束时触发，供父层固化缩放值。
  final VoidCallback onZoomEnd;

  /// Fires on double-tap; argument is the seek step (negative = backward).
  ///
  /// 双击触发；参数为进度步长（负值=快退）。
  final ValueChanged<Duration> onDoubleTapSeek;

  /// Fires on a single tap (used later to toggle the control bar).
  ///
  /// 单击触发（后续用于切换控制条显隐）。
  final VoidCallback? onTap;

  /// Creates the gesture detector overlay.
  ///
  /// 创建手势识别覆盖层。
  ///
  /// Example / 示例:
  /// ```dart
  /// VmGestureDetector(
  ///   config: const VmGestureConfig(),
  ///   isLive: false,
  ///   volumeGetter: () => 80,
  ///   brightnessGetter: () => 0.5,
  ///   onVolume: (v) {}, onBrightness: (b) {},
  ///   onSeekPreview: (s) {}, onSeekCommit: (s) {},
  ///   onZoomUpdate: (s) {}, onZoomEnd: () {},
  ///   onDoubleTapSeek: (d) {},
  /// );
  /// ```
  const VmGestureDetector({
    super.key,
    required this.config,
    required this.isLive,
    required this.volumeGetter,
    required this.brightnessGetter,
    required this.onVolume,
    required this.onBrightness,
    required this.onSeekPreview,
    required this.onSeekCommit,
    required this.onZoomUpdate,
    required this.onZoomEnd,
    required this.onDoubleTapSeek,
    this.onTap,
  });

  @override
  State<VmGestureDetector> createState() => _VmGestureDetectorState();
}

/// State machine for [VmGestureDetector]; holds per-drag snapshots.
///
/// [VmGestureDetector] 的状态机；保存每次拖动的起始快照。
class _VmGestureDetectorState extends State<VmGestureDetector> {
  _DragMode _mode = _DragMode.undecided;
  Offset _cum = Offset.zero;
  double _startValue = 0; // volume(0-100) or brightness(0-1) at drag start
  bool _startedLeft = true;
  Size _size = Size.zero;
  double _lastDoubleTapDx = 0;

  /// Records the tap position so double-tap can tell left from right.
  ///
  /// 记录点击位置，供双击判定左/右半屏。
  void _onDoubleTapDown(TapDownDetails d) => _lastDoubleTapDx = d.localPosition.dx;

  /// Applies a double-tap seek toward the tapped side (VOD only).
  ///
  /// 按点击侧执行双击快进/快退（仅点播）。
  void _onDoubleTap() {
    if (!widget.config.doubleTapSeek || widget.isLive) return;
    final backward = _lastDoubleTapDx < _size.width / 2;
    final step = widget.config.doubleTapStep;
    widget.onDoubleTapSeek(backward ? -step : step);
  }

  /// Resets per-drag state and snapshots the starting side.
  ///
  /// 重置本次拖动状态并记录起始侧。
  void _onScaleStart(ScaleStartDetails d) {
    _mode = _DragMode.undecided;
    _cum = Offset.zero;
    _startedLeft = d.localFocalPoint.dx < _size.width / 2;
  }

  /// Interprets drag/pinch movement and emits the matching intent.
  ///
  /// 解释拖动/捏合位移并发出对应意图。
  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_mode == _DragMode.zoom) {
      widget.onZoomUpdate(d.scale);
      return;
    }
    if (d.pointerCount >= 2) {
      if (!widget.config.pinchZoom) return;
      _mode = _DragMode.zoom;
      widget.onZoomUpdate(d.scale);
      return;
    }

    _cum += d.focalPointDelta;
    if (_mode == _DragMode.undecided) {
      if (_cum.distance < _kAxisLockThreshold) return;
      _mode = _decideMode();
      _snapshotStartValue();
    }
    _drive();
  }

  /// Chooses the axis/side once movement passes the lock threshold.
  ///
  /// 位移越过阈值后判定方向/侧别。
  _DragMode _decideMode() {
    if (_cum.dx.abs() > _cum.dy.abs()) {
      final canSeek = widget.config.horizontalSeek && !widget.isLive;
      return canSeek ? _DragMode.seek : _DragMode.undecided;
    }
    if (_startedLeft) {
      return widget.config.leftVerticalVolume ? _DragMode.volume : _DragMode.undecided;
    }
    return widget.config.rightVerticalBrightness
        ? _DragMode.brightness
        : _DragMode.undecided;
  }

  /// Captures the starting volume/brightness for the chosen mode.
  ///
  /// 为所选模式捕获起始音量/亮度。
  void _snapshotStartValue() {
    if (_mode == _DragMode.volume) {
      _startValue = widget.volumeGetter();
    } else if (_mode == _DragMode.brightness) {
      _startValue = widget.brightnessGetter();
    }
  }

  /// Emits the intent value derived from accumulated movement.
  ///
  /// 根据累计位移发出对应意图值。
  void _drive() {
    switch (_mode) {
      case _DragMode.seek:
        final seconds = _cum.dx / _size.width * _kFullWidthSeekSeconds;
        widget.onSeekPreview(seconds);
        break;
      case _DragMode.volume:
        final frac = -_cum.dy / _size.height; // up = louder
        widget.onVolume((_startValue + frac * 100).clamp(0, 100));
        break;
      case _DragMode.brightness:
        final frac = -_cum.dy / _size.height; // up = brighter
        widget.onBrightness((_startValue + frac).clamp(0.0, 1.0));
        break;
      case _DragMode.undecided:
      case _DragMode.zoom:
        break;
    }
  }

  /// Commits seek / finalizes zoom when the gesture ends.
  ///
  /// 手势结束时提交进度 / 固化缩放。
  void _onScaleEnd(ScaleEndDetails d) {
    if (_mode == _DragMode.seek) {
      widget.onSeekCommit(_cum.dx / _size.width * _kFullWidthSeekSeconds);
    } else if (_mode == _DragMode.zoom) {
      widget.onZoomEnd();
    }
    _mode = _DragMode.undecided;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
        );
      },
    );
  }
}
