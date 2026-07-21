import 'package:dio/dio.dart';
import './dioman_plugin.dart';

class DiomanNotifyOptions {}

/// 本插件用于从响应体中提取错误信息，并转换为文字通知用户
class DiomanNotify<T> extends DiomanPlugin {
  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:notify';
  DiomanNotify({
    required this.notify,
    required this.stringify,
  });
  Function(String message) notify;
  String Function(T? data, String message, int status, RequestOptions options)
      stringify;

  @override
  String get name => pluginName;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      _convert(response, null, response.requestOptions);
    } catch (_) {}
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      _convert(err.response, err.message, err.requestOptions);
    } catch (_) {}
    handler.next(err);
  }

  void _convert(Response? r, String? message, RequestOptions options) {
    final $message = stringify(
      r?.data as T?,
      message ?? r?.statusMessage ?? '',
      r?.statusCode ?? 0,
      r?.requestOptions ?? options,
    );

    if ($message.isNotEmpty) {
      notify($message);
    }
  }
}
