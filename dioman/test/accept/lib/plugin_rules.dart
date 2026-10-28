import 'package:dioman/dioman.dart';
import 'client.dart';

/// verifyPluginRules 的测试辅助入口。
/// 将实际安装图的每条边和 extra 键所有权转成可执行断言。
List<String> verifyPluginRules(ScenarioClient client) {
  final plugins = client.handle.plugins;
  Dioman.validate(plugins);
  final checked = <String>[];
  final byName = {for (final plugin in plugins) plugin.name: plugin};
  for (final plugin in plugins) {
    final order = plugin.ordering;
    final edges = <(String, String)>[
      for (final name in order.before)
        if (byName.containsKey(name)) (plugin.name, name),
      for (final name in order.after)
        if (byName.containsKey(name)) (name, plugin.name),
    ];
    for (final (before, after) in edges) {
      var rejected = false;
      try {
        Dioman.validate([byName[after]!, byName[before]!]);
      } on DiomanPluginOrderException catch (error) {
        rejected = error.issue == DiomanPluginOrderIssue.misordered;
      }
      if (!rejected) throw StateError('逆序未被拒绝：$before/$after');
      checked.add('lib/src/plugin_order.dart: $before < $after');
    }
    var duplicateRejected = false;
    try {
      Dioman.sort([plugin, plugin]);
    } on DiomanPluginOrderException catch (error) {
      duplicateRejected = error.issue == DiomanPluginOrderIssue.duplicateName;
    }
    if (!duplicateRejected) throw StateError('重复插件名未被拒绝：${plugin.name}');
    checked.add('lib/src/plugin_order.dart: unique ${plugin.name}');
  }
  if (DiomanExtraKeys.findSharedState(plugins).isNotEmpty) {
    throw StateError('正常安装存在 extra 状态冲突');
  }
  final names = <String>{};
  for (final key in DiomanExtraKeys.all) {
    if (!names.add(key.key)) throw StateError('extra 重复：${key.key}');
    // 传输层 adapter 不是插件，配置键的 owner 登记为类名，键由它自己的常量提供。
    final adapterKey = key.owner == DiomanExtraKeys.mockAdapterOwner;
    if (key.kind == DiomanExtraKeyKind.config &&
        (adapterKey
            ? key.key != DiomanMockAdapter.extraKey
            : key.key != key.owner)) {
      throw StateError('extra 配置键所有权错误：${key.key}');
    }
    if (key.kind == DiomanExtraKeyKind.state &&
        !key.key.startsWith('${key.owner}:')) {
      throw StateError('extra 状态键前缀错误：${key.key}');
    }
    checked.add('lib/src/extra_keys.dart: ${key.key}');
  }
  return checked;
}
