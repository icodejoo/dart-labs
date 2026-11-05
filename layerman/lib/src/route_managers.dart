import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'overlay_manager.dart';

/// 内置路由名的默认前缀。
const _routeNamePrefix = 'layerman://';

/// 将 [route] 推入 [navigator]，返回可定向关闭且等待退场结束的句柄。
///
/// 栈顶且无内部历史时关闭会携带结果并播放退场动画；否则只移除该路由。
/// 为兼容 Flutter 3.27，移除时不向 Navigator 传结果，因此直接使用句柄
/// 关闭被覆盖或带内部历史的路由时，`dismissed` 为 null；通过 [Layerman.close] 关闭时，
/// 编排器仍会将指定结果交付给 `open`。已移除的路由再次关闭为无操作。
/// 无需额外设置 `exitDuration`。ModalRoute 自动确认栈顶首帧；其它 TransitionRoute
/// 须通过 [visible] 提供自身成功绘制的信号。页面路由也可直接适配：
/// ```dart
/// manager.open<bool>(
///   present: (_) => presentRoute(navigator, MaterialPageRoute<bool>(
///     builder: (_) => const Scaffold(body: Text('页面')),
///   )),
/// );
/// ```
PresentedOverlay<T> presentRoute<T>(
  NavigatorState navigator,
  TransitionRoute<T> route, {
  Future<void>? visible,
}) {
  if (visible == null && route is! ModalRoute<T>) {
    throw ArgumentError('非 ModalRoute 必须提供首帧可见信号 visible');
  }
  navigator.push(route);
  return PresentedOverlay<T>(
    visible: visible ?? _routeVisible(route as ModalRoute<T>),
    dismissed: route.completed,
    dismiss: ([result]) async => _dismissRoute(route, result),
  );
}

/// 等待路由首帧成功构建、布局且位于栈顶；动画或遮盖变化时重新检查。
/// 未可见时只登记下一次自然帧的检查，不持续请求帧或驱动后台动画。
Future<void> _routeVisible<T>(ModalRoute<T> route) {
  final visible = Completer<void>();
  var pending = false;
  var ended = false;
  final animation = route.animation;
  final secondary = route.secondaryAnimation;
  late final VoidCallback schedule;

  /// 解除动画监听，避免关闭或已确认的路由继续持有确认器。
  void stop() {
    animation?.removeListener(schedule);
    secondary?.removeListener(schedule);
  }

  /// 合并同帧检查；静止界面也显式请求首帧。
  schedule = () {
    if (pending || ended || visible.isCompleted) return;
    pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pending = false;
      if (ended || visible.isCompleted) return;
      final context = route.subtreeContext;
      if (!route.isCurrent || context == null || !context.mounted) {
        schedule();
        return;
      }
      final render = context.findRenderObject();
      if (_hasBuildError(context as Element)) {
        visible.completeError(StateError('路由首帧构建失败'));
        stop();
      } else if (render != null &&
          render.attached &&
          (render is! RenderBox || render.hasSize) &&
          !route.offstage &&
          (animation == null || animation.value > 0)) {
        visible.complete();
        stop();
      } else {
        schedule();
      }
    });
  };

  animation?.addListener(schedule);
  secondary?.addListener(schedule);
  route.completed.then((_) {
    ended = true;
    stop();
  });
  schedule();
  WidgetsBinding.instance.scheduleFrame();
  return visible.future;
}

/// 检查首帧子树是否含 Flutter 用于替代构建失败内容的错误组件。
/// 仅识别 ErrorWidget；应用自定义 ErrorWidget.builder 返回其他组件时无法检测。
bool _hasBuildError(Element element) {
  if (element.widget is ErrorWidget) return true;
  var failed = false;
  element.visitChildren((child) {
    if (!failed) failed = _hasBuildError(child);
  });
  return failed;
}

/// 为自管 OverlayEntry 或第三方组件提供成功绘制后的首帧可见信号。
/// 包住实际内容，将同一个 [visible] 的 future 交给 PresentedOverlay；
/// 尚未绘制、被路由覆盖或构建失败时不会成功确认。
/// 替换确认器时，尚未确认的旧信号以 StateError 完成，避免把未绘制内容记为可见。
/// 应用若自定义 ErrorWidget.builder 返回非 ErrorWidget，构建失败检测会失效。
///
/// ```dart
/// import 'dart:async';
/// import 'package:flutter/material.dart';
/// import 'package:layerman/layerman.dart';
///
/// /// 在指定 Overlay 中插入内容，独立确认首帧与退场。
/// PresentedOverlay<void> presentTip(OverlayState overlay) {
///   final visible = Completer<void>();
///   final dismissed = Completer<void>();
///   final entry = OverlayEntry(
///     builder: (_) => OverlayVisibility(
///       visible: visible,
///       child: const Center(child: Material(child: Text('已保存'))),
///     ),
///   );
///   overlay.insert(entry);
///   return PresentedOverlay<void>(
///     visible: visible.future,
///     dismissed: dismissed.future,
///     dismiss: ([_]) async {
///       if (dismissed.isCompleted) return;
///       entry.remove();
///       entry.dispose();
///       dismissed.complete();
///     },
///   );
/// }
/// ```
class OverlayVisibility extends SingleChildRenderObjectWidget {
  /// 绑定本次展示的独立确认器与实际内容。
  const OverlayVisibility({
    super.key,
    required this.visible,
    required super.child,
  });

