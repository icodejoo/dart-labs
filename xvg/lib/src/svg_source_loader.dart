// Shared async loader + bounded cache for SVG source text coming from an
// asset bundle or the network, so `Xvg.asset`/`Xvg.network` and
// `SvgImageProvider.asset`/`.network` never fetch the same source twice.
//
// 共享的异步 SVG 源文本加载器 + 有界缓存，供 asset/网络加载。使
// `Xvg.asset`/`Xvg.network` 与 `SvgImageProvider.asset`/`.network` 不会
// 对同一个源重复拉取。
// Image providers now use the independent byte entry points below; only the
// existing text entry points share the source-text LRU with Xvg widgets.
// ImageProvider 现使用下方独立字节入口；只有原有文本入口与 Xvg 控件共享文本 LRU。

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_file.dart'
    if (dart.library.js_interop) 'platform_file_web.dart';
import 'source_network_native.dart'
    if (dart.library.js_interop) 'source_network_web.dart';
import 'svg_source_bytes.dart';

export 'svg_source_bytes.dart';

/// Loads and caches SVG source text fetched from an asset bundle or a URL.
///
/// Not part of the public API — reached only through [SvgSourceLoader.asset]/
/// [SvgSourceLoader.network], called by the `Xvg.asset`/`.network` widget
/// constructors and by `SvgImageProvider`.
///
/// 加载并缓存来自 asset bundle 或 URL 的 SVG 源文本。
///
/// 不属于公开 API——只经由 [SvgSourceLoader.asset]/[SvgSourceLoader.network]
/// 到达，供 `Xvg.asset`/`.network` 控件构造函数与 `SvgImageProvider` 使用。
/// Byte entry points serve ImageProviders without changing the text cache.
/// 字节入口供 ImageProvider 使用，不改变原有文本缓存。
class SvgSourceLoader {
  SvgSourceLoader._();

  /// Shared instance. / 共享单例。
  static final SvgSourceLoader instance = SvgSourceLoader._();

  /// Timeout for each network phase; tests may override the 30-second default.
  /// 每个网络阶段的超时；测试可覆盖默认的 30 秒。
  @visibleForTesting
  static Duration networkTimeout = const Duration(seconds: 30);

