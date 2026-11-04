import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../model/source.dart';
import 'fetcher.dart';
import 'models.dart';
import 'request_blocked.dart';
import 'request_context.dart';
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
/// Successful tracks are memoised per media; failures use a bounded retry
/// cooldown so a 404 never triggers a fetch on every scrub tick. Sprite sheets
/// are memoised too, bounded by `maxSprites` in least-recently-used order.
///
/// 基于服务端提供的 WebVTT 缩略图轨及其雪碧图的 [MovaThumbSource]。
///
/// 每个媒体记忆成功结果，失败结果只记忆一个重试冷却期：404 不能让每次拖动 tick 都
/// 重新发请求。雪碧图同样被记忆，按最近最少使用顺序、以 `maxSprites` 为上限。
class MovaVttThumbSource implements MovaThumbSource {
  /// Creates a VTT-backed thumbnail source.
  ///
  /// 创建基于 VTT 的缩略图来源。
  ///
  /// - [fetcher]: HTTP port used for the track and sprites / 拉取轨与雪碧图的
  ///   HTTP 端口
  /// - [closeFetcher]: 销毁时是否关闭端口，借用宿主端口时设为 false。
  /// - [resolveUrl]: strategy locating the track, defaults to [defaultVttUrl] /
  ///   定位轨的策略，默认为 [defaultVttUrl]
  /// - [maxSprites]: how many sprite sheets stay memoised / 最多记忆多少张雪碧图
  /// - [retryDelay]: 失败后冷却时间，默认 30 秒。
  /// - [now]: 重试时钟，默认 DateTime.now。
  ///
  /// 示例：`MovaVttThumbSource(fetcher: fetcher, retryDelay: Duration(seconds: 10))`。
  MovaVttThumbSource({
    required this.fetcher,
    this.closeFetcher = true,
    this.resolveUrl = defaultVttUrl,
    this.maxSprites = 4,
    this.retryDelay = const Duration(seconds: 30),
    DateTime Function() now = DateTime.now,
  }) : _now = now; // ignore: prefer_initializing_formals

  /// 失败后再次探测的冷却时间；默认 30 秒。
  final Duration retryDelay;

  /// 注入的时钟，用于可重复地测试重试冷却。
  final DateTime Function() _now;

  /// 下一次允许重试的时间；成功或换源时清除。
  DateTime? _retryAt;

  /// HTTP port used for the track and its sprite sheets.
  ///
  /// 拉取轨及其雪碧图所用的 HTTP 端口。
  final MovaHttpFetch fetcher;

  /// 销毁时是否关闭 HTTP 端口；借用宿主端口时设为 false，默认 true。
  final bool closeFetcher;

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

  /// Whether the URL solver explicitly disabled VTT for the current media.
  ///
  /// URL 策略明确返回 null 时禁用当前媒体；网络或解析失败仅进入冷却期。
  bool _unavailable = false;

  /// Memoised sprite sheets in least-recently-used-first order.
  ///
  /// 按"最久未使用在前"顺序记忆的雪碧图。
  final LinkedHashMap<String, Uint8List> _sprites =
      LinkedHashMap<String, Uint8List>();

  /// Bumped by every [reset]; in-flight fetches compare it to detect that the
  /// media changed, and then drop their result instead of writing it back.
  ///
  /// 每次 [reset] 都递增；在途拉取据此判断媒体已换，丢弃结果而不是写回。
  int _epoch = 0;

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
    if (_unavailable || (_retryAt != null && _now().isBefore(_retryAt!))) {
      return null;
    }
    final cached = _index;
    if (cached != null) return cached;

    final epoch = _epoch;
    final url = resolveUrl(source);
    if (url == null) {
      _unavailable = true;
      return null;
    }
    Uint8List? bytes;
    try {
      bytes = await movaFetchWithHeaders(fetcher, url, source.requestHeaders);
    } on PreviewPolicyBlocked {
      rethrow;
    } on PreviewRequestCancelled {
      rethrow;
    } on Object {
      bytes = null;
    }
    if (epoch != _epoch) return null;
    if (bytes == null) {
      _retryAt = _now().add(retryDelay);
      return null;
    }
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      _retryAt = _now().add(retryDelay);
      return null;
    }
    final index = parseVttThumbs(text, base: url);
    if (index.isEmpty) {
      _retryAt = _now().add(retryDelay);
      return null;
    }
    _retryAt = null;
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
  Future<Uint8List?> _sprite(Uri url, MovaSource source) async {
    final key = url.toString();
    final hit = _sprites.remove(key);
    if (hit != null) {
      _sprites[key] = hit;
      return hit;
    }
    final epoch = _epoch;
    final bytes = await movaFetchWithHeaders(
      fetcher,
      url,
      source.requestHeaders,
    );
    if (bytes == null || epoch != _epoch) return null;
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
    final epoch = _epoch;
    final index = await _ensureIndex(source);
    if (index == null || epoch != _epoch) return null;
    final cue = index.cueAt(bucket);
    if (cue == null) return null;
    final bytes = await _sprite(cue.image, source);
    if (bytes == null || epoch != _epoch) return null;
    return MovaThumb(at: bucket, bytes: bytes, crop: cue.crop);
  }

  @override
  Future<void> reset() async {
    _epoch++;
    _index = null;
    _unavailable = false;
    _retryAt = null;
    _sprites.clear();
  }

  @override
  Future<void> dispose() async {
    await reset();
    if (closeFetcher) await fetcher.close();
  }
}