  /// 本次展示独立的首帧确认器，构建失败时以错误完成。
  final Completer<void> visible;

  /// 创建在绘制之后确认的代理渲染对象。
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _VisibilityRender(context as Element, visible, ModalRoute.of(context));

  /// 更新重建后使用的确认器。
  @override
  void updateRenderObject(
    BuildContext context,
    // 精确约束内部渲染类型，不为覆盖签名额外公开渲染实现。
    // ignore: library_private_types_in_public_api
    covariant _VisibilityRender renderObject,
  ) {
    if (!identical(renderObject.visible, visible)) {
      final previous = renderObject.visible;
      // 旧确认器尚未见到成功帧：以失败结束，不能成功完成并误记频次。
      if (!previous.isCompleted) {
        previous.completeError(StateError('可见确认器在首帧前被替换'));
      }
      renderObject.visible = visible;
      renderObject.pending = false; // 旧帧末回调不能阻止新确认器登记绘制。
    }
    // ModalRoute.of 建立依赖；重挂载到另一条路由或路由状态改变时同步刷新。
    renderObject.route = ModalRoute.of(context);
    renderObject.markNeedsPaint();
  }
}

/// 实际内容参与绘制后，在帧末检查挂载、路由和构建结果。
class _VisibilityRender extends RenderProxyBox {
  /// 保存元素、确认器及所在路由。
  _VisibilityRender(this.element, this.visible, this.route);

  /// 用于检查首帧构建结果的元素。
  final Element element;

  /// 当前展示的可见确认器。
  Completer<void> visible;

  /// 当前所在路由；依赖变更和跨路由重挂载时更新，顶层 OverlayEntry 可为空。
  ModalRoute<dynamic>? route;

  /// 同一帧只登记一次确认。
  bool pending = false;

  /// 成功绘制子树后，在帧末确认，零透明度或 Offstage 不会触发绘制。
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (pending || visible.isCompleted) return;
    pending = true;
    final painted = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) => _confirm(painted));
  }

  /// 已参与绘制后，覆盖期间只等待下一次自然帧，不驱动空转帧。
  void _confirm(Completer<void> painted) {
    if (!identical(visible, painted)) return; // 忽略旧确认器留下的帧末回调。
    pending = false;
    if (!attached || !element.mounted || visible.isCompleted) return;
    if (route != null && !route!.isCurrent) {
      pending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _confirm(painted));
      return;
    }
    if (_hasBuildError(element)) {
      visible.completeError(StateError('浮层首帧构建失败'));
    } else {
      visible.complete();
    }
  }
}

/// 只关闭指定路由，不影响覆盖它的其它路由。
void _dismissRoute<T>(TransitionRoute<T> route, T? result) {
  final nav = route.navigator;
  if (nav == null || !route.isActive) return;
  if (route.isCurrent && !route.willHandlePopInternally) {
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
    bool barrierDismissible = true,
    Color? barrierColor,
    bool useSafeArea = true,
    String routeNamePrefix = _routeNamePrefix,
  })  : _navigatorKey = navigatorKey,
        _barrierDismissible = barrierDismissible,
        _barrierColor = barrierColor,
        _useSafeArea = useSafeArea,
        _prefix = routeNamePrefix;

  /// 每次展示时查询的导航器键。
  final GlobalKey<NavigatorState> _navigatorKey;

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
    Widget Function(PresentContext<T> ctx, void Function([T? result]) close)
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

        route = createRoute(
          navigator,
          (_) => builder(ctx, ctx.close),
          RouteSettings(name: '$_prefix${ctx.id}'),
        );
        return presentRoute(navigator, route);
      };
}

/// 可全局复用的对话框 presenter 工厂，仅持有配置，不保存某次展示状态。
///
/// builder 的 close 总是通过当前条目上下文执行 beforeClose 守卫。
/// 返回键和遮罩仍由路由关闭并通过 dismissed 上报；实例可跨编排器复用。
class DialogManager extends _RouteManager {
  /// 使用指定导航器键；可设置默认遮罩、安全区域与路由名前缀。
  DialogManager(
    super.navigatorKey, {
    super.barrierDismissible,
    super.barrierColor,
    super.useSafeArea,
    super.routeNamePrefix,
  });

  /// 返回供 `Layerman.open<T>(present: ...)` 使用的 presenter。
  /// [builder] 接收当前条目上下文及可携带结果的 close；非空参数覆盖默认值。
  /// 展示时导航器尚未挂载会抛出 [StateError]，由编排器上报并丢弃条目。
  Present<T> call<T>(
    Widget Function(PresentContext<T> ctx, void Function([T? result]) close)
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
  /// 配置导航器、遮罩、安全区域及底部弹层的常用默认值。
  /// [isScrollControlled] 默认 false，允许单次调用覆盖。
  BottomSheetManager(
    super.navigatorKey, {
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
  /// close 一律经过当前条目的 beforeClose 守卫。
  Present<T> call<T>(
    Widget Function(PresentContext<T> ctx, void Function([T? result]) close)
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