  /// Loads raw asset [name], optionally from [bundle] and [package].
  /// Returns original bytes; this does not populate the text cache.
  /// 从可选 [bundle]、[package] 加载资源 [name] 的原始字节，不写入文本缓存。
  Future<Uint8List> assetBytes(
    String name, {
    AssetBundle? bundle,
    String? package,
  }) async {
    final key = package == null ? name : 'packages/$package/$name';
    final data = await (bundle ?? rootBundle).load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Reads original bytes from [file] without populating the text cache.
  /// 从 [file] 读取原始字节，不写入文本缓存。
  Future<Uint8List> fileBytes(File file) => file.readAsBytes();

  /// Fetches original image bytes and content type from [url], forwarding
  /// [headers] and cumulative progress to [onBytesReceived]. Non-200 responses
  /// throw [NetworkImageLoadException]; each network phase uses [networkTimeout].
  /// Failed or timed-out requests are aborted without closing the shared client.
  /// 从 [url] 获取原始图片字节及类型，透传 [headers]，通过 [onBytesReceived]
  /// 报告累计进度；非 200 抛 [NetworkImageLoadException]，各阶段限时 [networkTimeout]。
  /// 失败或超时只中止当前请求，不关闭共享客户端。
  Future<SvgSourceBytes> networkBytes(
    String url, {
    Map<String, String>? headers,
    void Function(int cumulativeBytesLoaded, int? expectedTotalBytes)?
    onBytesReceived,
  }) async {
    return loadNetworkBytes(url, headers, onBytesReceived, networkTimeout);
  }

  final Map<String, Future<String>> _inFlight = {};
  int _generation = 0;
  // Expando 按 bundle 身份分配编号，避免不同 bundle 的同名资源碰撞。
  final Expando<int> _bundleIds = Expando<int>();
  int _nextBundleId = 0;

  /// Returns a stable JSON key for [headers], sorted by header name, for
  /// cache and in-flight request identity. Null or empty maps return `[]`.
  /// Header names and values are preserved exactly as supplied.
  ///
  /// 将 [headers] 按头名称排序并返回稳定的 JSON 键，用于缓存和在途请求去重。
  /// 参数为 null 或空映射时返回 `[]`；头名称和值保留原样。
  static String headersKey(Map<String, String>? headers) {
    final keys = headers?.keys.toList() ?? <String>[];
    keys.sort();
    return jsonEncode([
      for (final key in keys) [key, headers![key]],
    ]);
  }

  final LinkedHashMap<String, String> _cache = LinkedHashMap<String, String>();

  /// Max cached source strings before least-recently-used ones are dropped.
  ///
  /// 缓存上限，超出后淘汰最久未用的条目。
  int maximumSize = 100;

  /// Loads [name] from [bundle] (or the ambient [rootBundle] when null),
  /// resolved against [package] the same way [AssetImage] does, caching the
  /// result by the fully-resolved asset key.
  ///
  /// 从 [bundle](为 null 时用环境 [rootBundle])加载 [name]，按 [package] 解析
  /// 方式与 [AssetImage] 一致，按完整解析后的 asset key 缓存结果。
  Future<String> asset(String name, {AssetBundle? bundle, String? package}) {
    final key = package == null ? name : 'packages/$package/$name';
    final effectiveBundle = bundle ?? rootBundle;
    final id = _bundleIds[effectiveBundle] ??= _nextBundleId++;
    return _cached('asset:$id:$key', () => effectiveBundle.loadString(key));
  }

  /// Loads the SVG source from [file] on disk, caching the result by its
  /// path. Rereads the file on a cache miss only — a change to the file on
  /// disk after this loader has cached it won't be picked up until the entry
  /// ages out of [maximumSize]'s LRU, mirroring the same one-shot-fetch
  /// trade-off [network] documents.
  ///
  /// 从磁盘上的 [file] 加载 SVG 源，按其路径缓存结果。只在缓存未命中时才重新读
  /// 文件——缓存之后文件在磁盘上被改动，要等这条缓存被 [maximumSize] 的 LRU
  /// 淘汰才会被重新读取，与 [network] 记录的"一次性拉取"取舍一致。
  Future<String> file(File file) =>
      _cached('file:${file.path}', file.readAsString);

  /// Loads the SVG source at [url] over plain HTTP(S), caching the result by
  /// [url]. No caching headers are honored — this is a one-shot fetch, not an
  /// HTTP cache; repeated builds hit [maximumSize]'s in-memory LRU instead.
  /// Connection, response headers, and the entire response body each have
  /// a separate 30-second timeout (up to 90 seconds total).
  ///
  /// 通过 HTTP(S) 加载 [url] 处的 SVG 源，按 [url] 缓存结果。不处理任何 HTTP
  /// 缓存头——这是一次性拉取，不是 HTTP 缓存；重复构建靠 [maximumSize] 的内存
  /// LRU 命中。
  /// 连接、响应头、完整响应体各自限时 30 秒（合计最多 90 秒）。
  Future<String> network(String url, {Map<String, String>? headers}) {
    final requestHeaders = headers == null
        ? null
        : Map<String, String>.of(headers);
    return _cached(
      'net:${jsonEncode([url, headersKey(requestHeaders)])}',
      () async {
        return loadNetworkText(url, requestHeaders, networkTimeout);
      },
    );
  }

  Future<String> _cached(String key, Future<String> Function() load) async {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // move to most-recently-used
      return hit;
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final generation = _generation;
    final future = Future<String>.sync(load).then((value) {
      if (generation != _generation) return value;
      _cache[key] = value;
      while (_cache.isNotEmpty && _cache.length > maximumSize) {
        _cache.remove(_cache.keys.first);
      }
      return value;
    });
    _inFlight[key] = future;
    void cleanup() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }

    future.then(
      (_) => cleanup(),
      onError: (Object _, StackTrace _) => cleanup(),
    );
    return future;
  }

  /// Drops cached sources and invalidates in-flight cache writes. Existing
  /// callers still receive their results; new callers start a fresh load.
  /// 清空缓存并使在途加载的缓存写入失效；旧调用方仍收到结果，新调用方重新加载。
  void clear() {
    _generation++;
    _cache.clear();
    _inFlight.clear();
  }
}
