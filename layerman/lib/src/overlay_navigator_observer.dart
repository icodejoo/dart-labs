import 'package:flutter/widgets.dart';

import 'overlay_manager.dart';

/// 将实际导航写入 [Layerman.setContext]，只通过 `didChangeTop` 观察栈顶。
/// 默认仅接受 [PageRoute]，忽略对话框、底部弹层和菜单等弹出路由，
/// 保留最近页面的上下文；弹窗关闭后返回页面时照常更新。
/// 传入 `routeFilter: (route) => true` 可恢复所有路由均参与更新的行为。
///
/// 加入 `MaterialApp.navigatorObservers` 即可使用。路径默认取路由名称，
/// 可用 `pathOf` 自定义；匿名页面和路径提取异常都写入 null，异常会被上报。
/// `MaterialApp.home` 的隐式路由名称为 `/`。
///
/// `contextKey` 默认是 `route`。嵌套 Navigator 可配置不同键，
/// 通过 `when: (ctx) => ctx['tabRoute'] == '/detail'` 读取；
/// `route:` 条件与 `pauseOnRoutes` 只识别默认的 `route` 键。
/// 每个键应由对应观察者负责，手动写入会在下次接受的导航变化时被覆盖。
///
/// 更新延后到帧后并显式请求帧，避免导航在构建期间触发同步通知。
/// 安排回调前及回调内均检查 [Layerman.isDisposed]，销毁后不再写入。
class LayermanNavigatorObserver extends NavigatorObserver {
  /// 创建观察者；[pathOf] 默认读取路由名称，抛异常时上报并写入 null。
  /// [routeFilter] 默认仅接受页面路由，拒绝时不提取路径也不安排更新。
  /// [contextKey] 指定写入的上下文键，默认值为 `route`。
  LayermanNavigatorObserver(
    this.manager, {
    String? Function(Route<dynamic> route)? pathOf,
    bool Function(Route<dynamic> route)? routeFilter,
    this.contextKey = 'route',
  })  : _pathOf = pathOf ?? _defaultPathOf,
        _routeFilter = routeFilter ?? _defaultRouteFilter;

  /// 接收路由上下文的管理器；已销毁时跳过更新。
  final Layerman manager;

  /// 写入的上下文键；`route:` 和 `pauseOnRoutes` 仅识别默认的 `route` 键。
  final String contextKey;

  /// 从已接受的路由提取路径。
  final String? Function(Route<dynamic> route) _pathOf;

  /// 判断是否接受当前栈顶路由。
  final bool Function(Route<dynamic> route) _routeFilter;

  /// 默认使用路由名称，匿名页面返回 null。
  static String? _defaultPathOf(Route<dynamic> route) => route.settings.name;

  /// 默认只接受页面，忽略对话框、底部弹层和菜单等弹出路由。
  static bool _defaultRouteFilter(Route<dynamic> route) => route is PageRoute;

  /// 接受的栈顶路由在帧后更新上下文，被过滤的路由不产生更新。
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    super.didChangeTop(topRoute, previousTopRoute);
    if (manager.isDisposed) return;
    if (!_routeFilter(topRoute)) return;

    String? path;
    try {
      path = _pathOf(topRoute);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'layerman',
        context: ErrorDescription(
          'while extracting the path for LayermanNavigatorObserver',
        ),
      ));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (manager.isDisposed) return;
      manager.setContext({contextKey: path});
    });
    // 帧后回调只有在实际运行帧后才触发。导航动画通常会请求帧，
    // 但空闲时不能依赖动画，否则回调可能一直挂起。
    WidgetsBinding.instance.scheduleFrame();
  }
}
