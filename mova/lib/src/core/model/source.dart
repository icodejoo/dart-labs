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

  /// Fallback addresses tried in order after [uri] fails, when
  /// `MovaOpts.recovery` is enabled (ignored otherwise). Order them yourself —
  /// mova only promises to try them in the order given.
  ///
  /// [uri] 失败后按顺序尝试的备选地址；仅在 `MovaOpts.recovery` 开启时使用（否则
  /// 忽略）。顺序由宿主排好——mova 只保证按给定顺序尝试。
  final List<String> alternatives;

  /// Creates a media source.
  ///
  /// 创建一个媒体源。
  ///
  /// - [uri]: media address / 媒体地址
  /// - [type]: stream type, defaults to VOD / 流类型，默认点播
  /// - [title]: optional title / 可选标题
  /// - [alternatives]: fallback addresses, see [alternatives] / 备选地址，见 [alternatives]
  ///
  /// Example / 示例:
  /// ```dart
  /// final src = MovaSource('https://host/live.m3u8', type: MovaStreamType.live);
  /// ```
  const MovaSource(this.uri, {this.type = MovaStreamType.vod, this.title, this.alternatives = const []});

  /// [uri] followed by [alternatives].
  ///
  /// [uri] 后接 [alternatives]。
  List<String> get uris => [uri, ...alternatives];

  /// Builds a source from candidate addresses: trims, drops empty/null and
  /// duplicates keeping order; the first becomes [uri], the rest
  /// [alternatives]. Returns null when nothing usable is left. Sorting and
  /// protocol filtering stay with the host — mova only cleans.
  ///
  /// 用候选地址构建源：去首尾空白、剔除空串/null 与重复项并保持顺序；第一个作 [uri]，
  /// 其余作 [alternatives]。一个可用的都没有时返回 null。排序与协议过滤留给宿主——
  /// mova 只做清洗。
  ///
  /// - [candidates]: raw addresses, best first / 原始地址，最优在前
  /// - [type]: stream type / 流类型
  /// - [title]: optional title / 可选标题
  ///
  /// Example / 示例:
  /// ```dart
  /// MovaSource.pick(['', ' https://a ', 'https://b', 'https://a'], type: MovaStreamType.live);
  /// // → MovaSource('https://a', alternatives: ['https://b'])
  /// ```
  static MovaSource? pick(
    Iterable<String?> candidates, {
    MovaStreamType type = MovaStreamType.vod,
    String? title,
  }) {
    final seen = <String>{};
    final clean = <String>[];
    for (final c in candidates) {
      final t = c?.trim();
      if (t == null || t.isEmpty || !seen.add(t)) continue;
      clean.add(t);
    }
    if (clean.isEmpty) return null;
    return MovaSource(clean.first, type: type, title: title, alternatives: clean.sublist(1));
  }

  /// Whether [other] would play the same media: same uri, type and
  /// alternatives (in order). The title is ignored — a renamed source is not
  /// worth reopening. Deliberately not `==`: this value is `const` and may be
  /// used by identity as a map key.
  ///
  /// [other] 是否会播放同一份媒体：uri、type 与备选地址（含顺序）都相同。标题不参与
  /// 比较——只改了名字不值得重开流。刻意不重写 `==`：该值是 `const`，可能被宿主按身份当
  /// Map key 用。
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaSource('https://a/live.flv').sameAs(const MovaSource('https://a/live.flv', title: 'x')); // true
  /// ```
  bool sameAs(MovaSource other) {
    if (uri != other.uri || type != other.type) return false;
    if (alternatives.length != other.alternatives.length) return false;
    for (var i = 0; i < alternatives.length; i++) {
      if (alternatives[i] != other.alternatives[i]) return false;
    }
    return true;
  }
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
