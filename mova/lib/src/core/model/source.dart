import 'dart:convert';

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

  /// Extra libmpv options applied for this source only: option/property name to
  /// value, e.g. `{'cache': 'no'}`. Set right before the source loads and
  /// restored to their previous values when the next source loads, so nothing
  /// leaks into the next source. An option mpv rejects is skipped silently.
  /// `demuxer-lavf-o` is merged into the existing list (key by key), not replaced.
  ///
  /// 仅对本源生效的 libmpv 选项：选项/属性名 → 值，例如 `{'cache': 'no'}`。在本源加载前
  /// 下发，下一个源加载时还原成原值，因此不会泄漏到下一个源。mpv 不接受的选项会被静默跳过。
  /// `demuxer-lavf-o` 按键并入现有列表而不是整体替换。
  final Map<String, String> mpvOptions;

  /// FFmpeg demuxer (libavformat) options for this source, sent through mpv's
  /// `demuxer-lavf-o` (e.g. `{'media_timeout': '3000000'}`). Merged after any
  /// `demuxer-lavf-o` you put in [mpvOptions].
  ///
  /// 本源的 FFmpeg demuxer（libavformat）选项，经 mpv 的 `demuxer-lavf-o` 下发（例如
  /// `{'media_timeout': '3000000'}`）。会拼接在 [mpvOptions] 自带的 `demuxer-lavf-o` 之后。
  final Map<String, String> demuxerOptions;

  /// WHEP shortcut: how long the WHEP demuxer waits without media before
  /// treating the stream as dead (its `media_timeout`, converted to
  /// microseconds). Applied only to `whep…` addresses; an explicit
  /// `media_timeout` in [demuxerOptions] wins. A short value makes a dropped
  /// publisher fail fast so recovery can reconnect sooner.
  ///
  /// WHEP 便捷项：WHEP demuxer 多久收不到媒体就判定流已死（即其 `media_timeout`，自动换算成
  /// 微秒）。仅对 `whep…` 地址生效；[demuxerOptions] 里显式写了 `media_timeout` 时以它为准。
  /// 取较短的值能让推流端掉线后快速失败，恢复机制才能更早重连。
  final Duration? whepMediaTimeout;

  /// Creates a media source.
  ///
  /// 创建一个媒体源。
  ///
  /// - [uri]: media address / 媒体地址
  /// - [type]: stream type, defaults to VOD / 流类型，默认点播
  /// - [title]: optional title / 可选标题
  /// - [alternatives]: fallback addresses, see [alternatives] / 备选地址，见 [alternatives]
  /// - [mpvOptions]: per-source libmpv options, see [mpvOptions] / 按源 libmpv 选项，见 [mpvOptions]
  /// - [demuxerOptions]: per-source `demuxer-lavf-o` entries, see [demuxerOptions] / 按源 demuxer 选项，见 [demuxerOptions]
  /// - [whepMediaTimeout]: WHEP `media_timeout` shortcut, see [whepMediaTimeout] / WHEP `media_timeout` 便捷项，见 [whepMediaTimeout]
  ///
  /// Example / 示例:
  /// ```dart
  /// final src = MovaSource('https://host/live.m3u8', type: MovaStreamType.live);
  /// final whep = MovaSource(
  ///   'whep+http://host:8889/x/whep',
  ///   type: MovaStreamType.live,
  ///   whepMediaTimeout: Duration(seconds: 3),
  /// );
  /// ```
  const MovaSource(
    this.uri, {
    this.type = MovaStreamType.vod,
    this.title,
    this.alternatives = const [],
    this.mpvOptions = const {},
    this.demuxerOptions = const {},
    this.whepMediaTimeout,
  });

  /// [uri] followed by [alternatives].
  ///
  /// [uri] 后接 [alternatives]。
  List<String> get uris => [uri, ...alternatives];

  /// The mpv options to apply while loading [address] (one of [uris]): [mpvOptions]
  /// plus a `demuxer-lavf-o` built from [demuxerOptions] and, for a `whep…`
  /// address, [whepMediaTimeout]. Returns a fresh map; empty when there is
  /// nothing to apply.
  ///
  /// 加载 [address]（[uris] 之一）时要应用的 mpv 选项：[mpvOptions]，加上由 [demuxerOptions]
  /// 以及（`whep…` 地址的）[whepMediaTimeout] 合成的 `demuxer-lavf-o`。返回新 Map；没有要应用的
  /// 内容时为空。
  ///
  /// - [address]: the address about to load / 即将加载的地址
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaSource('whep+http://h/x', whepMediaTimeout: Duration(seconds: 3))
  ///     .mpvOptionsFor('whep+http://h/x'); // {'demuxer-lavf-o': 'media_timeout=3000000'}
  /// ```
  Map<String, String> mpvOptionsFor(String address) {
    final out = Map<String, String>.of(mpvOptions);
    final lavf = Map<String, String>.of(demuxerOptions);
    final whepTimeout = whepMediaTimeout;
    if (whepTimeout != null && address.toLowerCase().startsWith('whep')) {
      lavf.putIfAbsent('media_timeout', () => whepTimeout.inMicroseconds.toString());
    }
    if (lavf.isNotEmpty) {
      final built = lavf.entries.map((e) => '${e.key}=${_lavfValue(e.value)}').join(',');
      final own = out[_kDemuxerLavfOption];
      out[_kDemuxerLavfOption] = own == null || own.isEmpty ? built : '$own,$built';
    }
    return out;
  }

  /// Quotes [value] for mpv's key-value list syntax (`%len%value` when it holds
  /// a separator, quote, `%` or whitespace).
  ///
  /// 按 mpv 键值列表语法给 [value] 加引（含分隔符、引号、`%` 或空白时用 `%长度%值`）。
  static String _lavfValue(String value) =>
      _needsQuoting.hasMatch(value) ? '%${utf8.encode(value).length}%$value' : value;

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
  /// - [mpvOptions]: per-source libmpv options / 按源 libmpv 选项
  /// - [demuxerOptions]: per-source `demuxer-lavf-o` entries / 按源 demuxer 选项
  /// - [whepMediaTimeout]: WHEP `media_timeout` shortcut / WHEP `media_timeout` 便捷项
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
    Map<String, String> mpvOptions = const {},
    Map<String, String> demuxerOptions = const {},
    Duration? whepMediaTimeout,
  }) {
    final seen = <String>{};
    final clean = <String>[];
    for (final c in candidates) {
      final t = c?.trim();
      if (t == null || t.isEmpty || !seen.add(t)) continue;
      clean.add(t);
    }
    if (clean.isEmpty) return null;
    return MovaSource(
      clean.first,
      type: type,
      title: title,
      alternatives: clean.sublist(1),
      mpvOptions: mpvOptions,
      demuxerOptions: demuxerOptions,
      whepMediaTimeout: whepMediaTimeout,
    );
  }

  /// Whether [other] would play the same media: same uri, type, alternatives
  /// (in order) and per-source options. The title is ignored — a renamed source is not
  /// worth reopening. Deliberately not `==`: this value is `const` and may be
  /// used by identity as a map key.
  ///
  /// [other] 是否会播放同一份媒体：uri、type、备选地址（含顺序）与按源选项都相同。标题不参与
  /// 比较——只改了名字不值得重开流。刻意不重写 `==`：该值是 `const`，可能被宿主按身份当
  /// Map key 用。
  ///
  /// Example / 示例:
  /// ```dart
  /// const MovaSource('https://a/live.flv').sameAs(const MovaSource('https://a/live.flv', title: 'x')); // true
  /// ```
  bool sameAs(MovaSource other) {
    if (uri != other.uri || type != other.type) return false;
    if (whepMediaTimeout != other.whepMediaTimeout) return false;
    if (!_sameMap(mpvOptions, other.mpvOptions) || !_sameMap(demuxerOptions, other.demuxerOptions)) return false;
    if (alternatives.length != other.alternatives.length) return false;
    for (var i = 0; i < alternatives.length; i++) {
      if (alternatives[i] != other.alternatives[i]) return false;
    }
    return true;
  }
}

/// mpv 属性名：FFmpeg demuxer 选项。
const String _kDemuxerLavfOption = 'demuxer-lavf-o';

/// 需要给 demuxer 选项值加引的字符：分隔符、等号、百分号、引号、反斜杠、空白。
final RegExp _needsQuoting = RegExp(r'''[,=%"'\\\s]''');

/// 两个字符串 Map 是否内容相同。
bool _sameMap(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
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
