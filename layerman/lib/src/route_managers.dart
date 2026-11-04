import 'package:flutter/material.dart';

import 'overlay_manager.dart';

/// 内置路由名的默认前缀。
const _routeNamePrefix = 'layerman://';

/// 将 [route] 推入 [navigator]，返回可定向关闭且等待退场结束的句柄。
///
/// 栈顶关闭会携带结果并播放退场动画；被覆盖时只移除该路由。
/// 为兼容 Flutter 3.27，移除时不向 Navigator 传结果，因此直接使用句柄
/// 关闭被覆盖的路由时，`dismissed` 为 null；通过 [Layerman.close] 关闭时，
/// 编排器仍会将指定结果交付给 `open`。已移除的路由再次关闭为无操作。
/// 无需额外设置 `exitDuration`。页面路由也可直接适配：
/// ```dart
/// manager.open<bool>(
///   present: (_) => presentRoute(navigator, MaterialPageRoute<bool>(
///     builder: (_) => const Scaffold(body: Text('页面')),
///   )),
/// );
/// ```
PresentedOverlay<T> presentRoute<T>(
  NavigatorState navigator,
  TransitionRoute<T> route,
) {
  navigator.push(route);
  return PresentedOverlay<T>(
    dismissed: route.completed,
    dismiss: ([result]) async => _dismissRoute(route, result),
  );
}

/// 只关闭指定路由，不影响覆盖它的其它路由。
void _dismissRoute<T>(TransitionRoute<T> route, T? result) {
  final nav = route.navigator;
  if (nav == null || !route.isActive) return;
  if (route.isCurrent) {
    nav.pop(result);
  } else {
    nav.removeRoute(route);
  }
}

/// 共用只读配置与每次展示独立的关闭回调。
abstract class _RouteManager {
  /// 保存配置，直到实际 present 才读取导航器。
  _RouteManager(
    GlobalKey<NavigatorState> navigatorKey, {
    Layerman? manager,
    bool barrierDismissible = true,
    Color? barrierColor,
    bool useSafeArea = true,
    String routeNamePrefix = _routeNamePrefix,
  })  : _navigatorKey = navigatorKey,
        _manager = manager,
        _barrierDismissible = barrierDismissible,
        _barrierColor = barrierColor,
        _useSafeArea = useSafeArea,
        _prefix = routeNamePrefix;

  /// 每次展示时查询的导航器键。
  final GlobalKey<NavigatorState> _navigatorKey;

  /// 可选的守卫与结果类型校验入口。
  final Layerman? _manager;

  /// 默认是否允许点击遮罩关闭。
  final bool _barrierDismissible;

  /// 默认遮罩颜色，空值使用 Material 主题。
  final Color? _barrierColor;

  /// 默认是否避开系统安全区域。
  final bool _useSafeArea;

  /// 路由名称前缀。
  final String _prefix;

  /// 为每次 present 创建独立路由及关闭回调。
  Present<T> _present<T>(
    Widget Function(PresentContext ctx, void Function([T? result]) close)
        builder,
    TransitionRoute<T> Function(
      NavigatorState navigator,
      WidgetBuilder builder,
      RouteSettings settings,
    ) createRoute,
  ) =>
      (ctx) {
        final navigator = _navigatorKey.currentState;
        if (navigator == null) {
          throw StateError(
            '$runtimeType 无法展示 ${ctx.id}：navigatorKey.currentState 为 null；'
            '请先挂载使用该 navigatorKey 的 Navigator。',
          );
        }
        late final TransitionRoute<T> route;

        /// 将本次关闭交给指定编排器，或直接定向关闭本次路由。
        void close([T? result]) {
          if (_manager != null) {
            _manager.close(ctx.id, result);
          } else {
            _dismissRoute(route, result);
          }
        }

        route = createRoute(
          navigator,
          (_) => builder(ctx, close),
          RouteSettings(name: '$_prefix${ctx.id}'),
        );
        return presentRoute(navigator, route);
      };
}

/// 可全局复用的对话框 presenter 工厂，仅持有配置，不保存某次展示状态。
///
/// 绑定 [Layerman] 后，builder 的 close 走其守卫和类型校验；未绑定则直接
/// 关闭对应路由（用户返回或遮罩关闭也直接走路由）。更换编排器时，可复用
/// 未绑定 manager 的实例；绑定的实例始终使用构造时指定的编排器。
class DialogManager extends _RouteManager {
  /// 使用指定导航器键；可设置默认遮罩、安全区域与路由名前缀。
  /// [manager] 可选，用于让 builder 的 close 经过 `beforeClose`。
  DialogManager(
    super.navigatorKey, {
    super.manager,
    super.barrierDismissible,
    super.barrierColor,
    super.useSafeArea,
    super.routeNamePrefix,
  });

