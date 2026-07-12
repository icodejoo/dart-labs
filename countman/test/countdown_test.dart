import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';
import 'package:countman/src/count_down/types.dart' show countdownClock;

// All tests use a fake clock injected via [countdownClock].
// No Future.delayed — time advances by mutating [_now] and calling tick()
// with matching dt, keeping tests fast and deterministic.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Advance the fake clock and return the matching dt.
Duration Function(Duration) _makeAdvance(DateTime Function() getNow, void Function(DateTime) setNow) {
  return (Duration d) {
    setNow(getNow().add(d));
    return d;
  };
}

void main() {
  late DateTime _now;
  late void Function(Duration) advance; // advances _now and returns dt

  setUp(() {
    _now = DateTime(2024, 1, 1, 12, 0, 0);
    countdownClock = () => _now;
    advance = (d) => _now = _now.add(d);
  });

  tearDown(() {
    countdownClock = DateTime.now; // restore
  });

  // ── Countdown.tick() direct unit tests ────────────────────────────────────

  group('Countdown.tick direct', () {
    late Countdown plugin;

    setUp(() {
      plugin = Countdown(name: 'direct', interval: 1000);
      plugin.onAttach(CountmanContext(requestFrame: () {}));
    });

    test('first frame renders full duration regardless of interval', () {
      TimeParts? got;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: (r) => got = r,
      ));

      plugin.tick(Duration.zero, Duration.zero); // frame 1: dt=0
      expect(got?.inSeconds, 5);
    });

    test('a task added mid-cycle still reports accurate remaining, not stale by the phase offset', () {
      // Group is 500ms into its shared 1000ms cycle (from an existing task)
      // when a brand-new task joins. Its first render must reflect the real
      // wall-clock remaining (~10s), not a value that's already "used up"
      // 500ms because the group happened to be mid-cycle.
      final existing = <TimeParts>[];
      plugin.add(CountdownOptions(duration: const Duration(seconds: 30), onUpdate: existing.add));
      plugin.tick(Duration.zero, Duration.zero); // frame 1: existing task starts, _accumMs=0

      advance(const Duration(milliseconds: 500));
      plugin.tick(const Duration(milliseconds: 500), const Duration(milliseconds: 500));
      // _accumMs is now 500 — half-way through the group's 1000ms cycle,
      // and the existing task hasn't been processed yet (accum < 1000).
      expect(existing.length, 1); // still just the initial render

      // New task joins right now, at the 500ms-into-cycle mark. Track every
      // update it gets (not just the first) to inspect both renders below.
      final newTaskUpdates = <TimeParts>[];
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: newTaskUpdates.add,
      ));

      // Next frame is a normal ~16ms tick — nowhere near the group's next
      // shouldProcess boundary (which is still ~484ms away).
      advance(const Duration(milliseconds: 16));
      plugin.tick(const Duration(milliseconds: 516), const Duration(milliseconds: 16));

      // The new task's first render must fire on this very next frame
      // (unconditionally, before the shouldProcess gate) and show ~10s
      // minus only the ~16ms that actually elapsed — NOT 10s minus 500ms.
      expect(newTaskUpdates.length, 1);
      expect(newTaskUpdates[0].inMilliseconds, closeTo(10000 - 16, 1));

      // Complete the group's cycle (500 + 16 + 484 = 1000ms since the
      // existing task's last process) and confirm the SAME new task's
      // second update reflects the true ~500ms that have now elapsed since
      // it was added (16 + 484), not a value assuming a full fresh 1000ms
      // cycle just because that's when the group happens to fire next.
      advance(const Duration(milliseconds: 484));
      plugin.tick(const Duration(milliseconds: 1000), const Duration(milliseconds: 484));

      expect(newTaskUpdates.length, 2);
      expect(newTaskUpdates[1].inMilliseconds, closeTo(10000 - 500, 1));
    });

    test('interval=1000: no onUpdate until 1 s of dt accumulates', () {
      final calls = <TimeParts>[];
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: calls.add,
      ));

      plugin.tick(Duration.zero, Duration.zero); // frame 1: started
      expect(calls.length, 1); // initial render

      // Several rapid frames — accum < 1000 ms
      plugin.tick(const Duration(milliseconds: 100), const Duration(milliseconds: 100));
      plugin.tick(const Duration(milliseconds: 200), const Duration(milliseconds: 100));
      plugin.tick(const Duration(milliseconds: 300), const Duration(milliseconds: 100));
      expect(calls.length, 1); // no extra calls yet
    });

    test('interval=1000: onUpdate fires after 1 s accumulates', () {
      final calls = <TimeParts>[];
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: calls.add,
      ));

      plugin.tick(Duration.zero, Duration.zero); // started
      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 1), const Duration(seconds: 1)); // accum=1000
      expect(calls.length, 2);
      expect(calls.last.inSeconds, 9); // 10s - 1s = 9s remaining
    });

    test('interval=0: onUpdate fires every frame', () {
      final p = Countdown(name: 'every_frame', interval: 0);
      p.onAttach(CountmanContext(requestFrame: () {}));

      int count = 0;
      p.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: (_) => count++,
      ));

      p.tick(Duration.zero, Duration.zero);
      advance(const Duration(milliseconds: 16));
      p.tick(const Duration(milliseconds: 16), const Duration(milliseconds: 16));
      advance(const Duration(milliseconds: 16));
      p.tick(const Duration(milliseconds: 32), const Duration(milliseconds: 16));
      expect(count, 3); // initial + 2 frames
    });

    test('onComplete fires when remaining reaches zero', () {
      bool done = false;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 2),
        onComplete: () => done = true,
      ));

      plugin.tick(Duration.zero, Duration.zero); // started
      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 1), const Duration(seconds: 1)); // 1s
      expect(done, isFalse);

      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 1)); // 2s done
      expect(done, isTrue);
    });

    test('onThreshold fires once when remaining crosses threshold', () {
      var count = 0;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      ));

      plugin.tick(Duration.zero, Duration.zero); // started: 5s, no crossing yet
      expect(count, 0);

      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 1), const Duration(seconds: 1)); // 4s
      expect(count, 0);

      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 1)); // 3s — crosses
      expect(count, 1);

      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 3), const Duration(seconds: 1)); // 2s — already fired
      expect(count, 1);
    });

    test('onThreshold does not fire when threshold is null', () {
      var count = 0;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 2),
        onThreshold: () => count++,
      ));

      plugin.tick(Duration.zero, Duration.zero);
      advance(const Duration(seconds: 3));
      plugin.tick(const Duration(seconds: 3), const Duration(seconds: 3));
      expect(count, 0);
    });

    test('CountdownHandle.reset re-arms onThreshold for a later crossing', () {
      var count = 0;
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      ));

      plugin.tick(Duration.zero, Duration.zero); // 5s
      advance(const Duration(seconds: 3));
      plugin.tick(const Duration(seconds: 3), const Duration(seconds: 3)); // 2s — crosses
      expect(count, 1);

      handle.reset(); // back to 5s, thresholdFired cleared
      plugin.tick(const Duration(seconds: 3), Duration.zero); // re-anchor frame
      advance(const Duration(seconds: 3));
      plugin.tick(const Duration(seconds: 6), const Duration(seconds: 3)); // 2s again — crosses again
      expect(count, 2);
    });

    test('onUpdate called with Duration.zero when done', () {
      TimeParts? lastValue;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 1),
        onUpdate: (r) => lastValue = r,
      ));

      plugin.tick(Duration.zero, Duration.zero);
      advance(const Duration(seconds: 2)); // overshoot
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 2));
      expect(lastValue?.value, Duration.zero);
    });

    test('paused task skips processing', () {
      final calls = <TimeParts>[];
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: calls.add,
      ));

      plugin.tick(Duration.zero, Duration.zero); // started
      handle.pause();
      final countBefore = calls.length;

      advance(const Duration(seconds: 2));
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 2)); // accum > interval, paused
      expect(calls.length, countBefore); // no calls while paused
    });

    test('returns false when all tasks done', () {
      plugin.add(CountdownOptions(duration: const Duration(seconds: 1)));
      plugin.tick(Duration.zero, Duration.zero);
      advance(const Duration(seconds: 2));
      final busy = plugin.tick(const Duration(seconds: 2), const Duration(seconds: 2));
      expect(busy, isFalse);
    });

    test('returns false when all tasks paused', () {
      final handle = plugin.add(CountdownOptions(duration: const Duration(seconds: 5)));
      plugin.tick(Duration.zero, Duration.zero);
      handle.pause();
      final busy = plugin.tick(const Duration(milliseconds: 16), const Duration(milliseconds: 16));
      expect(busy, isFalse);
    });

    test('interval remainder carries over', () {
      // interval=1000ms. Two ticks of 600ms each = 1200ms total.
      // First tick: accum=600 < 1000 → no process.
      // Second tick: accum=1200 >= 1000 → process, accum becomes 200.
      // Third tick (+600ms): accum=800 < 1000 → no process.
      // Fourth tick (+600ms): accum=1400 >= 1000 → process again.
      final calls = <int>[];
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: (r) => calls.add(r.inSeconds),
      ));

      plugin.tick(Duration.zero, Duration.zero); // started, calls=[10]

      advance(const Duration(milliseconds: 600));
      plugin.tick(const Duration(milliseconds: 600), const Duration(milliseconds: 600));
      expect(calls.length, 1); // accum=600

      advance(const Duration(milliseconds: 600));
      plugin.tick(const Duration(milliseconds: 1200), const Duration(milliseconds: 600));
      expect(calls.length, 2); // accum crossed 1000 → processed, accum=200

      advance(const Duration(milliseconds: 600));
      plugin.tick(const Duration(milliseconds: 1800), const Duration(milliseconds: 600));
      expect(calls.length, 2); // accum=800

      advance(const Duration(milliseconds: 600));
      plugin.tick(const Duration(milliseconds: 2400), const Duration(milliseconds: 600));
      expect(calls.length, 3); // accum=1400 → processed again
    });
  });

  // ── CountdownHandle ───────────────────────────────────────────────────────

  group('CountdownHandle', () {
    late Countdown plugin;

    setUp(() {
      plugin = Countdown(name: 'handle_test', interval: 1000);
      Countman.use(plugin);
    });

    // Countman.destroy() is called explicitly at the end of each test body
    // so the ticker stops before Flutter's cleanup checks for lingering callbacks.

    testWidgets('pause freezes remaining', (t) async {
      TimeParts? lastRemaining;
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: (r) => lastRemaining = r,
      ));

      await t.pump(); // frame 1: started, remaining=5s
      handle.pause();
      expect(handle.isPaused, isTrue);

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2)); // ticked but paused
      expect(handle.remaining.inSeconds, lastRemaining!.inSeconds);
      Countman.destroy();
    });

    testWidgets('resume continues from paused remaining', (t) async {
      final calls = <int>[];
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: (r) => calls.add(r.inSeconds),
      ));

      await t.pump(); // started: 5s
      handle.pause();

      advance(const Duration(seconds: 2));
      handle.resume();
      await t.pump(); // re-anchor frame
      expect(handle.isPaused, isFalse);
      expect(calls.last, 5); // still 5s (paused duration)

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1)); // 1s interval → 4s
      expect(calls.last, 4);
      Countman.destroy();
    });

    testWidgets('reset restarts from full duration', (t) async {
      final calls = <int>[];
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: (r) => calls.add(r.inSeconds),
      ));

      await t.pump(); // started: 5s
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2)); // → 3s

      handle.reset();
      await t.pump(); // re-anchor: renders full 5s again
      expect(calls.last, 5);
      Countman.destroy();
    });

    testWidgets('reset with new duration', (t) async {
      final calls = <int>[];
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: (r) => calls.add(r.inSeconds),
      ));

      await t.pump();
      handle.reset(duration: const Duration(seconds: 30));
      await t.pump();
      expect(calls.last, 30);
      Countman.destroy();
    });

    testWidgets('cancel stops updates', (t) async {
      final calls = <TimeParts>[];
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 10),
        onUpdate: calls.add,
      ));

      await t.pump();
      handle.cancel();
      final countBefore = calls.length;

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(calls.length, countBefore);
      Countman.destroy();
    });

    testWidgets('isDone true after countdown reaches zero', (t) async {
      bool doneFired = false;
      final handle = plugin.add(CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () => doneFired = true,
      ));

      await t.pump(); // started
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2)); // done
      expect(handle.isDone, isTrue);
      expect(doneFired, isTrue);
      Countman.destroy();
    });
  });

  // ── Ticker integration ────────────────────────────────────────────────────

  group('Ticker integration', () {
    tearDown(Countman.destroy);

    testWidgets('ticker auto-stops when all tasks complete', (t) async {
      final plugin = Countdown(name: 'auto_stop', interval: 1000);
      Countman.use(plugin);

      plugin.add(CountdownOptions(duration: const Duration(seconds: 1)));
      await t.pump();

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(Countman.isRunning, isFalse);
    });

    testWidgets('Counter and Countdown coexist on one ticker', (t) async {
      final up   = Counter(name: 'up');
      final down = Countdown(name: 'down', interval: 0);
      Countman.use(up);
      Countman.use(down);

      double? upDone;
      bool downDone = false;

      up.add(CounterOptions(
        to: 100,
        duration: const Duration(milliseconds: 500),
        onComplete: (v) => upDone = v,
      ));
      down.add(CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () => downDone = true,
      ));

      await t.pump(); // both started

      // Advance counter to completion (500ms)
      await t.pump(const Duration(milliseconds: 600));
      expect(upDone, 100.0);

      // Advance countdown to completion
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(downDone, isTrue);
    });
  });

  // ── countdown() top-level ─────────────────────────────────────────────────

  group('countdown() top-level', () {
    tearDown(Countman.destroy);

    testWidgets('auto-bootstraps default Countdown instance', (t) async {
      bool done = false;
      countdown(CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () => done = true,
      ));

      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(done, isTrue);
    });

    testWidgets('re-registers after destroy()', (t) async {
      bool first = false;
      countdown(CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () => first = true,
      ));
      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      Countman.destroy();
      expect(first, isTrue);

      bool second = false;
      countdown(CountdownOptions(
        duration: const Duration(seconds: 1),
        onComplete: () => second = true,
      ));
      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      Countman.destroy();
      expect(second, isTrue);
    });
  });

  // ── CountdownBuilder ───────────────────────────────────────────────────────

  group('CountdownBuilder', () {
    tearDown(Countman.destroy);

    testWidgets('renders initial duration on first frame', (t) async {
      await t.pumpWidget(_wrap(
        CountdownBuilder(
          duration: const Duration(minutes: 2),
          builder: (_, r, __) => Text(CountdownFormat.ms(r)),
        ),
      ));
      await t.pump(); // first frame: initial value
      Countman.destroy();

      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('calls onComplete when countdown reaches zero', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(
        CountdownBuilder(
          duration: const Duration(seconds: 2),
          onComplete: () => done = true,
          builder: (_, r, __) => Text('${r.inSeconds}'),
        ),
      ));

      await t.pump(); // started

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      Countman.destroy();

      expect(done, isTrue);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('calls onThreshold once when remaining crosses threshold', (t) async {
      var count = 0;
      await t.pumpWidget(_wrap(
        CountdownBuilder(
          duration: const Duration(seconds: 5),
          threshold: const Duration(seconds: 3),
          onThreshold: () => count++,
          builder: (_, r, __) => Text('${r.inSeconds}'),
        ),
      ));

      await t.pump(); // started: 5s
      expect(count, 0);

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2)); // 3s — crosses
      Countman.destroy();

      expect(count, 1);
    });

    testWidgets('duration change restarts countdown', (t) async {
      Duration currentDuration = const Duration(minutes: 5);
      late StateSetter set;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        set = s;
        return CountdownBuilder(
          duration: currentDuration,
          builder: (_, r, __) => Text(CountdownFormat.ms(r)),
        );
      })));

      await t.pump(); // 05:00

      set(() => currentDuration = const Duration(minutes: 3));
      await t.pump(); // restart with new duration
      await t.pump(); // first frame of new task

      Countman.destroy();
      expect(find.text('03:00'), findsOneWidget);
    });

    testWidgets('controller pause/resume/reset work', (t) async {
      final ctrl = CountdownController();

      await t.pumpWidget(_wrap(
        CountdownBuilder(
          duration: const Duration(seconds: 10),
          controller: ctrl,
          builder: (_, r, __) => Text('${r.inSeconds}'),
        ),
      ));

      await t.pump(); // started: 10s

      ctrl.pause();
      expect(ctrl.isPaused, isTrue);

      ctrl.resume();
      expect(ctrl.isPaused, isFalse);

      ctrl.reset(duration: const Duration(seconds: 5));
      await t.pump(); // re-anchor
      expect(ctrl.remaining.inSeconds, 5);

      Countman.destroy();
    });

    testWidgets('custom plugin used when provided', (t) async {
      final group = Countdown(name: 'custom_group', interval: 0);
      Countman.use(group);

      bool done = false;
      await t.pumpWidget(_wrap(
        CountdownBuilder(
          duration: const Duration(seconds: 2),
          plugin: group,
          onComplete: () => done = true,
          builder: (_, r, __) => Text('${r.inSeconds}'),
        ),
      ));

      await t.pump(); // started

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      Countman.destroy();

      expect(done, isTrue);
    });

    testWidgets('disposes task when widget is removed', (t) async {
      final calls = <TimeParts>[];
      await t.pumpWidget(_wrap(
        CountdownBuilder(
          duration: const Duration(seconds: 10),
          builder: (_, r, __) { calls.add(r); return const SizedBox(); },
        ),
      ));

      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));

      await t.pumpWidget(_wrap(const SizedBox())); // remove widget
      final countAfterRemove = calls.length;

      advance(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));
      Countman.destroy();

      expect(calls.length, countAfterRemove); // no more updates
    });
  });

  // ── CountdownFormat ───────────────────────────────────────────────────────

  group('onThreshold threading — CountdownText / CountdownRing', () {
    tearDown(Countman.destroy);

    testWidgets('CountdownText fires onThreshold', (t) async {
      var count = 0;
      await t.pumpWidget(_wrap(CountdownText(
        to: const Duration(seconds: 5),
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      )));
      await t.pump();
      expect(count, 0);

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(count, 1);
    });

    testWidgets('CountdownRing fires onThreshold', (t) async {
      var count = 0;
      await t.pumpWidget(_wrap(CountdownRing(
        to: const Duration(seconds: 5),
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      )));
      await t.pump();
      expect(count, 0);

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(count, 1);
    });
  });

  group('resolveDeadline string parsing', () {
    test('standard ISO-8601 string parses via the DateTime.parse fast path', () {
      final d = resolveDeadline('2025-12-31T10:00:00');
      expect(d, DateTime(2025, 12, 31, 10, 0, 0));
    });

    test('slash-separated date+time falls back to the lenient pattern', () {
      // DateTime.parse rejects "/" separators — must go through the fallback.
      final d = resolveDeadline('2025/12/31 10:30:15');
      expect(d, DateTime(2025, 12, 31, 10, 30, 15));
    });

    test('date-only slash string defaults time to midnight via fallback', () {
      final d = resolveDeadline('2025/06/01');
      expect(d, DateTime(2025, 6, 1));
    });

    test('fallback pattern reads only the first 3 fraction chars, unpadded (matches dayjs)', () {
      // dayjs does `(d[7] || '0').substring(0, 3)` with no zero-padding, so a
      // 1-digit fraction is taken literally as milliseconds: ".5" -> 5ms,
      // not 500ms. Ported faithfully rather than "fixed".
      final oneDigit = resolveDeadline('2025/01/02 03:04:05.5');
      expect(oneDigit, DateTime(2025, 1, 2, 3, 4, 5, 5));

      final threeDigits = resolveDeadline('2025/01/02 03:04:05.500');
      expect(threeDigits, DateTime(2025, 1, 2, 3, 4, 5, 500));

      final longer = resolveDeadline('2025/01/02 03:04:05.123456');
      expect(longer, DateTime(2025, 1, 2, 3, 4, 5, 123)); // truncated to first 3 digits
    });

    test('a Z-suffixed string that DateTime.parse rejects still throws', () {
      // No explicit "Z" guard needed here (unlike dayjs, which checks for
      // one before running its regex on the hot path) — _lenientDatePattern
      // has nothing that consumes "Z" and is `$`-anchored, so it already
      // can't match a Z-suffixed string; this just documents that the two
      // parse attempts still fail together and throw, as expected.
      expect(() => resolveDeadline('2025/12/31Z'), throwsFormatException);
    });

    test('year-only slash string defaults month/day to 1 via fallback', () {
      final d = resolveDeadline('2025');
      expect(d, DateTime(2025, 1, 1));
    });

    test('garbage string fails both DateTime.parse and the fallback pattern', () {
      expect(() => resolveDeadline('not a date'), throwsFormatException);
    });

    test('out-of-range components roll over like the DateTime constructor normally does', () {
      // Dart's DateTime(year, month, day, ...) constructor normalizes
      // out-of-range components instead of throwing (month 13 → next
      // January, day 40 rolls into the following month) — same leniency
      // the fallback pattern inherits, matching how a plain JS `new
      // Date(2025, 12, 40)` would also roll over rather than error.
      final d = resolveDeadline('2025/13/40');
      expect(d, DateTime(2025, 13, 40));
    });
  });

  group('CountdownFormat', () {
    TimeParts tp(Duration d) => TimeParts.of(d);

    test('hms', () {
      expect(CountdownFormat.hms(tp(const Duration(hours: 1, minutes: 23, seconds: 45))), '01:23:45');
      expect(CountdownFormat.hms(tp(const Duration(hours: 10))), '10:00:00');
    });

    test('ms', () {
      expect(CountdownFormat.ms(tp(const Duration(minutes: 3, seconds: 7))), '03:07');
      expect(CountdownFormat.ms(tp(const Duration(minutes: 90, seconds: 5))), '90:05');
    });

    test('msTenths', () {
      expect(CountdownFormat.msTenths(
          tp(const Duration(minutes: 1, seconds: 5, milliseconds: 350))), '01:05.3');
    });

    test('msMillis', () {
      expect(CountdownFormat.msMillis(
          tp(const Duration(minutes: 1, seconds: 5, milliseconds: 327))), '01:05.327');
      expect(CountdownFormat.msMillis(tp(const Duration(seconds: 3, milliseconds: 7))), '00:03.007');
      expect(CountdownFormat.msMillis(tp(const Duration(milliseconds: 500))), '00:00.500');
    });

    test('auto: ≥1h → hms', () {
      final s = CountdownFormat.auto(tp(const Duration(hours: 2)));
      expect(s.split(':').length, 3);
    });

    test('auto: <10s → msTenths', () {
      expect(CountdownFormat.auto(tp(const Duration(seconds: 9, milliseconds: 700))), '00:09.7');
    });

    test('auto: 10s–59m59s → ms', () {
      expect(CountdownFormat.auto(tp(const Duration(minutes: 2, seconds: 30))), '02:30');
    });
  });
}
