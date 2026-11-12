import 'package:flutter/widgets.dart';

/// 动态配置的 Widget 构建函数，json 的解释由注册者负责。
typedef LuckyViewBuilder = Widget Function(
    BuildContext context, Map<String, dynamic> json);

/// 实例级注册表，只包含调用者显式加入的玩法。
final class LuckyGameRegistry {
  /// 创建空注册表。
  LuckyGameRegistry();

  /// 显式注册的构建函数。
  final Map<String, LuckyViewBuilder> _builders = {};

  /// 注册 [key]；同名覆盖之前的构建函数。
  void add(String key, LuckyViewBuilder builder) => _builders[key] = builder;

  /// 用 [key] 构建 Widget，未注册时返回 null。
  Widget? build(String key, BuildContext context, Map<String, dynamic> json) =>
      _builders[key]?.call(context, json);

  /// 已注册键的只读快照。
  Iterable<String> get keys => List.unmodifiable(_builders.keys);
}
