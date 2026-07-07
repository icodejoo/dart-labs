import 'package:dio/dio.dart';
import './dioman_plugin.dart';

class DiomanNotifyOptions {}

/// 本插件用于从响应体中提取错误信息，并转换为文字通知用户
class DiomanNotify<T> extends DiomanPlugin {
  static const _name = 'dioman:notify';
  DiomanNotify({
    required this.notify,
    required this.stringify,
  });
  Function(String message) notify;
  Function(T? data, String message, int status, RequestOptions options)
      stringify;

  @override
  String get name => _name;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _convert(response, null, response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _convert(err.response, err.message, err.requestOptions);

    handler.next(err);
  }

  void _convert(Response? r, String? message, RequestOptions options) {
    final $message = stringify(
      r?.data as T?,
      message ?? r?.statusMessage ?? '',
      r?.statusCode ?? 0,
      r?.requestOptions ?? options,
    );

    if ($message) {
      notify($message);
    }
  }
}
