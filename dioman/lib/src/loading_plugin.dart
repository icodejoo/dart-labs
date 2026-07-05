// ignore_for_file: prefer_initializing_formals
import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// Tracks in-flight requests and notifies via a callback.
///
/// Calls [onChanged](true) when the first request starts, and
/// [onChanged](false) when the last one completes. This makes it trivial
/// to drive a global loading indicator without any Rx dependency.
///
/// Per-request opt-out: `options.extra['loading'] = false`.
///
/// ```dart
/// final loading = LoadingPlugin(
///   onChanged: (active) => setState(() => _loading = active),
/// );
/// dio.interceptors.add(loading);
/// ```
class LoadingPlugin extends DioPlugin {
  LoadingPlugin({required void Function(bool loading) onChanged})
      : _onChanged = onChanged;

  static const _kBracketed = '_loading_bracketed';

  final void Function(bool loading) _onChanged;
  int _count = 0;

  /// Number of requests currently in-flight.
  int get activeCount => _count;

  @override
  String get name => 'loading';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['loading'] != false) {
      options.extra[_kBracketed] = true;
      if (_count++ == 0) _onChanged(true);
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _decrement(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _decrement(err.requestOptions);
    handler.next(err);
  }

  // Only decrement for a request this plugin actually incremented for. An
  // earlier interceptor's onRequest can short-circuit (cache/share/mock hit)
  // before this plugin's onRequest ever runs — if that resolve is later
  // propagated with `callFollowingResponseInterceptor: true`, this onResponse
  // still fires and, without this guard, would decrement a counter it never
  // incremented (stealing a slot from an unrelated in-flight request).
  void _decrement(RequestOptions options) {
    if (options.extra.remove(_kBracketed) == true) {
      if (_count > 0 && --_count == 0) _onChanged(false);
    }
  }

  @override
  void dispose() {
    _count = 0;
    _onChanged(false);
  }
}
