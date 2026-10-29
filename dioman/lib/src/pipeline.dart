import 'context.dart';
import 'plugin.dart';
import 'response.dart';
import 'stages.dart';

/// 插件校验错误的参数名。
const _nameArgument = 'name';

/// 编译后的上下文执行器。
typedef DiomanRunner<R extends DiomanResponse<dynamic>>
    = Future<DiomanResponse<dynamic>> Function(DiomanContext<R> ctx);

/// 已安装的配置及实例。
class DiomanRegistration<R extends DiomanResponse<dynamic>> {
  /// 保存配置与客户端实例。
  const DiomanRegistration(this.plugin, this.instance);

  /// 插件配置。
  final DiomanPlugin<R> plugin;

  /// setup 返回的独立状态。
  final DiomanPluginInstance<R>? instance;
}

/// 按名称确定位置；自定义插件位于同阶段内置插件前后。
(int, int) _position(DiomanPlugin plugin) {
  for (final entry in diomanBuiltinStages.entries) {
    final index = entry.value.indexOf(plugin.name);
    if (index >= 0) return (entry.key.index, index);
  }
  if (plugin.name.startsWith('dioman:')) {
    throw ArgumentError.value(plugin.name, _nameArgument, '保留前缀');
  }
  return (plugin.stage.index, plugin.enforce == DiomanEnforce.pre ? -1 : 100);
}

/// 在 setup 前验证重名和保留前缀，拒绝非法配置且不产生副作用。
void validateDiomanPlugins(Iterable<DiomanPlugin> plugins) {
  final names = <String>{};
  for (final plugin in plugins) {
    if (!names.add(plugin.name)) {
      throw ArgumentError.value(plugin.name, _nameArgument, '插件重名');
    }
    if (!diomanSetupPlugins.contains(plugin.name)) _position(plugin);
  }
}

/// 稳定排序已启用且有 handle 的插件；不修改输入。
List<DiomanRegistration<R>>
    sortDiomanPipeline<R extends DiomanResponse<dynamic>>(
        List<DiomanRegistration<R>> registrations) {
  final indexed =
      registrations.indexed.where((e) => e.$2.instance != null).toList();
  indexed.sort((a, b) {
    final x = _position(a.$2.plugin);
    final y = _position(b.$2.plugin);
    final stage = x.$1.compareTo(y.$1);
    if (stage != 0) return stage;
    final order = x.$2.compareTo(y.$2);
    return order == 0 ? a.$1.compareTo(b.$1) : order;
  });
  return indexed.map((e) => e.$2).toList();
}

/// 从内到外编译一次；每层含一个异常边界，无补丁复用上下文。
DiomanRunner<R> compileDiomanPipeline<R extends DiomanResponse<dynamic>>(
    List<DiomanRegistration<R>> layers, DiomanRunner<R> transport) {
  var run = transport;
  for (final layer in layers.reversed) {
    final inner = run;
    run = (ctx) async {
      try {
        return await layer.instance!.handle(ctx, ([patch]) async {
          DiomanContext<R> target;
          try {
            target = patch == null ? ctx : ctx.derive(patch);
          } catch (e, s) {
            return ctx.fail(DiomanFailure(
                kind: DiomanKind.internal, error: e, errorStack: s));
          }
          return inner(target);
        });
      } catch (e, s) {
        return ctx.fail(
            DiomanFailure(kind: DiomanKind.internal, error: e, errorStack: s));
      }
    };
  }
  return run;
}
