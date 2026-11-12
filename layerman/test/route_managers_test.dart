import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// 测试共用的条目标识与结果。
const _a = 'a';
const _b = 'b';
const _c = 'c';
const _result = '指定结果';
const _prefix = 'layerman://';
const _customPrefix = 'test://';
const _home = '首页';
const _barrierPoint = Offset(10, 10);
const _defaultColor = Colors.red;
const _overrideColor = Colors.green;

/// 记录真实导航栈，用来核对定向移除与栈顶状态。
class _Routes extends NavigatorObserver {
  /// 尚未被 pop 或 remove 的路由。
  final routes = <Route<dynamic>>[];

  /// 按条目标识获取内置路由。
  Route<dynamic> entry(String id, {String prefix = _prefix}) =>
      routes.singleWhere((route) => route.settings.name == '$prefix$id');

  /// 检查条目是否已进入真实导航栈。
  bool has(String id) =>
      routes.any((route) => route.settings.name == '$_prefix$id');

  /// 记录入栈。
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
  }

  /// 记录用户返回或程序 pop。
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }

  /// 记录非栈顶路由的定向移除。
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.remove(route);
  }
}

/// 创建编排器并保证每个测试结束后释放计时器。
Layerman _manager() {
  final manager = Layerman();
  addTearDown(manager.dispose);
  return manager;
}

/// 挂载真实 MaterialApp，并提供可选主题。
Future<void> _app(
  WidgetTester tester,
  GlobalKey<NavigatorState> key,
  _Routes observer, {
  ThemeData? theme,
}) =>
    tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      navigatorObservers: [observer],
      theme: theme,
      home: const Scaffold(body: Text(_home)),
    ));

/// 构建尺寸稳定、可点击关闭的对话框。
Widget _dialog(PresentContext ctx, void Function([String?]) close) =>
    AlertDialog(
      title: Text(ctx.id),
      actions: [
        TextButton(onPressed: () => close(_result), child: const Text(_result)),
      ],
    );

/// 构建保留顶部遮罩的底部弹层。
Widget _sheet(PresentContext ctx, void Function([String?]) close) => SizedBox(
      height: 200,
      child: Center(
        child: TextButton(
          onPressed: () => close(_result),
          child: Text(ctx.id),
        ),
      ),
    );

