// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'dio_plugin.dart';

const _kCount = '_retry_count';

/// Retries failed requests with configurable back-off.
///
/// Supports two failure modes:
/// - **HTTP / network errors** (`onError` path) — network timeouts, 5xx, etc.
/// - **Business-level errors** (`isExceptionRequest`) — treat a 200 response
///   as a failure based on the response body (e.g. `code != 0`).
///
/// Per-request configuration via `options.extra['retry']`:
/// - `int`                        → max retry count
/// - `{'max': int, 'isException': fn}` → full config
/// - `false`                      → skip retry for this request
///
/// ```dart
/// final retry = RetryPlugin(
///   dio: dio,
///   max: 3,
///   isExceptionRequest: (r) => r.data['code'] != 0,
/// );
/// dio.interceptors.add(retry);
/// ```
class RetryPlugin extends DioPlugin {
  RetryPlugin({
    required Dio dio,
    this.max = 0,
    this.delay,
    bool Function(DioException)? retryIf,
    bool Function(Response<dynamic>)? isExceptionRequest,
  })  : _dio = dio,
        _retryIf = retryIf ?? _defaultRetryIf,
        _isException = isExceptionRequest;

  final Dio _dio;

  /// Default max retries (0 = no retry unless overridden per request).
  final int max;

  /// Delay before each attempt. Defaults to exponential back-off: 1s, 2s, 4s.
  final Duration Function(int attempt)? delay;

  final bool Function(DioException) _retryIf;

  /// If provided, a 2xx response for which this returns `true` is treated as
  /// a failure and retried (business-level exception).
  final bool Function(Response<dynamic>)? _isException;

  static bool _defaultRetryIf(DioException e) {
    final s = e.response?.statusCode;
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError ||
        (s != null && s >= 500 && s != 501);
  }

  Duration _delay(int attempt) =>
      delay?.call(attempt) ?? Duration(milliseconds: 1000 * (1 << attempt));

  @override
  String get name => 'retry';

  // ── Business-level failure (onResponse) ───────────────────────────────────

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final config = response.requestOptions;
    if (config.extra['retry'] == false) return handler.next(response);
    final isException = _resolveException(config);
    if (isException == null || !isException(response)) return handler.next(response);

    // Business failure: attempt retry.
    final m = _resolveMax(config);
    final count = (config.extra[_kCount] as int? ?? 0);
    if (count >= m) {
      config.extra[_kCount] = 0;
      return handler.next(response);
    }
    config.extra[_kCount] = count + 1;
    await Future<void>.delayed(_delay(count));
    if (config.cancelToken?.isCancelled == true) return handler.next(response);
    try {
      handler.resolve(await _dio.fetch<dynamic>(config));
    } catch (_) {
      handler.next(response);
    }
  }

  // ── HTTP / network failure (onError) ──────────────────────────────────────

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final config = err.requestOptions;
    if (config.extra['retry'] == false) return handler.next(err);
    if (!_retryIf(err)) return handler.next(err);

    final m = _resolveMax(config);
    final count = (config.extra[_kCount] as int? ?? 0);
    if (count >= m) {
      config.extra[_kCount] = 0;
      return handler.next(err);
    }
    config.extra[_kCount] = count + 1;
    await Future<void>.delayed(_delay(count));
    if (config.cancelToken?.isCancelled == true) return handler.next(err);
    try {
      handler.resolve(await _dio.fetch<dynamic>(config));
    } catch (_) {
      handler.next(err);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _resolveMax(RequestOptions opts) {
    final v = opts.extra['retry'];
    if (v is int) return v;
    if (v is Map && v['max'] is int) return v['max'] as int;
    return max;
  }

  bool Function(Response<dynamic>)? _resolveException(RequestOptions opts) {
    final v = opts.extra['retry'];
    if (v is Map && v['isException'] is Function) {
      return v['isException'] as bool Function(Response<dynamic>);
    }
    return _isException;
  }
}
