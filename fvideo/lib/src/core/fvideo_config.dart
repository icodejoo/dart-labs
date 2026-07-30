/// Video surface fill mode.
///
/// 画面填充模式。
enum FvideoFit {
  /// Fit entirely inside the box, letterboxed (default).
  ///
  /// 完整放入画框，可能留黑边（默认）。
  contain,

  /// Fill the box, cropping overflow.
  ///
  /// 铺满画框，裁掉溢出部分。
  cover,

  /// Stretch to fill, ignoring aspect ratio.
  ///
  /// 拉伸铺满，忽略宽高比。
  fill;

  /// The next mode in the contain → cover → fill cycle.
  ///
  /// contain → cover → fill 循环中的下一个模式。
  FvideoFit get next => switch (this) {
        FvideoFit.contain => FvideoFit.cover,
        FvideoFit.cover => FvideoFit.fill,
        FvideoFit.fill => FvideoFit.contain,
      };

  /// Short display label for the mode.
  ///
  /// 模式的简短显示标签。
  String get label => switch (this) {
        FvideoFit.contain => '适应',
        FvideoFit.cover => '裁剪',
        FvideoFit.fill => '拉伸',
      };
}

/// Gesture configuration for the fvideo player overlay.
///
/// Side mapping follows the product spec: left-vertical = volume,
/// right-vertical = brightness, horizontal = seek. (This intentionally
/// differs from media_kit's built-in controls, whose sides are swapped
/// and not configurable.)
///
/// fvideo 播放器手势层的配置。
///
/// 侧别映射遵循产品规格：左侧竖滑=音量，右侧竖滑=亮度，横滑=进度。
/// （这与 media_kit 内置控制条相反，且内置侧别写死不可配。）
class FvideoGestureConfig {
  /// Horizontal drag seeks the timeline (VOD only).
  ///
  /// 横向拖动调整进度（仅点播）。
  final bool horizontalSeek;

  /// Vertical drag on the left half adjusts volume.
  ///
  /// 左半屏竖向拖动调整音量。
  final bool leftVerticalVolume;

  /// Vertical drag on the right half adjusts screen brightness.
  ///
  /// 右半屏竖向拖动调整屏幕亮度。
  final bool rightVerticalBrightness;

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

  /// Creates a gesture config; all gestures on by default.
  ///
  /// 创建手势配置；默认全部开启。
  ///
  /// Example / 示例:
  /// ```dart
  /// const cfg = FvideoGestureConfig(pinchZoom: false);
  /// ```
  const FvideoGestureConfig({
    this.horizontalSeek = true,
    this.leftVerticalVolume = true,
    this.rightVerticalBrightness = true,
    this.doubleTapSeek = true,
    this.doubleTapStep = const Duration(seconds: 10),
    this.pinchZoom = true,
  });
}
