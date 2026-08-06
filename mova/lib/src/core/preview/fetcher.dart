import 'dart:io';
import 'dart:typed_data';

/// Fetches small auxiliary assets (WebVTT tracks, sprite sheets) over HTTP.
///
/// A port rather than a direct `HttpClient` call so tests can serve canned
/// bytes and hosts can inject their own auth headers, CDN rewriting or caching
/// HTTP stack.
///
/// 通过 HTTP 拉取小型辅助资源（WebVTT 轨、雪碧图）。
///
/// 之所以做成端口而不是直接调 `HttpClient`：测试可以喂预置字节，宿主也可以
/// 注入自己的鉴权头、CDN 改写或带缓存的 HTTP 栈。
abstract class MovaHttpFetch {
  /// Fetches [url]; returns null on any non-200 response or transport error.
  ///
  /// 拉取 [url]；任何非 200 响应或传输错误都返回 null。
  ///
  /// - [url]: the absolute URL to fetch / 要拉取的绝对 URL
  ///
  /// Returns the response body, or null on failure.
  ///
  /// 返回响应体；失败时返回 null。
  Future<Uint8List?> get(Uri url);

  /// Releases any connections this fetcher holds.
  ///
  /// 释放该 fetcher 持有的连接。
  Future<void> close();
}

/// The default [MovaHttpFetch], built on `dart:io`'s [HttpClient].
///
/// Chosen over `package:http` so preview support adds no new dependency; every
/// failure mode collapses to null so a broken thumbnail track never surfaces
/// as a playback error.
///
/// 默认的 [MovaHttpFetch]，基于 `dart:io` 的 [HttpClient]。
///
/// 相比 `package:http` 选它是为了让预览功能不引入任何新依赖；所有失败路径都
/// 收敛为 null，坏掉的缩略图轨绝不会冒充成播放错误。
class IoHttpFetcher implements MovaHttpFetch {
  /// Creates a fetcher with a per-request [timeout].
  ///
  /// 创建一个每请求超时为 [timeout] 的 fetcher。
  ///
  /// - [timeout]: total per-request deadline / 单次请求的总超时
  IoHttpFetcher({this.timeout = const Duration(seconds: 10)});

  /// Total per-request deadline.
  ///
  /// 单次请求的总超时。
  final Duration timeout;

  /// The lazily created client; null until the first request.
  ///
  /// 惰性创建的客户端；首次请求前为 null。
  HttpClient? _client;

  @override
  Future<Uint8List?> get(Uri url) async {
    final client = _client ??= (HttpClient()..connectionTimeout = timeout);
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final chunks = await response.toList().timeout(timeout);
      final out = <int>[];
      for (final c in chunks) {
        out.addAll(c);
      }
      return Uint8List.fromList(out);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> close() async {
    _client?.close(force: true);
    _client = null;
  }
}
