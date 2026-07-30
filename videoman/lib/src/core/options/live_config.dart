/// Seek behaviour available on a live stream.
///
/// 直播流可用的进度拖动行为。
enum VmLiveSeekMode {
  /// No seeking on the live timeline.
  ///
  /// 直播时间轴不可拖动。
  off,

  /// Seek within the server-side DVR window.
  ///
  /// 在服务端 DVR 窗口内拖动。
  dvr,

  /// Seek within a locally buffered time-shift window.
  ///
  /// 在本地缓冲的时移窗口内拖动。
  timeshift,
}

/// Live-playback configuration.
///
/// 直播播放配置。
class VmLiveConfig {
  /// Which seek mode is available for the live stream.
  ///
  /// 直播流可用的拖动模式。
  final VmLiveSeekMode seekMode;

  /// Size of the DVR/time-shift window, when [seekMode] is not [VmLiveSeekMode.off].
  ///
  /// DVR/时移窗口的大小（[seekMode] 非 [VmLiveSeekMode.off] 时生效）。
  final Duration? dvrWindow;

  /// How close to the live edge counts as "at the edge" for UI purposes.
  ///
  /// 用于 UI 判断"已处于直播边缘"的接近阈值。
  final Duration edgeThreshold;

  /// Creates a live config; seeking off and a 10-second edge threshold by
  /// default.
  ///
  /// 创建直播配置；默认禁用拖动，边缘阈值为 10 秒。
  const VmLiveConfig({
    this.seekMode = VmLiveSeekMode.off,
    this.dvrWindow,
    this.edgeThreshold = const Duration(seconds: 10),
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmLiveConfig &&
          runtimeType == other.runtimeType &&
          seekMode == other.seekMode &&
          dvrWindow == other.dvrWindow &&
          edgeThreshold == other.edgeThreshold;

  @override
  int get hashCode => Object.hash(seekMode, dvrWindow, edgeThreshold);
}
