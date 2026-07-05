import 'package:dio/dio.dart';
import 'dio_plugin.dart';

// Internal slot for the injected CancelToken.
const _kToken = '_cancel_token';

/// Injects a [CancelToken] into every request that does not already
/// have one, and maintains a registry so [cancelAll] can abort all
/// in-flight requests for a given [Dio] instance.
///
/// Requests that supply their own [CancelToken] via `options.cancelToken`
/// are left untouched.
///
/// ```dart
/// final cancelPlugin = CancelPlugin();
/// dio.interceptors.add(cancelPlugin);
///
/// // Later, abort everything (e.g. page navigation):
/// cancelAll(dio, 'page left');
/// ```
class CancelPlugin extends DioPlugin {
  CancelPlugin() : _tokens = {};

  final Set<CancelToken> _tokens;

  @override
  String get name => 'cancel';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final existing = options.cancelToken;
    if (existing != null) {
      // RetryPlugin re-dispatches through the full chain via the app's own
      // Dio, reusing the same RequestOptions (and thus the same CancelToken
      // this plugin injected on the first attempt). _release already
      // deregistered it after that attempt's error, so without this it would
      // stay untracked — and uncancellable via cancelAll — for every
      // subsequent retry. Only re-register tokens this plugin itself
      // injected (never a caller-supplied one) and that aren't already spent.
      if (options.extra[_kToken] == existing && !existing.isCancelled) {
        _tokens.add(existing);
      }
      return handler.next(options);
    }

    final token = CancelToken();
    options.cancelToken = token;
    options.extra[_kToken] = token;
    _tokens.add(token);
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _release(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _release(err.requestOptions);
    handler.next(err);
  }

  void _release(RequestOptions options) {
    final token = options.extra[_kToken] as CancelToken?;
    if (token != null) _tokens.remove(token);
  }

  /// Cancel all in-flight requests managed by this plugin instance.
  /// Returns the number of tokens cancelled.
  int cancelAll([String? reason]) {
    final n = _tokens.length;
    for (final t in _tokens) {
      t.cancel(reason ?? 'cancelAll');
    }
    _tokens.clear();
    return n;
  }

  @override
  void dispose() {
    cancelAll('plugin ejected');
  }
}

/// Convenience top-level helper.
/// Finds [CancelPlugin] by name on [dio] and calls [CancelPlugin.cancelAll].
/// Returns the count, or 0 if the plugin is not installed.
int cancelAll(Dio dio, [String? reason]) {
  final plugin = dio.interceptors
      .whereType<CancelPlugin>()
      .firstOrNull;
  return plugin?.cancelAll(reason) ?? 0;
}
