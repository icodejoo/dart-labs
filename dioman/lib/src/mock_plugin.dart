import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// A function that decides whether a mock response should fall back to the
/// real API. Return `true` to trigger fallback.
typedef MockFallbackDecider = bool Function({
  Response<dynamic>? response,
  DioException? error,
});

/// Default fallback condition: 404 response, or any network-level error
/// (excluding user-initiated cancellations).
bool defaultFallback({Response<dynamic>? response, DioException? error}) {
  if (response != null) return response.statusCode == 404;
  if (error == null) return false;
  if (error.type == DioExceptionType.cancel) return false;
  return true; // network unreachable → fallback to real API
}

/// Route-based mock plugin.
///
/// Matches requests by `'METHOD:path'` key and resolves them from a handler.
/// If no route matches **or** the handler returns a 404 / network error,
/// the request falls back to the real API automatically.
///
/// Per-request opt-out: `options.extra['mock'] = false`.
/// Per-request override: `options.extra['mock'] = {'mockUrl': 'http://...'}`.
///
/// ```dart
/// final mock = MockPlugin(
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
class MockPlugin extends DioPlugin {
  MockPlugin({
    this.enabled = false,
    this.mockUrl,
    MockFallbackDecider? fallbackWhen,
    Map<String, MockHandler>? routes,
  })  : _fallbackWhen = fallbackWhen ?? defaultFallback,
        _routes = routes ?? {};

  /// Master switch — set to `kDebugMode` or an env flag.
  final bool enabled;

  /// Base URL of the mock server (e.g. Apifox / Mock.js).
  /// Used when no inline handler matches.
  final String? mockUrl;

  final MockFallbackDecider _fallbackWhen;
  final Map<String, MockHandler> _routes;

  // Bare Dio reused for mock-server redirects. `_rewriteUrl` produces an
  // absolute URL, so no baseUrl is needed and a single shared instance works
  // for every mockUrl — avoiding a fresh HttpClient per redirected request.
  // Closed in [dispose].
  Dio? _redirectDio;
  Dio get _redirect => _redirectDio ??= Dio();

  // Decodes an inline handler's raw ResponseBody the same way dio's own
  // dispatch path would (JSON/text decode) — constructing a Response
  // directly from an undecoded ResponseBody would leave `.data` holding the
  // raw stream wrapper instead of the parsed payload.
  static final _transformer = FusedTransformer();

  @override
  String get name => 'mock';

  // ── Route management ──────────────────────────────────────────────────────

  void add(String routeKey, MockHandler handler) => _routes[routeKey] = handler;
  void remove(String routeKey) => _routes.remove(routeKey);
  void reset() => _routes.clear();

  // ── Interceptor ───────────────────────────────────────────────────────────

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!enabled) return handler.next(options);
    if (options.extra['mock'] == false) return handler.next(options);

    // 1. Try inline handler first.
    // Uses the resolved path (matching BuildKeyPlugin's key scheme) so route
    // registration is consistent regardless of absolute vs relative URLs.
    final routeKey = '${options.method.toUpperCase()}:${options.uri.path}';
    final inlineHandler = _routes[routeKey];
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
    final url = _resolveMockUrl(options);
    if (url == null) return handler.next(options); // no mock URL → passthrough

    // queryParameters: {} — _rewriteUrl already folds the original query
    // string into the rewritten path; leaving the map populated would make
    // dio append it a second time when it builds the request URI.
    final mockOptions = options.copyWith(
      path: _rewriteUrl(options.uri, url),
      queryParameters: {},
    );

    try {
      final resp = await _redirect.fetch<dynamic>(mockOptions);
      if (_fallbackWhen(response: resp)) {
        return handler.next(options); // fallback to real API
      }
      handler.resolve(resp, true);
    } on DioException catch (e) {
      if (_fallbackWhen(error: e)) {
        return handler.next(options); // mock server unreachable → real API
      }
      handler.reject(e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String? _resolveMockUrl(RequestOptions opts) {
    final v = opts.extra['mock'];
    if (v is Map) return (v['mockUrl'] as String?) ?? mockUrl;
    return mockUrl;
  }

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
typedef MockHandler = Future<ResponseBody> Function(RequestOptions options);
