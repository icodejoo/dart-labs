// Real-device (Windows desktop) full-API integration test.
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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:layerman_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The demo manager is a global; tests share one app process.
  setUp(() {
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

  // No more exitDuration default (it's a per-open() grace now, null unless a
  // page opts in) — the plain demo cards close immediately and only the
  // manager's `gap` (300ms, set in manager.dart) delays the next activation.
  Future<void> advance(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  testWidgets('mixed: native → GetX → bot_toast strictly one at a time',
      (tester) async {
    await boot(tester);
    await goTo(tester, 'External Presenters');

    await tester.tap(find.byKey(const Key('btn-mixed')));
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

  testWidgets('serial ×3 advances the queue as each card is closed',
      (tester) async {
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

  testWidgets('affix: a replace launched from INSIDE FIX cannot cover it',
      (tester) async {
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

  testWidgets('overlap: stack B from INSIDE A — both visible at once',
      (tester) async {
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

  testWidgets('pauseAll freezes serial + overlaps; resumeAll releases',
      (tester) async {
    await boot(tester);

    await goTo(tester, 'Pause & Resume');
    await tester.tap(find.byKey(const Key('btn-pause-all')));
    await tester.pumpAndSettle();

    await goTo(tester, 'Replace & Affix');
    await tester.tap(find.byKey(const Key('btn-replace-demo'))); // serial frozen
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

  testWidgets('programmatic: one card first, more enqueued seconds later',
      (tester) async {
    await boot(tester);
    await goTo(tester, 'Queue Basics');

    await tester.tap(find.byKey(const Key('btn-prog')));
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

  testWidgets('two 2×2 groups; clearWhere removes exactly group A',
      (tester) async {
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
    app.om.clearWhere(
        (r) => r.data is Map && (r.data as Map)['group'] == 'a');
    await tester.pumpAndSettle();
    expect(find.text('A1'), findsNothing); // group A gone
    expect(find.text('A2'), findsNothing);
    expect(find.text('B1'), findsOneWidget); // group B untouched
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('conditions ride REAL navigation to /promo and back',
      (tester) async {
    await boot(tester);
    // Regression coverage for a real bug found in code review: MaterialApp's
    // implicit `home:` route reports as '/' (Flutter's own
    // Navigator.defaultRouteName), not '/home' — main.dart uses a named
    // `initialRoute`/`routes` to give it a real name. Assert the actual label
    // text (not just activeIds/queuedIds) so a regression shows up here.
    expect(app.om.currentRoute, '/home');
    expect(find.textContaining('route: /home'), findsOneWidget);

    await goTo(tester, 'Conditions');
    await tester.tap(find.byKey(const Key('btn-cond-promo'))); // on /home: gated
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
    expect(find.text('ROUTE /promo'), findsNothing); // dismissWhenUnmet pulled it down
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
    expect(find.text('ZONE CARD'), findsOneWidget); // shows immediately on /home

    await tester.tap(find.text('close ZONE CARD'));
    await advance(tester);
    expect(app.om.activeIds, isEmpty);

    await tester.tap(find.byKey(const Key('btn-goto-zone')));
    await tester.pumpAndSettle();
    expect(find.text('/zone — no-overlay zone'), findsOneWidget); // real page covers HomePage
    expect(app.om.isPaused, isTrue); // auto-frozen by entering /zone

    // btn-queue-in-zone lives on the Pause page, now covered by the pushed
    // /zone route — call the manager directly (equivalent effect, no UI
    // needed) via the openCard helper re-exported by main.dart.
    app.openCard('zone-card', text: 'ZONE CARD');
    await tester.pumpAndSettle();
    expect(find.text('ZONE CARD'), findsNothing); // queued, not shown while frozen
    expect(app.om.queuedIds, contains('zone-card'));

    await tester.pageBack(); // leave /zone
    await tester.pumpAndSettle();
    expect(app.om.isPaused, isFalse); // auto-resumed
    expect(find.text('ZONE CARD'), findsOneWidget); // now shows

    app.om.close('zone-card');
    await advance(tester);
  });

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
    expect(app.om.queuedIds, contains('cd-s'));
  });

  testWidgets('cooldown minGap=5s blocks, then AUTO-shows when it expires',
      (tester) async {
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

  testWidgets('resolve: fetches on grant, shows with backend data',
      (tester) async {
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

  testWidgets('beforeClose: locked per open, close vetoed until unlocked',
      (tester) async {
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

  testWidgets('update(id, patch) live-updates the shown card', (tester) async {
    await boot(tester);
    await goTo(tester, 'Lifecycle');

    await tester.tap(find.byKey(const Key('btn-upd-show')));
    await tester.pumpAndSettle();
    expect(find.text('n = 0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-update')));
    await tester.pumpAndSettle();
    expect(find.text('n = 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-update')));
    await tester.pumpAndSettle();
    expect(find.text('n = 2'), findsOneWidget);

    await tester.tap(find.text('close n = 2'));
    await advance(tester);
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
}
