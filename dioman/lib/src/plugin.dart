import 'client.dart';
import 'context.dart';
import 'request.dart';
import 'response.dart';
import 'stages.dart';

/// 从同一基准继续执行内层；可多次调用，结果总是响应对象。
typedef DiomanNext<R extends DiomanResponse<dynamic>>
    = Future<DiomanResponse<dynamic>> Function([RequestPatch? patch]);

/// 插件只保存配置；每个客户端 setup 一次，状态放在返回实例里。
abstract class DiomanPlugin<R extends DiomanResponse<dynamic>> {
  /// 支持常量插件配置。
  const DiomanPlugin();

  /// 唯一名称；dioman: 前缀保留给内置插件。
  String get name;

  /// 默认位于尝试阶段。
  DiomanStage get stage => DiomanStage.attempt;

  /// 默认排在阶段内置插件之后。
  DiomanEnforce get enforce => DiomanEnforce.post;

  /// false 时不调用 setup，也不进 inspect。
  bool get enabled => true;

  /// 创建客户端独立状态；null 表示只有 setup 效果，不进入链。
  DiomanPluginInstance<R>? setup(Dioman<R> client);
}

/// 客户端专属插件状态及管理 API 的载体。
abstract class DiomanPluginInstance<R extends DiomanResponse<dynamic>> {
  /// 执行本层，例如 `return next()`；同步和异步异常均由边界隔离。
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next);

  /// 释放实例资源，客户端逆注册顺序调用。
  void dispose() {}
}
