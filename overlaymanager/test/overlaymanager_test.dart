import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// Pump an [OverlayManagerScope] hosting [manager] and run the post-frame
/// attach so the manager is ready to render.
Future<void> pumpHost(WidgetTester tester, OverlayManager manager) async {
  await tester.pumpWidget(
    MaterialApp(
      home: OverlayManagerScope(
        manager: manager,
        child: const Scaffold(body: Center(child: Text('home'))),
      ),
    ),
  );
  await tester.pump(); // run addPostFrameCallback -> attach
}

/// A trivial overlay body that shows its label.
Widget label(String text) => Center(child: Text(text));

/// Simulates an external overlay backend (showDialog / GetX / bot_toast):
/// [present] is what the orchestrator calls when the queue grants permission;
/// [userClose] simulates the user closing the backend directly (barrier tap,
/// back button, timeout); [dismiss] is the orchestrator-driven graceful close.
class _FakeBackend {
  final Completer<String?> _dismissed = Completer<String?>();
  bool presented = false;
  bool dismissCalled = false;

  PresentedOverlay<String> present(PresentContext context) {
    presented = true;
    return PresentedOverlay<String>(
      dismissed: _dismissed.future,
      dismiss: ([String? result]) async {
        dismissCalled = true;
        if (!_dismissed.isCompleted) _dismissed.complete(result);
      },
    );
  }

  void userClose(String? result) {
    if (!_dismissed.isCompleted) _dismissed.complete(result);
  }
}

