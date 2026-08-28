// Shared async loader + bounded cache for SVG source text coming from an
// asset bundle or the network, so `Svgx.asset`/`Svgx.network` and
// `SvgImageProvider.asset`/`.network` never fetch the same source twice.
//
// 共享的异步 SVG 源文本加载器 + 有界缓存，供 asset/网络加载。使
// `Svgx.asset`/`Svgx.network` 与 `SvgImageProvider.asset`/`.network` 不会
// 对同一个源重复拉取。

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads and caches SVG source text fetched from an asset bundle or a URL.
///
/// Not part of the public API — reached only through [SvgSourceLoader.asset]/
/// [SvgSourceLoader.network], called by the `Svgx.asset`/`.network` widget
/// constructors and by `SvgImageProvider`.
///
/// 加载并缓存来自 asset bundle 或 URL 的 SVG 源文本。
///
/// 不属于公开 API——只经由 [SvgSourceLoader.asset]/[SvgSourceLoader.network]
/// 到达，供 `Svgx.asset`/`.network` 控件构造函数与 `SvgImageProvider` 使用。
class SvgSourceLoader {
  SvgSourceLoader._();

  /// Shared instance. / 共享单例。
  static final SvgSourceLoader instance = SvgSourceLoader._();

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
    return _cached(key, () => effectiveBundle.loadString(key));
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
  Future<String> file(File file) => _cached(file.path, file.readAsString);

  /// Loads the SVG source at [url] over plain HTTP(S), caching the result by
  /// [url]. No caching headers are honored — this is a one-shot fetch, not an
  /// HTTP cache; repeated builds hit [maximumSize]'s in-memory LRU instead.
  ///
  /// 通过 HTTP(S) 加载 [url] 处的 SVG 源，按 [url] 缓存结果。不处理任何 HTTP
  /// 缓存头——这是一次性拉取，不是 HTTP 缓存；重复构建靠 [maximumSize] 的内存
  /// LRU 命中。
  Future<String> network(String url, {Map<String, String>? headers}) {
    return _cached(url, () async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        headers?.forEach(request.headers.add);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Svgx.network: $url returned HTTP ${response.statusCode}',
            uri: Uri.parse(url),
          );
        }
        return await response.transform(utf8.decoder).join();
      } finally {
        client.close();
      }
    });
  }

  Future<String> _cached(String key, Future<String> Function() load) async {
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // move to most-recently-used
      return hit;
    }
    final value = await load();
    _cache[key] = value;
    while (_cache.length > maximumSize) {
      _cache.remove(_cache.keys.first);
    }
    return value;
  }

  /// Drops every cached source string. / 清空全部已缓存源文本。
  void clear() => _cache.clear();
}
