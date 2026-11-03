import 'dart:async';
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
class MovaIoHttpFetcher implements MovaHttpFetch {
  /// Creates a fetcher with a per-request [timeout].
  ///
  /// 创建一个每请求超时为 [timeout] 的 fetcher。
  ///
  /// - [timeout]: total per-request deadline / 单次请求的总超时
  MovaIoHttpFetcher({this.timeout = const Duration(seconds: 10)});

  /// Total per-request deadline.
  ///
  /// 单次请求的总超时。
  final Duration timeout;

  /// The lazily created client; null until the first request.
  ///
  /// 惰性创建的客户端；首次请求前为 null。
  HttpClient? _client;

  /// 正在执行的取消回调；close 同步唤醒所有等待者。
  final Set<void Function()> _pending = {};

  /// 已关闭后不再创建新的连接。
  bool _closed = false;

  /// 拉取 [url]，总期限涵盖连接、响应头及响应体；失败返回 null。
  ///
  /// 示例：`await fetcher.get(Uri.parse('https://host/thumb.vtt'))`。
  @override
  Future<Uint8List?> get(Uri url) async {
    if (_closed) return null;
    final client = _client ??= (HttpClient()..connectionTimeout = timeout);
    final result = Completer<Uint8List?>();
    HttpClientRequest? request;

    /// 超时或关闭时中止套接字并唤醒调用方。
    void cancel() {
      request?.abort();
      if (!result.isCompleted) result.complete(null);
    }

    /// 执行完整请求，迟到的连接立即中止，避免释放后重新挂起。
    Future<void> run() async {
      try {
        final req = await client.getUrl(url);
        request = req;
        if (result.isCompleted || _closed) {
          req.abort();
          return;
        }
        final response = await req.close();
        if (response.statusCode != HttpStatus.ok) {
          cancel();
          return;
        }
        final chunks = await response.toList();
        final out = BytesBuilder(copy: false);
        for (final chunk in chunks) {
          out.add(chunk);
        }
        if (!result.isCompleted) result.complete(out.takeBytes());
      } on Object {
        cancel();
      }
    }

    _pending.add(cancel);
    final timer = Timer(timeout, cancel);
    unawaited(run());
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _pending.remove(cancel);
    }
  }

  /// 中止在途请求并永久关闭；无参数、无返回值。
  ///
  /// 示例：`await fetcher.close()`；重复调用安全。
  @override
  Future<void> close() async {
    _closed = true;
    for (final cancel in _pending.toList()) {
      cancel();
    }
    _client?.close(force: true);
    _client = null;
  }
}
