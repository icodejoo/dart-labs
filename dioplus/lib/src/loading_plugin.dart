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

  final void Function(bool loading) _onChanged;
  int _count = 0;

  /// Number of requests currently in-flight.
  int get activeCount => _count;

  @override
  String get name => 'loading';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['loading'] != false) {
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

  void _decrement(RequestOptions options) {
    if (options.extra['loading'] != false) {
      if (_count > 0 && --_count == 0) _onChanged(false);
    }
  }

  @override
  void dispose() {
    _count = 0;
    _onChanged(false);
  }
}
