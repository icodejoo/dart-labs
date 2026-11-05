import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

final navigatorKey = GlobalKey<NavigatorState>();

// 原样复制 README 中文共享 helper，确保配方直接可用。
Present<T> dialog<T>(Widget child) => (ctx) {
      final navigator = navigatorKey.currentState!;
      final route = DialogRoute<T>(
        context: navigator.context,
        settings: RouteSettings(name: 'om://${ctx.id}'),
        builder: (_) => child,
      );
      navigator.push(route);
      return PresentedOverlay<T>(
        dismissed: route.completed, // 退场动画结束后完成，并携带 pop 的结果
        dismiss: ([r]) async {
          final nav = route.navigator;
          if (nav == null || !route.isActive) return;
          if (route.isCurrent && !route.willHandlePopInternally) {
            nav.pop(r); // 栈顶：播放退场动画
          } else {
            nav.removeRoute(route); // 被其它路由盖住：只移除这一条
          }
        },
      );
    };

// 记录真实路由，既检查队列状态，也检查 Navigator 中实际留下了什么。
class _RouteObserver extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  Route<dynamic> named(String name) =>
      routes.singleWhere((route) => route.settings.name == name);
}

class CheckoutPage extends StatelessWidget {
  const CheckoutPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('结算页面'));
}

// README 页面配方的 present 回调。
Present<void> checkout() => (ctx) {
      final navigator = navigatorKey.currentState!;
      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/checkout'),
        builder: (_) => const CheckoutPage(),
      );
      navigator.push(route);
      return PresentedOverlay<void>(
        dismissed: route.completed,
        dismiss: ([_]) async {
          final nav = route.navigator;
          if (nav == null || !route.isActive) return;
          if (route.isCurrent && !route.willHandlePopInternally) {
            nav.pop();
          } else {
            nav.removeRoute(route);
          }
        },
      );
    };

/// 挂载配方共用的导航器与首页。
Future<void> _pumpApp(WidgetTester tester, _RouteObserver observer) =>
    tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      home: const Scaffold(body: Text('首页')),
    ));