void main() {
  for (final bottomSheet in [false, true]) {
    final kind = bottomSheet ? '底部弹层' : '对话框';

    testWidgets('$kind：被 B 覆盖的 A 定向关闭，交付结果并推进 C', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      final dialogs = DialogManager(key);
      final sheets = BottomSheetManager(key);
      final present =
          bottomSheet ? sheets<String>(_sheet) : dialogs<String>(_dialog);
      await _app(tester, key, observer);
      final a = manager.open<String>(id: _a, present: present);
      await tester.pumpAndSettle();
      final routeA = observer.entry(_a);
      manager.open<String>(id: _b, mode: OverlayMode.overlap, present: present);
      await tester.pumpAndSettle();
      final routeB = observer.entry(_b);
      manager.open<String>(id: _c, present: present);
      expect(routeA.isCurrent, isFalse);
      expect(routeB.isCurrent, isTrue);
      expect(observer.has(_c), isFalse);
      expect(manager.queuedIds, [_c]);

      manager.close(_a, _result);
      await tester.pumpAndSettle();
      expect(await a, _result);
      expect(routeA.navigator, isNull);
      expect(observer.routes, isNot(contains(routeA)));
      expect(observer.routes, contains(routeB));
      expect(routeB.isActive, isTrue);
      expect(observer.entry(_c).isCurrent, isTrue);
      expect(manager.activeIds, containsAll([_b, _c]));
    });

    testWidgets('$kind：用户 pop 等退场完成才交付结果及推进队列', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      final present = bottomSheet
          ? BottomSheetManager(key)<String>(_sheet)
          : DialogManager(key)<String>(_dialog);
      await _app(tester, key, observer);
      var delivered = false;
      final a = manager.open<String>(id: _a, present: present);
      a.then((_) => delivered = true);
      await tester.pumpAndSettle();
      final routeA = observer.entry(_a) as TransitionRoute<dynamic>;
      manager.open<String>(id: _c, present: present);
      key.currentState!.pop(_result);
      await tester.pump();
      expect(routeA.animation!.status, AnimationStatus.reverse);
      expect(delivered, isFalse);
      expect(observer.has(_c), isFalse);
      expect(manager.queuedIds, [_c]);

      await tester.pumpAndSettle();
      expect(await a, _result);
      expect(observer.entry(_c).isCurrent, isTrue);
    });

    for (final defaultDismissible in [false, true]) {
      testWidgets('$kind：遮罩默认 $defaultDismissible，单次可反向覆盖', (tester) async {
        final key = GlobalKey<NavigatorState>();
        final observer = _Routes();
        final manager = _manager();
        final dialogs =
            DialogManager(key, barrierDismissible: defaultDismissible);
        final sheets =
            BottomSheetManager(key, barrierDismissible: defaultDismissible);
        final a =
            bottomSheet ? sheets<String>(_sheet) : dialogs<String>(_dialog);
        final b = bottomSheet
            ? sheets<String>(_sheet, barrierDismissible: !defaultDismissible)
            : dialogs<String>(_dialog, barrierDismissible: !defaultDismissible);
        await _app(tester, key, observer);
        final resultA = manager.open<String>(id: _a, present: a);
        final resultB = manager.open<String>(id: _b, present: b);
        await tester.pumpAndSettle();
        await tester.tapAt(_barrierPoint);
        await tester.pumpAndSettle();
        if (!defaultDismissible) {
          expect(observer.entry(_a).isCurrent, isTrue);
          expect(observer.has(_b), isFalse);
          manager.close(_a);
          await tester.pumpAndSettle();
        }
        expect(await resultA, isNull);
        expect(observer.entry(_b).isCurrent, isTrue);
        await tester.tapAt(_barrierPoint);
        await tester.pumpAndSettle();
        if (defaultDismissible) {
          expect(observer.entry(_b).isCurrent, isTrue);
          manager.close(_b);
          await tester.pumpAndSettle();
        }
        expect(await resultB, isNull);
        expect(observer.has(_b), isFalse);
      });
    }

    testWidgets('$kind：builder close 守卫拒绝和放行均生效', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      var allow = false;
      var calls = 0;
      final present = bottomSheet
          ? BottomSheetManager(key)<String>(_sheet)
          : DialogManager(key)<String>(_dialog);
      await _app(tester, key, observer);
      final result = manager.open<String>(
        id: _a,
        present: present,
        beforeClose: () {
          calls++;
          return allow;
        },
      );
      await tester.pumpAndSettle();
      final button =
          find.widgetWithText(TextButton, bottomSheet ? _a : _result);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(observer.entry(_a).isCurrent, isTrue);
      allow = true;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(await result, _result);
      expect(observer.has(_a), isFalse);
    });

    testWidgets('$kind：builder close 一律经过守卫拒绝关闭', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      var calls = 0;
      final present = bottomSheet
          ? BottomSheetManager(key)<String>(_sheet)
          : DialogManager(key)<String>(_dialog);
      await _app(tester, key, observer);
      final result = manager.open<String>(
        id: _a,
        present: present,
        beforeClose: () {
          calls++;
          return false;
        },
      );
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(TextButton, bottomSheet ? _a : _result));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(observer.has(_a), isTrue);
      manager.remove(_a);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(observer.has(_a), isFalse);
    });

    testWidgets('$kind：导航器缺失会上报丢弃，队列继续且挂载后实例可复用', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      // 构造和创建 presenter 都无需已挂载的导航器。
      final present = bottomSheet
          ? BottomSheetManager(key)<String>(_sheet)
          : DialogManager(key)<String>(_dialog);
      manager.pauseAll();
      final failed = manager.open<String>(id: _a, present: present);
      var continued = false;
      manager.open<void>(
          id: _b,
          present: (_) {
            continued = true;
            return PresentedOverlay<void>(dismissed: Future<void>.value());
          });
      manager.resumeAll();
      expect(
          tester.takeException(),
          isA<StateError>().having(
            (error) => error.message,
            '说明缺失导航器',
            contains('navigatorKey.currentState'),
          ));
      await tester.pump();
      expect(await failed, isNull);
      expect(continued, isTrue);
      expect(manager.isShowing(_a), isFalse);
      await _app(tester, key, observer);
      manager.open<String>(id: _c, present: present);
      await tester.pumpAndSettle();
      expect(observer.entry(_c).isCurrent, isTrue);
    });
  }

  for (final bottomSheet in [false, true]) {
    testWidgets('${bottomSheet ? '底部弹层' : '对话框'}同一实例的多个 close 互不干扰，重复关闭无操作',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      final closes = <String, void Function([String?])>{};

      /// 为每个条目记录独立的关闭回调。
      Widget builder(PresentContext ctx, void Function([String?]) close) {
        closes[ctx.id] = close;
        return bottomSheet ? _sheet(ctx, close) : _dialog(ctx, close);
      }

      final present = bottomSheet
          ? BottomSheetManager(key)<String>(builder)
          : DialogManager(key)<String>(builder);
      await _app(tester, key, observer);
      final a = manager.open<String>(id: _a, present: present);
      await tester.pumpAndSettle();
      final b = manager.open<String>(
          id: _b, mode: OverlayMode.overlap, present: present);
      await tester.pumpAndSettle();
      final routeB = observer.entry(_b);
      closes[_a]!(_result);
      await tester.pumpAndSettle();
      expect(await a, _result); // builder close 经编排器先交付结果。
      expect(observer.routes, contains(routeB));
      expect(routeB.isCurrent, isTrue);
      closes[_a]!();
      await tester.pumpAndSettle();
      expect(routeB.isCurrent, isTrue);
      closes[_b]!(_result);
      await tester.pumpAndSettle();
      expect(await b, _result);
      expect(observer.has(_b), isFalse);
    });
  }

  testWidgets('同一实例在应用重建与更换 Layerman 后可复用', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final dialogs = DialogManager(key);
    final oldManager = Layerman();
    await _app(tester, key, _Routes());
    oldManager.open<String>(id: _a, present: dialogs<String>(_dialog));
    await tester.pumpAndSettle();
    oldManager.dispose();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(key.currentState, isNull);
    final manager = _manager();
    final observer = _Routes();
    await _app(tester, key, observer);
    final result =
        manager.open<String>(id: _b, present: dialogs<String>(_dialog));
    await tester.pumpAndSettle();
    expect(observer.entry(_b).isCurrent, isTrue);
    await tester.tap(find.text(_result));
    await tester.pumpAndSettle();
    expect(await result, _result);
  });

  testWidgets('对话框保留主题与本地化，支持默认配置及单次颜色和安全区域覆盖', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final observer = _Routes();
    final manager = _manager();
    final dialogs = DialogManager(key,
        barrierColor: _defaultColor,
        useSafeArea: false,
        routeNamePrefix: _customPrefix);
    final theme = ThemeData(primaryColor: _overrideColor);
    await _app(tester, key, observer, theme: theme);
    Color? seenColor;
    final present = dialogs<String>((ctx, close) => Builder(builder: (context) {
          seenColor = Theme.of(context).primaryColor;
          return _dialog(ctx, close);
        }));
    manager.open<String>(id: _a, present: present);
    await tester.pumpAndSettle();
    final routeA =
        observer.entry(_a, prefix: _customPrefix) as DialogRoute<String>;
    expect(routeA.barrierColor, _defaultColor);
    expect(routeA.barrierLabel,
        MaterialLocalizations.of(key.currentContext!).modalBarrierDismissLabel);
    expect(seenColor, _overrideColor);
    expect(
        find.ancestor(
            of: find.byType(AlertDialog), matching: find.byType(SafeArea)),
        findsNothing);
    manager.close(_a);
    await tester.pumpAndSettle();
    manager.open<String>(
        id: _b,
        present: dialogs<String>(_dialog,
            barrierColor: _overrideColor, useSafeArea: true));
    await tester.pumpAndSettle();
    final routeB =
        observer.entry(_b, prefix: _customPrefix) as DialogRoute<String>;
    expect(routeB.barrierColor, _overrideColor);
    expect(
        find.ancestor(
            of: find.byType(AlertDialog), matching: find.byType(SafeArea)),
        findsOneWidget);
  });

  testWidgets('底部弹层默认配置与所有常用单次覆盖传给真实路由', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final observer = _Routes();
    final manager = _manager();
    final sheets = BottomSheetManager(key,
        barrierColor: _defaultColor,
        backgroundColor: _defaultColor,
        enableDrag: false,
        showDragHandle: false,
        useSafeArea: false);
    await _app(tester, key, observer);
    final result =
        manager.open<String>(id: _a, present: sheets<String>(_sheet));
    await tester.pumpAndSettle();
    final a = observer.entry(_a) as ModalBottomSheetRoute<String>;
    expect(a.isScrollControlled, isFalse);
    expect(a.enableDrag, isFalse);
    expect(a.showDragHandle, isFalse);
    expect(a.useSafeArea, isFalse);
    expect(a.backgroundColor, _defaultColor);
    expect(a.barrierColor, _defaultColor);
    manager.close(_a, _result);
    await tester.pumpAndSettle();
    expect(await result, _result);
    expect(a.navigator, isNull);
    manager.open<String>(
        id: _b,
        present: sheets<String>(_sheet,
            isScrollControlled: true,
            enableDrag: true,
            showDragHandle: true,
            useSafeArea: true,
            barrierColor: _overrideColor,
            backgroundColor: _overrideColor));
    await tester.pumpAndSettle();
    final b = observer.entry(_b) as ModalBottomSheetRoute<String>;
    expect(b.isScrollControlled, isTrue);
    expect(b.enableDrag, isTrue);
    expect(b.showDragHandle, isTrue);
    expect(b.useSafeArea, isTrue);
    expect(b.backgroundColor, _overrideColor);
    expect(b.barrierColor, _overrideColor);
  });

  testWidgets('底部弹层构造时可启用完整高度，单次 false 覆盖 true', (tester) async {
    final key = GlobalKey<NavigatorState>();
    final observer = _Routes();
    final manager = _manager();
    final sheets = BottomSheetManager(key, isScrollControlled: true);
    await _app(tester, key, observer);
    manager.open<String>(id: _a, present: sheets<String>(_sheet));
    await tester.pumpAndSettle();
    expect(
        (observer.entry(_a) as ModalBottomSheetRoute<String>)
            .isScrollControlled,
        isTrue);
    manager.close(_a);
    await tester.pumpAndSettle();
    manager.open<String>(
        id: _b, present: sheets<String>(_sheet, isScrollControlled: false));
    await tester.pumpAndSettle();
    expect(
        (observer.entry(_b) as ModalBottomSheetRoute<String>)
            .isScrollControlled,
        isFalse);
  });

  for (final buried in [false, true]) {
    testWidgets('presentRoute 页面在${buried ? '被覆盖' : '栈顶'}时定向关闭且可重复 dismiss',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      final observer = _Routes();
      final manager = _manager();
      await _app(tester, key, observer);
      late PresentedOverlay<String> handle;
      final result = manager.open<String>(
          id: _a,
          present: (_) {
            handle = presentRoute(
                key.currentState!,
                MaterialPageRoute<String>(
                  settings: const RouteSettings(name: '$_prefix$_a'),
                  builder: (_) => const Scaffold(body: Text(_a)),
                ));
            return handle;
          });
      await tester.pumpAndSettle();
      final routeA = observer.entry(_a);
      Route<dynamic>? routeB;
      if (buried) {
        manager.open<String>(
            id: _b,
            mode: OverlayMode.overlap,
            present: DialogManager(key)<String>(_dialog));
        await tester.pumpAndSettle();
        routeB = observer.entry(_b);
      }
      expect(routeA.isCurrent, !buried);
      manager.close(_a, _result);
      await tester.pumpAndSettle();
      expect(await result, _result);
      expect(routeA.navigator, isNull);
      expect(observer.routes, isNot(contains(routeA)));
      await handle.dismiss!();
      await tester.pumpAndSettle();
      if (routeB != null) {
        expect(observer.routes, contains(routeB));
        expect(routeB.isCurrent, isTrue);
      } else {
        expect(find.text(_home), findsOneWidget);
      }
    });
  }
}
