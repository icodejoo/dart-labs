/// Stream type of a media source: on-demand (VOD) vs live.
///
/// 媒体源的流类型：点播（VOD）与直播（Live）。
enum VmStreamType {
  /// On-demand playback: seekable, has a fixed duration.
  ///
  /// 点播：可拖动进度，时长固定。
  vod,

  /// Live playback: usually not seekable, edge follows real time.
  ///
  /// 直播：通常不可拖动，播放头跟随实时边缘。
  live,
}

/// A playable media source description.
///
/// 一个可播放的媒体源描述。
class VmSource {
  /// Media URI (network URL or local file path).
  ///
  /// 媒体地址（网络 URL 或本地文件路径）。
  final String uri;

  /// Stream type; drives which control-bar layout is used.
  ///
  /// 流类型；决定使用哪套控制条布局。
  final VmStreamType type;

  /// Optional display title shown by the controls.
  ///
  /// 可选的标题，供控制条展示。
  final String? title;

  /// Creates a media source.
  ///
  /// 创建一个媒体源。
  ///
  /// - [uri]: media address / 媒体地址
  /// - [type]: stream type, defaults to VOD / 流类型，默认点播
  /// - [title]: optional title / 可选标题
  ///
  /// Example / 示例:
  /// ```dart
  /// final src = VmSource('https://host/live.m3u8', type: VmStreamType.live);
  /// ```
  const VmSource(this.uri, {this.type = VmStreamType.vod, this.title});
}