void main() {
  testWidgets('被 overlap B 遮住的 A 可定向关闭并交付结果，随后显示 C 且保留 B', (tester) async {
    final observer = _RouteObserver();
    final manager = Layerman();
    addTearDown(manager.dispose);
    await _pumpApp(tester, observer);

    final a = manager.open<String>(
      id: 'a',
      present: dialog(const AlertDialog(title: Text('弹窗 A'))),
    );
    await tester.pumpAndSettle();
    final routeA = observer.named('om://a');
    manager.open<String>(
      id: 'b',
      mode: OverlayMode.overlap,
      present: dialog(const AlertDialog(title: Text('弹窗 B'))),
    );
    await tester.pumpAndSettle();
    final routeB = observer.named('om://b');
    manager.open<String>(
      id: 'c',
      present: dialog(const AlertDialog(title: Text('弹窗 C'))),
    );
    await tester.pump();
    expect(routeA.isCurrent, isFalse);
    expect(routeB.isCurrent, isTrue);
    expect(manager.queuedIds, ['c']);
    expect(observer.routes.any((route) => route.settings.name == 'om://c'),
        isFalse);

    manager.close('a', '指定结果');
    await tester.pumpAndSettle();

    expect(await a, '指定结果');
    expect(observer.routes, isNot(contains(routeA)));
    expect(routeA.navigator, isNull);
    expect(manager.isShowing('a'), isFalse);
    expect(manager.activeIds, containsAll(['b', 'c']));
    expect(observer.named('om://c').isCurrent, isTrue);
    expect(observer.routes, contains(routeB));
    expect(routeB.isActive, isTrue);
    expect(find.text('弹窗 C'), findsOneWidget);
    expect(find.text('弹窗 B', skipOffstage: false), findsOneWidget);
  });

  testWidgets('用户 pop 携带结果，退场动画完成后才显示下一个条目', (tester) async {
    final observer = _RouteObserver();
    final manager = Layerman();
    addTearDown(manager.dispose);
    await _pumpApp(tester, observer);
    var resultDelivered = false;
    final a = manager.open<String>(
      id: 'a',
      present: dialog(const AlertDialog(title: Text('弹窗 A'))),
    );
    a.then((_) => resultDelivered = true);
    await tester.pumpAndSettle();
    final routeA = observer.named('om://a') as TransitionRoute<dynamic>;
    var cPresented = false;
    manager.open<String>(
      id: 'c',
      present: (ctx) {
        cPresented = true;
        return dialog<String>(const AlertDialog(title: Text('弹窗 C')))(ctx);
      },
    );

    navigatorKey.currentState!.pop('ok');
    await tester.pump(); // 仅一帧，退场动画还没有结束。
    expect(routeA.animation!.status, AnimationStatus.reverse);
    expect(cPresented, isFalse);
    expect(resultDelivered, isFalse);
    expect(manager.queuedIds, ['c']);

    await tester.pumpAndSettle();
    expect(await a, 'ok');
    expect(cPresented, isTrue);
    expect(find.text('弹窗 C'), findsOneWidget);
  });

  for (final buried in [false, true]) {
    testWidgets('页面路由在${buried ? '被遮挡' : '栈顶'}时均可被 close 关闭', (tester) async {
      final observer = _RouteObserver();
      final manager = Layerman();
      addTearDown(manager.dispose);
      await _pumpApp(tester, observer);
      final page = manager.open<void>(id: 'checkout', present: checkout());
      await tester.pumpAndSettle();
      final route = observer.named('/checkout');
      Route<dynamic>? cover;
      if (buried) {
        manager.open<String>(
          id: 'cover',
          mode: OverlayMode.overlap,
          present: dialog(const AlertDialog(title: Text('覆盖弹窗'))),
        );
        await tester.pumpAndSettle();
        cover = observer.named('om://cover');
      }
      expect(route.isCurrent, !buried);

      manager.close('checkout');
      await tester.pumpAndSettle();
      await page;

      expect(route.navigator, isNull);
      expect(observer.routes, isNot(contains(route)));
      expect(manager.isShowing('checkout'), isFalse);
      expect(find.text('结算页面', skipOffstage: false), findsNothing);
      if (cover != null) {
        expect(observer.routes, contains(cover));
        expect(cover.isCurrent, isTrue);
        expect(manager.isShowing('cover'), isTrue);
      } else {
        expect(find.text('首页'), findsOneWidget);
      }
    });
  }

  testWidgets('ModalBottomSheetRoute 配方可构建并通过 close 关闭', (tester) async {
    final observer = _RouteObserver();
    final manager = Layerman();
    addTearDown(manager.dispose);
    await _pumpApp(tester, observer);
    final sheet = manager.open<bool>(
      id: 'sheet',
      present: (ctx) {
        final navigator = navigatorKey.currentState!;
        // 此处只验证普通 Navigator 的 Route 逻辑；Get.key 配方由 example/test/readme_backend_recipe_test.dart 验证。
        final route = ModalBottomSheetRoute<bool>(
          settings: RouteSettings(name: 'om://${ctx.id}'),
          builder: (_) => const Text('底部弹层'),
          isScrollControlled: false,
        );
        navigator.push(route);
        return PresentedOverlay<bool>(
          dismissed: route.completed,
          dismiss: ([r]) async {
            final nav = route.navigator;
            if (nav == null || !route.isActive) return;
            if (route.isCurrent && !route.willHandlePopInternally) {
              nav.pop(r);
            } else {
              nav.removeRoute(route);
            }
          },
        );
      },
    );
    await tester.pumpAndSettle();
    final route = observer.named('om://sheet');
    expect(find.text('底部弹层'), findsOneWidget);

    manager.close('sheet', true);
    await tester.pumpAndSettle();

    expect(await sheet, isTrue);
    expect(route.navigator, isNull);
    expect(observer.routes, isNot(contains(route)));
    expect(manager.isShowing('sheet'), isFalse);
    expect(find.text('底部弹层'), findsNothing);
  });
}
