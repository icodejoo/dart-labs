import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/ui/mini/mini_ctl.dart';
import 'package:mova/src/ui/mini/mini_host.dart';
import 'package:mova/src/ui/mini/mini_window.dart';
import 'package:mova/src/ui/player.dart';
import 'package:mova/src/ui/skins/default_skin.dart';

import '../../support/fake_api.dart';

const _enabledOpts = MovaOpts(mini: MovaMiniConfig(enabled: true));

void main() {
  group('Mount B — MovaMiniHost (persistent)', () {
    testWidgets('ctl.api == null renders nothing extra; child renders normally', (tester) async {
      final ctl = MovaMiniCtl();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctl, child: child!),
        home: const Text('home'),
      ));
      expect(find.text('home'), findsOneWidget);
      expect(find.byType(MovaMiniWindow), findsNothing);
    });

    testWidgets('cfg.enabled == false renders nothing (closed-state hard constraint)', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: const MovaOpts());
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctl, child: child!),
        home: const Text('home'),
      ));
      await ctl.show(api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsNothing);
    });

    testWidgets('show(api) renders exactly one MovaMiniWindow', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctl, child: child!),
        home: const Text('home'),
      ));
      await ctl.show(api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsOneWidget);
    });

    testWidgets('the window survives push/pop and paints above pushed routes', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        builder: (context, child) => MovaMiniHost(ctl: ctl, child: child!),
        home: const Text('page1'),
      ));
      await ctl.show(api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsOneWidget);

      navKey.currentState!.push(MaterialPageRoute(builder: (_) => const Text('page2')));
      await tester.pumpAndSettle();
      expect(find.text('page2'), findsOneWidget);
      expect(find.byType(MovaMiniWindow), findsOneWidget, reason: 'window stays mounted above the new route');

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(MovaMiniWindow), findsOneWidget);
    });

    testWidgets('hide() removes the window; child unaffected', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctl, child: child!),
        home: const Text('home'),
      ));
      await ctl.show(api);
      await tester.pump();
      await ctl.hide();
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('replacing ctl migrates the listener; host disposal does not dispose ctl', (tester) async {
      final ctl1 = MovaMiniCtl();
      final ctl2 = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: MovaMiniHost(key: key, ctl: ctl1, child: const Text('home')),
      ));
      await tester.pumpWidget(MaterialApp(
        home: MovaMiniHost(key: key, ctl: ctl2, child: const Text('home')),
      ));
      await ctl2.show(api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(() => ctl2.show(api), returnsNormally);
    });
  });

  group('Mount A — MovaMiniCtl.showInPage (in-page)', () {
    testWidgets('inserts exactly one MovaMiniWindow into the page Overlay', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));
      await ctl.showInPage(ctx, api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsOneWidget);
    });

    testWidgets('window position is unaffected by scrolling the hosting ListView', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return ListView.builder(
            itemCount: 100,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('item $i')),
          );
        }),
      ));
      await ctl.showInPage(ctx, api);
      await tester.pump();
      final before = tester.getTopLeft(find.byType(MovaMiniWindow));
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      final after = tester.getTopLeft(find.byType(MovaMiniWindow));
      expect(after, before);
    });

    testWidgets('a pushed route covers the in-page window (expected, not a bug)', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => ctl.showInPage(context, api),
            child: const Text('show'),
          );
        }),
      ));
      await tester.tap(find.text('show'));
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsOneWidget);

      navKey.currentState!.push(MaterialPageRoute(builder: (_) => const Text('page2')));
      await tester.pumpAndSettle();
      // The window widget is still technically in the tree (rootOverlay:
      // false targets the page's own Overlay, buried under the new route's
      // Overlay entry) — a tap at its old location must not reach it: the
      // new route's own Text covers it instead of the window's picture.
      await tester.tap(find.text('page2'), warnIfMissed: false);
      await tester.pump();
      expect(api.lastMini, isTrue, reason: 'the buried window must not have received the tap');
    });

    testWidgets('hide() after popping the hosting page cleanly removes the entry, never throws', (tester) async {
      // A plain single-Navigator MaterialApp has exactly one shared Overlay
      // for every route — popping a route does not, by itself, destroy that
      // Overlay (only a page that nests its own Overlay/Navigator gets true
      // per-page teardown; see showInPage's doc comment). So the entry can
      // legitimately still be mounted right after a pop; what must hold
      // regardless is that hide() afterwards is always safe.
      //
      // 普通单 Navigator 的 MaterialApp 对所有路由只有一个共享 Overlay——
      // pop 一个路由本身并不会销毁这个 Overlay（只有页面自己嵌套一个
      // Overlay/Navigator 才有真正意义上的随页面销毁，见 showInPage 文档注释）。
      // 所以 pop 后 entry 完全可能仍然挂载；无论如何都必须成立的是：之后调用
      // hide() 永远安全。
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => navKey.currentState!.push(MaterialPageRoute(builder: (inner) {
              WidgetsBinding.instance.addPostFrameCallback((_) => ctl.showInPage(inner, api));
              return const SizedBox();
            })),
            child: const Text('go'),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(MovaMiniWindow), findsOneWidget);

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(() => ctl.hide(), returnsNormally);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsNothing);
    });

    testWidgets('dragging the in-page window moves it and clamps within the page viewport', (tester) async {
      // snapToEdge off so release-time re-snap does not mask whether the
      // drag itself moved the window.
      //
      // 关掉 snapToEdge，避免松手重新吸边掩盖拖动本身是否真的移动了小窗。
      const noSnap = MovaOpts(mini: MovaMiniConfig(enabled: true, snapToEdge: false));
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: noSnap);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));
      await ctl.showInPage(ctx, api);
      await tester.pump();
      final gestureFinder = find.byKey(const ValueKey('movaMiniWindowGesture'));
      final before = tester.getTopLeft(gestureFinder);
      await tester.drag(gestureFinder, const Offset(-40, 0));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(gestureFinder);
      expect(after, isNot(before));
    });

    testWidgets('cfg.enabled == false: showInPage inserts no entry (closed-state hard constraint)', (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: const MovaOpts());
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));
      await ctl.showInPage(ctx, api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsNothing);
      expect(ctl.mount, MovaMiniMount.none);
    });
  });

  group('Equivalence — the same MovaMiniWindow under either shell', () {
    testWidgets('first-frame rect is identical whether mounted via OverlayEntry or Positioned.fill', (tester) async {
      const config = MovaMiniConfig(enabled: true, margin: 10, width: 120);
      final ctlA = MovaMiniCtl();
      final apiA = FakeMovaApi(options: const MovaOpts(mini: config));

      late BuildContext ctxA;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctxA = context;
          return const SizedBox();
        }),
      ));
      await ctlA.showInPage(ctxA, apiA);
      await tester.pump();
      final rectA = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));
      await ctlA.hide();
      await tester.pumpWidget(const SizedBox()); // 强制卸载整棵旧树，含旧 Overlay/entry

      final ctlB = MovaMiniCtl();
      final apiB = FakeMovaApi(options: const MovaOpts(mini: config));
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctlB, child: child!),
        home: const SizedBox(),
      ));
      await ctlB.show(apiB);
      await tester.pump();
      final rectB = tester.getTopLeft(find.byKey(const ValueKey('movaMiniWindowGesture')));

      expect(rectA, rectB);
    });

    testWidgets('tapping the picture calls hide() under either shell', (tester) async {
      final ctlA = MovaMiniCtl();
      final apiA = FakeMovaApi(options: _enabledOpts);
      late BuildContext ctxA;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctxA = context;
          return const SizedBox();
        }),
      ));
      await ctlA.showInPage(ctxA, apiA);
      await tester.pump();
      final rectA = tester.getRect(find.byKey(const ValueKey('movaMiniWindowGesture')));
      await tester.tapAt(rectA.bottomLeft + const Offset(4, -4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(apiA.lastMini, isFalse);

      final ctlB = MovaMiniCtl();
      final apiB = FakeMovaApi(options: _enabledOpts);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctlB, child: child!),
        home: const SizedBox(),
      ));
      await ctlB.show(apiB);
      await tester.pump();
      final rectB = tester.getRect(find.byKey(const ValueKey('movaMiniWindowGesture')));
      await tester.tapAt(rectB.bottomLeft + const Offset(4, -4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(apiB.lastMini, isFalse);
    });

    testWidgets('showInPage + MovaMiniHost together still render exactly one MovaMiniWindow and one render surface',
        (tester) async {
      final ctl = MovaMiniCtl();
      final api = FakeMovaApi(options: _enabledOpts);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MovaMiniHost(ctl: ctl, child: child!),
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));
      await ctl.showInPage(ctx, api);
      await tester.pump();
      expect(find.byType(MovaMiniWindow), findsOneWidget, reason: 'host must not also render since mount == page');
      expect(find.byType(MovaPlayer), findsOneWidget);
    });

    testWidgets('page-side MovaPlayer stops rendering its own surface while MovaState.mini is true', (tester) async {
      final api = FakeMovaApi(options: _enabledOpts);
      api.push(const MovaState(mini: true));
      await tester.pumpWidget(MaterialApp(
        home: MovaPlayer(api: api, skin: const MovaDefSkin()),
      ));
      // With mini active the page-side default skin's operable layer (which
      // would otherwise host the render surface's chrome) is hidden by
      // _MiniHidden — proven indirectly via the fullscreen button vanishing,
      // the same signal used in mini_skin_test.dart.
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    });
  });
}
