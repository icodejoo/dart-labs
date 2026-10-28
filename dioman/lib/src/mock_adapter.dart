import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 内联 mock 处理器：收到请求，直接返回一个 [ResponseBody]。
typedef MockHandler = Future<ResponseBody> Function(RequestOptions options);

/// 判断 mock 响应是否该回落到真实 API 的函数，返回 `true` 表示触发回落。
///
/// 在 [DiomanMockAdapter] 里：转发到 mock 服务器拿到响应时传 `response`
/// （其 `data` 是原始 [ResponseBody]，状态码未经 Dio 校验），传输层抛错时传
/// `error`。
typedef MockFallbackDecider = bool Function({
  Response<dynamic>? response,
  DioException? error,
});

/// [DiomanMockAdapter] 的默认回落条件，作用于转发到 mock 服务器的那条路径。
///
/// 返回 `true`（回落到真实 API）的情况：
/// - 传入了 [response] 且状态码为 404；
/// - 传入了 [error] 且不是用户主动取消（[DioExceptionType.cancel]）——包括连接
///   失败、各类超时、证书错误、未知错误。
///
/// 用户取消、其它 [response]（如 2xx、500）、两个参数都为空时返回 `false`；两者
/// 同时给出时以 [response] 为准。注意 mock 服务器的 500 在 adapter 层只是一个
/// [response]，默认不回落，交给 Dio 按状态码校验后抛出。
///
/// - [response]：mock 服务器返回的响应（如果有）。
/// - [error]：转发时抛出的错误（如果有）。
/// - 返回值：是否回落到真实 API。
///
/// ```dart
/// // 只在 404 与网络不通时回落，mock 服务器报 500 则原样交给 Dio
/// DiomanMockAdapter(
///   inner: dio.httpClientAdapter,
///   mockUrl: 'http://localhost:4523',
///   fallbackWhen: ({response, error}) =>
///       defaultFallback(response: response, error: error),
/// );
/// ```
bool defaultFallback({Response<dynamic>? response, DioException? error}) {
  if (response != null) return response.statusCode == 404;
  if (error == null) return false;
  if (error.type == DioExceptionType.cancel) return false;
  return true; // 网络不通 → 回落到真实 API
}

/// [DiomanMockAdapter] 的单请求覆盖，写在 `extra[DiomanMockAdapter.extraKey]`。
///
/// ```dart
/// dio.get('/pets', options: Options(extra: {
///   DiomanMockAdapter.extraKey:
///       const DiomanMockOptions(mockUrl: 'http://localhost:9999'),
/// }));
/// ```
class DiomanMockOptions {
  /// 创建单请求覆盖配置。
  const DiomanMockOptions(
      {this.enabled, this.mockUrl, this.routes, this.fallbackWhen});

  /// `false` 表示本次请求跳过 mock，`null`（默认）沿用 adapter 的 `enabled`。
  final bool? enabled;

  /// 仅本次请求覆盖 adapter 默认的 mock 服务器 URL。
  final String? mockUrl;

  /// 仅本次请求叠加在 adapter 已注册路由之上的额外路由（key 冲突时以这里为准，
  /// adapter 的其它路由不受影响）。
  final Map<String, MockHandler>? routes;

  /// 仅本次请求覆盖 adapter 默认的 `fallbackWhen`。
  final MockFallbackDecider? fallbackWhen;
}

/// Transport-level mocking with inline routes, mock-server forwarding and real
/// API fallback. Wrap the host adapter; this is not a DiomanPlugin and has no
/// interceptor ordering constraints. Auth/retry replays use it again and share
/// can merge concurrent mock requests. Install ONLY in development/test flavors:
/// this pure Dart library cannot detect your application's release mode.
/// Mock responses carry [markerHeader]; DiomanCache never stores them, even if
/// shouldStore returns true. Existing real cache hits may bypass this adapter.
/// Dio decodes and validates every response; fallbackWhen receives raw
/// ResponseBody data on responses (404 falls back by default), or a
/// DioException on transport errors. HTTP 500 reaches Dio normally.
///
/// 传输层 mock：支持内联路由、mock 服务转发与真实接口回落。包装宿主 adapter，
/// 不通过 Dioman.install 安装，不在拦截器链上，无顺序约束；auth/retry 重放再次
/// 经过它，share 可合并并发 mock 请求。只应在开发/测试 flavor 中安装，纯 Dart
/// 库无法判断 release。mock 响应带 [markerHeader]，DiomanCache 一律不缓存，
/// shouldStore 不能放开；已有真实缓存命中可跳过 adapter。响应由 Dio 统一解码、
/// 校验状态；fallbackWhen 的 response.data 是原始 ResponseBody，默认只对 404
/// 响应回落，传输异常传 error，HTTP 500 照常交给 Dio。
///
/// ```dart
/// // In your development/test flavor bootstrap only:
/// dio.httpClientAdapter = DiomanMockAdapter(
///   inner: dio.httpClientAdapter,
///   routes: {'GET:/pets': (_) async => ResponseBody.fromString('[]', 200,
///     headers: {Headers.contentTypeHeader: ['application/json']})},
/// );
///
/// // 单请求覆盖：false 跳过 mock，或传 DiomanMockOptions
/// dio.get('/pets', options: Options(extra: {DiomanMockAdapter.extraKey: false}));
/// ```
class DiomanMockAdapter implements HttpClientAdapter {
  /// Wrap [inner], with optional routes and mock-server fallback.
  ///
  /// 包装 [inner]，可配置内联路由及 mock 服务回落策略。
  DiomanMockAdapter({
    required HttpClientAdapter inner,
    Map<String, MockHandler> routes = const {},
    String? mockUrl,
    MockFallbackDecider fallbackWhen = defaultFallback,
    bool enabled = true,
  })  : _inner = inner,
        _routes = routes,
        _mockUrl = mockUrl,
        _fallbackWhen = fallbackWhen,
        _enabled = enabled;

