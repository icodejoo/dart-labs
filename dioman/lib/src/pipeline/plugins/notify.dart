import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../response.dart';
import '../stages.dart';

/// 每逻辑请求只读取最终结果并通知至多一次。
/// 回调接收基础结果；读取扩展字段前应使用 is 检查子类。
class DiomanNotify<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// [notify] 接收非空文本和最终结果；[stringify] 返回空串表示不通知。
  /// 例如 `DiomanNotify(notify: (message, r) => print(message))`。
  const DiomanNotify(
      {required this.notify,
      this.stringify = defaultStringify,
      this.enabled = true});

  /// 通知回调，异常隔离并记日志。
  final void Function(String message, DiomanResponse<dynamic> result) notify;

  /// 消息生成回调，与 notify 共享通知异常边界。
  final String Function(DiomanResponse<dynamic> result, DiomanContext<R> ctx)
      stringify;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:notify';

  /// 请求级只接受 bool；false 关闭。
  static final option = DiomanOptionKey<bool>(pluginName);

  /// 默认忽略成功、取消、静默请求，否则取消息或 kind/status。
  static String defaultStringify(
          DiomanResponse<dynamic> r, DiomanContext ctx) =>
      r.ok || r.kind == DiomanKind.cancel || ctx.request.silent
          ? ''
          : (r.message.isEmpty ? '${r.kind.name} ${r.status}' : r.message);

  /// 返回稳定名称。
  @override
  String get name => pluginName;

  /// 最外层结果观察阶段。
  @override
  DiomanStage get stage => DiomanStage.outer;

  /// 建立客户端实例。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Notify<R>(this);
}

/// 不持有跨请求状态的通知实例。
class _Notify<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> {
  /// 保存配置。
  _Notify(this.config);

  /// 插件配置。
  final DiomanNotify<R> config;

  /// 等待最终结果后重查取消，通知异常不改变结果。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final on = resolveOption<bool>(
        ctx.request.call.options[DiomanNotify.option],
        base: true,
        merge: identical);
    final r = await next();
    final cancelled = ctx.cancelled();
    if (on == null) return r;
    // internal 优先，取消不掩盖程序错误。
    final result = r.kind == DiomanKind.internal ? r : cancelled ?? r;
    try {
      final text = config.stringify(result, ctx);
      if (text.isNotEmpty) config.notify(text, result);
    } catch (e, s) {
      ctx.client.logError('[${DiomanNotify.pluginName}] 通知回调失败: $e\n$s');
    }
    return r;
  }
}
