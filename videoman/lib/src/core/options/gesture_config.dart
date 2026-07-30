/// Gesture configuration for the videoman player overlay.
///
/// Side mapping follows the product spec: left-vertical = volume,
/// right-vertical = brightness, horizontal = seek. (This intentionally
/// differs from media_kit's built-in controls, whose sides are swapped
/// and not configurable.)
///
/// videoman 播放器手势层的配置。
///
/// 侧别映射遵循产品规格：左侧竖滑=音量，右侧竖滑=亮度，横滑=进度。
/// （这与 media_kit 内置控制条相反，且内置侧别写死不可配。）
class VmGestureConfig {
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

  /// Creates a gesture config; all gestures on by default.
  ///
  /// 创建手势配置；默认全部开启。
  ///
  /// Example / 示例:
  /// ```dart
  /// const cfg = VmGestureConfig(pinchZoom: false);
  /// ```
  const VmGestureConfig({
    this.horizontalSeek = true,
    this.leftVerticalVolume = true,
    this.rightVerticalBrightness = true,
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
      other is VmGestureConfig &&
          runtimeType == other.runtimeType &&
          horizontalSeek == other.horizontalSeek &&
          leftVerticalVolume == other.leftVerticalVolume &&
          rightVerticalBrightness == other.rightVerticalBrightness &&
          doubleTapSeek == other.doubleTapSeek &&
          doubleTapStep == other.doubleTapStep &&
          pinchZoom == other.pinchZoom &&
          maxZoom == other.maxZoom &&
          hSeekSpanPerScreen == other.hSeekSpanPerScreen &&
          vSensitivity == other.vSensitivity &&
          allowWhenLive == other.allowWhenLive;

  @override
  int get hashCode => Object.hash(
        horizontalSeek,
        leftVerticalVolume,
        rightVerticalBrightness,
        doubleTapSeek,
        doubleTapStep,
        pinchZoom,
        maxZoom,
        hSeekSpanPerScreen,
        vSensitivity,
        allowWhenLive,
      );
}
