// Android 手机真机全 API 集成测试。
//
// Rewritten for the headless `present:`-only manager (see CHANGELOG 0.2.0):
// the manager renders nothing itself, so every overlay in this app shows
// through a real backend (showDialog/Get.dialog/bot_toast/ShadSonner) — those
// dialogs are pushed on the ROOT navigator, so once shown they are visible
// regardless of which DemoShell destination is currently selected. Only the
// *trigger* buttons live on a specific destination page, so tests navigate
// there first via [goTo].
//
// Dropped along with the removed API: barrier/barrierDismissible assertions
// (no such thing on open() anymore — a backend renders its own barrier),
// OverlayManagerScope/attach() assertions (the manager attaches to nothing),
// and the old "replace displaces to the queue and resumes" assertion —
// replace now always CLOSES the preempted overlay (result null) and it never
// reshows (see CHANGELOG 0.2.0 "Behavior").
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:layerman_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The demo manager is a global; tests share one app process.
  setUp(() {
    app.appLifecycle?.didChangeAppLifecycleState(AppLifecycleState.resumed);
    app.om.resumeAll();
    app.om.clear();
  });

  // Force the wide (>=700 logical px) DemoShell layout for every test, so the
  // destination list is a permanent side panel (no Drawer/hamburger to open
  // first) and [goTo] can just tap the ListTile directly.
  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    app.main();
    await tester.pumpAndSettle();
  }

  // Navigate DemoShell's side nav to the destination whose label is [label].
  Future<void> goTo(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
  }

  // 先把按钮滚进内容区再点：手机上同一个 1400×900 视口排版更高，页面底部的
  // 触发按钮会落到视口之外或被底部状态条盖住（桌面上正好放得下）。
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  // No more exitDuration default (it's a per-open() grace now, null unless a
  // page opts in) — the plain demo cards close immediately and only the
  // manager's `gap` (300ms, set in manager.dart) delays the next activation.
  Future<void> advance(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  testWidgets('mixed: native → GetX → bot_toast strictly one at a time', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'External Presenters');

    await tapVisible(tester, find.byKey(const Key('btn-mixed')));
    await tester.pumpAndSettle();

    expect(find.text('1/3 Native dialog'), findsOneWidget);
    expect(find.text('2/3 GetX dialog'), findsNothing);
    expect(find.text('3/3 bot_toast — layerman wins'), findsNothing);

    await tester.tap(find.byKey(const Key('OK1')));
    await advance(tester);
    expect(find.text('2/3 GetX dialog'), findsOneWidget);

    await tester.tap(find.byKey(const Key('OK2')));
    await advance(tester);
    expect(find.text('3/3 bot_toast — layerman wins'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('3/3 bot_toast — layerman wins'), findsNothing);
    expect(app.om.activeIds, isEmpty);
    expect(app.om.queuedIds, isEmpty);
  });

  testWidgets('serial ×3 advances the queue as each card is closed', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Queue Basics');

    await tester.tap(find.byKey(const Key('btn-queue3')));
    await tester.pumpAndSettle();
    expect(find.text('Q1'), findsOneWidget);
    expect(app.om.queuedIds, containsAll(<String>['q2', 'q3']));

    await tester.tap(find.text('close Q1'));
    await advance(tester);
    expect(find.text('Q1'), findsNothing);
    expect(find.text('Q2'), findsOneWidget);

    await tester.tap(find.text('close Q2'));
    await advance(tester);
    expect(find.text('Q3'), findsOneWidget);

    await tester.tap(find.text('close Q3'));
    await advance(tester);
    expect(app.om.activeIds, isEmpty);
  });

  testWidgets(
      'replace: R2 preempts R1 and CLOSES it — R1 never comes back '
      '(0.2.0 behavior change)', (tester) async {
    await boot(tester);
    await goTo(tester, 'Replace & Affix');

    await tester.tap(find.byKey(const Key('btn-replace-demo')));
    await tester.pumpAndSettle();
    expect(find.text('R1'), findsOneWidget);

    await tester.tap(find.text('replace with R2'));
    await tester.pumpAndSettle();
    expect(find.text('R1'), findsNothing); // preempted...
    expect(find.text('R2'), findsOneWidget);
    // ...and CLOSED, not displaced to the queue (unlike pre-0.2.0 behavior).
    expect(app.om.queuedIds, isNot(contains('r1')));

    await tester.tap(find.text('close R2'));
    await advance(tester);
    expect(find.text('R1'), findsNothing); // R1 does NOT come back
    expect(app.om.activeIds, isEmpty);
    expect(app.om.queuedIds, isEmpty);
  });

  testWidgets('affix: a replace launched from INSIDE FIX cannot cover it', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Replace & Affix');

    await tester.tap(find.byKey(const Key('btn-affix-demo')));
    await tester.pumpAndSettle();
    expect(find.text('FIX (affix)'), findsOneWidget);

    await tester.tap(find.text('try to replace FIX')); // in-overlay action
    await tester.pumpAndSettle();
    expect(find.text('FIX (affix)'), findsOneWidget); // NOT covered / displaced
    expect(find.text('TRY'), findsNothing);
    expect(app.om.queuedIds, contains('try')); // waits at the queue front

    await tester.tap(find.text('close FIX (affix)'));
    await advance(tester);
    expect(find.text('TRY'), findsOneWidget); // its turn right after

    await tester.tap(find.text('close TRY'));
    await advance(tester);
  });

  testWidgets('overlap: stack B from INSIDE A — both visible at once', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Overlap');

    await tester.tap(find.byKey(const Key('btn-ovl-a')));
    await tester.pumpAndSettle();
    expect(find.text('OVA'), findsOneWidget);

    await tester.tap(find.text('stack OVB')); // in-overlay action
    await tester.pumpAndSettle();
    expect(find.text('OVA'), findsOneWidget); // BOTH on screen
    expect(find.text('OVB (overlap)'), findsOneWidget);
    expect(app.om.activeIds, containsAll(<String>['ova', 'ovb']));

    await tester.tap(find.text('close OVB (overlap)'));
    await advance(tester);
    expect(find.text('OVB (overlap)'), findsNothing);
    expect(find.text('OVA'), findsOneWidget); // serial slot untouched

    await tester.tap(find.text('close OVA'));
    await advance(tester);
  });

  testWidgets('pauseAll freezes serial + overlaps; resumeAll releases', (
    tester,
  ) async {
    await boot(tester);

    await goTo(tester, 'Pause & Resume');
    await tester.tap(find.byKey(const Key('btn-pause-all')));
    await tester.pumpAndSettle();

    await goTo(tester, 'Replace & Affix');
    await tester.tap(
      find.byKey(const Key('btn-replace-demo')),
    ); // serial frozen
    await tester.pumpAndSettle();

    await goTo(tester, 'Overlap');
    await tester.tap(find.byKey(const Key('btn-groups'))); // overlaps held
    await tester.pumpAndSettle();

    expect(app.om.activeIds, isEmpty);
    expect(find.text('R1'), findsNothing);
    expect(find.text('A1'), findsNothing);

    await goTo(tester, 'Pause & Resume');
    await tester.tap(find.byKey(const Key('btn-resume-all')));
    await tester.pumpAndSettle();

    expect(find.text('R1'), findsOneWidget); // serial released
    expect(find.text('A1'), findsOneWidget); // held overlaps released
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('programmatic: one card first, more enqueued seconds later', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Queue Basics');

    await tapVisible(tester, find.byKey(const Key('btn-prog')));
    await tester.pumpAndSettle();
    expect(find.text('X1'), findsOneWidget);
    expect(app.om.queuedIds, isEmpty); // only one so far

    await tester.pump(const Duration(milliseconds: 2200)); // program pushes
    await tester.pumpAndSettle();
    expect(app.om.queuedIds, containsAll(<String>['x2', 'x3']));

    await tester.tap(find.text('close X1'));
    await advance(tester);
    expect(find.text('X2'), findsOneWidget); // serial progression

    await tester.tap(find.text('close X2'));
    await advance(tester);
    expect(find.text('X3'), findsOneWidget);

    await tester.tap(find.text('close X3'));
    await advance(tester);
  });

  testWidgets('two 2×2 groups; clearWhere removes exactly group A', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Overlap');

    await tester.tap(find.byKey(const Key('btn-groups')));
    await tester.pumpAndSettle();
    for (final t in ['A1', 'A2', 'B1', 'B2']) {
      expect(find.text(t), findsOneWidget); // 2 groups visible side by side
    }

    // The 4 floating cards are centered on the FULL viewport (a bare
    // OverlayEntry, not scoped to this page) and one of them ends up
    // covering btn-clear-a-grp's own screen position at this fixed test
    // viewport size -- tapping it would silently hit the card's own Material
    // instead (same class of issue as the pauseOnRoutes test's
    // btn-queue-in-zone). Call the manager directly instead, exactly what the
    // button's own onPressed does.
    app.om.clearWhere((r) => r.data is Map && (r.data as Map)['group'] == 'a');
    await tester.pumpAndSettle();
    expect(find.text('A1'), findsNothing); // group A gone
    expect(find.text('A2'), findsNothing);
    expect(find.text('B1'), findsOneWidget); // group B untouched
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('conditions ride REAL navigation to /promo and back', (
    tester,
  ) async {
    await boot(tester);
    // Regression coverage for a real bug found in code review: MaterialApp's
    // implicit `home:` route reports as '/' (Flutter's own
    // Navigator.defaultRouteName), not '/home' — main.dart uses a named
    // `initialRoute`/`routes` to give it a real name. Assert the actual label
    // text (not just activeIds/queuedIds) so a regression shows up here.
    expect(app.om.currentRoute, '/home');
    expect(find.textContaining('route: /home'), findsOneWidget);

    await goTo(tester, 'Conditions');
    await tester.tap(
      find.byKey(const Key('btn-cond-promo')),
    ); // on /home: gated
    await tester.pumpAndSettle();
    expect(find.text('ROUTE /promo'), findsNothing);
    expect(app.om.queuedIds, contains('cond-promo'));

    await tester.tap(find.byKey(const Key('btn-goto-promo')));
    await tester.pumpAndSettle();
    expect(find.text('/promo'), findsOneWidget); // real page's AppBar title
    expect(find.text('ROUTE /promo'), findsOneWidget); // route matched -> shown
    expect(app.om.currentRoute, '/promo');

    await tester.pageBack(); // leave /promo
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.text('ROUTE /promo'),
      findsNothing,
    ); // dismissWhenUnmet pulled it down
    expect(app.om.activeIds, isEmpty);
    expect(app.om.currentRoute, '/home'); // back to the REAL '/home', not '/'
    expect(find.textContaining('route: /home'), findsOneWidget);
  });

  testWidgets(
    'pauseOnRoutes: /zone auto-freezes the queue via LayermanNavigatorObserver '
    '— zero manual setContext/pauseAll calls anywhere in app code',
    (tester) async {
      await boot(tester);
      await goTo(tester, 'Pause & Resume');

      await tester.tap(find.byKey(const Key('btn-queue-in-zone')));
      await tester.pumpAndSettle();
      expect(
        find.text('ZONE CARD'),
        findsOneWidget,
      ); // shows immediately on /home

      await tester.tap(find.text('close ZONE CARD'));
      await advance(tester);
      expect(app.om.activeIds, isEmpty);

      await tester.tap(find.byKey(const Key('btn-goto-zone')));
      await tester.pumpAndSettle();
      expect(
        find.text('/zone — no-overlay zone'),
        findsOneWidget,
      ); // real page covers HomePage
      expect(app.om.isPaused, isTrue); // auto-frozen by entering /zone

      // btn-queue-in-zone lives on the Pause page, now covered by the pushed
      // /zone route — call the manager directly (equivalent effect, no UI
      // needed) via the openCard helper re-exported by main.dart.
      app.openCard('zone-card', text: 'ZONE CARD');
      await tester.pumpAndSettle();
      expect(
        find.text('ZONE CARD'),
        findsNothing,
      ); // queued, not shown while frozen
      expect(app.om.queuedIds, contains('zone-card'));

      await tester.pageBack(); // leave /zone
      await tester.pumpAndSettle();
      expect(app.om.isPaused, isFalse); // auto-resumed
      expect(find.text('ZONE CARD'), findsOneWidget); // now shows

      app.om.close('zone-card');
      await advance(tester);
    },
  );

  testWidgets('cooldown session=1 blocks the second show', (tester) async {
    await boot(tester);
    await goTo(tester, 'Cooldown');

    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    expect(find.text('SESSION 1'), findsOneWidget);

    await tester.tap(find.text('close SESSION 1'));
    await advance(tester);

    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    expect(find.text('SESSION 1'), findsNothing); // capped for this session
    expect(app.om.queuedIds, isNot(contains('cd-s'))); // 0.3.0：达到永久上限即丢弃。
  });

  testWidgets('cooldown minGap=5s blocks, then AUTO-shows when it expires', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Cooldown');

    await tester.tap(find.byKey(const Key('btn-cdg')));
    await tester.pumpAndSettle();
    expect(find.text('GAP 5s'), findsOneWidget);
    await tester.tap(find.text('close GAP 5s'));
    await advance(tester);

    await tester.tap(find.byKey(const Key('btn-cdg')));
    await tester.pumpAndSettle();
    expect(find.text('GAP 5s'), findsNothing); // inside the 5s gap → queued
    expect(app.om.queuedIds, contains('cd-g'));

    // No nudge: a time-based cooldown arms its own wake timer, so the queued
    // card appears on its own once the 5s window elapses.
    await tester.pump(const Duration(seconds: 5, milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('GAP 5s'), findsOneWidget);

    await tester.tap(find.text('close GAP 5s'));
    await advance(tester);
  });

  testWidgets('resolve: fetches on grant, shows with backend data', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Lifecycle');

    await tester.tap(find.byKey(const Key('btn-resolve')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('RESOLVED'), findsNothing); // still resolving

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('RESOLVED v=42'), findsOneWidget); // payload injected

    await tester.tap(find.text('close RESOLVED v=42'));
    await advance(tester);
  });

  testWidgets('beforeClose: locked per open, close vetoed until unlocked', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Lifecycle');

    await tester.tap(find.byKey(const Key('btn-guard')));
    await tester.pumpAndSettle();
    expect(find.text('GUARD 🔒'), findsOneWidget); // lock RESETS per open

    await tester.tap(find.text('close GUARD 🔒'));
    await tester.pumpAndSettle();
    expect(find.text('GUARD 🔒'), findsOneWidget); // vetoed while locked

    await tester.tap(find.byKey(const Key('btn-unlock')));
    await tester.pumpAndSettle();
    expect(find.text('GUARD 🔓'), findsOneWidget); // live-updated lock state

    await tester.tap(find.text('close GUARD 🔓'));
    await advance(tester);
    expect(find.textContaining('GUARD'), findsNothing);
  });

  testWidgets('update(id, patch) renders manager data through dataListenable', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Lifecycle');

    await tapVisible(tester, find.byKey(const Key('btn-upd-show')));
    await tester.pumpAndSettle();
    expect(find.text('n = 0'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('btn-update')));
    await tester.pumpAndSettle();
    expect(find.text('n = 1'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('btn-update')));
    await tester.pumpAndSettle();
    expect(find.text('n = 2'), findsOneWidget);

    // 绕过页面计数器直接更新；只通知而不写入数据时必然失败。
    app.om.update('upd', {'n': 37});
    await tester.pumpAndSettle();
    expect(find.text('n = 37'), findsOneWidget);
    expect(find.text('n = 2'), findsNothing);
    // 只合并其它字段时，管理器中的 n 必须保留。
    app.om.update('upd', {'extra': 'merged!'});
    await tester.pumpAndSettle();
    expect(find.text('n = 37'), findsOneWidget);

    await tapVisible(tester, find.text('close n = 37'));
    await advance(tester);
  });

  testWidgets('B2: pauseAll remains reachable while P1 is visible', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Pause & Resume');
    await tapVisible(tester, find.byKey(const Key('btn-queue-3-for-pause')));
    await tester.pumpAndSettle();
    expect(find.text('P1'), findsOneWidget);
    expect(app.om.queuedIds, containsAll(['p2', 'p3']));

    // 真正点击页面按钮，验证非模态卡片不会挡住暂停操作。
    await tapVisible(tester, find.byKey(const Key('btn-pause-all')));
    await tester.pumpAndSettle();
    expect(app.om.isPaused, isTrue);
    await tapVisible(tester, find.text('close P1'));
    await advance(tester);
    expect(find.text('P1'), findsNothing);
    expect(find.text('P2'), findsNothing);
    expect(app.om.queuedIds, containsAll(['p2', 'p3']));

    await tapVisible(tester, find.byKey(const Key('btn-resume-all')));
    await advance(tester);
    expect(find.text('P2'), findsOneWidget);
    await tapVisible(tester, find.text('close P2'));
    await advance(tester);
    await tapVisible(tester, find.text('close P3'));
    await advance(tester);
  });

  testWidgets('B3: removing ShadSheet before its first frame leaves no sheet', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'Mixed UI Libraries');
    await tapVisible(tester, find.byKey(const Key('btn-shad-sheet')));
    // tapVisible 点击后不 pump，移除必须发生在 sheet 的 builder 执行前。
    expect(app.om.activeIds, contains('shad-sheet'));
    app.om.remove('shad-sheet');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('layerman → showShadSheet'), findsNothing);
    expect(app.om.activeIds, isNot(contains('shad-sheet')));
  });

  testWidgets('B4: manager close dismisses the PresentContext toast', (
    tester,
  ) async {
    await boot(tester);
    await goTo(tester, 'External Presenters');
    await tapVisible(tester, find.byKey(const Key('btn-ctx-inspect')));
    // 固定等待入场动画，避免等待完整自动关闭周期。
    await tester.pump(const Duration(milliseconds: 300));
    const message = 'ctx.id=ctx-insp  ctx.slot=inspect-slot';
    expect(find.text(message), findsOneWidget);
    app.om.close('ctx-insp');
    // 跑完退场动画和随后的移除帧。toast 静止时没有排帧，pumpAndSettle 会立刻返回，
    // 所以空 dismiss 等不到 3 秒自然超时，无法蒙混通过。
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(app.om.activeIds, isNot(contains('ctx-insp')));
  });

  testWidgets('restart rebuilds the app with a FRESH manager', (tester) async {
    await boot(tester);
    await goTo(tester, 'Cooldown');

    // Ensure the session cooldown is exhausted on the CURRENT manager (the
    // earlier cooldown test may already have used it up — same process).
    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    if (find.text('SESSION 1').evaluate().isNotEmpty) {
      await tester.tap(find.text('close SESSION 1'));
      await advance(tester);
      await tester.tap(find.byKey(const Key('btn-cds')));
      await tester.pumpAndSettle();
    }
    expect(find.text('SESSION 1'), findsNothing); // capped on the old manager

    await goTo(tester, 'Setup & Restart');
    // btn-restart sits below the fold in this page's long
    // SingleChildScrollView — scroll it into view first, or tap() computes a
    // global offset outside the viewport and silently hits nothing (the
    // button never actually fires).
    await tester.ensureVisible(find.byKey(const Key('btn-restart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-restart')));
    await tester.pumpAndSettle();
    expect(app.om.activeIds, isEmpty); // fresh manager, empty world
    expect(app.om.queuedIds, isEmpty);
    expect(find.textContaining('route: /home'), findsOneWidget);

    await goTo(tester, 'Cooldown');
    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    expect(find.text('SESSION 1'), findsOneWidget); // session counter was reset

    await tester.tap(find.text('close SESSION 1'));
    await advance(tester);
  });

  testWidgets('GetX snackbar scheduled through the manager', (tester) async {
    await boot(tester);
    await goTo(tester, 'External Presenters');

    await tester.tap(find.byKey(const Key('btn-snack')));
    // GetX chains entrance→auto-close→exit without an idle gap — pump fixed
    // real time to catch the visible plateau instead of pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Saved'), findsOneWidget);
    expect(Get.isSnackbarOpen, isTrue);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
    expect(app.om.activeIds, isEmpty);
    expect(app.om.queuedIds, isEmpty);
  });

  group('1.0 真机回归', () {
    /// 抑制演示共用的卡片标识与操作键。
    const sup = 'SUP', supOpen = 'btn-sup-open', supClose = 'sup-close';

    /// 跨槽位演示共用的卡片文案和操作键。
    const modal = 'BLK-MODAL', toast = 'BLK-TOAST', overlap = 'BLK-OVL';

    /// modal 的打开与关闭操作键。
    const modalOpen = 'btn-blk-modal', modalClose = 'blk-modal-close';

    /// 打开演示页并使用稳定键点击，等待本次界面更新。
    Future<void> press(WidgetTester tester, String key) async {
      await tapVisible(tester, find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    /// 每条用例复用真机启动与侧边导航。
    Future<void> features(WidgetTester tester) async {
      await boot(tester);
      await goTo(tester, 'v0.3 Features');
    }

    tearDown(() {
      app.om.clear();
      app.om.clearCooldowns();
    });

    testWidgets('不再提示后同 id 不再出场，重置后恢复', (tester) async {
      await features(tester);
      await press(tester, supOpen);
      expect(find.text(sup), findsOneWidget);
      await press(tester, 'sup-never');
      expect(find.text(sup), findsNothing);
      expect(find.text('sup: closed never'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key(supOpen)));
      expect(find.text(sup), findsNothing);
      await tester.pump();
      expect(find.text(sup), findsNothing);
      expect(find.text('sup: suppressed null'), findsOneWidget);
      expect(app.om.queuedIds, isNot(contains(sup)));
      await press(tester, 'btn-sup-status');
      expect(
        find.text('sup: canShow=false suppressed=true permanent=true'),
        findsOneWidget,
      );
      await press(tester, 'btn-sup-reset');
      await press(tester, supOpen);
      expect(find.text(sup), findsOneWidget);
      await press(tester, supClose);
      expect(find.text(sup), findsNothing);
      expect(find.text('sup: closed close'), findsOneWidget);
    });

    testWidgets('稍后提示：抑制期间排队，到期后自动出场', (tester) async {
      await features(tester);
      await press(tester, supOpen);
      await press(tester, 'sup-later');
      expect(find.text('sup: closed later'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key(supOpen)));
      await tester.pump();
      expect(find.text(sup), findsNothing);
      expect(app.om.queuedIds, contains(sup));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(sup), findsNothing);
      // 只推进时间，不用点击或 settle 推动引擎唤醒。
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text(sup), findsOneWidget);
      expect(app.om.queuedIds, isNot(contains(sup)));
      await press(tester, supClose);
    });

    testWidgets('modal 打开期间 toast 等待，关闭后出场', (tester) async {
      await features(tester);
      await press(tester, modalOpen);
      expect(find.text(modal), findsOneWidget);
      await press(tester, 'blk-toast');
      expect(find.text(toast), findsNothing);
      expect(app.om.queuedIds, contains(toast));
      expect(find.text('blk: modal=true toast=queued'), findsOneWidget);
      await press(tester, modalClose);
      await advance(tester);
      expect(find.text(modal), findsNothing);
      expect(find.text(toast), findsOneWidget);
      expect(find.text('blk: modal=false toast=shown'), findsOneWidget);
      await tapVisible(tester, find.text('close $toast'));
      await advance(tester);
    });

    testWidgets('modal 打开期间 overlap toast 被持有，关闭后出场', (tester) async {
      await features(tester);
      await press(tester, modalOpen);
      expect(find.text(modal), findsOneWidget);
      await press(tester, 'blk-toast-overlap');
      expect(find.text(overlap), findsNothing);
      expect(app.om.queuedIds, contains(overlap));
      await press(tester, modalClose);
      await advance(tester);
      expect(find.text(modal), findsNothing);
      expect(find.text(overlap), findsOneWidget);
      expect(app.om.queuedIds, isNot(contains(overlap)));
      await tapVisible(tester, find.text('close $overlap'));
      await advance(tester);
    });

    testWidgets('没有 modal 时 toast 直接出场', (tester) async {
      await features(tester);
      await press(tester, 'btn-blk-toast');
      expect(find.text(modal), findsNothing);
      expect(find.text(toast), findsOneWidget);
      expect(app.om.queuedIds, isNot(contains(toast)));
      await tapVisible(tester, find.text('close $toast'));
      await advance(tester);
      expect(find.text(toast), findsNothing);
    });
  });

  group('0.3.0 真机回归', () {
    /// 延迟出场两条用例共用的文案与操作键。
    const ovdText = 'OVD', ovdOpenKey = 'btn-ovd-open';

    /// 延迟条目的移除按钮键。
    const ovdRemoveKey = 'btn-ovd-remove';

    /// 打开新能力页面，复用已有的真机启动和滚动辅助函数。
    Future<void> features(WidgetTester tester) async {
      await boot(tester);
      await goTo(tester, 'v0.3 Features');
    }

    /// 点击稳定键；模态框内的同名操作优先于被遮住的页面操作。
    Future<void> press(WidgetTester tester, String key) async {
      await tapVisible(tester, find.byKey(Key(key)).last);
      await tester.pumpAndSettle();
    }

    tearDown(() {
      app.om.clear();
      app.om.setContext({'user': null, 'roles': <String>{}});
      app.appLifecycle?.didChangeAppLifecycleState(AppLifecycleState.resumed);
      app.om.resumeAll();
    });

    testWidgets('overlap 延迟一秒，半秒内不可见而约一点二秒后出现', (tester) async {
      await features(tester);
      // 点击后直接计时，避免 settle 消耗延迟观测窗口。
      await tapVisible(tester, find.byKey(const Key(ovdOpenKey)));
      expect(find.text(ovdText), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(ovdText), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text(ovdText), findsOneWidget);
      await press(tester, ovdRemoveKey);
      expect(find.text(ovdText), findsNothing);
    });

    testWidgets('overlap 等待期间移除，两秒内始终不出场', (tester) async {
      await features(tester);
      await tapVisible(tester, find.byKey(const Key(ovdOpenKey)));
      expect(find.text(ovdText), findsNothing);
      await press(tester, ovdRemoveKey);
      expect(find.text(ovdText), findsNothing);
      // 分段检查整个等待窗口，防止先闪现再消失。
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(ovdText), findsNothing);
      }
      expect(app.om.activeIds, isEmpty);
    });

    testWidgets('ctx.close 锁定时被拒绝，解锁后返回 closed ok', (tester) async {
      await features(tester);
      const cardText = 'CTX', closeKey = 'ctx-close';
      final label = find.byKey(const Key('ctx-outcome'));
      await press(tester, 'btn-ctx-open');
      expect(find.text(cardText), findsOneWidget);
      expect(find.text('ctx-lock: on'), findsOneWidget);
      final initial = tester.widget<Text>(label).data;
      await press(tester, closeKey);
      expect(find.text(cardText), findsOneWidget);
      expect(tester.widget<Text>(label).data, initial);
      await press(tester, 'btn-ctx-lock');
      expect(find.text('ctx-lock: off'), findsOneWidget);
      await press(tester, closeKey);
      await advance(tester);
      expect(find.text(cardText), findsNothing);
      expect(tester.widget<Text>(label).data, 'ctx: closed ok');
    });

    testWidgets('auth 普通用户等待，VIP 放行，退出登录自动关闭', (tester) async {
      await features(tester);
      const cardText = 'VIP-ONLY';
      await press(tester, 'btn-login-user');
      await press(tester, 'btn-vip-open');
      expect(find.text(cardText), findsNothing);
      expect(app.om.queuedIds, contains(cardText));
      await press(tester, 'btn-login-vip');
      expect(find.text(cardText), findsOneWidget);
      await press(tester, 'btn-logout');
      await advance(tester);
      expect(find.text(cardText), findsNothing);
      expect(app.om.activeIds, isEmpty);
      app.om.clear();
    });

    testWidgets('官方对话框打开并由自身按钮关闭', (tester) async {
      await features(tester);
      await press(tester, 'btn-dm-open');
      expect(find.text('DM-A'), findsOneWidget);
      await press(tester, 'dm-a-close');
      expect(find.text('DM-A'), findsNothing);
      expect(app.om.activeIds, isEmpty);
    });

    testWidgets('B6：限定页面的对话框不会因自身路由而关闭', (tester) async {
      await features(tester);
      await press(tester, 'btn-dm-route');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('DM-A'), findsOneWidget);
      expect(app.om.currentRoute, '/home');
      await press(tester, 'dm-a-close');
      expect(find.text('DM-A'), findsNothing);
    });

    testWidgets('B4：定点关闭被覆盖的 A，保留 B', (tester) async {
      await features(tester);
      await press(tester, 'btn-dm-buried');
      expect(find.text('DM-A'), findsOneWidget);
      expect(find.text('DM-B'), findsOneWidget);
      await press(tester, 'btn-dm-close-a');
      expect(find.text('DM-A'), findsNothing);
      expect(find.text('DM-B'), findsOneWidget);
      expect(app.om.activeIds, isNot(contains('dm-a')));
      await press(tester, 'dm-b-close');
      expect(find.text('DM-B'), findsNothing);
    });

    testWidgets('官方底部弹层打开和关闭', (tester) async {
      await features(tester);
      await press(tester, 'btn-bs-open');
      expect(find.text('BS-1'), findsOneWidget);
      await press(tester, 'bs-close');
      expect(find.text('BS-1'), findsNothing);
      expect(app.om.activeIds, isEmpty);
    });

    testWidgets('ticket 区分主动关闭与替换原因', (tester) async {
      await features(tester);
      expect(find.text('outcome: -'), findsOneWidget);
      await press(tester, 'btn-outcome-open');
      await tapVisible(tester, find.text('close OUTCOME'));
      await advance(tester);
      expect(find.text('outcome: closed'), findsOneWidget);
      await press(tester, 'btn-outcome-open');
      await press(tester, 'btn-outcome-replace');
      expect(find.text('outcome: replaced'), findsOneWidget);
      expect(find.text('OUTCOME'), findsNothing);
      await tapVisible(tester, find.text('close NEXT'));
      await advance(tester);
    });

    testWidgets('实时数据从零更新，关闭后不再显示', (tester) async {
      await features(tester);
      await press(tester, 'btn-live-open');
      expect(find.text('live n=0'), findsOneWidget);
      await press(tester, 'btn-live-update');
      expect(find.text('live n=0'), findsNothing);
      expect(find.text('live n=1'), findsOneWidget);
      await tapVisible(tester, find.text('close live n=1'));
      await advance(tester);
      expect(find.text('live n=1'), findsNothing);
    });

    testWidgets('失联后端在两秒超时后释放槽位并上报', (tester) async {
      await features(tester);
      await press(tester, 'btn-stuck-open');
      expect(find.text('STUCK'), findsOneWidget);
      await press(tester, 'btn-after-stuck-open');
      expect(app.om.queuedIds, contains('after-stuck'));
      // 关闭后不经过 press 的 settle，避免真机耗时侵占两秒观测窗口。
      await tapVisible(tester, find.byKey(const Key('btn-stuck-close')));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('AFTER'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1700));
      expect(tester.takeException(), isA<TimeoutException>());
      await tester.pumpAndSettle();
      expect(find.text('AFTER'), findsOneWidget);
      expect(app.om.activeIds, isNot(contains('stuck')));
      await tapVisible(tester, find.text('close AFTER'));
      await advance(tester);
      await press(tester, 'btn-stuck-clear');
      expect(find.text('STUCK'), findsNothing);
    });

    testWidgets('后台阻止新卡出场，恢复前台后放行', (tester) async {
      await features(tester);
      await press(tester, 'btn-lifecycle-pause');
      expect(find.text('paused: true'), findsOneWidget);
      await press(tester, 'btn-live-open');
      expect(find.text('live n=0'), findsNothing);
      expect(app.om.queuedIds, contains('live'));
      await press(tester, 'btn-lifecycle-resume');
      expect(find.text('paused: false'), findsOneWidget);
      expect(find.text('live n=0'), findsOneWidget);
      await tapVisible(tester, find.text('close live n=0'));
      await advance(tester);
    });

    testWidgets('build 中打开在帧后出现且重建不会重复提交', (tester) async {
      await features(tester);
      const cardText = 'BUILD-OPEN';
      expect(find.text(cardText), findsNothing);
      await tapVisible(tester, find.byKey(const Key('btn-build-open')));
      expect(find.text(cardText), findsNothing);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(cardText), findsOneWidget);
      await tapVisible(tester, find.text('close $cardText'));
      await advance(tester);
      await press(tester, 'btn-build-open');
      expect(tester.takeException(), isNull);
      expect(find.text(cardText), findsNothing);
    });

    testWidgets('冷却查询反映永久上限，重置后可以再次展示', (tester) async {
      await features(tester);
      const openKey = 'btn-cdq-open';
      const statusKey = 'btn-cdq-status';
      const cardText = 'CDQ';
      const available = 'cdq: canShow=true permanent=false';
      const blocked = 'cdq: canShow=false permanent=true';
      final label = find.byKey(const Key('cdq-label'));
      await press(tester, statusKey);
      expect(tester.widget<Text>(label).data, available);
      await press(tester, openKey);
      expect(find.text(cardText), findsOneWidget);
      await tapVisible(tester, find.text('close $cardText'));
      await advance(tester);
      await press(tester, openKey);
      expect(find.text(cardText), findsNothing);
      await press(tester, statusKey);
      expect(tester.widget<Text>(label).data, blocked);
      await press(tester, 'btn-cdq-reset');
      await press(tester, statusKey);
      expect(tester.widget<Text>(label).data, available);
      await press(tester, openKey);
      expect(find.text(cardText), findsOneWidget);
      await tapVisible(tester, find.text('close $cardText'));
      await advance(tester);
    });

    testWidgets('清理标签仅移除促销卡，重复清理保留无标签卡', (tester) async {
      await features(tester);
      const promo1 = 'TAG-P1', promo2 = 'TAG-P2', normal = 'TAG-N';
      const clearKey = 'btn-tag-clear';
      await press(tester, 'btn-tag-open');
      for (final text in [promo1, promo2, normal]) {
        expect(find.text(text), findsOneWidget);
      }
      await press(tester, clearKey);
      expect(find.text(promo1), findsNothing);
      expect(find.text(promo2), findsNothing);
      expect(find.text(normal), findsOneWidget);
      await press(tester, clearKey);
      expect(find.text(normal), findsOneWidget);
      await tapVisible(tester, find.text('close $normal'));
      await advance(tester);
      expect(find.text(normal), findsNothing);
    });

    testWidgets('排队过期从未展示，清理占位后也不会出现', (tester) async {
      await features(tester);
      await press(tester, 'btn-expire-open');
      expect(app.om.queuedIds, contains('exp'));
      expect(find.text('EXP'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(app.om.queuedIds, isNot(contains('exp')));
      expect(find.text('EXP'), findsNothing);
      await press(tester, 'btn-expire-clear');
      await advance(tester);
      expect(find.text('EXP'), findsNothing);
      expect(app.om.activeIds, isEmpty);
    });
  });
}
