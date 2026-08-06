/// Which action a directional drag performs.
///
/// Decoupling side from action lets hosts remap freely — e.g. put brightness
/// on the right, or disable one side with [none]. The vertical actions
/// ([volume]/[brightness]) are driven by vertical drag distance; [seek] is
/// driven by horizontal distance, so it only makes sense on [horizontal].
///
/// 某个方向的拖动执行哪个动作。
///
/// 将侧别与动作解耦，宿主可自由重映射——例如把亮度放右侧，或用 [none] 禁用
/// 某一侧。竖向动作（[volume]/[brightness]）由竖向拖动距离驱动；[seek] 由横向
/// 距离驱动，故只在 [horizontal] 上有意义。
enum MovaGestAction {
  /// The direction is disabled.
  ///
  /// 该方向被禁用。
  none,

  /// Adjust volume.
  ///
  /// 调整音量。
  volume,

  /// Adjust screen brightness.
  ///
  /// 调整屏幕亮度。
  brightness,

  /// Seek the timeline.
  ///
  /// 拖动进度。
  seek,
}

/// Gesture configuration for the mova player overlay.
///
/// Directional drags map to actions via [leftVertical]/[rightVertical]/
/// [horizontal], so the side↔action pairing is fully configurable. Defaults
/// follow the mainstream convention (bilibili et al.): left-vertical =
/// brightness, right-vertical = volume, horizontal = seek.
///
/// mova 播放器手势层的配置。
///
/// 各方向拖动经 [leftVertical]/[rightVertical]/[horizontal] 映射到动作，侧别与
/// 动作的配对完全可配。默认对齐主流约定（bilibili 等）：左侧竖滑=亮度，
/// 右侧竖滑=音量，横滑=进度。
class MovaGestConfig {
  /// Action for a horizontal drag. Defaults to [MovaGestAction.seek].
  ///
  /// 横向拖动的动作。默认 [MovaGestAction.seek]。
  final MovaGestAction horizontal;

  /// Action for a vertical drag starting on the left half. Defaults to
  /// [MovaGestAction.brightness].
  ///
  /// 从左半屏开始的竖向拖动的动作。默认 [MovaGestAction.brightness]。
  final MovaGestAction leftVertical;

  /// Action for a vertical drag starting on the right half. Defaults to
  /// [MovaGestAction.volume].
  ///
  /// 从右半屏开始的竖向拖动的动作。默认 [MovaGestAction.volume]。
  final MovaGestAction rightVertical;

  /// Double-tap left/right to seek backward/forward (VOD only).
  ///
  /// 双击左/右侧快退/快进（仅点播）。
  final bool doubleTapSeek;

  /// Step applied per double-tap seek.
  ///
  /// 每次双击快进/快退的步长。
  final Duration doubleTapStep;

  /// Pinch with two fingers to zoom the video.
  ///
  /// 双指捏合缩放画面。
  final bool pinchZoom;

  /// Maximum zoom factor reachable via pinch.
  ///
  /// 双指捏合可达到的最大缩放倍数。
  final double maxZoom;

  /// Timeline span (in wall-clock duration) mapped to one full screen width
  /// of horizontal drag.
  ///
  /// 横向拖动滑满一屏宽度所对应的时间轴跨度。
  final Duration hSeekSpanPerScreen;

  /// Multiplier applied to raw vertical drag distance before mapping to
  /// volume/brightness delta; higher values make the gesture more sensitive.
  ///
  /// 竖向拖动距离映射为音量/亮度增量前的放大系数；数值越大手势越灵敏。
  final double vSensitivity;

  /// Whether gestures remain active while playing a live stream.
  ///
  /// 直播场景下手势是否仍然生效。
  final bool allowWhenLive;

  /// Creates a gesture config; sides map to the mainstream defaults.
  ///
  /// 创建手势配置；各侧别按主流默认映射。
  ///
  /// Example / 示例:
  /// ```dart
  /// // Swap the sides back, and disable pinch-zoom.
  /// const cfg = MovaGestConfig(
  ///   leftVertical: MovaGestAction.volume,
  ///   rightVertical: MovaGestAction.brightness,
  ///   pinchZoom: false,
  /// );
  /// ```
  const MovaGestConfig({
    this.horizontal = MovaGestAction.seek,
    this.leftVertical = MovaGestAction.brightness,
    this.rightVertical = MovaGestAction.volume,
    this.doubleTapSeek = true,
    this.doubleTapStep = const Duration(seconds: 10),
    this.pinchZoom = true,
    this.maxZoom = 3.0,
    this.hSeekSpanPerScreen = const Duration(seconds: 90),
    this.vSensitivity = 1.0,
    this.allowWhenLive = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaGestConfig &&
          runtimeType == other.runtimeType &&
          horizontal == other.horizontal &&
          leftVertical == other.leftVertical &&
          rightVertical == other.rightVertical &&
          doubleTapSeek == other.doubleTapSeek &&
          doubleTapStep == other.doubleTapStep &&
          pinchZoom == other.pinchZoom &&
          maxZoom == other.maxZoom &&
          hSeekSpanPerScreen == other.hSeekSpanPerScreen &&
          vSensitivity == other.vSensitivity &&
          allowWhenLive == other.allowWhenLive;

  @override
  int get hashCode => Object.hash(
        horizontal,
        leftVertical,
        rightVertical,
        doubleTapSeek,
        doubleTapStep,
        pinchZoom,
        maxZoom,
        hSeekSpanPerScreen,
        vSensitivity,
        allowWhenLive,
      );
}
