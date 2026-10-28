import 'package:dio/dio.dart';
import './dioman_plugin.dart';
import 'normalize_plugin.dart';
import 'plugin_order.dart';

/// 保留的兼容类型，不提供请求配置。
@Deprecated('No per-request options; configure DiomanNotify directly.')
class DiomanNotifyOptions {}

/// 本插件用于从响应体中提取错误信息，并转换为文字通知用户
class DiomanNotify<T> extends DiomanPlugin {
  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:notify';

  /// 同一逻辑请求已发送通知的状态键。
  static const _kSent = '$pluginName:sent';

  /// 创建插件实例。
  DiomanNotify({
    required this.notify,
    required this.stringify,
  });

  /// 接收转换后的通知文本。
  Function(String message) notify;

  /// 根据响应数据及状态生成通知文本。
  String Function(T? data, String message, int status, RequestOptions options)
      stringify;

  /// 插件的公开协议名称。
  @override
  String get name => pluginName;

  /// 通知需要读取解包前的业务信封。
  @override
  DiomanPluginOrder get ordering => const DiomanPluginOrder(
        before: {DiomanNormalize.pluginName},
      );

  /// 新一次分发清理上次通知状态。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra.remove(_kSent);
    handler.next(options);
  }

  /// 处理响应并完成当前响应出口。
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      _convert(response, null, response.requestOptions);
    } catch (_) {}
    handler.next(response);
  }

  /// 处理失败并完成当前错误出口。
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      _convert(err.response, err.message, err.requestOptions);
    } catch (_) {}
    handler.next(err);
  }

  /// 把响应信息转换为通知文本。
  void _convert(Response? r, String? message, RequestOptions options) {
    if (options.extra[_kSent] == true) return;
    final $message = stringify(
      r?.data as T?,
      message ?? r?.statusMessage ?? '',
      r?.statusCode ?? 0,
      r?.requestOptions ?? options,
    );

    if ($message.isNotEmpty) {
      options.extra[_kSent] = true;
      notify($message);
    }
  }
}
