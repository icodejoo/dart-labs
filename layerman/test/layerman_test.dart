import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerman/layerman.dart';

/// Simulates an external overlay backend (showDialog / GetX / bot_toast):
/// [present] is what the orchestrator calls when the queue grants permission;
/// [userClose] simulates the user closing the backend directly (barrier tap,
/// back button, timeout); [dismiss] is the orchestrator-driven graceful close.
class _FakeBackend<T> {
  final Completer<T?> _dismissed = Completer<T?>();
  bool presented = false;
  bool dismissCalled = false;

  /// The [Present] callback: hand this straight to `open(present: ...)`.
  PresentedOverlay<T> present(PresentContext context) {
    presented = true;
    return PresentedOverlay<T>(
      dismissed: _dismissed.future,
      dismiss: ([T? result]) async {
        dismissCalled = true;
        if (!_dismissed.isCompleted) _dismissed.complete(result);
      },
    );
  }

  /// Simulate the backend closing itself (user tap, barrier, back button,
  /// timeout) without going through the orchestrator's `dismiss`.
  void userClose(T? result) {
    if (!_dismissed.isCompleted) _dismissed.complete(result);
  }
}

void main() {
  testWidgets('serial: only one overlay shows at a time; the rest queue',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final a = _FakeBackend<String>();
    final b = _FakeBackend<String>();
    manager.open(id: 'a', present: a.present);
    manager.open(id: 'b', present: b.present);
    await tester.pump();

    expect(a.presented, isTrue);
    expect(b.presented, isFalse);
    expect(manager.activeIds, <String>['a']);
    expect(manager.queuedIds, <String>['b']);

    manager.dispose();
  });

  testWidgets('closing the active overlay advances to the next',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final a = _FakeBackend<String>();
    final b = _FakeBackend<String>();
    manager.open(
      id: 'a',
      present: a.present,
      exitDuration: const Duration(milliseconds: 100),
    );
    manager.open(id: 'b', present: b.present);
    await tester.pump();
    expect(manager.isShowing('a'), isTrue);

    manager.close('a');
    await tester.pump(); // phase -> closing (exit grace pending)
    expect(manager.isShowing('a'), isTrue); // still in closing phase
    await tester.pump(
        const Duration(milliseconds: 100)); // exit -> removed + next shown

    expect(manager.isShowing('a'), isFalse);
    expect(b.presented, isTrue);
    expect(manager.activeIds, <String>['b']);

    manager.dispose();
  });

  testWidgets('priority: higher priority shows before lower when slot frees',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final a = _FakeBackend<String>();
    final low = _FakeBackend<String>();
    final high = _FakeBackend<String>();
    manager.open(id: 'a', present: a.present); // activates now
    manager.open(id: 'low', priority: 1, present: low.present);
    manager.open(id: 'high', priority: 10, present: high.present);
    await tester.pump();
    expect(manager.isShowing('a'), isTrue);

    manager.close('a');
    await tester.pump(); // exit immediate (default) -> removed + next shown
    expect(manager.isShowing('high'), isTrue);
    expect(manager.isShowing('low'), isFalse);

    manager.close('high');
    await tester.pump();
    expect(manager.isShowing('low'), isTrue);

    manager.dispose();
  });

  testWidgets('show returns a Future that resolves with the close result',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final backend = _FakeBackend<String>();
    final future =
        manager.open<String>(id: 'confirm', present: backend.present);
    await tester.pump();
    expect(backend.presented, isTrue);

    backend.userClose('yes'); // e.g. the backend's own "OK" button
    await tester.pump();

    expect(await future, 'yes');

    manager.dispose();
  });

  testWidgets('manager.close(id, value) also delivers the result',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final backend = _FakeBackend<int>();
    final future = manager.open<int>(id: 'n', present: backend.present);
    await tester.pump();

    manager.close('n', 42);
    await tester.pump();

    expect(await future, 42);

    manager.dispose();
  });

  testWidgets('dismiss / no-result close resolves the Future with null',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final backend = _FakeBackend<String>();
    final future = manager.open<String>(id: 'x', present: backend.present);
    await tester.pump();

    manager.dismiss('x');
    await tester.pump();

    expect(await future, isNull);

    manager.dispose();
  });

  testWidgets('replace: preempts the current overlay, closing it (result null)',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final a = _FakeBackend<String>();
    final b = _FakeBackend<String>();
    final aFuture = manager.open<String>(id: 'a', present: a.present);
    await tester.pump();
    expect(manager.isShowing('a'), isTrue);

    manager.open(id: 'b', replace: true, present: b.present);
    await tester.pump();

    expect(manager.isShowing('a'), isFalse);
    expect(manager.isShowing('b'), isTrue);
    expect(await aFuture, isNull); // preempted -> closed with null, not requeued
    expect(manager.queuedIds, isNot(contains('a')));

    manager.close('b');
    await tester.pump();
    expect(manager.activeIds, isEmpty); // 'a' does NOT resume; it is gone for good

    manager.dispose();
  });

  testWidgets('replace closes the current AND front-bands ahead of queued',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final a = _FakeBackend<String>();
    final b = _FakeBackend<String>();
    final r = _FakeBackend<String>();
    final aFuture = manager.open<String>(id: 'a', present: a.present); // active
    manager.open(id: 'b', present: b.present); // queued first
    manager.open(id: 'r', replace: true, present: r.present);
    await tester.pump();

    expect(manager.isShowing('r'), isTrue); // preempts A AND outranks queued B
    expect(manager.isShowing('a'), isFalse);
    expect(await aFuture, isNull); // closed for good, not requeued
    expect(manager.queuedIds, <String>['b']); // only b still waits

    manager.close('r');
    await tester.pump();
    expect(manager.isShowing('b'), isTrue); // next in queue — NOT the closed 'a'

    manager.dispose();
  });

  group('replace closes the preempted entry — regression (code-review)', () {
    testWidgets('replacing a RESOLVING entry discards it — resolver never '
        'runs twice and stale data never opens', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      var calls = 0;
      var presented = false;
      final backend = Completer<String?>();
      final aFuture = manager.open<String>(
        id: 'a',
        resolve: () {
          calls++;
          return backend.future;
        },
        present: (ctx) {
          presented = true;
          return PresentedOverlay<String>(dismissed: Completer<String?>().future);
        },
      );
      await tester.pump();
      expect(manager.activeIds, isEmpty); // resolving, nothing shown
      expect(calls, 1);

      final b = _FakeBackend<String>();
      manager.open(id: 'b', replace: true, present: b.present);
      await tester.pump();
      expect(manager.isShowing('b'), isTrue);
      expect(manager.queuedIds, isNot(contains('a'))); // discarded, not displaced
      expect(await aFuture, isNull); // settled null

      backend.complete('X'); // the stale resolver finishes late
      await tester.pump();
      expect(calls, 1); // NOT re-run
      expect(presented, isFalse); // stale payload never opens

      manager.dispose();
    });

    testWidgets("a queued entry's close() is a no-op until it is actually shown",
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final a = _FakeBackend<String>();
      final q = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      final qFuture = manager.open<String>(id: 'q', present: q.present);
      await tester.pump();
      expect(manager.queuedIds, contains('q'));

      manager.close('q', 'x'); // never shown -> no-op
      await tester.pump();
      expect(manager.queuedIds, contains('q')); // still queued
      expect(qFuture, isA<Future<String?>>()); // not settled

      manager.close('a');
      await tester.pump();
      expect(manager.isShowing('q'), isTrue); // it eventually shows

      manager.dispose();
    });

    testWidgets('clear() cancels an armed cooldown wake timer', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var t = DateTime(2026, 1, 1, 12);
      final manager = Layerman(now: () => t);

      const cd = OverlayCooldown(minGap: Duration(seconds: 1));
      final g1 = _FakeBackend<String>();
      manager.open(id: 'g', cooldown: cd, present: g1.present);
      await tester.pump();
      manager.close('g');
      await tester.pump();
      final g2 = _FakeBackend<String>();
      manager.open(id: 'g', cooldown: cd, present: g2.present);
      await tester.pump();
      expect(g2.presented, isFalse); // queued, wake timer armed

      manager.clear(); // must cancel the armed timer

      var ticked = false;
      manager.addListener(() => ticked = true);
      t = t.add(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 1200)); // past the old wake
      expect(ticked, isFalse); // no stray notify from a surviving timer
      expect(manager.queuedIds, isEmpty);

      manager.dispose();
    });

    testWidgets(
        'a beforeClose guard pending when a replace discards the entry is '
        'safely ignored — no double-settle, no crash', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final guardVerdict = Completer<bool>();
      final a = _FakeBackend<String>();
      final aFuture = manager.open<String>(
        id: 'a',
        beforeClose: () => guardVerdict.future,
        present: a.present,
      );
      await tester.pump();

      manager.close('a', 'done'); // guard in flight, entry still open

      final b = _FakeBackend<String>();
      manager.open(id: 'b', replace: true, present: b.present);
      await tester.pump();
      expect(manager.isShowing('b'), isTrue);
      expect(await aFuture, isNull); // discarded by the replace before the guard settled

      guardVerdict.complete(true); // late verdict must not resurrect/re-settle 'a'
      await tester.pump();
      await tester.pump();
      expect(await aFuture, isNull); // unchanged

      manager.dispose();
    });
  });

  testWidgets('overlap: bypasses the queue and stacks on top', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final a = _FakeBackend<String>();
    final top = _FakeBackend<String>();
    manager.open(id: 'a', present: a.present);
    manager.open(id: 'top', overlap: true, present: top.present);
    await tester.pump();

    expect(manager.isShowing('a'), isTrue);
    expect(manager.isShowing('top'), isTrue); // both shown simultaneously
    expect(manager.activeIds, containsAll(<String>['a', 'top']));

    manager.dispose();
  });

  testWidgets('duration: overlay auto-closes after its duration elapses',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final backend = _FakeBackend<String>();
    manager.open(
      id: 't',
      duration: const Duration(milliseconds: 500),
      present: backend.present,
    );
    await tester.pump();
    expect(manager.isShowing('t'), isTrue);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(manager.isShowing('t'), isFalse);

    manager.dispose();
  });

  testWidgets('gap: next overlay waits the gap after the previous is removed',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman(gap: const Duration(milliseconds: 300));

    final a = _FakeBackend<String>();
    final b = _FakeBackend<String>();
    manager.open(id: 'a', present: a.present);
    manager.open(id: 'b', present: b.present);
    await tester.pump();
    expect(manager.isShowing('a'), isTrue);

    manager.close('a');
    await tester.pump(); // A removed, gap timer armed
    expect(manager.isShowing('a'), isFalse);
    expect(b.presented, isFalse); // still waiting out the gap

    await tester.pump(const Duration(milliseconds: 300));
    expect(b.presented, isTrue);

    manager.dispose();
  });

  testWidgets('named slots run independent serial queues', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final manager = Layerman();

    final t = _FakeBackend<String>();
    final s = _FakeBackend<String>();
    manager.open(id: 't', slot: 'toast', present: t.present);
    manager.open(id: 's', slot: 'sheet', present: s.present);
    await tester.pump();

    // Different slots -> both active at once.
    expect(t.presented, isTrue);
    expect(s.presented, isTrue);

    manager.dispose();
  });

  group('timing (delay / gap / exitDuration) — TS parity', () {
    testWidgets('delay: waits before appearing, even for the first overlay',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final d = _FakeBackend<String>();
      manager.open(
        id: 'd',
        delay: const Duration(milliseconds: 200),
        present: d.present,
      );
      await tester.pump();
      expect(d.presented, isFalse); // cold start also honors delay
      expect(manager.queuedIds, contains('d'));

      await tester.pump(const Duration(milliseconds: 200));
      expect(d.presented, isTrue);

      manager.dispose();
    });

    testWidgets('replace during the gap skips the remaining gap (TS rule)',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman(gap: const Duration(milliseconds: 300));

      final a = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      await tester.pump();
      manager.close('a');
      await tester.pump(); // removed; gap timer armed

      final r = _FakeBackend<String>();
      manager.open(id: 'r', replace: true, present: r.present);
      await tester.pump();
      expect(r.presented, isTrue); // did NOT wait out the gap

      manager.dispose();
    });

    testWidgets('exitDuration is configured per-open, independently of any '
        'other entry', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final x = _FakeBackend<String>();
      manager.open(
        id: 'x',
        exitDuration: const Duration(milliseconds: 400),
        present: x.present,
      );
      await tester.pump();
      manager.close('x');
      await tester.pump(const Duration(milliseconds: 200));
      expect(manager.isShowing('x'), isTrue); // grace still running
      await tester.pump(const Duration(milliseconds: 200));
      expect(manager.isShowing('x'), isFalse);

      manager.dispose();
    });

    testWidgets('manual close cancels the pending duration timer',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
      final future = manager.open<String>(
        id: 't',
        duration: const Duration(milliseconds: 500),
        present: backend.present,
      );
      await tester.pump();
      manager.close('t', 'manual');
      await tester.pump();
      expect(await future, 'manual'); // not overwritten by the timer
      await tester.pump(const Duration(milliseconds: 600)); // timer must be dead
      expect(manager.activeIds, isEmpty);

      manager.dispose();
    });

    testWidgets(
        'delay is not bypassed when a second entry is enqueued during the delay',
        (tester) async {
      // Regression: _schedule re-picked the front entry after a second open()
      // triggered it. delayConsumed=true caused the delay to be skipped and
      // the entry to activate immediately.
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final slow = _FakeBackend<String>();
      manager.open(
        id: 'slow',
        delay: const Duration(milliseconds: 300),
        present: slow.present,
      );
      await tester.pump(); // delay timer armed; nothing presented yet
      expect(slow.presented, isFalse);

      // Enqueue a second entry — must NOT cause SLOW to bypass its delay.
      final fast = _FakeBackend<String>();
      manager.open(
        id: 'fast',
        delay: const Duration(milliseconds: 100),
        present: fast.present,
      );
      await tester.pump();
      expect(slow.presented, isFalse); // delay still in progress

      // After SLOW's full delay, it activates (FAST waits behind it).
      await tester.pump(const Duration(milliseconds: 300));
      expect(slow.presented, isTrue);
      expect(fast.presented, isFalse);

      manager.dispose();
    });

    testWidgets('replace during an appear delay skips the delay (TS rule)',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final delayed = _FakeBackend<String>();
      manager.open(
        id: 'delayed',
        delay: const Duration(milliseconds: 300),
        present: delayed.present,
      );
      await tester.pump(); // delay timer armed
      expect(delayed.presented, isFalse);

      // A replace entry: must cancel the delay and activate immediately.
      final r = _FakeBackend<String>();
      manager.open(id: 'r', replace: true, present: r.present);
      await tester.pump();
      expect(r.presented, isTrue); // jumped ahead without waiting

      manager.dispose();
    });
  });

  group('priority & ordering — TS parity', () {
    testWidgets('equal priority breaks ties FIFO', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final a = _FakeBackend<String>();
      final first = _FakeBackend<String>();
      final second = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      manager.open(id: 'first', priority: 5, present: first.present);
      manager.open(id: 'second', priority: 5, present: second.present);
      await tester.pump();

      manager.close('a');
      await tester.pump();
      expect(manager.isShowing('first'), isTrue);
      manager.close('first');
      await tester.pump();
      expect(manager.isShowing('second'), isTrue);

      manager.dispose();
    });
  });

  group('duplicate id — TS parity', () {
    testWidgets('reusing an active id replaces in place (old result null)',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final v1 = _FakeBackend<String>();
      final v2 = _FakeBackend<String>();
      final first = manager.open<String>(id: 'dup', present: v1.present);
      await tester.pump();
      expect(manager.isShowing('dup'), isTrue);
      expect(v1.presented, isTrue);

      final second = manager.open<String>(id: 'dup', present: v2.present);
      await tester.pump();
      expect(v2.presented, isTrue); // shown immediately, no queue trip
      expect(manager.queuedIds, isEmpty);
      expect(await first, isNull); // old handle settled

      manager.close('dup', 'v');
      await tester.pump();
      expect(await second, 'v');

      manager.dispose();
    });

    testWidgets('reusing a queued id overrides the queued entry',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final block = _FakeBackend<String>();
      final q1 = _FakeBackend<String>();
      final q2 = _FakeBackend<String>();
      manager.open(id: 'block', present: block.present);
      final old = manager.open<String>(id: 'dup', present: q1.present);
      manager.open(id: 'dup', present: q2.present);
      await tester.pump();
      expect(await old, isNull); // overridden while queued

      manager.close('block');
      await tester.pump();
      expect(q1.presented, isFalse);
      expect(q2.presented, isTrue); // new config won

      manager.dispose();
    });
  });

  group('lifecycle & results — TS parity', () {
    testWidgets('close on a queued id is a no-op; remove takes it out',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final a = _FakeBackend<String>();
      final q = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      final queued = manager.open<String>(id: 'q', present: q.present);
      await tester.pump();

      manager.close('q'); // not open -> no-op
      await tester.pump();
      expect(manager.queuedIds, contains('q'));
      expect(manager.isShowing('a'), isTrue);

      manager.remove('q');
      await tester.pump();
      expect(manager.queuedIds, isEmpty);
      expect(await queued, isNull);
      expect(manager.isShowing('a'), isTrue); // current untouched

      manager.dispose();
    });

    testWidgets('clear(): everything removed, all pending results resolve null',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final a = _FakeBackend<String>();
      final b = _FakeBackend<String>();
      final o = _FakeBackend<String>();
      final f1 = manager.open<String>(id: 'a', present: a.present);
      final f2 = manager.open<String>(id: 'b', present: b.present);
      final f3 =
          manager.open<String>(id: 'o', overlap: true, present: o.present);
      await tester.pump();

      manager.clear();
      await tester.pump();
      expect(manager.activeIds, isEmpty);
      expect(manager.queuedIds, isEmpty);
      expect(await f1, isNull);
      expect(await f2, isNull);
      expect(await f3, isNull);

      manager.dispose();
    });

    testWidgets('data carries the opaque payload into PresentContext',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      Object? seen;
      manager.open(
        id: 'd',
        data: {'kind': 'promo'},
        present: (ctx) {
          seen = ctx.data;
          return PresentedOverlay<void>(dismissed: Completer<void>().future);
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final base = _FakeBackend<String>();
      final o1 = _FakeBackend<String>();
      final o2 = _FakeBackend<String>();
      manager.open(id: 'base', present: base.present);
      manager.open(id: 'o1', overlap: true, present: o1.present);
      manager.open(id: 'o2', overlap: true, present: o2.present);
      await tester.pump();
      expect(base.presented, isTrue);
      expect(o1.presented, isTrue);
      expect(o2.presented, isTrue);

      manager.close('o1');
      await tester.pump();
      expect(manager.isShowing('o1'), isFalse);
      expect(manager.isShowing('o2'), isTrue); // others untouched
      expect(manager.isShowing('base'), isTrue); // serial slot untouched

      manager.dispose();
    });

    testWidgets('overlap honors duration auto-close', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
      manager.open(
        id: 'o',
        overlap: true,
        duration: const Duration(milliseconds: 300),
        present: backend.present,
      );
      await tester.pump();
      expect(manager.isShowing('o'), isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(manager.isShowing('o'), isFalse);

      manager.dispose();
    });
  });

  group('introspection & notifications — TS parity', () {
    testWidgets('ChangeNotifier fires on transitions', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      var ticks = 0;
      manager.addListener(() => ticks++);
      final a = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      await tester.pump();
      final afterShow = ticks;
      expect(afterShow, greaterThan(0));

      manager.close('a');
      await tester.pump();
      expect(ticks, greaterThan(afterShow));

      manager.dispose();
    });

    testWidgets('currentRoute mirrors the route key set via setContext',
        (tester) async {
      final manager = Layerman();
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final a = _FakeBackend<String>();
      final backend = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
      final future = manager.open<String>(id: 'ext', present: backend.present);
      final next = _FakeBackend<String>();
      manager.open(id: 'next', present: next.present);
      await tester.pump();
      expect(backend.presented, isTrue);
      expect(next.presented, isFalse);

      backend.userClose('yes'); // e.g. barrier tap / back button / timeout
      await tester.pump(); // flush the dismissed microtask -> queue advances
      await tester.pump(); // let the newly activated 'next' present

      expect(await future, 'yes');
      expect(next.presented, isTrue); // queue advanced

      manager.dispose();
    });

    testWidgets('manager.close drives the backend dismiss handle',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
      final future = manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();

      manager.close('ext', 'r');
      await tester.pump();

      expect(backend.dismissCalled, isTrue); // graceful, targeted close
      expect(await future, 'r'); // orchestrator result wins
      expect(manager.activeIds, isEmpty);

      manager.dispose();
    });

    testWidgets('external entries work without any widget ever being pumped',
        (tester) async {
      final manager = Layerman(); // no pumpWidget at all
      final backend = _FakeBackend<String>();
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
      final extFuture =
          manager.open<String>(id: 'ext', present: backend.present);
      await tester.pump();
      expect(backend.presented, isTrue);

      final b = _FakeBackend<String>();
      manager.open(id: 'b', replace: true, present: b.present);
      await tester.pump();

      expect(backend.dismissCalled, isTrue); // backend asked to close
      expect(await extFuture, isNull); // preempted -> null
      expect(b.presented, isTrue);

      manager.dispose();
    });

    testWidgets('exitDuration acts as post-dismiss grace before advancing',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
      manager.open<String>(
        id: 'ext',
        present: backend.present,
        exitDuration: const Duration(milliseconds: 100),
      );
      final next = _FakeBackend<String>();
      manager.open(id: 'next', present: next.present);
      await tester.pump();

      backend.userClose(null); // route future completes at animation start
      await tester.pump();
      expect(next.presented, isFalse); // grace: exit anim still playing

      await tester.pump(const Duration(milliseconds: 100));
      expect(next.presented, isTrue);

      manager.dispose();
    });

    testWidgets('clear() best-effort dismisses external backends',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final base = _FakeBackend<String>();
      final backend = _FakeBackend<String>();
      manager.open(id: 'base', present: base.present);
      manager.open<String>(id: 'ext', overlap: true, present: backend.present);
      await tester.pump();

      expect(base.presented, isTrue); // serial slot untouched
      expect(backend.presented, isTrue); // presented immediately, no queue
      expect(manager.activeIds, containsAll(<String>['base', 'ext']));

      manager.dispose();
    });

    testWidgets('external duration auto-close drives the backend dismiss',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = _FakeBackend<String>();
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final done = Completer<String?>();
      final future = manager.open<String>(
        id: 'ext',
        present: (ctx) => PresentedOverlay<String>(dismissed: done.future),
      );
      final next = _FakeBackend<String>();
      manager.open(id: 'next', present: next.present);
      await tester.pump();

      manager.close('ext', 'r'); // cannot preempt the backend -> detach
      await tester.pump();
      await tester.pump();
      expect(await future, 'r'); // orchestrator result still delivered
      expect(next.presented, isTrue); // queue advanced anyway

      manager.dispose();
    });

    testWidgets('PresentContext carries id / slot / data', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      var allow = false;
      final g = _FakeBackend<String>();
      manager.open(id: 'g', beforeClose: () => allow, present: g.present);
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final g = _FakeBackend<String>();
      manager.open(
        id: 'g',
        beforeClose: () async => false,
        present: g.present,
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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final fix = _FakeBackend<String>();
      final n = _FakeBackend<String>();
      final r = _FakeBackend<String>();
      manager.open(id: 'fix', affix: true, present: fix.present);
      manager.open(id: 'n', priority: 100, present: n.present);
      manager.open(id: 'r', replace: true, present: r.present);
      await tester.pump();

      expect(manager.isShowing('fix'), isTrue); // not displaced
      expect(manager.queuedIds, containsAll(<String>['n', 'r']));

      manager.close('fix');
      await tester.pump();
      expect(manager.isShowing('r'), isTrue); // replace band beats priority 100

      manager.close('r');
      await tester.pump();
      expect(manager.isShowing('n'), isTrue);

      manager.dispose();
    });

    testWidgets('duplicate-id self-update is NOT blocked by affix',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final v1 = _FakeBackend<String>();
      final v2 = _FakeBackend<String>();
      manager.open(id: 'fix', affix: true, present: v1.present);
      await tester.pump();
      manager.open(id: 'fix', affix: true, present: v2.present);
      await tester.pump();
      expect(v2.presented, isTrue);
      expect(manager.isShowing('fix'), isTrue);

      manager.dispose();
    });
  });

  group('pause / resume — TS parity', () {
    testWidgets('pauseAll is a full freeze; resumeAll releases everything',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      manager.pauseAll();
      final s = _FakeBackend<String>();
      final o = _FakeBackend<String>();
      manager.open(id: 's', present: s.present); // serial frozen
      manager.open(id: 'o', overlap: true, present: o.present); // held
      await tester.pump();
      expect(manager.activeIds, isEmpty);
      expect(manager.queuedIds, containsAll(<String>['s', 'o']));

      manager.resumeAll();
      await tester.pump();
      expect(s.presented, isTrue);
      expect(o.presented, isTrue);

      manager.dispose();
    });

    testWidgets('pause(id)/resume(id) freeze the duration countdown',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      var t = DateTime(2026, 1, 1, 12);
      final manager = Layerman(now: () => t);

      final backend = _FakeBackend<String>();
      manager.open(
        id: 'p',
        duration: const Duration(seconds: 1),
        present: backend.present,
      );
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 500));
      t = t.add(const Duration(milliseconds: 500));
      manager.pause('p'); // remaining = 500ms

      await tester.pump(const Duration(seconds: 3)); // frozen
      expect(manager.isShowing('p'), isTrue);

      manager.resume('p');
      await tester.pump(const Duration(milliseconds: 500));
      expect(manager.isShowing('p'), isFalse); // resumed with remaining time

      manager.dispose();
    });
  });

  group('pauseOnRoutes — route-zone auto pause/resume', () {
    testWidgets('entering a matching route pauses the queue; leaving resumes',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman(pauseOnRoutes: const ['/checkout']);

      manager.setContext({'route': '/checkout'});
      final a = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      await tester.pump();
      expect(a.presented, isFalse); // route zone froze activation
      expect(manager.isPaused, isTrue);

      manager.setContext({'route': '/home'});
      await tester.pump();
      expect(a.presented, isTrue); // left the zone -> resumed
      expect(manager.isPaused, isFalse);

      manager.dispose();
    });

    testWidgets('route zone does not undo an unrelated manual pauseAll',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman(pauseOnRoutes: const ['/checkout']);

      manager.pauseAll();
      manager.setContext({'route': '/checkout'}); // enters zone too
      final a = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      await tester.pump();
      expect(a.presented, isFalse);

      manager.setContext({'route': '/home'}); // leaves zone; still manual-paused
      await tester.pump();
      expect(a.presented, isFalse); // still frozen
      expect(manager.isPaused, isTrue);

      manager.resumeAll();
      await tester.pump();
      expect(a.presented, isTrue);

      manager.dispose();
    });

    testWidgets('manual resumeAll does not undo an active route zone',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman(pauseOnRoutes: const ['/checkout']);

      manager.setContext({'route': '/checkout'}); // zone active
      manager.pauseAll(); // also manually paused (redundant but legal)
      manager.resumeAll(); // clears the MANUAL pause only
      final a = _FakeBackend<String>();
      manager.open(id: 'a', present: a.present);
      await tester.pump();
      expect(a.presented, isFalse); // route zone still holds it
      expect(manager.isPaused, isTrue);

      manager.setContext({'route': '/home'});
      await tester.pump();
      expect(a.presented, isTrue);

      manager.dispose();
    });
  });

  group('LayermanNavigatorObserver — auto route context', () {
    // Every callback defers its setContext to a post-frame callback (see the
    // class doc) — pumpAndSettle flushes that plus the extra frame needed to
    // observe the resulting state change. The observer listens to
    // didChangeTop (the CURRENT topmost route), not the legacy
    // didPush/didPop/didReplace/didRemove quartet.
    MaterialPageRoute<void> route(String? name, {Object? arguments}) =>
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name, arguments: arguments),
          builder: (_) => const SizedBox(),
        );

    testWidgets('didChangeTop makes route-conditioned overlays eligible',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();
      final observer = LayermanNavigatorObserver(manager);

      final a = _FakeBackend<String>();
      manager.open(id: 'a', route: '/checkout', present: a.present);
      await tester.pump();
      expect(a.presented, isFalse); // no route observed yet

      observer.didChangeTop(route('/checkout'), null);
      await tester.pumpAndSettle();
      expect(a.presented, isTrue);

      manager.dispose();
    });

    testWidgets('a later didChangeTop (e.g. after a pop) restores the '
        'previous path', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();
      final observer = LayermanNavigatorObserver(manager);

      final home = route('/home');
      final checkout = route('/checkout');
      observer.didChangeTop(home, null);
      observer.didChangeTop(checkout, home);
      await tester.pumpAndSettle();

      final a = _FakeBackend<String>();
      manager.open(id: 'a', route: '/home', present: a.present);
      await tester.pump();
      expect(a.presented, isFalse); // currently on /checkout

      observer.didChangeTop(home, checkout); // back to /home
      await tester.pumpAndSettle();
      expect(a.presented, isTrue);

      manager.dispose();
    });

    testWidgets('an anonymous route (no settings.name) clears the route '
        'context — dismissWhenUnmet pulls the shown overlay down',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();
      final observer = LayermanNavigatorObserver(manager);

      final home = route('/home');
      observer.didChangeTop(home, null);
      await tester.pumpAndSettle();
      final a = _FakeBackend<String>();
      manager.open(id: 'a', route: '/home', present: a.present);
      await tester.pumpAndSettle();
      expect(manager.isShowing('a'), isTrue);

      observer.didChangeTop(route(null), home); // no name
      await tester.pumpAndSettle();
      expect(manager.isShowing('a'), isFalse);

      manager.dispose();
    });

    testWidgets('custom pathOf overrides the default RouteSettings.name lookup',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();
      final observer = LayermanNavigatorObserver(
        manager,
        pathOf: (r) => r.settings.arguments as String?,
      );

      final a = _FakeBackend<String>();
      manager.open(id: 'a', route: '/via-args', present: a.present);
      await tester.pump();

      observer.didChangeTop(
        route('/ignored', arguments: '/via-args'),
        null,
      );
      await tester.pumpAndSettle();
      expect(a.presented, isTrue);

      manager.dispose();
    });

    testWidgets('a throwing pathOf is reported, not propagated — route '
        'treated as unresolvable', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();
      final observer = LayermanNavigatorObserver(
        manager,
        pathOf: (r) => throw StateError('bad extractor'),
      );

      final a = _FakeBackend<String>();
      manager.open(id: 'a', route: '/checkout', present: a.present);
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
      expect(a.presented, isFalse); // treated as unresolvable, not '/checkout'
      expect(manager.currentRoute, isNull);

      manager.dispose();
    });

    testWidgets('a manager disposed before the deferred frame runs is never '
        'called into (no ChangeNotifier-after-dispose)', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();
      final observer = LayermanNavigatorObserver(manager);

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
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      manager.setContext({'route': '/home'});
      final a = _FakeBackend<String>();
      manager.open(id: 'a', route: '/target', present: a.present);
      await tester.pump();
      expect(a.presented, isFalse);
      expect(manager.queuedIds, contains('a')); // waits, not dropped

      manager.setContext({'route': '/target'});
      await tester.pump();
      expect(a.presented, isTrue);

      manager.dispose();
    });

    testWidgets('route supports List<String> and RegExp', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      manager.setContext({'route': '/user/42'});
      final list = _FakeBackend<String>();
      final re = _FakeBackend<String>();
      manager.open(id: 'list', route: const ['/a', '/b'], present: list.present);
      manager.open(
          id: 're', route: RegExp(r'^/user/\d+$'), present: re.present);
      await tester.pump();
      expect(list.presented, isFalse);
      expect(re.presented, isTrue);

      manager.dispose();
    });

    testWidgets('requiresAuth + when overrides the sugar', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      manager.setContext({'auth': false});
      final au = _FakeBackend<String>();
      manager.open(id: 'au', requiresAuth: true, present: au.present);
      await tester.pump();
      expect(au.presented, isFalse);

      // `when` is the sole authority: ignores mismatching route/auth.
      final wn = _FakeBackend<String>();
      manager.open(
        id: 'wn',
        route: '/nope',
        requiresAuth: true,
        when: (ctx) => true,
        present: wn.present,
      );
      await tester.pump();
      expect(wn.presented, isTrue);

      manager.dispose();
    });

    testWidgets('dismissWhenUnmet (default) removes a shown overlay; '
        'false keeps it', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      manager.setContext({'route': '/home'});
      final a = _FakeBackend<String>();
      final b = _FakeBackend<String>();
      manager.open(id: 'a', route: '/home', present: a.present);
      manager.open(id: 'b', present: b.present); // unconditional
      await tester.pump();
      expect(manager.isShowing('a'), isTrue);

      manager.setContext({'route': '/other'}); // a no longer eligible
      await tester.pump();
      expect(manager.isShowing('a'), isFalse); // auto-dismissed
      expect(b.presented, isTrue); // queue advanced

      manager.setContext({'route': '/home'});
      final keep = _FakeBackend<String>();
      manager.open(
        id: 'keep',
        route: '/home',
        dismissWhenUnmet: false,
        replace: true,
        present: keep.present,
      );
      await tester.pump();
      manager.setContext({'route': '/other'});
      await tester.pump();
      expect(manager.isShowing('keep'), isTrue); // opted out

      manager.dispose();
    });

    testWidgets('an ineligible replace does not displace the current (5b); '
        'an ineligible overlap is dropped', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final keep = _FakeBackend<String>();
      manager.open(id: 'keep', present: keep.present);
      await tester.pump();
      final rx = _FakeBackend<String>();
      manager.open(
        id: 'rx',
        replace: true,
        requiresAuth: true, // auth unset -> ineligible
        present: rx.present,
      );
      await tester.pump();
      expect(manager.isShowing('keep'), isTrue); // untouched
      expect(manager.queuedIds, contains('rx')); // waits instead

      var oxPresented = false;
      final dropped = manager.open<String>(
        id: 'ox',
        overlap: true,
        requiresAuth: true,
        present: (ctx) {
          oxPresented = true;
          return PresentedOverlay<String>(dismissed: Completer<String?>().future);
        },
      );
      await tester.pump();
      expect(oxPresented, isFalse); // now-or-never: dropped
      expect(await dropped, isNull);

      manager.dispose();
    });
  });

  group('cooldown — TS parity', () {
    testWidgets('session cap blocks the second show', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      const cd = OverlayCooldown(session: 1);
      final s1 = _FakeBackend<String>();
      manager.open(id: 's', cooldown: cd, present: s1.present);
      await tester.pump();
      manager.close('s');
      await tester.pump();

      final s2 = _FakeBackend<String>();
      manager.open(id: 's', cooldown: cd, present: s2.present);
      await tester.pump();
      expect(s2.presented, isFalse); // capped, waits in queue
      expect(manager.queuedIds, contains('s'));

      manager.dispose();
    });

    testWidgets('minGap blocks inside the window, allows after', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var t = DateTime(2026, 1, 1, 12);
      final manager = Layerman(now: () => t);

      const cd = OverlayCooldown(minGap: Duration(seconds: 10));
      final g1 = _FakeBackend<String>();
      manager.open(id: 'g', cooldown: cd, present: g1.present);
      await tester.pump();
      manager.close('g');
      await tester.pump();

      final g2 = _FakeBackend<String>();
      manager.open(id: 'g', cooldown: cd, present: g2.present);
      await tester.pump();
      expect(g2.presented, isFalse); // inside the gap

      t = t.add(const Duration(seconds: 11));
      manager.setContext({}); // nudge re-evaluation (cooldown expiry is silent)
      await tester.pump();
      expect(g2.presented, isTrue);

      manager.dispose();
    });

    testWidgets('minGap auto-wakes the queued entry when it expires (no nudge)',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      var t = DateTime(2026, 1, 1, 12);
      final manager = Layerman(now: () => t);

      const cd = OverlayCooldown(minGap: Duration(milliseconds: 500));
      final g1 = _FakeBackend<String>();
      manager.open(id: 'g', cooldown: cd, present: g1.present);
      await tester.pump();
      manager.close('g');
      await tester.pump();

      final g2 = _FakeBackend<String>();
      manager.open(id: 'g', cooldown: cd, present: g2.present);
      await tester.pump();
      expect(g2.presented, isFalse); // inside the gap → queued

      // Advance the clock and let the armed wake timer fire — crucially with
      // NO setContext nudge: a time-based cooldown wakes its own queue.
      t = t.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 520));
      expect(g2.presented, isTrue);

      manager.dispose();
    });

    testWidgets('day cap resets across the local midnight', (tester) async {
      await tester.pumpWidget(const SizedBox());
      var t = DateTime(2026, 1, 1, 23, 59);
      final manager = Layerman(now: () => t);

      const cd = OverlayCooldown(day: 1);
      final d1 = _FakeBackend<String>();
      manager.open(id: 'd', cooldown: cd, present: d1.present);
      await tester.pump();
      manager.close('d');
      await tester.pump();

      final d2 = _FakeBackend<String>();
      manager.open(id: 'd', cooldown: cd, present: d2.present);
      await tester.pump();
      expect(d2.presented, isFalse); // same day

      t = DateTime(2026, 1, 2, 0, 1); // crossed midnight
      manager.setContext({});
      await tester.pump();
      expect(d2.presented, isTrue);

      manager.dispose();
    });

    testWidgets('total persists across manager instances via storage',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final storage = MemoryCooldownStorage();
      const cd = OverlayCooldown(total: 1);

      final m1 = Layerman(cooldownStorage: storage);
      await m1.ready();
      final t1 = _FakeBackend<String>();
      m1.open(id: 't', cooldown: cd, present: t1.present);
      await tester.pump(); // open + fire-and-forget persist
      await tester.pump();
      m1.dispose();

      final m2 = Layerman(cooldownStorage: storage);
      await m2.ready(); // hydrates the persisted counter
      final t2 = _FakeBackend<String>();
      m2.open(id: 't', cooldown: cd, present: t2.present);
      await tester.pump();
      expect(t2.presented, isFalse); // total cap survived the restart

      m2.dispose();
    });
  });

  group('resolve (backend-driven data) — TS parity', () {
    testWidgets('resolved data becomes PresentContext.data; slot is committed',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final backend = Completer<String?>();
      Object? seenData;
      manager.open<String>(
        id: 'r',
        resolve: () => backend.future,
        present: (ctx) {
          seenData = ctx.data;
          return PresentedOverlay<String>(dismissed: Completer<String?>().future);
        },
      );
      final hi = _FakeBackend<String>();
      manager.open(id: 'hi', priority: 100, present: hi.present);
      await tester.pump();
      expect(manager.activeIds, isEmpty); // resolving, nothing visible yet
      expect(hi.presented, isFalse); // cannot preempt the commitment

      backend.complete('X');
      await tester.pump();
      await tester.pump();
      expect(seenData, 'X'); // data injected
      expect(manager.isShowing('r'), isTrue);
      expect(manager.queuedIds, contains('hi'));

      manager.dispose();
    });

    testWidgets('resolve returning null skips to the next', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      var presentCalled = false;
      final skipped = manager.open<String>(
        id: 'r',
        resolve: () async => null,
        present: (ctx) {
          presentCalled = true;
          return PresentedOverlay<String>(dismissed: Completer<String?>().future);
        },
      );
      final next = _FakeBackend<String>();
      manager.open(id: 'next', present: next.present);
      await tester.pump();
      await tester.pump();
      expect(presentCalled, isFalse);
      expect(next.presented, isTrue);
      expect(await skipped, isNull);

      manager.dispose();
    });
  });

  group('update / clearWhere — TS parity', () {
    testWidgets(
        'update(id, patch) shallow-merges data in place and notifies listeners',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      manager.open(
        id: 'u',
        data: {'n': 1, 'keep': 'x'},
        present: (ctx) =>
            PresentedOverlay<void>(dismissed: Completer<void>().future),
      );
      await tester.pump();

      var notified = false;
      manager.addListener(() => notified = true);
      manager.update('u', {'n': 2});

      // clearWhere's predicate is the only public window onto an entry's live
      // data; use it purely as an inspector (always return false) to confirm
      // the merge without actually removing the entry.
      Object? seenData;
      manager.clearWhere((r) {
        if (r.id == 'u') seenData = r.data;
        return false;
      });
      expect(seenData, {'n': 2, 'keep': 'x'}); // merged in place
      expect(notified, isTrue);

      manager.dispose();
    });

    testWidgets('clearWhere removes matching entries only', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final manager = Layerman();

      final keep = _FakeBackend<String>();
      final drop1 = _FakeBackend<String>();
      final drop2 = _FakeBackend<String>();
      manager.open(id: 'keep', present: keep.present);
      manager.open(id: 'drop-1', data: {'group': 'x'}, present: drop1.present);
      manager.open(
          id: 'drop-2',
          slot: 'toast',
          data: {'group': 'x'},
          present: drop2.present);
      await tester.pump();

      manager.clearWhere(
          (r) => r.data is Map && (r.data as Map)['group'] == 'x');
      await tester.pump();
      expect(manager.isShowing('keep'), isTrue);
      expect(manager.queuedIds, isEmpty);
      expect(manager.isShowing('drop-2'), isFalse);

      manager.dispose();
    });
  });
}
