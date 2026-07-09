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
      Duration? got;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 5),
        onUpdate: (r) => got = r,
      ));

      plugin.tick(Duration.zero, Duration.zero); // frame 1: dt=0
      expect(got?.inSeconds, 5);
    });

    test('interval=1000: no onUpdate until 1 s of dt accumulates', () {
      final calls = <Duration>[];
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
      final calls = <Duration>[];
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

    test('onDone fires when remaining reaches zero', () {
      bool done = false;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 2),
        onDone: () => done = true,
      ));

      plugin.tick(Duration.zero, Duration.zero); // started
      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 1), const Duration(seconds: 1)); // 1s
      expect(done, isFalse);

      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 1)); // 2s done
      expect(done, isTrue);
    });

    test('onUpdate called with Duration.zero when done', () {
      Duration? lastValue;
      plugin.add(CountdownOptions(
        duration: const Duration(seconds: 1),
        onUpdate: (r) => lastValue = r,
      ));

      plugin.tick(Duration.zero, Duration.zero);
      advance(const Duration(seconds: 2)); // overshoot
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 2));
      expect(lastValue, Duration.zero);
    });

    test('paused task skips processing', () {
      final calls = <Duration>[];
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
      Duration? lastRemaining;
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
      final calls = <Duration>[];
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
        onDone: () => doneFired = true,
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

    testWidgets('Countup and Countdown coexist on one ticker', (t) async {
      final up   = Countup(name: 'up');
      final down = Countdown(name: 'down', interval: 0);
      Countman.use(up);
      Countman.use(down);

      double? upDone;
      bool downDone = false;

      up.add(CountupOptions(
        to: 100,
        duration: const Duration(milliseconds: 500),
        onDone: (v) => upDone = v,
      ));
      down.add(CountdownOptions(
        duration: const Duration(seconds: 1),
        onDone: () => downDone = true,
      ));

      await t.pump(); // both started

      // Advance countup to completion (500ms)
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
        onDone: () => done = true,
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
        onDone: () => first = true,
      ));
      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      Countman.destroy();
      expect(first, isTrue);

      bool second = false;
      countdown(CountdownOptions(
        duration: const Duration(seconds: 1),
        onDone: () => second = true,
      ));
      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      Countman.destroy();
      expect(second, isTrue);
    });
  });

  // ── CountdownWidget ───────────────────────────────────────────────────────

  group('CountdownWidget', () {
    tearDown(Countman.destroy);

    testWidgets('renders initial duration on first frame', (t) async {
      await t.pumpWidget(_wrap(
        CountdownWidget(
          duration: const Duration(minutes: 2),
          builder: (_, r) => Text(CountdownFormat.ms(r)),
        ),
      ));
      await t.pump(); // first frame: initial value
      Countman.destroy();

      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets('calls onDone when countdown reaches zero', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(
        CountdownWidget(
          duration: const Duration(seconds: 2),
          onDone: () => done = true,
          builder: (_, r) => Text('${r.inSeconds}'),
        ),
      ));

      await t.pump(); // started

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      Countman.destroy();

      expect(done, isTrue);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('duration change restarts countdown', (t) async {
      Duration currentDuration = const Duration(minutes: 5);
      late StateSetter set;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        set = s;
        return CountdownWidget(
          duration: currentDuration,
          builder: (_, r) => Text(CountdownFormat.ms(r)),
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
        CountdownWidget(
          duration: const Duration(seconds: 10),
          controller: ctrl,
          builder: (_, r) => Text('${r.inSeconds}'),
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
        CountdownWidget(
          duration: const Duration(seconds: 2),
          plugin: group,
          onDone: () => done = true,
          builder: (_, r) => Text('${r.inSeconds}'),
        ),
      ));

      await t.pump(); // started

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      Countman.destroy();

      expect(done, isTrue);
    });

    testWidgets('disposes task when widget is removed', (t) async {
      final calls = <Duration>[];
      await t.pumpWidget(_wrap(
        CountdownWidget(
          duration: const Duration(seconds: 10),
          builder: (_, r) { calls.add(r); return const SizedBox(); },
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

  group('CountdownFormat', () {
    test('hms', () {
      expect(CountdownFormat.hms(const Duration(hours: 1, minutes: 23, seconds: 45)), '01:23:45');
      expect(CountdownFormat.hms(const Duration(hours: 10)), '10:00:00');
    });

    test('ms', () {
      expect(CountdownFormat.ms(const Duration(minutes: 3, seconds: 7)), '03:07');
      expect(CountdownFormat.ms(const Duration(minutes: 90, seconds: 5)), '90:05');
    });

    test('msTenths', () {
      expect(CountdownFormat.msTenths(
          const Duration(minutes: 1, seconds: 5, milliseconds: 350)), '01:05.3');
    });

    test('auto: ≥1h → hms', () {
      final s = CountdownFormat.auto(const Duration(hours: 2));
      expect(s.split(':').length, 3);
    });

    test('auto: <10s → msTenths', () {
      expect(CountdownFormat.auto(const Duration(seconds: 9, milliseconds: 700)), '00:09.7');
    });

    test('auto: 10s–59m59s → ms', () {
      expect(CountdownFormat.auto(const Duration(minutes: 2, seconds: 30)), '02:30');
    });
  });
}
