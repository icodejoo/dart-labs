import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

/// Covers the shared [TaskQueuePlugin] base: the P0 concurrent-modification
/// guarantee (callbacks mutating the task map mid-tick) and the count-up
/// negative-value switch.
void main() {
  CountmanContext noopCtx() => CountmanContext(requestFrame: () {});

  // ── lazy self-registration on first add() ──────────────────────────
  group('lazy self-registration (user plugin passed straight to add/widget)', () {
    tearDown(Countman.destroy);

    test('unnamed-instance user plugin self-attaches on first add — no LateInit', () {
      Countman.destroy();
      // Created but NOT Countman.use()'d, as when handed straight to a widget.
      final p = Countdown(name: 'selfreg-unique', interval: 100);
      expect(
        () => p.add(const CountdownOptions(duration: Duration(seconds: 5))),
        returnsNormally,
      );
      expect(Countman.pluginCount, greaterThan(0));
    });

    test('name clash with an already-registered different instance → clear StateError', () {
      Countman.destroy();
      final a = Countdown(name: 'selfreg-dup', interval: 100);
      a.add(const CountdownOptions(duration: Duration(seconds: 5))); // registers 'selfreg-dup'
      final b = Countdown(name: 'selfreg-dup', interval: 200); // same name, different instance
      expect(
        () => b.add(const CountdownOptions(duration: Duration(seconds: 5))),
        throwsStateError,
      );
    });
  });

  // ── P0: structural mutation of the task map during tick() ──────────

  group('P0 concurrent modification (no ConcurrentModificationError)', () {
    test('counter: add() inside onComplete during tick', () {
      final p = Counter(name: 'p0_up_add');
      p.onAttach(noopCtx());

      var secondRan = false;
      p.add(CounterOptions(
        to: 10,
        duration: const Duration(milliseconds: 50),
        onComplete: (_) => p.add(CounterOptions(
          to: 20,
          duration: const Duration(milliseconds: 50),
          onUpdate: (_) => secondRan = true,
        )),
      ));

      p.tick(Duration.zero, Duration.zero); // frame 1: started
      // frame 2: first task completes; onComplete adds a task mid-iteration.
      expect(
        () => p.tick(const Duration(milliseconds: 100), const Duration(milliseconds: 100)),
        returnsNormally,
      );
      p.tick(const Duration(milliseconds: 110), const Duration(milliseconds: 10)); // deferred task renders
      expect(secondRan, isTrue);
    });

    test('counter: cancel() another task inside onUpdate during tick', () {
      final p = Counter(name: 'p0_up_cancel');
      p.onAttach(noopCtx());

      late CounterHandle b;
      var bUpdates = 0;
      p.add(CounterOptions(
        to: 10,
        duration: const Duration(milliseconds: 100),
        onUpdate: (_) => b.cancel(), // cancels the *other* task mid-iteration
      ));
      b = p.add(CounterOptions(
        to: 10,
        duration: const Duration(milliseconds: 100),
        onUpdate: (_) => bUpdates++,
      ));

      // frame 1: both render initial; A's onUpdate cancels B (deferred to end).
      expect(() => p.tick(Duration.zero, Duration.zero), returnsNormally);
      final afterFrame1 = bUpdates;
      p.tick(const Duration(milliseconds: 20), const Duration(milliseconds: 20));
      expect(bUpdates, afterFrame1); // B was removed, no more updates
    });

    test('countdown: onComplete adds another countdown mid-tick', () {
      var fakeNow = DateTime(2024);
      countdownClock = () => fakeNow;
      addTearDown(() => countdownClock = DateTime.now);

      final p = Countdown(name: 'p0_cd', interval: 0);
      p.onAttach(noopCtx());

      var chained = false;
      p.add(CountdownOptions(
        duration: const Duration(milliseconds: 100),
        onComplete: () => p.add(CountdownOptions(
          duration: const Duration(milliseconds: 100),
          onUpdate: (_) => chained = true,
        )),
      ));

      p.tick(Duration.zero, Duration.zero); // frame 1: render initial remaining
      fakeNow = fakeNow.add(const Duration(milliseconds: 200)); // deadline passed
      expect(
        () => p.tick(const Duration(milliseconds: 16), const Duration(milliseconds: 16)),
        returnsNormally,
      );
      p.tick(const Duration(milliseconds: 32), const Duration(milliseconds: 16));
      expect(chained, isTrue);
    });

    test('elapsed: cancel() inside onUpdate during tick', () {
      var fakeNow = DateTime(2024);
      countdownClock = () => fakeNow;
      addTearDown(() => countdownClock = DateTime.now);

      final p = Elapsed(name: 'p0_el', interval: 0);
      p.onAttach(noopCtx());

      late ElapsedHandle h;
      h = p.add(ElapsedOptions(onUpdate: (_) => h.cancel()));

      p.tick(Duration.zero, Duration.zero); // frame 1: render initial (elapsed 0)
      fakeNow = fakeNow.add(const Duration(milliseconds: 20));
      expect(
        () => p.tick(const Duration(milliseconds: 16), const Duration(milliseconds: 16)),
        returnsNormally,
      );
    });
  });

  // ── count-up negative switch ──────────────────────────────────────

  group('counter allowNegative', () {
    test('default (false) clamps emitted values to >= 0', () {
      final p = Counter(name: 'neg_off');
      p.onAttach(noopCtx());

      final vals = <double>[];
      p.add(CounterOptions(
        from: 0,
        to: -100,
        duration: const Duration(milliseconds: 100),
        onUpdate: vals.add,
      ));

      p.tick(Duration.zero, Duration.zero);                                          // from
      p.tick(const Duration(milliseconds: 50), const Duration(milliseconds: 50));    // raw -50 → 0
      p.tick(const Duration(milliseconds: 200), const Duration(milliseconds: 150));  // done raw -100 → 0

      expect(vals.every((v) => v >= 0), isTrue);
      expect(vals.last, 0.0);
    });

    test('true reaches the negative target', () {
      final p = Counter(name: 'neg_on');
      p.onAttach(noopCtx());

      final vals = <double>[];
      p.add(CounterOptions(
        from: 0,
        to: -100,
        allowNegative: true,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 100),
        onUpdate: vals.add,
      ));

      p.tick(Duration.zero, Duration.zero);
      p.tick(const Duration(milliseconds: 50), const Duration(milliseconds: 50));
      p.tick(const Duration(milliseconds: 200), const Duration(milliseconds: 150));

      expect(vals.any((v) => v < 0), isTrue);
      expect(vals.last, -100.0);
    });
  });

  group('AnimatedCounter controller swap (memory)', () {
    testWidgets('swapping controllers unbinds the OLD one, not the new', (tester) async {
      final a = AnimatedCounterController(initialValue: 0);
      final b = AnimatedCounterController(initialValue: 0);

      Widget build(AnimatedCounterController c) => MaterialApp(
            home: Scaffold(body: AnimatedCounter(value: 0, controller: c)),
          );

      await tester.pumpWidget(build(a));
      expect(a.$pauseCallback, isNotNull); // a is bound

      await tester.pumpWidget(build(b));
      await tester.pump();

      expect(a.$pauseCallback, isNull);    // OLD controller fully unbound
      expect(b.$pauseCallback, isNotNull); // NEW controller bound
      Countman.destroy();
    });
  });

  group('AnimatedCounter all-nines detection (n%9 fix)', () {
    test('fires only for repunits (9, 99, 999…), not every multiple of 9', () {
      for (final n in [9, 99, 999, 9999, 999999999]) {
        expect(isAllNinesTarget(n), isTrue, reason: '$n is all-nines');
      }
      for (final n in [18, 27, 36, 45, 90, 108, 900, 1000, 10]) {
        expect(isAllNinesTarget(n), isFalse, reason: '$n is not all-nines');
      }
      expect(isAllNinesTarget(0), isFalse);
    });
  });

  group('lifecycle callbacks', () {
    test('counter: onReady (sync add) → onStart (first frame) → onCancel', () {
      final p = Counter(name: 'lc_up');
      p.onAttach(noopCtx());
      final ev = <String>[];
      final h = p.add(CounterOptions(
        to: 10,
        duration: const Duration(milliseconds: 50),
        onReady: () => ev.add('ready'),
        onStart: () => ev.add('start'),
        onCancel: () => ev.add('cancel'),
      ));
      expect(ev, ['ready']); // fired synchronously at add()

      p.tick(Duration.zero, Duration.zero); // first frame → start
      expect(ev, ['ready', 'start']);

      h.cancel();
      expect(ev, ['ready', 'start', 'cancel']);
    });

    test('onCancel does NOT fire on natural completion', () {
      final p = Counter(name: 'lc_done');
      p.onAttach(noopCtx());
      var cancelled = false;
      p.add(CounterOptions(
        to: 10,
        duration: const Duration(milliseconds: 50),
        onCancel: () => cancelled = true,
      ));
      p.tick(Duration.zero, Duration.zero);
      p.tick(const Duration(milliseconds: 100), const Duration(milliseconds: 100)); // completes
      expect(cancelled, isFalse);
    });

    test('countdown: onPause / onResume fire from the handle', () {
      var fakeNow = DateTime(2024);
      countdownClock = () => fakeNow;
      addTearDown(() => countdownClock = DateTime.now);

      final p = Countdown(name: 'lc_cd', interval: 0);
      p.onAttach(noopCtx());
      final ev = <String>[];
      final h = p.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onPause: () => ev.add('pause'),
        onResume: () => ev.add('resume'),
      ));
      p.tick(Duration.zero, Duration.zero);
      h.pause();
      h.resume();
      expect(ev, ['pause', 'resume']);
    });
  });

  group('TimeParts', () {
    test('decomposes a duration into d/h/m/s/ms + totals + progress', () {
      final p = TimeParts.of(
        const Duration(days: 1, hours: 2, minutes: 3, seconds: 4, milliseconds: 5),
        const Duration(days: 2),
      );
      expect(p.days, 1);
      expect(p.hours, 2);
      expect(p.minutes, 3);
      expect(p.seconds, 4);
      expect(p.millis, 5);
      expect(p.totalHours, 26);
      expect(p.parts, [1, 2, 3, 4, 5]);
      expect(p.progress, greaterThan(0));
      expect(p.progress, lessThan(1));
    });

    test('elapsed-style parts (no total) report zero progress', () {
      final p = TimeParts.of(const Duration(seconds: 90));
      expect(p.total, isNull);
      expect(p.progress, 0);
      expect(p.minutes, 1);
      expect(p.seconds, 30);
    });

    test('per-task isolation: two countdowns keep distinct parts', () {
      var fakeNow = DateTime(2024);
      countdownClock = () => fakeNow;
      addTearDown(() => countdownClock = DateTime.now);

      final p = Countdown(name: 'iso', interval: 0);
      p.onAttach(noopCtx());
      TimeParts? a, b;
      p.add(CountdownOptions(duration: const Duration(seconds: 10), onUpdate: (x) => a = x));
      p.add(CountdownOptions(duration: const Duration(seconds: 30), onUpdate: (x) => b = x));

      p.tick(Duration.zero, Duration.zero); // both render initial
      expect(a!.inSeconds, 10);
      expect(b!.inSeconds, 30); // distinct — not collapsed to one shared value
    });
  });

  group('edge cases', () {
    test('dt spike does not fire a burst of catch-up ticks (modulo drain)', () {
      var fakeNow = DateTime(2024);
      countdownClock = () => fakeNow;
      addTearDown(() => countdownClock = DateTime.now);

      final p = Countdown(name: 'spike', interval: 1000);
      p.onAttach(noopCtx());

      var updates = 0;
      p.add(CountdownOptions(
        duration: const Duration(seconds: 100),
        onUpdate: (_) => updates++,
      ));

      p.tick(Duration.zero, Duration.zero); // frame 1: render initial (updates=1)

      // Huge dt (app returned from a 5 s background) — processes exactly once.
      fakeNow = fakeNow.add(const Duration(seconds: 5));
      p.tick(const Duration(seconds: 5), const Duration(seconds: 5));
      final afterSpike = updates;

      // Subsequent normal frames must NOT keep processing to "catch up".
      for (var i = 0; i < 3; i++) {
        fakeNow = fakeNow.add(const Duration(milliseconds: 16));
        p.tick(Duration(milliseconds: 5000 + 16 * (i + 1)), const Duration(milliseconds: 16));
      }
      expect(updates, afterSpike); // no burst
    });

    testWidgets('AnimatedCounter tolerates a non-finite value', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AnimatedCounter(value: double.infinity, duration: Duration(milliseconds: 50))),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      Countman.destroy();
    });
  });

  group('a11y semantics', () {
    testWidgets('RingCounter exposes a percentage semantics value', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: RingCounter(to: 100, duration: Duration(milliseconds: 100))),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // reach 100%

      final node = tester.getSemantics(find.descendant(
        of: find.byType(RingCounter),
        matching: find.byType(CustomPaint),
      ).first);
      expect(node.value, endsWith('%'));
      handle.dispose();
      Countman.destroy();
    });
  });

  group('OdometerCounter negative display', () {
    testWidgets('shows leading minus when allowNegative and value < 0', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: OdometerCounter(
              from: 0,
              to: -5,
              allowNegative: true,
              duration: Duration(milliseconds: 100),
            ),
          ),
        ),
      ));

      await tester.pump();                                   // frame 1: from=0, no minus
      await tester.pump(const Duration(milliseconds: 200));  // reaches -5
      await tester.pump();

      expect(find.text('-'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('no minus when allowNegative is false (value clamped to 0)', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: OdometerCounter(
              from: 0,
              to: -5,
              duration: Duration(milliseconds: 100),
            ),
          ),
        ),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.text('-'), findsNothing);
      Countman.destroy();
    });
  });

  group('OdometerCounter anti-alias (huge range)', () {
    testWidgets('0 → 999,999,999 animates and settles without throwing', (tester) async {
      // Range/duration triggers the coprime-step anti-alias path; it must run
      // and snap to the exact target on completion without exceptions.
      //
      // 该量级/时长触发互质步长防混叠路径；须正常运行并在完成时精确吸附到目标，无异常。
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: OdometerCounter(
              from: 0,
              to: 999999999,
              duration: Duration(milliseconds: 300),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      Countman.destroy();
    });
  });
}
