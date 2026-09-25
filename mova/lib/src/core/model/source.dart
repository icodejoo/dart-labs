/// Stream type of a media source: on-demand (VOD) vs live.
///
/// 媒体源的流类型：点播（VOD）与直播（Live）。
enum MovaStreamType {
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
class MovaSource {
  /// Media URI (network URL or local file path).
  ///
  /// 媒体地址（网络 URL 或本地文件路径）。
  final String uri;

  /// Stream type; drives which control-bar layout is used.
  ///
  /// 流类型；决定使用哪套控制条布局。
  final MovaStreamType type;

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
  /// final src = MovaSource('https://host/live.m3u8', type: MovaStreamType.live);
  /// ```
  const MovaSource(this.uri, {this.type = MovaStreamType.vod, this.title});
}

/// Resolves the content source on demand, called only when the player is
/// actually about to open it.
///
/// Exists so a host can hand `MovaAdController` a promise of a source rather than a
/// source: the real content URL is commonly decided *after* the pre-roll has
/// played — by entitlement/DRM checks, by the viewer profile, or simply
/// because a signed URL minted at page load would already have expired by the
/// time the ads finish.
///
/// 按需解析正片源，仅在播放器真的要打开它时才被调用。
///
/// 它的存在是为了让宿主能把"一个源的承诺"而非"一个源"交给 `MovaAdController`：
/// 真实的正片地址常常是在前贴片播完*之后*才定下来的——取决于权益/DRM 校验、
/// 用户画像，或者仅仅因为页面加载时签发的签名 URL 到广告播完早就过期了。
typedef MovaSourceResolver = Future<MovaSource> Function();
