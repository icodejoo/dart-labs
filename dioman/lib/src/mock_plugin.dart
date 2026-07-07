import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// A function that decides whether a mock response should fall back to the
/// real API. Return `true` to trigger fallback.
///
/// 判断mock响应是否该回落到真实API的函数。返回`true`表示触发回落。
typedef MockFallbackDecider = bool Function({
  Response<dynamic>? response,
  DioException? error,
});

/// Default fallback condition: 404 response, or any network-level error
/// (excluding user-initiated cancellations).
///
/// 默认回落条件：404响应，或任意网络层错误（用户主动取消除外）。
bool defaultFallback({Response<dynamic>? response, DioException? error}) {
  if (response != null) return response.statusCode == 404;
  if (error == null) return false;
  if (error.type == DioExceptionType.cancel) return false;
  return true; // network unreachable → fallback to real API
}

/// Per-request override for [DiomanMock], read from `extra['dioman:mock']`.
///
/// [DiomanMock]的单请求覆盖，从`extra['dioman:mock']`读取。
class DiomanMockOptions {
  const DiomanMockOptions({this.enabled, this.mockUrl, this.routes, this.fallbackWhen});

  /// `false` skips mocking for this request. `null` (default) inherits
  /// [DiomanMock.enabled].
  ///
  /// `false`表示本次请求跳过mock。`null`（默认）沿用[DiomanMock.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default mock server URL for this request only.
  ///
  /// 仅本次请求覆盖插件默认的mock服务器URL。
  final String? mockUrl;

  /// Extra routes merged on top of the plugin's own registered routes for
  /// this request only (these keys win on conflict; the plugin's other
  /// routes are untouched).
  ///
  /// 仅本次请求，叠加在插件已注册路由之上的额外路由（key冲突时以这里为准，
  /// 插件的其它路由不受影响）。
  final Map<String, MockHandler>? routes;

  /// Overrides the plugin's default `fallbackWhen` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`fallbackWhen`。
  final MockFallbackDecider? fallbackWhen;
}

/// Route-based mock plugin.
///
/// 基于路由的mock插件。
///
/// Matches requests by `'METHOD:path'` key and resolves them from a handler.
/// If no route matches **or** the handler returns a 404 / network error,
/// the request falls back to the real API automatically.
///
/// 用`'METHOD:path'`匹配请求并交给处理器解析。若没有路由匹配，**或**处理器
/// 返回404/网络错误，会自动回落到真实API。
///
/// Per-request opt-out: `options.extra['dioman:mock'] = const DiomanMockOptions(enabled: false)`.
/// Per-request override: `options.extra['dioman:mock'] = const DiomanMockOptions(mockUrl: 'http://...')`.
///
/// ```dart
/// final mock = DiomanMock(
///   enabled: true, // set to kDebugMode in real projects
///   mockUrl: 'http://localhost:4523',
/// );
/// dio.interceptors.add(mock);
///
/// // Register inline handlers (bypass mockUrl, resolve directly):
/// mock.add('GET:/pet', (opts) async => ResponseBody.fromString(
///   '[{"id":1}]', 200,
///   headers: {Headers.contentTypeHeader: ['application/json']},
/// ));
/// ```
class DiomanMock extends DiomanPlugin {
  DiomanMock({
    this.enabled = false,
    this.mockUrl,
    MockFallbackDecider? fallbackWhen,
    Map<String, MockHandler>? routes,
  })  : fallbackWhen = fallbackWhen ?? defaultFallback,
        _routes = routes ?? {};

  /// Master switch — set to `kDebugMode` or an env flag.
  ///
  /// 总开关——一般设为`kDebugMode`或某个环境变量。
  final bool enabled;

  /// Base URL of the mock server (e.g. Apifox / Mock.js).
  /// Used when no inline handler matches.
  ///
  /// mock服务器的base URL（例如Apifox/Mock.js）。没有内联处理器匹配时使用。
  final String? mockUrl;

  /// Decides whether a mock hit should fall back to the real API. Defaults
  /// to [defaultFallback]. Overridable per request via
  /// [DiomanMockOptions.fallbackWhen].
  ///
  /// 判断mock命中是否该回落到真实API，默认[defaultFallback]。可通过
  /// [DiomanMockOptions.fallbackWhen]按请求覆盖。
  final MockFallbackDecider fallbackWhen;

  /// Registered inline route handlers, keyed by `'METHOD:path'`.
  ///
  /// 已注册的内联路由处理器，按`'METHOD:path'`索引。
  final Map<String, MockHandler> _routes;

