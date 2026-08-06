import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../model/source.dart';
import 'fetcher.dart';
import 'models.dart';
import 'source.dart';
import 'vtt.dart';

/// Strategy for locating a media's WebVTT thumbnail track.
///
/// 定位某个媒体的 WebVTT 缩略图轨的策略。
///
/// - [source]: the media being previewed / 正在预览的媒体
///
/// Returns the track URL, or null to disable the VTT source for this media.
///
/// 返回该轨的 URL；返回 null 表示对该媒体禁用 VTT 来源。
typedef MovaVttUrlSolver = Uri? Function(MovaSource source);

/// The conventional thumbnail track location: the media URL with `.vtt`
/// appended to its path, query and fragment preserved.
///
/// 约定的缩略图轨位置：在媒体 URL 的路径后追加 `.vtt`，保留 query 与 fragment。
///
/// - [source]: the media being previewed / 正在预览的媒体
///
/// Returns the derived URL, or null when the media URI has no usable path.
///
/// 返回推导出的 URL；媒体 URI 没有可用路径时返回 null。
Uri? defaultVttUrl(MovaSource source) {
  final u = Uri.tryParse(source.uri);
  if (u == null || u.path.isEmpty) return null;
  return u.replace(path: '${u.path}.vtt');
}

/// A [MovaThumbSource] backed by a server-provided WebVTT thumbnail track and
/// its sprite sheets.
///
/// The track is fetched once per media and memoised, including the negative
/// result: a 404 must not trigger a fetch on every scrub tick. Sprite sheets
/// are memoised too, bounded by `maxSprites` in least-recently-used order.
///
/// 基于服务端提供的 WebVTT 缩略图轨及其雪碧图的 [MovaThumbSource]。
///
/// 每个媒体只拉取一次轨并记忆结果——包括失败结果：404 不能让每次拖动 tick 都
/// 重新发请求。雪碧图同样被记忆，按最近最少使用顺序、以 `maxSprites` 为上限。
class MovaVttThumbSource implements MovaThumbSource {
  /// Creates a VTT-backed thumbnail source.
  ///
  /// 创建基于 VTT 的缩略图来源。
  ///
  /// - [fetcher]: HTTP port used for the track and sprites / 拉取轨与雪碧图的
  ///   HTTP 端口
  /// - [resolveUrl]: strategy locating the track, defaults to [defaultVttUrl] /
  ///   定位轨的策略，默认为 [defaultVttUrl]
  /// - [maxSprites]: how many sprite sheets stay memoised / 最多记忆多少张雪碧图
  MovaVttThumbSource({
    required this.fetcher,
    this.resolveUrl = defaultVttUrl,
    this.maxSprites = 4,
  });

  /// HTTP port used for the track and its sprite sheets.
  ///
  /// 拉取轨及其雪碧图所用的 HTTP 端口。
  final MovaHttpFetch fetcher;

  /// Strategy locating the WebVTT track for a media.
  ///
  /// 为某个媒体定位 WebVTT 轨的策略。
  final MovaVttUrlSolver resolveUrl;

  /// Ceiling on memoised sprite sheets.
  ///
  /// 记忆雪碧图的数量上限。
  final int maxSprites;

  /// The parsed track for the current media, or null before the first fetch.
  ///
  /// 当前媒体已解析的轨；首次拉取前为 null。
  MovaThumbIndex? _index;

  /// Whether resolving/fetching/parsing the track already failed for the
  /// current media, so it must not be retried on every scrub.
  ///
  /// 当前媒体的轨是否已在解析/拉取/定位环节失败过，避免每次拖动都重试。
  bool _unavailable = false;

  /// Memoised sprite sheets in least-recently-used-first order.
  ///
  /// 按"最久未使用在前"顺序记忆的雪碧图。
  final LinkedHashMap<String, Uint8List> _sprites = LinkedHashMap<String, Uint8List>();

  @override
  String get name => 'vtt';

  /// Fetches and parses the track once per media.
  ///
  /// 每个媒体只拉取并解析一次轨。
  ///
  /// - [source]: the media being previewed / 正在预览的媒体
  ///
  /// Returns the parsed index, or null when unavailable.
  ///
  /// 返回解析出的索引；不可用时返回 null。
  Future<MovaThumbIndex?> _ensureIndex(MovaSource source) async {
    if (_unavailable) return null;
    final cached = _index;
    if (cached != null) return cached;

    final url = resolveUrl(source);
    if (url == null) {
      _unavailable = true;
      return null;
    }
    final bytes = await fetcher.get(url);
    if (bytes == null) {
      _unavailable = true;
      return null;
    }
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      _unavailable = true;
      return null;
    }
    final index = parseVttThumbs(text, base: url);
    if (index.isEmpty) {
      _unavailable = true;
      return null;
    }
    _index = index;
    return index;
  }

  /// Fetches [url]'s sprite sheet, memoising it under an LRU bound.
  ///
  /// 拉取 [url] 对应的雪碧图，并在 LRU 上限内记忆之。
  ///
  /// - [url]: the sprite sheet URL / 雪碧图 URL
  ///
  /// Returns the sheet bytes, or null when the fetch failed.
  ///
  /// 返回雪碧图字节；拉取失败时返回 null。
  Future<Uint8List?> _sprite(Uri url) async {
    final key = url.toString();
    final hit = _sprites.remove(key);
    if (hit != null) {
      _sprites[key] = hit;
      return hit;
    }
    final bytes = await fetcher.get(url);
    if (bytes == null) return null;
    if (maxSprites > 0) {
      _sprites[key] = bytes;
      while (_sprites.length > maxSprites) {
        _sprites.remove(_sprites.keys.first);
      }
    }
    return bytes;
  }

  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async {
    final index = await _ensureIndex(source);
    if (index == null) return null;
    final cue = index.cueAt(bucket);
    if (cue == null) return null;
    final bytes = await _sprite(cue.image);
    if (bytes == null) return null;
    return MovaThumb(at: bucket, bytes: bytes, crop: cue.crop);
  }

  @override
  Future<void> reset() async {
    _index = null;
    _unavailable = false;
    _sprites.clear();
  }

  @override
  Future<void> dispose() async {
    await reset();
    await fetcher.close();
  }
}
