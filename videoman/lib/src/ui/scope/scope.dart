import 'package:flutter/widgets.dart';

import '../../core/api.dart';

/// Publishes a [VmApi] instance down the widget tree so descendant widgets
/// (e.g. [VmSelector] and friends) can find it without it being threaded
/// through every constructor.
///
/// 将一个 [VmApi] 实例向下发布到组件树，使后代组件（如 [VmSelector] 及其
/// 同类）无需层层传参即可找到它。
class VmScope extends InheritedWidget {
  /// Wraps [child] with a scope that exposes [api] to descendants.
  ///
  /// [api] is the capability surface to publish. [child] is the subtree
  /// that (transitively) depends on it.
  ///
  /// 用一个向后代暴露 [api] 的作用域包裹 [child]。
  ///
  /// [api] 为要发布的能力面。[child] 为（间接）依赖它的子树。
  const VmScope({required this.api, required super.child, super.key});

  /// The capability surface published to descendants.
  ///
  /// 发布给后代的能力面。
  final VmApi api;

  /// Looks up the nearest enclosing [VmScope] and returns its [api].
  ///
  /// Throws a [FlutterError] if [context] is not below a [VmScope].
  ///
  /// 查找最近的 [VmScope] 并返回其 [api]。
  ///
  /// 若 [context] 不在任何 [VmScope] 之下则抛出 [FlutterError]。
  static VmApi of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<VmScope>();
    if (scope == null) {
      throw FlutterError(
        'VmScope.of() called outside a VmScope. Wrap your widget in VmPlayer or VmScope.',
      );
    }
    return scope.api;
  }

  @override
  bool updateShouldNotify(VmScope oldWidget) => api != oldWidget.api;
}