  /// 返回供 `Layerman.open<T>(present: ...)` 使用的 presenter。
  /// [builder] 接收当前条目上下文及可携带结果的 close；非空参数覆盖默认值。
  /// 展示时导航器尚未挂载会抛出 [StateError]，由编排器上报并丢弃条目。
  Present<T> call<T>(
    Widget Function(PresentContext ctx, void Function([T? result]) close)
        builder, {
    bool? barrierDismissible,
    Color? barrierColor,
    bool? useSafeArea,
  }) =>
      _present<T>(builder, (navigator, widgetBuilder, settings) {
        final context = navigator.context;
        return DialogRoute<T>(
          context: context,
          builder: widgetBuilder,
          settings: settings,
          barrierDismissible: barrierDismissible ?? _barrierDismissible,
          barrierColor: barrierColor ??
              _barrierColor ??
              DialogTheme.of(context).barrierColor ??
              Theme.of(context).dialogTheme.barrierColor ??
              Colors.black54,
          barrierLabel:
              MaterialLocalizations.of(context).modalBarrierDismissLabel,
          useSafeArea: useSafeArea ?? _useSafeArea,
          themes: InheritedTheme.capture(from: context, to: context),
        );
      });
}

/// 可全局复用的模态底部弹层 presenter 工厂，关闭契约与 [DialogManager] 相同。
class BottomSheetManager extends _RouteManager {
  /// 配置导航器、可选编排器、遮罩、安全区域及底部弹层的常用默认值。
  /// [isScrollControlled] 默认 false，允许单次调用覆盖。
  BottomSheetManager(
    super.navigatorKey, {
    super.manager,
    super.barrierDismissible,
    super.barrierColor,
    super.useSafeArea,
    super.routeNamePrefix,
    bool isScrollControlled = false,
    Color? backgroundColor,
    bool enableDrag = true,
    bool? showDragHandle,
  })  : _isScrollControlled = isScrollControlled,
        _backgroundColor = backgroundColor,
        _enableDrag = enableDrag,
        _showDragHandle = showDragHandle;

  /// 默认是否允许弹层使用完整高度。
  final bool _isScrollControlled;

  /// 默认弹层背景色。
  final Color? _backgroundColor;

  /// 默认是否允许拖动关闭。
  final bool _enableDrag;

  /// 默认是否显示拖动把手，空值使用主题。
  final bool? _showDragHandle;

  /// 返回底部弹层 presenter；非空参数覆盖构造默认值。
  /// [builder] 接收条目上下文及 close；导航器未挂载时抛出 [StateError]。
  /// 绑定 manager 时 close 经过守卫；否则直接关闭本次路由。
  Present<T> call<T>(
    Widget Function(PresentContext ctx, void Function([T? result]) close)
        builder, {
    bool? barrierDismissible,
    Color? barrierColor,
    bool? useSafeArea,
    bool? isScrollControlled,
    Color? backgroundColor,
    bool? enableDrag,
    bool? showDragHandle,
  }) =>
      _present<T>(builder, (navigator, widgetBuilder, settings) {
        final context = navigator.context;
        final localizations = MaterialLocalizations.of(context);
        return ModalBottomSheetRoute<T>(
          builder: widgetBuilder,
          settings: settings,
          capturedThemes: InheritedTheme.capture(from: context, to: context),
          barrierLabel: localizations.scrimLabel,
          barrierOnTapHint:
              localizations.scrimOnTapHint(localizations.bottomSheetLabel),
          isDismissible: barrierDismissible ?? _barrierDismissible,
          modalBarrierColor: barrierColor ??
              _barrierColor ??
              Theme.of(context).bottomSheetTheme.modalBarrierColor,
          useSafeArea: useSafeArea ?? _useSafeArea,
          isScrollControlled: isScrollControlled ?? _isScrollControlled,
          backgroundColor: backgroundColor ?? _backgroundColor,
          enableDrag: enableDrag ?? _enableDrag,
          showDragHandle: showDragHandle ?? _showDragHandle,
        );
      });
}
