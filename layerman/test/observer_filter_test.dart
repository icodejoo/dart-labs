import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// 测试使用的页面路径与上下文键。
const _home = '/home';
const _zone = '/zone';
const _detail = '/detail';
const _popup = 'layerman://promo';
const _routeKey = 'route';
const _tabKey = 'tabRoute';
const _promo = 'promo';
const _queued = 'queued';
const _dialogText = '确认弹窗';
const _sheetText = '底部弹层';

/// 创建具名或匿名页面，用于触发真实导航。
MaterialPageRoute<void> _page(String? name, {Widget? body}) =>
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => Scaffold(body: body ?? const SizedBox()),
    );

/// 挂载真实应用并完成初始导航，返回用于操作的导航键。
Future<GlobalKey<NavigatorState>> _mount(
  WidgetTester tester,
  List<NavigatorObserver> observers, {
  Widget? body,
}) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: key,
    navigatorObservers: observers,
    onGenerateRoute: (settings) => _page(settings.name),
    onGenerateInitialRoutes: (_) => [_page(_home, body: body)],
  ));
  await tester.pumpAndSettle();
  return key;
}

/// 创建管理器并保证测试结束时释放资源，兼容测试中提前销毁。
Layerman _manager({List<String>? pauseOnRoutes}) {
  final manager = Layerman(pauseOnRoutes: pauseOnRoutes ?? const []);
  addTearDown(() {
    if (!manager.isDisposed) manager.dispose();
  });
  return manager;
}

/// 不渲染界面的后端，记录排队条目何时获得展示许可。
class _Backend {
  /// 展示完成信号，由编排器关闭时完成。
  final _dismissed = Completer<void>();

  /// 记录后端是否已经被调用。
  bool presented = false;

  /// 返回可被编排器定点关闭的后端句柄。
  PresentedOverlay<void> present(PresentContext context) {
    presented = true;
    return PresentedOverlay<void>(
      dismissed: _dismissed.future,
      dismiss: ([_]) async {
        if (!_dismissed.isCompleted) _dismissed.complete();
      },
    );
  }
}

/// 运行真实 showDialog 后端；关闭回调持有弹窗自己的路由对象。
PresentedOverlay<void> _presentDialog(BuildContext context) {
  Route<dynamic>? dialogRoute;
  final navigator = Navigator.of(context);
  final dismissed = showDialog<void>(
    context: context,
    routeSettings: const RouteSettings(name: _popup),
    builder: (dialogContext) {
      dialogRoute = ModalRoute.of(dialogContext)!;
      return const AlertDialog(content: Text(_dialogText));
    },
  );
  return PresentedOverlay<void>(
    dismissed: dismissed,
    dismiss: ([_]) async {
      final route = dialogRoute;
      if (route == null || !route.isActive) return;
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    },
  );
}