  /// 单请求覆盖用的 `extra` 键：值为 [DiomanMockOptions]，或 `false`（跳过 mock）。
  static const extraKey = 'dioman:mock';

  /// Header identifying a mock response; its presence vetoes cache writes.
  ///
  /// 标识 mock 响应的头；存在此头即禁止缓存写入。
  static const markerHeader = 'x-dioman-mock';

  /// 被包装的真实传输层。
  final HttpClientAdapter _inner;

  /// 内联路由，按 `'METHOD:path'` 索引。
  final Map<String, MockHandler> _routes;

  /// 默认 mock 服务器地址，为空则只走内联路由。
  final String? _mockUrl;

  /// 默认回落判定。
  final MockFallbackDecider _fallbackWhen;

  /// 总开关。
  final bool _enabled;

  /// Resolve a route, forward to mock, or pass through to the real transport.
  ///
  /// 命中内联路由、转发 mock 服务，或透传给真实传输层。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final override = options.extra[extraKey];
    final o = override is DiomanMockOptions ? override : null;
    if (override == false || !(o?.enabled ?? _enabled)) {
      return _inner.fetch(options, requestStream, cancelFuture);
    }
    final key = '${options.method.toUpperCase()}:${options.uri.path}';
    final handler = o?.routes?[key] ?? _routes[key];
    if (handler != null) {
      return _mark(await _cancelable(
          Future.sync(() => handler(options)), options, cancelFuture));
    }
    final mockUrl = o?.mockUrl ?? _mockUrl;
    if (mockUrl == null) {
      return _inner.fetch(options, requestStream, cancelFuture);
    }

    // A request stream is single-use. Buffer large bodies in memory too, so
    // forwarding and fallback each receive a complete, independent stream.
    final bytes = requestStream == null
        ? null
        : await _cancelable(
            requestStream
                .fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
            options,
            cancelFuture);
    Stream<Uint8List>? replay() =>
        bytes == null ? null : Stream.value(Uint8List.fromList(bytes));
    final original = options.uri;
    final base = mockUrl.replaceAll(RegExp(r'/+$'), '');
    final path = '/${original.path.replaceAll(RegExp(r'^/+'), '')}';
    final query = original.hasQuery ? '?${original.query}' : '';
    final forwarded =
        options.copyWith(path: '$base$path$query', queryParameters: {});
    final fallback = o?.fallbackWhen ?? _fallbackWhen;
    ResponseBody body;
    try {
      // IO aborts may surface as plain HttpException. Race cancellation here
      // too, so defaultFallback sees a cancel rather than a transport failure.
      body = await _cancelable(_inner.fetch(forwarded, replay(), cancelFuture),
          options, cancelFuture);
    } catch (error, stack) {
      final dioError = error is DioException
          ? error
          : DioException(
              requestOptions: forwarded, error: error, stackTrace: stack);
      if (!fallback(error: dioError)) rethrow;
      return _inner.fetch(options, replay(), cancelFuture);
    }
    if (fallback(
        response: Response<ResponseBody>(
            requestOptions: forwarded,
            data: body,
            statusCode: body.statusCode,
            statusMessage: body.statusMessage,
            headers: Headers.fromMap(body.headers)))) {
      // Release the discarded HTTP response before issuing the real request.
      await _cancelable(body.stream.drain<void>(), options, cancelFuture);
      return _inner.fetch(options, replay(), cancelFuture);
    }
    return _mark(body);
  }

  /// 给响应打上 [markerHeader]（覆盖同名头）。
  static ResponseBody _mark(ResponseBody body) {
    body.headers = {...body.headers}
      ..removeWhere((key, _) => key.toLowerCase() == markerHeader);
    body.headers[markerHeader] = ['1'];
    return body;
  }

  /// 让 [work] 与取消信号赛跑，取消时抛取消错误。
  static Future<T> _cancelable<T>(
      Future<T> work, RequestOptions options, Future<void>? cancelFuture) {
    if (cancelFuture == null) return work;
    return Future.any([
      work,
      cancelFuture.then<T>((_) => throw options.cancelToken?.cancelError ??
          DioException.requestCancelled(
              requestOptions: options, reason: 'cancelled'))
    ]);
  }

  /// Close the wrapped transport, preserving [force].
  ///
  /// 关闭被包装的传输层，透传 [force]。
  @override
  void close({bool force = false}) => _inner.close(force: force);
}