void main() {
  testWidgets('serial: only one overlay shows at a time; the rest queue',
      (tester) async {
    final manager = OverlayManager();
    await pumpHost(tester, manager);

    manager.open(id: 'a', builder: (c, h) => label('A'));
    manager.open(id: 'b', builder: (c, h) => label('B'));
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsNothing);
    expect(manager.activeIds, <String>['a']);
    expect(manager.queuedIds, <String>['b']);

    manager.dispose();
  });

  testWidgets('closing the active overlay advances to the next',
      (tester) async {
    final manager =
        OverlayManager(exitDuration: const Duration(milliseconds: 100));
    await pumpHost(tester, manager);

    manager.open(id: 'a', builder: (c, h) => label('A'));
    manager.open(id: 'b', builder: (c, h) => label('B'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);

    manager.close('a');
    await tester.pump(); // phase -> closing (still mounted)
    expect(manager.isShowing('a'), isTrue); // still in closing phase
    await tester.pump(const Duration(milliseconds: 100)); // exit -> removed
    await tester.pump(); // build the newly activated 'b'

    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    expect(manager.activeIds, <String>['b']);

    manager.dispose();
  });

  testWidgets('priority: higher priority shows before lower when slot frees',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    manager.open(id: 'a', builder: (c, h) => label('A')); // activates now
    manager.open(id: 'low', priority: 1, builder: (c, h) => label('LOW'));
    manager.open(id: 'high', priority: 10, builder: (c, h) => label('HIGH'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);

    manager.close('a');
    await tester.pump(); // exit zero -> removed + next activated
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('LOW'), findsNothing);

    manager.close('high');
    await tester.pump();
    expect(find.text('LOW'), findsOneWidget);

    manager.dispose();
  });

  testWidgets('show returns a Future that resolves with the close result',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    final future = manager.open<String>(
      id: 'confirm',
      builder: (c, h) => TextButton(
        onPressed: () => h.close('yes'),
        child: const Text('OK'),
      ),
    );
    await tester.pump();
    expect(find.text('OK'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pump();

    expect(await future, 'yes');

    manager.dispose();
  });

  testWidgets('manager.close(id, value) also delivers the result',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    final future = manager.open<int>(id: 'n', builder: (c, h) => label('N'));
    await tester.pump();

    manager.close('n', 42);
    await tester.pump();

    expect(await future, 42);

    manager.dispose();
  });

  testWidgets('dismiss / no-result close resolves the Future with null',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    final future = manager.open<String>(id: 'x', builder: (c, h) => label('X'));
    await tester.pump();

    manager.dismiss('x');
    await tester.pump();

    expect(await future, isNull);

    manager.dispose();
  });

  testWidgets('replace: preempts the current overlay; it returns to the queue',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    final aFuture =
        manager.open<String>(id: 'a', builder: (c, h) => label('A'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);

    manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
    await tester.pump();

    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    // Displaced back to the queue (result still pending), NOT dropped.
    expect(manager.queuedIds, contains('a'));

    manager.close('b');
    await tester.pump();
    expect(find.text('A'), findsOneWidget); // A resumes once B closes

    manager.close('a', 'done');
    await tester.pump();
    expect(await aFuture, 'done'); // its own close settles it, not the replace

    manager.dispose();
  });

  testWidgets('replace displaces the current AND front-bands ahead of queued',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    manager.open(id: 'a', builder: (c, h) => label('A')); // active
    manager.open(id: 'b', builder: (c, h) => label('B')); // queued first
    manager.open(id: 'r', replace: true, builder: (c, h) => label('R'));
    await tester.pump();

    expect(find.text('R'), findsOneWidget); // preempts A AND outranks queued B
    expect(find.text('A'), findsNothing);
    expect(manager.queuedIds, containsAll(<String>['a', 'b'])); // both waiting

    manager.close('r');
    await tester.pump();
    expect(find.text('A'), findsOneWidget); // displaced A (oldest seq) resumes first

    manager.close('a');
    await tester.pump();
    expect(find.text('B'), findsOneWidget); // then the rest of the queue

    manager.dispose();
  });

  group('replace / displace — regression (code-review)', () {
    testWidgets('displaced entry with a one-shot cooldown still re-shows and '
        'its future settles (no permanent hang)', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      final aFuture = manager.open<String>(
        id: 'a',
        cooldown: const OverlayCooldown(session: 1),
        builder: (c, h) => label('A'),
      );
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(manager.queuedIds, contains('a'));

      manager.close('b');
      await tester.pump();
      expect(find.text('A'), findsOneWidget); // exempt: re-shows despite session:1

      manager.close('a', 'ok');
      await tester.pump();
      expect(await aFuture, 'ok'); // settles, not stranded

      manager.dispose();
    });

    testWidgets('replacing a RESOLVING entry discards it — resolver never '
        'runs twice and stale data never opens', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      var calls = 0;
      final backend = Completer<String?>();
      final aFuture = manager.open<String>(
        id: 'a',
        resolve: () {
          calls++;
          return backend.future;
        },
        builder: (c, h) => label('A:${h.data}'),
      );
      await tester.pump();
      expect(manager.activeIds, isEmpty); // resolving, nothing shown
      expect(calls, 1);

      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      expect(manager.queuedIds, isNot(contains('a'))); // discarded, not displaced
      expect(await aFuture, isNull); // settled null

      backend.complete('X'); // the stale resolver finishes late
      await tester.pump();
      expect(calls, 1); // NOT re-run
      expect(find.textContaining('A:'), findsNothing); // stale payload never opens

      manager.dispose();
    });

    testWidgets('close() on a displaced entry settles it and stops the re-show',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      final aFuture =
          manager.open<String>(id: 'a', builder: (c, h) => label('A'));
      await tester.pump();
      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(manager.queuedIds, contains('a'));

      manager.close('a', 'bye'); // via the still-held handle path
      await tester.pump();
      expect(await aFuture, 'bye'); // delivered, not dropped
      expect(manager.queuedIds, isNot(contains('a')));

      manager.close('b');
      await tester.pump();
      expect(find.text('A'), findsNothing); // does NOT re-appear

      manager.dispose();
    });

    testWidgets('a normal queued entry\'s close() is still a no-op (not '
        'mistaken for displaced)', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(id: 'a', builder: (c, h) => label('A'));
      final qFuture =
          manager.open<String>(id: 'q', builder: (c, h) => label('Q'));
      await tester.pump();
      expect(manager.queuedIds, contains('q'));

      manager.close('q', 'x'); // never shown -> no-op
      await tester.pump();
      expect(manager.queuedIds, contains('q')); // still queued
      expect(qFuture, isA<Future<String?>>()); // not settled

      manager.close('a');
      await tester.pump();
      expect(find.text('Q'), findsOneWidget); // it eventually shows

      manager.dispose();
    });

    testWidgets('a displaced entry resumes its REMAINING duration, not a full '
        'one', (tester) async {
      var t = DateTime(2026, 1, 1, 12);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      manager.open(
        id: 'a',
        duration: const Duration(seconds: 10),
        builder: (c, h) => label('A'),
      );
      await tester.pump();

      t = t.add(const Duration(seconds: 8)); // 2s of the 10s left
      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      manager.close('b');
      await tester.pump();
      expect(find.text('A'), findsOneWidget); // re-shown with ~2s remaining

      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('A'), findsOneWidget); // still up before 2s
      await tester.pump(const Duration(milliseconds: 700)); // now past 2s
      expect(find.text('A'), findsNothing); // auto-closed on REMAINING, not 10s

      manager.dispose();
    });

    testWidgets('a displaced replace entry does not out-band the replacer',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      // 'a' is itself a replace (shows immediately — nothing to preempt).
      manager.open(id: 'a', replace: true, builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      // 'b' (also replace) displaces 'a'. 'b' must show; 'a' must NOT jump back
      // ahead of it despite 'a' having the older seq.
      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(manager.queuedIds, contains('a'));

      manager.close('b');
      await tester.pump();
      expect(find.text('A'), findsOneWidget); // resumes only after the replacer

      manager.dispose();
    });

    testWidgets('clear() cancels an armed cooldown wake timer', (tester) async {
      var t = DateTime(2026, 1, 1, 12);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      const cd = OverlayCooldown(minGap: Duration(seconds: 1));
      manager.open(id: 'g', cooldown: cd, builder: (c, h) => label('G'));
      await tester.pump();
      manager.close('g');
      await tester.pump();
      manager.open(id: 'g', cooldown: cd, builder: (c, h) => label('G2'));
      await tester.pump();
      expect(find.text('G2'), findsNothing); // queued, wake timer armed

      manager.clear(); // must cancel the armed timer

      var ticked = false;
      manager.addListener(() => ticked = true);
      t = t.add(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1200)); // past the old wake
      expect(ticked, isFalse); // no stray notify from a surviving timer
      expect(manager.queuedIds, isEmpty);

      manager.dispose();
    });

    testWidgets('a displaced entry with resolve reuses its fetched data — '
        'the resolver is NOT invoked again on resume', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      var calls = 0;
      manager.open<Map<String, int>>(
        id: 'a',
        resolve: () async {
          calls++;
          return {'v': calls};
        },
        builder: (c, h) => label('A:${(h.data as Map)['v']}'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('A:1'), findsOneWidget);
      expect(calls, 1);

      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(manager.queuedIds, contains('a'));

      manager.close('b');
      await tester.pump();
      expect(find.text('A:1'), findsOneWidget); // same payload, no re-fetch
      expect(calls, 1); // resolver NOT called again

      manager.dispose();
    });

    testWidgets('beforeClose still gates close() on a displaced entry',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      var allow = false;
      manager.open<String>(
        id: 'a',
        beforeClose: () => allow,
        builder: (c, h) => label('A'),
      );
      await tester.pump();
      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(manager.queuedIds, contains('a'));

      manager.close('a', 'nope'); // guard still false -> vetoed
      await tester.pump();
      expect(manager.queuedIds, contains('a')); // still queued, not removed

      allow = true;
      manager.close('a', 'ok'); // guard now true -> takes effect
      await tester.pump();
      expect(manager.queuedIds, isNot(contains('a')));

      manager.dispose();
    });

    testWidgets('an approved async beforeClose still finalizes a close even '
        'if the entry gets displaced while the guard is pending',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      final guardVerdict = Completer<bool>();
      final aFuture = manager.open<String>(
        id: 'a',
        beforeClose: () => guardVerdict.future,
        builder: (c, h) => label('A'),
      );
      await tester.pump();

      manager.close('a', 'done'); // guard in flight, entry still open

      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(find.text('B'), findsOneWidget);
      expect(manager.queuedIds, contains('a')); // displaced while guard pending

      guardVerdict.complete(true); // approve after the displace
      await tester.pump();
      await tester.pump();
      expect(await aFuture, 'done'); // the approved close still lands
      expect(manager.queuedIds, isNot(contains('a')));

      manager.dispose();
    });
  });

  testWidgets('overlap: bypasses the queue and stacks on top', (tester) async {
    final manager = OverlayManager();
    await pumpHost(tester, manager);

    manager.open(id: 'a', builder: (c, h) => label('A'));
    manager.open(id: 'top', overlap: true, builder: (c, h) => label('TOP'));
    await tester.pump();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('TOP'), findsOneWidget); // both shown simultaneously
    expect(manager.activeIds, containsAll(<String>['a', 'top']));

    manager.dispose();
  });

  testWidgets('barrierDismissible: tapping the barrier dismisses the overlay',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    final future = manager.open<String>(
      id: 'dlg',
      barrierDismissible: true,
      barrierColor: const Color(0x88000000),
      builder: (c, h) => const Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: Center(child: Text('DLG')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('DLG'), findsOneWidget);

    // Tap top-left corner (on the barrier, away from the centered content).
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();

    expect(find.text('DLG'), findsNothing);
    expect(await future, isNull);

    manager.dispose();
  });

  testWidgets('duration: overlay auto-closes after its duration elapses',
      (tester) async {
    final manager = OverlayManager(exitDuration: Duration.zero);
    await pumpHost(tester, manager);

    manager.open(
      id: 't',
      duration: const Duration(milliseconds: 500),
      builder: (c, h) => label('T'),
    );
    await tester.pump();
    expect(find.text('T'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('T'), findsNothing);

    manager.dispose();
  });

  testWidgets('gap: next overlay waits the gap after the previous is removed',
      (tester) async {
    final manager = OverlayManager(
      gap: const Duration(milliseconds: 300),
      exitDuration: Duration.zero,
    );
    await pumpHost(tester, manager);

    manager.open(id: 'a', builder: (c, h) => label('A'));
    manager.open(id: 'b', builder: (c, h) => label('B'));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);

    manager.close('a');
    await tester.pump(); // A removed, gap timer armed
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing); // still waiting out the gap

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('B'), findsOneWidget);

    manager.dispose();
  });

  testWidgets('named slots run independent serial queues', (tester) async {
    final manager = OverlayManager();
    await pumpHost(tester, manager);

    manager.open(id: 't', slot: 'toast', builder: (c, h) => label('TOAST'));
    manager.open(id: 's', slot: 'sheet', builder: (c, h) => label('SHEET'));
    await tester.pump();

    // Different slots -> both active at once.
    expect(find.text('TOAST'), findsOneWidget);
    expect(find.text('SHEET'), findsOneWidget);

    manager.dispose();
  });

  group('timing (delay / gap / exitDuration) — TS parity', () {
    testWidgets('delay: waits before appearing, even for the first overlay',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.open(
        id: 'd',
        delay: const Duration(milliseconds: 200),
        builder: (c, h) => label('D'),
      );
      await tester.pump();
      expect(find.text('D'), findsNothing); // cold start also honors delay
      expect(manager.queuedIds, contains('d'));

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('D'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('replace during the gap skips the remaining gap (TS rule)',
        (tester) async {
      final manager = OverlayManager(
        gap: const Duration(milliseconds: 300),
        exitDuration: Duration.zero,
      );
      await pumpHost(tester, manager);

      manager.open(id: 'a', builder: (c, h) => label('A'));
      await tester.pump();
      manager.close('a');
      await tester.pump(); // removed; gap timer armed

      manager.open(id: 'r', replace: true, builder: (c, h) => label('R'));
      await tester.pump();
      expect(find.text('R'), findsOneWidget); // did NOT wait out the gap

      manager.dispose();
    });

    testWidgets('per-overlay exitDuration overrides the manager default',
        (tester) async {
      final manager =
          OverlayManager(exitDuration: const Duration(milliseconds: 100));
      await pumpHost(tester, manager);

      manager.open(
        id: 'x',
        exitDuration: const Duration(milliseconds: 400),
        builder: (c, h) => label('X'),
      );
      await tester.pump();
      manager.close('x');
      await tester.pump(const Duration(milliseconds: 200));
      expect(manager.isShowing('x'), isTrue); // manager default would be gone
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(manager.isShowing('x'), isFalse);

      manager.dispose();
    });

    testWidgets('manual close cancels the pending duration timer',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      final future = manager.open<String>(
        id: 't',
        duration: const Duration(milliseconds: 500),
        builder: (c, h) => label('T'),
      );
      await tester.pump();
      manager.close('t', 'manual');
      await tester.pump();
      expect(await future, 'manual'); // not overwritten by the timer
      await tester.pump(const Duration(milliseconds: 600)); // timer must be dead
      expect(manager.activeIds, isEmpty);

      manager.dispose();
    });
  });

  group('priority & ordering — TS parity', () {
    testWidgets('equal priority breaks ties FIFO', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(id: 'a', builder: (c, h) => label('A'));
      manager.open(id: 'first', priority: 5, builder: (c, h) => label('FIRST'));
      manager.open(id: 'second', priority: 5, builder: (c, h) => label('SECOND'));
      await tester.pump();

      manager.close('a');
      await tester.pump();
      expect(find.text('FIRST'), findsOneWidget);
      manager.close('first');
      await tester.pump();
      expect(find.text('SECOND'), findsOneWidget);

      manager.dispose();
    });
  });

  group('duplicate id — TS parity', () {
    testWidgets('reusing an active id replaces in place (old result null)',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      final first = manager.open<String>(id: 'dup', builder: (c, h) => label('V1'));
      await tester.pump();
      expect(find.text('V1'), findsOneWidget);

      final second = manager.open<String>(id: 'dup', builder: (c, h) => label('V2'));
      await tester.pump();
      expect(find.text('V1'), findsNothing);
      expect(find.text('V2'), findsOneWidget); // shown immediately, no queue trip
      expect(manager.queuedIds, isEmpty);
      expect(await first, isNull); // old handle settled

      manager.close('dup', 'v');
      await tester.pump();
      expect(await second, 'v');

      manager.dispose();
    });

    testWidgets('reusing a queued id overrides the queued entry',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(id: 'block', builder: (c, h) => label('BLOCK'));
      final old = manager.open<String>(id: 'dup', builder: (c, h) => label('Q1'));
      manager.open(id: 'dup', builder: (c, h) => label('Q2'));
      await tester.pump();
      expect(await old, isNull); // overridden while queued

      manager.close('block');
      await tester.pump();
      expect(find.text('Q1'), findsNothing);
      expect(find.text('Q2'), findsOneWidget); // new config won

      manager.dispose();
    });
  });

  group('lifecycle & results — TS parity', () {
    testWidgets('close on a queued id is a no-op; remove takes it out',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.open(id: 'a', builder: (c, h) => label('A'));
      final queued = manager.open<String>(id: 'q', builder: (c, h) => label('Q'));
      await tester.pump();

      manager.close('q'); // not open -> no-op
      await tester.pump();
      expect(manager.queuedIds, contains('q'));
      expect(find.text('A'), findsOneWidget);

      manager.remove('q');
      await tester.pump();
      expect(manager.queuedIds, isEmpty);
      expect(await queued, isNull);
      expect(find.text('A'), findsOneWidget); // current untouched

      manager.dispose();
    });

    testWidgets('clear(): everything removed, all pending results resolve null',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final f1 = manager.open<String>(id: 'a', builder: (c, h) => label('A'));
      final f2 = manager.open<String>(id: 'b', builder: (c, h) => label('B'));
      final f3 = manager.open<String>(
          id: 'o', overlap: true, builder: (c, h) => label('O'));
      await tester.pump();

      manager.clear();
      await tester.pump();
      expect(manager.activeIds, isEmpty);
      expect(manager.queuedIds, isEmpty);
      expect(await f1, isNull);
      expect(await f2, isNull);
      expect(await f3, isNull);
      expect(find.text('A'), findsNothing);
      expect(find.text('O'), findsNothing);

      manager.dispose();
    });

    testWidgets('handle.data carries the opaque payload', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      Object? seen;
      manager.open(
        id: 'd',
        data: {'kind': 'promo'},
        builder: (c, h) {
          seen = h.data;
          return label('D');
        },
      );
      await tester.pump();
      expect(seen, {'kind': 'promo'});

      manager.dispose();
    });
  });

  group('overlap — TS parity', () {
    testWidgets('multiple overlaps coexist and close independently',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(id: 'base', builder: (c, h) => label('BASE'));
      manager.open(id: 'o1', overlap: true, builder: (c, h) => label('O1'));
      manager.open(id: 'o2', overlap: true, builder: (c, h) => label('O2'));
      await tester.pump();
      expect(find.text('BASE'), findsOneWidget);
      expect(find.text('O1'), findsOneWidget);
      expect(find.text('O2'), findsOneWidget);

      manager.close('o1');
      await tester.pump();
      expect(find.text('O1'), findsNothing);
      expect(find.text('O2'), findsOneWidget); // others untouched
      expect(find.text('BASE'), findsOneWidget); // serial slot untouched

      manager.dispose();
    });

    testWidgets('overlap honors duration auto-close', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(
        id: 'o',
        overlap: true,
        duration: const Duration(milliseconds: 300),
        builder: (c, h) => label('O'),
      );
      await tester.pump();
      expect(find.text('O'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('O'), findsNothing);

      manager.dispose();
    });
  });

  group('introspection & notifications — TS parity', () {
    testWidgets('ChangeNotifier fires on transitions', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      var ticks = 0;
      manager.addListener(() => ticks++);
      manager.open(id: 'a', builder: (c, h) => label('A'));
      await tester.pump();
      final afterShow = ticks;
      expect(afterShow, greaterThan(0));

      manager.close('a');
      await tester.pump();
      expect(ticks, greaterThan(afterShow));

      manager.dispose();
    });

    testWidgets('builtin entries queued before attach show after attach',
        (tester) async {
      final manager = OverlayManager();
      manager.open(id: 'early', builder: (c, h) => label('EARLY'));
      expect(manager.activeIds, isEmpty); // no OverlayState yet
      expect(manager.queuedIds, contains('early'));

      await pumpHost(tester, manager); // attach happens post-frame
      await tester.pump();
      expect(find.text('EARLY'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('currentRoute mirrors the route key set via setContext',
        (tester) async {
      final manager = OverlayManager();
      expect(manager.currentRoute, isNull);

      manager.setContext({'route': '/checkout'});
      expect(manager.currentRoute, '/checkout');

      manager.setContext({'route': null});
      expect(manager.currentRoute, isNull);

      manager.dispose();
    });
  });

  group('external presenter (orchestrating third-party overlay systems)', () {
    testWidgets('present is called only when the queue grants permission',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      manager.open(id: 'a', builder: (c, h) => label('A'));
      manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();
      expect(backend.presented, isFalse); // queued behind A

      manager.close('a');
      await tester.pump();
      expect(backend.presented, isTrue); // slot freed -> presented
      expect(manager.activeIds, contains('ext'));

      manager.dispose();
    });

    testWidgets('backend-closed (user path) resolves the Future and advances',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      final future = manager.open<String>(id: 'ext', present: backend.present);
      manager.open(id: 'next', builder: (c, h) => label('NEXT'));
      await tester.pump();
      expect(backend.presented, isTrue);
      expect(find.text('NEXT'), findsNothing);

      backend.userClose('yes'); // e.g. barrier tap / back button / timeout
      await tester.pump(); // flush the dismissed microtask -> queue advances
      await tester.pump(); // build the newly inserted 'next' entry

      expect(await future, 'yes');
      expect(find.text('NEXT'), findsOneWidget); // queue advanced

      manager.dispose();
    });

    testWidgets('manager.close drives the backend dismiss handle',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      final future = manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();

      manager.close('ext', 'r');
      await tester.pump();

      expect(backend.dismissCalled, isTrue); // graceful, targeted close
      expect(await future, 'r'); // orchestrator result wins
      expect(manager.activeIds, isEmpty);

      manager.dispose();
    });

    testWidgets('external entries do not require an attached OverlayState',
        (tester) async {
      final manager = OverlayManager(); // never attached
      final backend = _FakeBackend();
      final future = manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();
      expect(backend.presented, isTrue); // backend renders itself

      backend.userClose('ok');
      await tester.pump();
      expect(await future, 'ok');

      manager.dispose();
    });

    testWidgets('replace preempts an external overlay (best-effort dismiss)',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      final extFuture =
          manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();
      expect(backend.presented, isTrue);

      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();

      expect(backend.dismissCalled, isTrue); // backend asked to close
      expect(await extFuture, isNull); // preempted -> null
      expect(find.text('B'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('exitDuration acts as post-dismiss grace before advancing',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      manager.open<String>(
        id: 'ext',
        present: backend.present,
        exitDuration: const Duration(milliseconds: 100),
      );
      manager.open(id: 'next', builder: (c, h) => label('NEXT'));
      await tester.pump();

      backend.userClose(null); // route future completes at animation start
      await tester.pump();
      expect(find.text('NEXT'), findsNothing); // grace: exit anim still playing

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('NEXT'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('clear() best-effort dismisses external backends',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();

      manager.clear();
      await tester.pump();
      expect(backend.dismissCalled, isTrue);
      expect(manager.activeIds, isEmpty);

      manager.dispose();
    });

    testWidgets('external + overlap stacks over the serial slot',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      manager.open(id: 'base', builder: (c, h) => label('BASE'));
      manager.open<String>(id: 'ext', overlap: true, present: backend.present);
      await tester.pump();

      expect(find.text('BASE'), findsOneWidget); // serial slot untouched
      expect(backend.presented, isTrue); // presented immediately, no queue
      expect(manager.activeIds, containsAll(<String>['base', 'ext']));

      manager.dispose();
    });

    testWidgets('external duration auto-close drives the backend dismiss',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = _FakeBackend();
      final future = manager.open<String>(
        id: 'ext',
        duration: const Duration(milliseconds: 200),
        present: backend.present,
      );
      await tester.pump();
      expect(backend.dismissCalled, isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(backend.dismissCalled, isTrue); // timer -> close -> dismiss
      expect(await future, isNull);
      expect(manager.activeIds, isEmpty);

      manager.dispose();
    });

    testWidgets('external without a dismiss handle: close() just detaches',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final done = Completer<String?>();
      final future = manager.open<String>(
        id: 'ext',
        present: (ctx) => PresentedOverlay<String>(dismissed: done.future),
      );
      manager.open(id: 'next', builder: (c, h) => label('NEXT'));
      await tester.pump();

      manager.close('ext', 'r'); // cannot preempt the backend -> detach
      await tester.pump();
      await tester.pump();
      expect(await future, 'r'); // orchestrator result still delivered
      expect(find.text('NEXT'), findsOneWidget); // queue advanced anyway

      manager.dispose();
    });

    testWidgets('PresentContext carries id / slot / data', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      PresentContext? seen;
      final done = Completer<void>();
      manager.open<void>(
        id: 'ctx',
        slot: 'toast',
        data: 42,
        present: (ctx) {
          seen = ctx;
          return PresentedOverlay<void>(dismissed: done.future);
        },
      );
      await tester.pump();
      expect(seen!.id, 'ctx');
      expect(seen!.slot, 'toast');
      expect(seen!.data, 42);

      manager.dispose();
    });
  });

  group('beforeClose guard — TS parity', () {
    testWidgets('returning false cancels the close; true allows it',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      var allow = false;
      manager.open(id: 'g', beforeClose: () => allow, builder: (c, h) => label('G'));
      await tester.pump();

      manager.close('g');
      await tester.pump();
      expect(manager.isShowing('g'), isTrue); // guarded

      allow = true;
      manager.close('g');
      await tester.pump();
      expect(manager.isShowing('g'), isFalse);

      manager.dispose();
    });

    testWidgets('async guard is awaited; remove() bypasses the guard',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(
        id: 'g',
        beforeClose: () async => false,
        builder: (c, h) => label('G'),
      );
      await tester.pump();
      manager.close('g');
      await tester.pump();
      await tester.pump();
      expect(manager.isShowing('g'), isTrue); // async guard vetoed

      manager.remove('g'); // bypass
      await tester.pump();
      expect(manager.isShowing('g'), isFalse);

      manager.dispose();
    });
  });

  group('affix — TS parity', () {
    testWidgets('affix blocks replace; the replacer front-bands the queue',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(id: 'fix', affix: true, builder: (c, h) => label('FIX'));
      manager.open(id: 'n', priority: 100, builder: (c, h) => label('N'));
      manager.open(id: 'r', replace: true, builder: (c, h) => label('R'));
      await tester.pump();

      expect(find.text('FIX'), findsOneWidget); // not displaced
      expect(manager.queuedIds, containsAll(<String>['n', 'r']));

      manager.close('fix');
      await tester.pump();
      expect(find.text('R'), findsOneWidget); // replace band beats priority 100

      manager.close('r');
      await tester.pump();
      expect(find.text('N'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('duplicate-id self-update is NOT blocked by affix',
        (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      manager.open(id: 'fix', affix: true, builder: (c, h) => label('V1'));
      await tester.pump();
      manager.open(id: 'fix', affix: true, builder: (c, h) => label('V2'));
      await tester.pump();
      expect(find.text('V1'), findsNothing);
      expect(find.text('V2'), findsOneWidget);

      manager.dispose();
    });
  });

  group('pause / resume — TS parity', () {
    testWidgets('pauseAll is a full freeze; resumeAll releases everything',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.pauseAll();
      manager.open(id: 's', builder: (c, h) => label('S')); // serial frozen
      manager.open(id: 'o', overlap: true, builder: (c, h) => label('O')); // held
      await tester.pump();
      expect(manager.activeIds, isEmpty);
      expect(manager.queuedIds, containsAll(<String>['s', 'o']));

      manager.resumeAll();
      await tester.pump();
      expect(find.text('S'), findsOneWidget);
      expect(find.text('O'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('pause(id)/resume(id) freeze the duration countdown',
        (tester) async {
      var t = DateTime(2026, 1, 1, 12);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      manager.open(
        id: 'p',
        duration: const Duration(seconds: 1),
        builder: (c, h) => label('P'),
      );
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 500));
      t = t.add(const Duration(milliseconds: 500));
      manager.pause('p'); // remaining = 500ms

      await tester.pump(const Duration(seconds: 3)); // frozen
      expect(manager.isShowing('p'), isTrue);

      manager.resume('p');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(manager.isShowing('p'), isFalse); // resumed with remaining time

      manager.dispose();
    });
  });

  group('pauseOnRoutes — route-zone auto pause/resume', () {
    testWidgets('entering a matching route pauses the queue; leaving resumes',
        (tester) async {
      final manager = OverlayManager(pauseOnRoutes: const ['/checkout']);
      await pumpHost(tester, manager);

      manager.setContext({'route': '/checkout'});
      manager.open(id: 'a', builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsNothing); // route zone froze activation
      expect(manager.isPaused, isTrue);

      manager.setContext({'route': '/home'});
      await tester.pump();
      expect(find.text('A'), findsOneWidget); // left the zone -> resumed
      expect(manager.isPaused, isFalse);

      manager.dispose();
    });

    testWidgets('route zone does not undo an unrelated manual pauseAll',
        (tester) async {
      final manager = OverlayManager(pauseOnRoutes: const ['/checkout']);
      await pumpHost(tester, manager);

      manager.pauseAll();
      manager.setContext({'route': '/checkout'}); // enters zone too
      manager.open(id: 'a', builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsNothing);

      manager.setContext({'route': '/home'}); // leaves zone; still manual-paused
      await tester.pump();
      expect(find.text('A'), findsNothing); // still frozen
      expect(manager.isPaused, isTrue);

      manager.resumeAll();
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('manual resumeAll does not undo an active route zone',
        (tester) async {
      final manager = OverlayManager(pauseOnRoutes: const ['/checkout']);
      await pumpHost(tester, manager);

      manager.setContext({'route': '/checkout'}); // zone active
      manager.pauseAll(); // also manually paused (redundant but legal)
      manager.resumeAll(); // clears the MANUAL pause only
      manager.open(id: 'a', builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsNothing); // route zone still holds it
      expect(manager.isPaused, isTrue);

      manager.setContext({'route': '/home'});
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      manager.dispose();
    });
  });

  group('OverlayNavigatorObserver — auto route context', () {
    // Every callback defers its setContext to a post-frame callback (see the
    // class doc) — pumpAndSettle flushes that plus the extra frame the
    // resulting OverlayEntry insertion/removal needs to actually render.
    // The observer listens to didChangeTop (the CURRENT topmost route),
    // not the legacy didPush/didPop/didReplace/didRemove quartet.
    MaterialPageRoute<void> route(String? name, {Object? arguments}) =>
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name, arguments: arguments),
          builder: (_) => const SizedBox(),
        );

    testWidgets('didChangeTop makes route-conditioned overlays eligible',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);
      final observer = OverlayNavigatorObserver(manager);

      manager.open(id: 'a', route: '/checkout', builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsNothing); // no route observed yet

      observer.didChangeTop(route('/checkout'), null);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('a later didChangeTop (e.g. after a pop) restores the '
        'previous path', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);
      final observer = OverlayNavigatorObserver(manager);

      final home = route('/home');
      final checkout = route('/checkout');
      observer.didChangeTop(home, null);
      observer.didChangeTop(checkout, home);
      await tester.pumpAndSettle();

      manager.open(id: 'a', route: '/home', builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsNothing); // currently on /checkout

      observer.didChangeTop(home, checkout); // back to /home
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('an anonymous route (no settings.name) clears the route '
        'context — dismissWhenUnmet pulls the shown overlay down',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);
      final observer = OverlayNavigatorObserver(manager);

      final home = route('/home');
      observer.didChangeTop(home, null);
      await tester.pumpAndSettle();
      manager.open(id: 'a', route: '/home', builder: (c, h) => label('A'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      observer.didChangeTop(route(null), home); // no name
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);

      manager.dispose();
    });

    testWidgets('custom pathOf overrides the default RouteSettings.name lookup',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);
      final observer = OverlayNavigatorObserver(
        manager,
        pathOf: (r) => r.settings.arguments as String?,
      );

      manager.open(id: 'a', route: '/via-args', builder: (c, h) => label('A'));
      await tester.pump();

      observer.didChangeTop(
        route('/ignored', arguments: '/via-args'),
        null,
      );
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('a throwing pathOf is reported, not propagated — route '
        'treated as unresolvable', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);
      final observer = OverlayNavigatorObserver(
        manager,
        pathOf: (r) => throw StateError('bad extractor'),
      );

      manager.open(id: 'a', route: '/checkout', builder: (c, h) => label('A'));
      await tester.pump();

      // A thrown pathOf reports via FlutterError.reportError instead of
      // propagating — swap in a no-op handler for this call so the test
      // framework doesn't treat the (expected, handled) report as a failure.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      try {
        observer.didChangeTop(route('/checkout'), null); // must not throw
      } finally {
        FlutterError.onError = originalOnError;
      }
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing); // treated as unresolvable, not '/checkout'
      expect(manager.currentRoute, isNull);

      manager.dispose();
    });

    testWidgets('a manager disposed before the deferred frame runs is never '
        'called into (no ChangeNotifier-after-dispose)', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);
      final observer = OverlayNavigatorObserver(manager);

      observer.didChangeTop(route('/checkout'), null); // queues a post-frame callback
      manager.dispose(); // disposed BEFORE the callback gets a chance to fire
      expect(manager.isDisposed, isTrue);

      // Must not throw ("used after being disposed"): the deferred callback
      // checks isDisposed and no-ops instead of calling setContext.
      await tester.pumpAndSettle();
    });
  });

  group('conditions (when / route / requiresAuth / setContext) — TS parity',
      () {
    testWidgets('route gating: waits until setContext matches', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.setContext({'route': '/home'});
      manager.open(id: 'a', route: '/target', builder: (c, h) => label('A'));
      await tester.pump();
      expect(find.text('A'), findsNothing);
      expect(manager.queuedIds, contains('a')); // waits, not dropped

      manager.setContext({'route': '/target'});
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('route supports List<String> and RegExp', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.setContext({'route': '/user/42'});
      manager.open(id: 'list', route: const ['/a', '/b'], builder: (c, h) => label('L'));
      manager.open(id: 're', route: RegExp(r'^/user/\d+$'), builder: (c, h) => label('RE'));
      await tester.pump();
      expect(find.text('L'), findsNothing);
      expect(find.text('RE'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('requiresAuth + when overrides the sugar', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.setContext({'auth': false});
      manager.open(id: 'au', requiresAuth: true, builder: (c, h) => label('AU'));
      await tester.pump();
      expect(find.text('AU'), findsNothing);

      // `when` is the sole authority: ignores mismatching route/auth.
      manager.open(
        id: 'wn',
        route: '/nope',
        requiresAuth: true,
        when: (ctx) => true,
        builder: (c, h) => label('WN'),
      );
      await tester.pump();
      expect(find.text('WN'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('dismissWhenUnmet (default) removes a shown overlay; '
        'false keeps it', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.setContext({'route': '/home'});
      manager.open(id: 'a', route: '/home', builder: (c, h) => label('A'));
      manager.open(id: 'b', builder: (c, h) => label('B')); // unconditional
      await tester.pump();
      expect(find.text('A'), findsOneWidget);

      manager.setContext({'route': '/other'}); // a no longer eligible
      await tester.pump();
      expect(find.text('A'), findsNothing); // auto-dismissed
      expect(find.text('B'), findsOneWidget); // queue advanced

      manager.setContext({'route': '/home'});
      manager.open(
        id: 'keep',
        route: '/home',
        dismissWhenUnmet: false,
        replace: true,
        builder: (c, h) => label('KEEP'),
      );
      await tester.pump();
      manager.setContext({'route': '/other'});
      await tester.pump();
      expect(find.text('KEEP'), findsOneWidget); // opted out

      manager.dispose();
    });

    testWidgets('an ineligible replace does not displace the current (5b); '
        'an ineligible overlap is dropped', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.open(id: 'keep', builder: (c, h) => label('KEEP'));
      await tester.pump();
      manager.open(
        id: 'rx',
        replace: true,
        requiresAuth: true, // auth unset -> ineligible
        builder: (c, h) => label('RX'),
      );
      await tester.pump();
      expect(find.text('KEEP'), findsOneWidget); // untouched
      expect(manager.queuedIds, contains('rx')); // waits instead

      final dropped = manager.open<String>(
        id: 'ox',
        overlap: true,
        requiresAuth: true,
        builder: (c, h) => label('OX'),
      );
      await tester.pump();
      expect(find.text('OX'), findsNothing); // now-or-never: dropped
      expect(await dropped, isNull);

      manager.dispose();
    });
  });

  group('cooldown — TS parity', () {
    testWidgets('session cap blocks the second show', (tester) async {
      final manager = OverlayManager(exitDuration: Duration.zero);
      await pumpHost(tester, manager);

      const cd = OverlayCooldown(session: 1);
      manager.open(id: 's', cooldown: cd, builder: (c, h) => label('S'));
      await tester.pump();
      manager.close('s');
      await tester.pump();

      manager.open(id: 's', cooldown: cd, builder: (c, h) => label('S2'));
      await tester.pump();
      expect(find.text('S2'), findsNothing); // capped, waits in queue
      expect(manager.queuedIds, contains('s'));

      manager.dispose();
    });

    testWidgets('minGap blocks inside the window, allows after', (tester) async {
      var t = DateTime(2026, 1, 1, 12);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      const cd = OverlayCooldown(minGap: Duration(seconds: 10));
      manager.open(id: 'g', cooldown: cd, builder: (c, h) => label('G'));
      await tester.pump();
      manager.close('g');
      await tester.pump();

      manager.open(id: 'g', cooldown: cd, builder: (c, h) => label('G2'));
      await tester.pump();
      expect(find.text('G2'), findsNothing); // inside the gap

      t = t.add(const Duration(seconds: 11));
      manager.setContext({}); // nudge re-evaluation (cooldown expiry is silent)
      await tester.pump();
      expect(find.text('G2'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('minGap auto-wakes the queued entry when it expires (no nudge)',
        (tester) async {
      var t = DateTime(2026, 1, 1, 12);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      const cd = OverlayCooldown(minGap: Duration(milliseconds: 500));
      manager.open(id: 'g', cooldown: cd, builder: (c, h) => label('G'));
      await tester.pump();
      manager.close('g');
      await tester.pump();

      manager.open(id: 'g', cooldown: cd, builder: (c, h) => label('G2'));
      await tester.pump();
      expect(find.text('G2'), findsNothing); // inside the gap → queued

      // Advance the clock and let the armed wake timer fire — crucially with
      // NO setContext nudge: a time-based cooldown wakes its own queue.
      t = t.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 520));
      expect(find.text('G2'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('a displaced overlay re-shows without re-counting its cooldown',
        (tester) async {
      var t = DateTime(2026, 1, 1, 12);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      const cd = OverlayCooldown(day: 2); // at most twice per local day

      manager.open(id: 'a', cooldown: cd, builder: (c, h) => label('A'));
      await tester.pump(); // 1st count
      manager.open(id: 'b', replace: true, builder: (c, h) => label('B'));
      await tester.pump();
      expect(manager.queuedIds, contains('a')); // displaced, not dropped

      manager.close('b');
      await tester.pump();
      expect(find.text('A'), findsOneWidget); // re-shows; the re-open is exempt
      manager.close('a');
      await tester.pump();

      // Because the displaced re-show did NOT burn a count, a genuine second
      // show is still allowed...
      manager.open(id: 'a', cooldown: cd, builder: (c, h) => label('A2'));
      await tester.pump();
      expect(find.text('A2'), findsOneWidget); // 2nd of 2
      manager.close('a');
      await tester.pump();

      // ...but the third hits the day:2 cap.
      manager.open(id: 'a', cooldown: cd, builder: (c, h) => label('A3'));
      await tester.pump();
      expect(find.text('A3'), findsNothing);

      manager.dispose();
    });

    testWidgets('day cap resets across the local midnight', (tester) async {
      var t = DateTime(2026, 1, 1, 23, 59);
      final manager =
          OverlayManager(exitDuration: Duration.zero, now: () => t);
      await pumpHost(tester, manager);

      const cd = OverlayCooldown(day: 1);
      manager.open(id: 'd', cooldown: cd, builder: (c, h) => label('D'));
      await tester.pump();
      manager.close('d');
      await tester.pump();

      manager.open(id: 'd', cooldown: cd, builder: (c, h) => label('D2'));
      await tester.pump();
      expect(find.text('D2'), findsNothing); // same day

      t = DateTime(2026, 1, 2, 0, 1); // crossed midnight
      manager.setContext({});
      await tester.pump();
      expect(find.text('D2'), findsOneWidget);

      manager.dispose();
    });

    testWidgets('total persists across manager instances via storage',
        (tester) async {
      final storage = MemoryCooldownStorage();
      const cd = OverlayCooldown(total: 1);

      final m1 = OverlayManager(
          exitDuration: Duration.zero, cooldownStorage: storage);
      await m1.ready();
      await pumpHost(tester, m1);
      m1.open(id: 't', cooldown: cd, builder: (c, h) => label('T'));
      await tester.pump(); // open + fire-and-forget persist
      await tester.pump();
      m1.dispose();

      final m2 = OverlayManager(
          exitDuration: Duration.zero, cooldownStorage: storage);
      await m2.ready(); // hydrates the persisted counter
      await pumpHost(tester, m2);
      m2.open(id: 't', cooldown: cd, builder: (c, h) => label('T2'));
      await tester.pump();
      expect(find.text('T2'), findsNothing); // total cap survived the restart

      m2.dispose();
    });
  });

  group('resolve (backend-driven data) — TS parity', () {
    testWidgets('resolved data becomes handle.data; slot is committed',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final backend = Completer<String?>();
      manager.open<String>(
        id: 'r',
        resolve: () => backend.future,
        builder: (c, h) => label('R:${h.data}'),
      );
      manager.open(id: 'hi', priority: 100, builder: (c, h) => label('HI'));
      await tester.pump();
      expect(manager.activeIds, isEmpty); // resolving, nothing visible yet
      expect(find.text('HI'), findsNothing); // cannot preempt the commitment

      backend.complete('X');
      await tester.pump();
      await tester.pump();
      expect(find.text('R:X'), findsOneWidget); // data injected
      expect(manager.queuedIds, contains('hi'));

      manager.dispose();
    });

    testWidgets('resolve returning null skips to the next', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      final skipped = manager.open<String>(
        id: 'r',
        resolve: () async => null,
        builder: (c, h) => label('R'),
      );
      manager.open(id: 'next', builder: (c, h) => label('NEXT'));
      await tester.pump();
      await tester.pump();
      expect(find.text('R'), findsNothing);
      expect(find.text('NEXT'), findsOneWidget);
      expect(await skipped, isNull);

      manager.dispose();
    });
  });

  group('update / clearWhere — TS parity', () {
    testWidgets('update(id, patch) shallow-merges data and rebuilds',
        (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.open(
        id: 'u',
        data: {'n': 1, 'keep': 'x'},
        builder: (c, h) {
          final d = h.data as Map;
          return label('n=${d['n']} keep=${d['keep']}');
        },
      );
      await tester.pump();
      expect(find.text('n=1 keep=x'), findsOneWidget);

      manager.update('u', {'n': 2});
      await tester.pump();
      expect(find.text('n=2 keep=x'), findsOneWidget); // merged in place

      manager.dispose();
    });

    testWidgets('clearWhere removes matching entries only', (tester) async {
      final manager = OverlayManager();
      await pumpHost(tester, manager);

      manager.open(id: 'keep', builder: (c, h) => label('KEEP'));
      manager.open(id: 'drop-1', data: {'group': 'x'}, builder: (c, h) => label('D1'));
      manager.open(
          id: 'drop-2',
          slot: 'toast',
          data: {'group': 'x'},
          builder: (c, h) => label('D2'));
      await tester.pump();

      manager.clearWhere(
          (r) => r.data is Map && (r.data as Map)['group'] == 'x');
      await tester.pump();
      expect(manager.isShowing('keep'), isTrue);
      expect(manager.queuedIds, isEmpty);
      expect(find.text('D2'), findsNothing);

      manager.dispose();
    });
  });

  testWidgets('phase transitions from open to closing on close', (tester) async {
    final manager =
        OverlayManager(exitDuration: const Duration(milliseconds: 200));
    await pumpHost(tester, manager);

    late OverlayHandle<void> captured;
    manager.open<void>(
      id: 'p',
      builder: (c, h) {
        captured = h;
        return label('P');
      },
    );
    await tester.pump();
    expect(captured.phase, OverlayPhase.open);

    manager.close('p');
    await tester.pump();
    expect(captured.phase, OverlayPhase.closing);

    await tester.pump(const Duration(milliseconds: 200));
    manager.dispose();
  });
}
