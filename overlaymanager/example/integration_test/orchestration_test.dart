// Real-device (Windows desktop) full-API integration test.
//
// Interaction style mirrors the TS example's browser e2e lessons:
// replace/affix/overlap are driven from buttons INSIDE overlays (2+ overlays
// on screen to observe exclusion/stacking), conditions ride REAL navigation
// (a /promo page), the programmatic flow enqueues progressively, clearWhere
// clears one of two visible groups, beforeClose resets its lock per open, and
// a restart button rebuilds the whole app with a fresh manager.
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

  Future<void> boot(WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle();
  }

  // close(exit 200ms) + gap(300ms) + activation frame
  Future<void> advance(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  testWidgets('mixed: native → GetX → bot_toast strictly one at a time',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-mixed')));
    await tester.pumpAndSettle();

    expect(find.text('Native dialog'), findsOneWidget);
    expect(find.text('GetX dialog'), findsNothing);
    expect(find.text('bot_toast hello'), findsNothing);

    await tester.tap(find.byKey(const Key('OK-native')));
    await advance(tester);
    expect(find.text('GetX dialog'), findsOneWidget);

    await tester.tap(find.byKey(const Key('OK-getx')));
    await advance(tester);
    expect(find.text('bot_toast hello'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();
    expect(find.text('bot_toast hello'), findsNothing);
    expect(app.om.activeIds, isEmpty);
    expect(app.om.queuedIds, isEmpty);
  });

  testWidgets('serial ×3 + barrier(mask)-close advances the queue',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-queue3')));
    await tester.pumpAndSettle();
    expect(find.text('C1'), findsOneWidget);
    expect(app.om.queuedIds, containsAll(<String>['c2', 'c3']));

    // Mask close (NOT a button): tap the barrier far from the card.
    await tester.tapAt(const Offset(15, 520));
    await advance(tester);
    expect(find.text('C1'), findsNothing);
    expect(find.text('C2'), findsOneWidget); // queue advanced via mask close

    await tester.tap(find.text('close C2'));
    await advance(tester);
    expect(find.text('C3'), findsOneWidget);

    await tester.tap(find.text('close C3'));
    await advance(tester);
    expect(app.om.activeIds, isEmpty);
  });

  testWidgets('replace: R2 preempts R1, which returns to the queue',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-replace-demo')));
    await tester.pumpAndSettle();
    expect(find.text('R1'), findsOneWidget);

    await tester.tap(find.text('替换为 R2')); // in-overlay action
    await tester.pumpAndSettle();
    expect(find.text('R1'), findsNothing); // preempted...
    expect(find.text('R2'), findsOneWidget);
    expect(app.om.queuedIds, contains('r1')); // ...but displaced to the queue

    await tester.tap(find.text('close R2'));
    await advance(tester);
    expect(find.text('R1'), findsOneWidget); // R1 comes back once R2 closes

    await tester.tap(find.text('close R1'));
    await advance(tester);
    expect(app.om.activeIds, isEmpty);
  });

  testWidgets('affix: a replace launched from INSIDE FIX cannot cover it',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-affix')));
    await tester.pumpAndSettle();
    expect(find.text('FIX'), findsOneWidget);

    await tester.tap(find.text('尝试 replace 顶掉 FIX')); // in-overlay action
    await tester.pumpAndSettle();
    expect(find.text('FIX'), findsOneWidget); // NOT covered / displaced
    expect(find.text('TRY'), findsNothing);
    expect(app.om.queuedIds, contains('try')); // waits at the queue front

    await tester.tap(find.text('close FIX'));
    await advance(tester);
    expect(find.text('TRY'), findsOneWidget); // its turn right after

    await tester.tap(find.text('close TRY'));
    await advance(tester);
  });

  testWidgets('overlap: stack B from INSIDE A — both visible at once',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-overlap')));
    await tester.pumpAndSettle();
    expect(find.text('OVA'), findsOneWidget);

    await tester.tap(find.text('stack B')); // in-overlay action
    await tester.pumpAndSettle();
    expect(find.text('OVA'), findsOneWidget); // BOTH on screen
    expect(find.text('OVB'), findsOneWidget);
    expect(app.om.activeIds, containsAll(<String>['ova', 'ovb']));

    await tester.tap(find.text('close OVB'));
    await advance(tester);
    expect(find.text('OVB'), findsNothing);
    expect(find.text('OVA'), findsOneWidget); // serial slot untouched

    await tester.tap(find.text('close OVA'));
    await advance(tester);
  });

  testWidgets('pauseAll freezes serial + overlaps; resumeAll releases',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-pause')));
    await tester.tap(find.byKey(const Key('btn-replace-demo'))); // serial frozen
    await tester.tap(find.byKey(const Key('btn-groups'))); // overlaps held
    await tester.pumpAndSettle();
    expect(app.om.activeIds, isEmpty);
    expect(find.text('R1'), findsNothing);
    expect(find.text('A1'), findsNothing);

    await tester.tap(find.byKey(const Key('btn-resume')));
    await tester.pumpAndSettle();
    expect(find.text('R1'), findsOneWidget); // serial released
    expect(find.text('A1'), findsOneWidget); // held overlaps released
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('programmatic: one card first, more enqueued seconds later',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-data')));
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

    await tester.tap(find.byKey(const Key('btn-groups')));
    await tester.pumpAndSettle();
    for (final t in ['A1', 'A2', 'B1', 'B2']) {
      expect(find.text(t), findsOneWidget); // 2 groups visible side by side
    }

    await tester.tap(find.byKey(const Key('btn-clear-a')));
    await tester.pumpAndSettle();
    expect(find.text('A1'), findsNothing); // group A gone
    expect(find.text('A2'), findsNothing);
    expect(find.text('B1'), findsOneWidget); // group B untouched
    expect(find.text('B2'), findsOneWidget);
  });

  testWidgets('conditions ride REAL navigation to /promo and back',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-cond'))); // on /home: gated
    await tester.pumpAndSettle();
    expect(find.text('COND'), findsNothing);
    expect(app.om.queuedIds, contains('cond'));

    await tester.tap(find.byKey(const Key('btn-goto-promo')));
    await tester.pumpAndSettle();
    expect(find.text('PROMO PAGE'), findsOneWidget); // real page
    expect(find.text('COND'), findsOneWidget); // route matched -> shown

    await tester.pageBack(); // leave /promo
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('COND'), findsNothing); // dismissWhenUnmet pulled it down
    expect(app.om.activeIds, isEmpty);
  });

  testWidgets('cooldown session=1 blocks the second show', (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    expect(find.text('CDS'), findsOneWidget);

    await tester.tap(find.text('close CDS'));
    await advance(tester);

    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    expect(find.text('CDS'), findsNothing); // capped for this session
    expect(app.om.queuedIds, contains('cd-s'));
  });

  testWidgets('cooldown minGap=2s blocks, then AUTO-shows when it expires',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-cdg')));
    await tester.pumpAndSettle();
    expect(find.text('CDG'), findsOneWidget);
    await tester.tap(find.text('close CDG'));
    await advance(tester);

    await tester.tap(find.byKey(const Key('btn-cdg')));
    await tester.pumpAndSettle();
    expect(find.text('CDG'), findsNothing); // inside the 2s gap → queued
    expect(app.om.queuedIds, contains('cd-g'));

    // No nudge: a time-based cooldown arms its own wake timer, so the queued
    // card appears on its own once the 2s window elapses.
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();
    expect(find.text('CDG'), findsOneWidget);

    await tester.tap(find.text('close CDG'));
    await advance(tester);
  });

  testWidgets('resolve: fetches on grant, shows with backend data',
      (tester) async {
    await boot(tester);

    await tester.tap(find.byKey(const Key('btn-resolve')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('DATA:'), findsNothing); // still resolving

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('DATA:42'), findsOneWidget); // payload injected

    await tester.tap(find.text('close DATA:42'));
    await advance(tester);
  });

  testWidgets('beforeClose: locked per open, close vetoed until unlocked',
      (tester) async {
    await boot(tester);

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

    await tester.tap(find.byKey(const Key('btn-upd-show')));
    await tester.pumpAndSettle();
    expect(find.text('n=0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-update')));
    await tester.pumpAndSettle();
    expect(find.text('n=1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-update')));
    await tester.pumpAndSettle();
    expect(find.text('n=2'), findsOneWidget);

    await tester.tap(find.text('close n=2'));
    await advance(tester);
  });

  testWidgets('restart rebuilds the app with a FRESH manager', (tester) async {
    await boot(tester);

    // Ensure the session cooldown is exhausted on the CURRENT manager (the
    // earlier cooldown test may already have used it up — same process).
    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    if (find.text('CDS').evaluate().isNotEmpty) {
      await tester.tap(find.text('close CDS'));
      await advance(tester);
      await tester.tap(find.byKey(const Key('btn-cds')));
      await tester.pumpAndSettle();
    }
    expect(find.text('CDS'), findsNothing); // capped on the old manager

    await tester.tap(find.byKey(const Key('btn-restart')));
    await tester.pumpAndSettle();
    expect(app.om.activeIds, isEmpty); // fresh manager, empty world
    expect(app.om.queuedIds, isEmpty);
    expect(find.textContaining('路由: /home'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn-cds')));
    await tester.pumpAndSettle();
    expect(find.text('CDS'), findsOneWidget); // session counter was reset

    await tester.tap(find.text('close CDS'));
    await advance(tester);
  });

  testWidgets('GetX snackbar scheduled through the manager', (tester) async {
    await boot(tester);

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