/// 验证页面过滤、独立上下文及导航回调的不变量。
void main() {
  testWidgets('页面 push 和 pop 更新路径，匿名页面仍清空路径', (tester) async {
    final manager = _manager();
    final key = await _mount(tester, [LayermanNavigatorObserver(manager)]);
    expect(manager.currentRoute, _home);

    key.currentState!.push(_page(_detail));
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _detail);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _home);

    final backend = _Backend();
    manager.open<void>(id: _promo, route: _home, present: backend.present);
    expect(manager.isShowing(_promo), isTrue);
    key.currentState!.push(_page(null));
    await tester.pumpAndSettle();
    expect(manager.currentRoute, isNull);
    expect(manager.isShowing(_promo), isFalse);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _home);
  });

  testWidgets('B6：路由条件 overlap 弹窗不会因自己的 showDialog 被关闭', (tester) async {
    final manager = _manager();
    final key = await _mount(tester, [LayermanNavigatorObserver(manager)]);
    final result = manager.open<void>(
      id: _promo,
      overlap: true,
      route: _home,
      present: (_) => _presentDialog(key.currentContext!),
    );
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _home);
    expect(manager.isShowing(_promo), isTrue);
    expect(find.text(_dialogText), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(manager.isShowing(_promo), isTrue);
    expect(find.text(_dialogText), findsOneWidget);

    manager.close(_promo);
    await tester.pumpAndSettle();
    await result;
    expect(find.text(_dialogText), findsNothing);
    expect(manager.currentRoute, _home);
  });

  testWidgets('B7：免打扰页的匿名确认框不释放队列，离开页面才恢复', (tester) async {
    final manager = _manager(pauseOnRoutes: const [_zone]);
    final key = await _mount(tester, [LayermanNavigatorObserver(manager)]);
    key.currentState!.push(_page(_zone));
    await tester.pumpAndSettle();
    expect(manager.isPaused, isTrue);
    final backend = _Backend();
    manager.open<void>(id: _queued, present: backend.present);
    final dialog = showDialog<void>(
      context: key.currentContext!,
      builder: (_) => const AlertDialog(content: Text(_dialogText)),
    );
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _zone);
    expect(manager.isPaused, isTrue);
    expect(backend.presented, isFalse);
    expect(manager.queuedIds, contains(_queued));

    key.currentState!.pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(manager.currentRoute, _zone);
    expect(manager.isPaused, isTrue);
    expect(backend.presented, isFalse);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _home);
    expect(manager.isPaused, isFalse);
    expect(backend.presented, isTrue);
  });

  testWidgets('底部弹层也被默认过滤，关闭后仍保留页面路径', (tester) async {
    final manager = _manager();
    final key = await _mount(tester, [LayermanNavigatorObserver(manager)]);
    final sheet = showModalBottomSheet<void>(
      context: key.currentContext!,
      routeSettings: const RouteSettings(name: _popup),
      builder: (_) => const Text(_sheetText),
    );
    await tester.pumpAndSettle();
    expect(find.text(_sheetText), findsOneWidget);
    expect(manager.currentRoute, _home);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    await sheet;
    expect(manager.currentRoute, _home);
  });

  testWidgets('自定义过滤器接受所有路由时，具名及匿名弹窗均改写路径', (tester) async {
    final manager = _manager();
    final key = await _mount(tester, [
      LayermanNavigatorObserver(manager, routeFilter: (_) => true),
    ]);
    for (final name in <String?>[_popup, null]) {
      final dialog = showDialog<void>(
        context: key.currentContext!,
        routeSettings: RouteSettings(name: name),
        builder: (_) => const AlertDialog(content: Text(_dialogText)),
      );
      await tester.pumpAndSettle();
      expect(manager.currentRoute, name);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      await dialog;
      expect(manager.currentRoute, _home);
    }
  });

  testWidgets('自定义过滤器也可拒绝页面，不调用路径提取或通知管理器', (tester) async {
    final manager = _manager();
    manager.setContext(const {_routeKey: _zone});
    var calls = 0;
    final key = await _mount(tester, [
      LayermanNavigatorObserver(
        manager,
        routeFilter: (_) => false,
        pathOf: (route) {
          calls++;
          return route.settings.name;
        },
      ),
    ]);
    var notifications = 0;
    manager.addListener(() => notifications++);
    key.currentState!.push(_page(_detail));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(notifications, 0);
    expect(manager.currentRoute, _zone);
  });

  testWidgets('自定义键供 when 读取，不改变默认路径或触发默认免打扰条件', (tester) async {
    final manager = _manager(pauseOnRoutes: const [_zone]);
    manager.setContext(const {_routeKey: _home});
    final key = await _mount(tester, [
      LayermanNavigatorObserver(manager, contextKey: _tabKey),
    ]);
    final backend = _Backend();
    final defaultBackend = _Backend();
    manager.open<void>(
      id: _promo,
      when: (ctx) => ctx[_tabKey] == _zone,
      present: backend.present,
    );
    manager.open<void>(
      id: _queued,
      route: _zone,
      present: defaultBackend.present,
    );
    expect(backend.presented, isFalse);
    key.currentState!.push(_page(_zone));
    await tester.pumpAndSettle();
    expect(backend.presented, isTrue);
    expect(defaultBackend.presented, isFalse);
    expect(manager.currentRoute, _home);
    expect(manager.isPaused, isFalse);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(manager.isShowing(_promo), isFalse);
  });

  testWidgets('嵌套导航的两个观察者分别更新各自键，互不覆盖', (tester) async {
    final manager = _manager();
    final nestedKey = GlobalKey<NavigatorState>();
    final outerKey = await _mount(
      tester,
      [LayermanNavigatorObserver(manager)],
      body: Navigator(
        key: nestedKey,
        observers: [LayermanNavigatorObserver(manager, contextKey: _tabKey)],
        onGenerateRoute: (_) => _page(_detail),
      ),
    );
    final backend = _Backend();
    manager.open<void>(
      id: _promo,
      when: (ctx) => ctx[_tabKey] == _detail && ctx[_routeKey] == _home,
      present: backend.present,
    );
    expect(backend.presented, isTrue);
    nestedKey.currentState!.push(_page(_zone));
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _home);
    expect(manager.isShowing(_promo), isFalse);

    outerKey.currentState!.push(_page(_zone));
    await tester.pumpAndSettle();
    final both = _Backend();
    manager.open<void>(
      id: _queued,
      when: (ctx) => ctx[_tabKey] == _zone && ctx[_routeKey] == _zone,
      present: both.present,
    );
    expect(both.presented, isTrue);
    outerKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(manager.currentRoute, _home);
    expect(manager.isShowing(_queued), isFalse);
  });

  testWidgets('默认过滤的弹窗不提取路径、不通知也不请求帧，页面恢复后照常提取', (tester) async {
    final manager = _manager();
    var calls = 0;
    final observer = LayermanNavigatorObserver(manager, pathOf: (route) {
      calls++;
      return route.settings.name;
    });
    final key = await _mount(tester, [observer]);
    final baseline = calls;
    var notifications = 0;
    manager.addListener(() => notifications++);
    final dialog = DialogRoute<void>(
      context: key.currentContext!,
      builder: (_) => const SizedBox(),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    observer.didChangeTop(dialog, null);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(calls, baseline);
    expect(notifications, 0);
    dialog.dispose();

    final shown = showDialog<void>(
      context: key.currentContext!,
      builder: (_) => const AlertDialog(content: Text(_dialogText)),
    );
    await tester.pumpAndSettle();
    expect(calls, baseline);
    expect(notifications, 0);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    await shown;
    expect(calls, baseline + 1);
    expect(notifications, 1);
  });

  testWidgets('路径提取异常被上报并按 null 更新，更新仍延后且主动请求帧', (tester) async {
    final manager = _manager();
    var shouldThrow = false;
    final observer = LayermanNavigatorObserver(manager, pathOf: (route) {
      if (shouldThrow) throw StateError('路径提取失败');
      return route.settings.name;
    });
    await _mount(tester, [observer]);
    shouldThrow = true;
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    final page = _page(_detail);
    try {
      observer.didChangeTop(page, null);
    } finally {
      FlutterError.onError = previous;
    }
    expect(errors, hasLength(1));
    expect(errors.single.exception, isA<StateError>());
    expect(manager.currentRoute, _home);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(manager.currentRoute, isNull);
    page.dispose();
  });

  testWidgets('调度前或帧后回调前销毁管理器，均不再写入上下文', (tester) async {
    final manager = _manager();
    var calls = 0;
    final observer = LayermanNavigatorObserver(manager, pathOf: (route) {
      calls++;
      return route.settings.name;
    });
    final key = await _mount(tester, [observer]);
    key.currentState!.push(_page(_detail));
    final beforeDispose = calls;
    manager.dispose();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(manager.currentRoute, _home);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, beforeDispose);
    expect(tester.takeException(), isNull);
  });
}
