import 'package:flutter/widgets.dart';

import 'providers.dart' show CountmanScope;
import 'reduce_motion.dart';

/// 当前上下文是否应当减弱动画。
///
/// 优先读取 `MediaQuery.maybeDisableAnimationsOf(context)`（会注册依赖，随系统
/// 设置变化重建）；没有 MediaQuery 时回退到平台标志 [reduceMotion]。
/// 返回 true 表示装饰性动画应直接跳到终值；功能性计时不受影响。
///
/// 示例：`final snap = reduceMotionOf(context);`
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? reduceMotion;

/// 解析组件使用的插件：组件显式插件 > 最近的 `CountmanScope<P>` 插件 > [fallback]。
///
/// 用 `getInheritedWidgetOfExactType` 读取，**不注册依赖**，可以在 `initState`
/// 里调用；需要随作用域变化重建时改用 [resolvePluginDependent]。
/// [widgetPlugin] 为组件显式传入的插件；[fallback] 仅在前两者都没有时调用。
///
/// 示例：`final p = resolvePlugin<Countdown>(context, widgetPlugin: widget.plugin, fallback: () => defaultCountdown);`
P resolvePlugin<P>(
  BuildContext context, {
  P? widgetPlugin,
  required P Function() fallback,
}) =>
    widgetPlugin ??
    context.getInheritedWidgetOfExactType<CountmanScope<P>>()?.plugin ??
    fallback();

/// 与 [resolvePlugin] 规则相同，但会向最近的 `CountmanScope<P>` 注册依赖，
/// 作用域变化时组件重建；用于 `didChangeDependencies` 或 `build`，不可在
/// `initState` 调用。
///
/// 示例：`final p = resolvePluginDependent<Counter>(context, widgetPlugin: widget.plugin, fallback: () => defaultCounter);`
P resolvePluginDependent<P>(
  BuildContext context, {
  P? widgetPlugin,
  required P Function() fallback,
}) => widgetPlugin ?? CountmanScope.maybeOf<P>(context)?.plugin ?? fallback();