  // Bare Dio reused for mock-server redirects. `_rewriteUrl` produces an
  // absolute URL, so no baseUrl is needed and a single shared instance works
  // for every mockUrl — avoiding a fresh HttpClient per redirected request.
  // Closed in [dispose].
  //
  // 复用一个裸Dio做mock服务器转发。`_rewriteUrl`生成的是绝对URL，所以不需要
  // baseUrl，一个共享实例就能处理所有mockUrl——避免每次转发都新建HttpClient。
  // 在[dispose]中关闭。
  Dio? _redirectDio;
  Dio get _redirect => _redirectDio ??= Dio();

  // Decodes an inline handler's raw ResponseBody the same way dio's own
  // dispatch path would (JSON/text decode) — constructing a Response
  // directly from an undecoded ResponseBody would leave `.data` holding the
  // raw stream wrapper instead of the parsed payload.
  //
  // 用跟dio自身分发路径一样的方式（JSON/文本解码）解析内联处理器返回的原始
  // ResponseBody——直接用未解码的ResponseBody构造Response会让`.data`是未解码的
  // 流包装对象而不是解析后的payload。
  static final _transformer = FusedTransformer();

  static const _name = 'dioman:mock';

  @override
  String get name => _name;

  // ── Route management ──────────────────────────────────────────────────────

  /// Registers an inline handler for `routeKey` (`'METHOD:path'`).
  ///
  /// 给`routeKey`（`'METHOD:path'`）注册一个内联处理器。
  void add(String routeKey, MockHandler handler) => _routes[routeKey] = handler;

  /// Removes the inline handler registered for `routeKey`.
  ///
  /// 移除`routeKey`已注册的内联处理器。
  void remove(String routeKey) => _routes.remove(routeKey);

  /// Clears all registered inline handlers.
  ///
  /// 清空所有已注册的内联处理器。
  void reset() => _routes.clear();

  // ── Interceptor ───────────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final override = options.extra[name];
    final o = override is DiomanMockOptions ? override : null;
    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(options);

    // 1. Try inline handler first.
    // Uses the resolved path (matching DiomanKey's key scheme) so route
    // registration is consistent regardless of absolute vs relative URLs.
    final routeKey = '${options.method.toUpperCase()}:${options.uri.path}';
    final inlineHandler = o?.routes?[routeKey] ?? _routes[routeKey];
    if (inlineHandler != null) {
      try {
        final body = await inlineHandler(options);
        final headers = Headers.fromMap(body.headers);
        body.headers = headers.map;
        final data = await _transformer.transformResponse(options, body);
        // callFollowingResponseInterceptor: true — a mock hit must still run
        // onResponse of normalize/cache/share (installed earlier in the
        // chain) so the shared-request completer settles and the envelope
        // is unwrapped the same way a real response would be.
        return handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            data: data,
            headers: headers,
            statusCode: body.statusCode,
            statusMessage: 'Mock',
          ),
          true,
        );
      } on DioException catch (e) {
        return handler.reject(e);
      }
    }

    // 2. Redirect to mock server if configured.
    final $mockUrl = o?.mockUrl ?? mockUrl;
    if ($mockUrl == null) return handler.next(options); // no mock URL → passthrough

    final $fallbackWhen = o?.fallbackWhen ?? fallbackWhen;

    // queryParameters: {} — _rewriteUrl already folds the original query
    // string into the rewritten path; leaving the map populated would make
    // dio append it a second time when it builds the request URI.
    final mockOptions = options.copyWith(
      path: _rewriteUrl(options.uri, $mockUrl),
      queryParameters: {},
    );

    try {
      final resp = await _redirect.fetch<dynamic>(mockOptions);
      if ($fallbackWhen(response: resp)) {
        return handler.next(options); // fallback to real API
      }
      handler.resolve(resp, true);
    } on DioException catch (e) {
      if ($fallbackWhen(error: e)) {
        return handler.next(options); // mock server unreachable → real API
      }
      handler.reject(e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _rewriteUrl(Uri original, String base) {
    final stripped = base.replaceAll(RegExp(r'/+$'), '');
    final path = '/${original.path.replaceAll(RegExp(r'^/+'), '')}';
    final query = original.hasQuery ? '?${original.query}' : '';
    return '$stripped$path$query';
  }

  @override
  void dispose() {
    _redirectDio?.close(force: true);
    _redirectDio = null;
  }
}

/// Inline mock handler — return a [ResponseBody] directly.
///
/// 内联mock处理器——直接返回一个[ResponseBody]。
typedef MockHandler = Future<ResponseBody> Function(RequestOptions options);
