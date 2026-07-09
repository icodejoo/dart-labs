import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// dt-accumulation model needs ≥2 frames to show progress:
//   frame 1 (dt=0) → renders initial value (from), marks task started
//   frame 2 (dt>0) → accumulates time, progressing / done

void main() {
  late Counter plugin;

  setUp(() {
    plugin = Counter(name: 'test_counter');
    Countman.use(plugin);
  });

  tearDown(Countman.destroy);

  // ── direct tick() unit tests (no scheduler) ────────────────────────

  test('tick: onComplete fires when accumulated dt >= duration', () {
    final p = Counter(name: 'direct');
    p.onAttach(CountmanContext(requestFrame: () {}));

    double? done;
    p.add(CounterOptions(
      to: 100,
      duration: const Duration(milliseconds: 100),
      onComplete: (v) => done = v,
    ));

    p.tick(Duration.zero, Duration.zero);                                          // frame 1: started
    expect(done, isNull);
    p.tick(const Duration(milliseconds: 50), const Duration(milliseconds: 50));   // frame 2: t=0.5
    expect(done, isNull);
    p.tick(const Duration(milliseconds: 200), const Duration(milliseconds: 150)); // frame 3: accum≥dur
    expect(done, 100.0);
  });

  test('tick: onUpdate fires each frame', () {
    final p = Counter(name: 'direct2');
    p.onAttach(CountmanContext(requestFrame: () {}));

    final values = <double>[];
    p.add(CounterOptions(
      to: 100,
      duration: const Duration(milliseconds: 100),
      onUpdate: values.add,
    ));

    p.tick(Duration.zero, Duration.zero);                                          // frame 1: value=from=0
    p.tick(const Duration(milliseconds: 50), const Duration(milliseconds: 50));   // frame 2: t=0.5
    p.tick(const Duration(milliseconds: 200), const Duration(milliseconds: 150)); // frame 3: done

    expect(values[0], 0.0);
    expect(values[1], greaterThan(0));
    expect(values[1], lessThan(100));
    expect(values[2], 100.0);
  });

  // ── basic animation ────────────────────────────────────────────────

  testWidgets('animates from 0 to target', (tester) async {
    final values = <double>[];
    plugin.add(CounterOptions(
      to: 100,
      duration: const Duration(milliseconds: 100),
      onUpdate: values.add,
    ));

    await tester.pump();                                   // frame 1: value=0
    expect(values.last, 0.0);

    await tester.pump(const Duration(milliseconds: 50));  // frame 2: t=0.5
    expect(values.last, greaterThan(0));
    expect(values.last, lessThan(100));

    await tester.pump(const Duration(milliseconds: 200)); // frame 3: done
    expect(values.last, 100.0);

    Countman.destroy();
  });

  testWidgets('calls onComplete when animation completes', (tester) async {
    double? doneValue;
    plugin.add(CounterOptions(
      to: 50,
      duration: const Duration(milliseconds: 50),
      onComplete: (v) => doneValue = v,
    ));

    await tester.pump();                                   // frame 1: start
    await tester.pump(const Duration(milliseconds: 100)); // frame 2: accum≥dur → done
    Countman.destroy();

    expect(doneValue, 50.0);
  });

  testWidgets('respects custom from value', (tester) async {
    final values = <double>[];
    plugin.add(CounterOptions(
      from: 200,
      to: 300,
      duration: const Duration(milliseconds: 100),
      onUpdate: values.add,
    ));

    await tester.pump(); // frame 1: value = from = 200
    Countman.destroy();

    expect(values.first, 200.0);
  });

  testWidgets('zero duration completes on second frame', (tester) async {
    double? doneValue;
    plugin.add(CounterOptions(
      to: 42,
      duration: Duration.zero,
      onComplete: (v) => doneValue = v,
    ));

    await tester.pump();                                  // frame 1: started, busy
    await tester.pump(const Duration(milliseconds: 1));  // frame 2: duration=0 → t=1 immediately
    Countman.destroy();

    expect(doneValue, 42.0);
  });

  // ── handle: retarget ───────────────────────────────────────────────

  testWidgets('retarget continues from current value', (tester) async {
    final values = <double>[];
    final handle = plugin.add(CounterOptions(
      to: 100,
      duration: const Duration(milliseconds: 200),
      onUpdate: values.add,
    ));

    await tester.pump();                                   // frame 1: value=0
    await tester.pump(const Duration(milliseconds: 100)); // frame 2: t=0.5, value≈50
    final midValue = values.last;
    expect(midValue, greaterThan(0));
    expect(midValue, lessThan(100));

    handle.update(to: 200);
    await tester.pump();                                   // retarget frame 1: renders midValue
    expect(values.last, midValue);
    Countman.destroy();
  });

  testWidgets('cancel stops further updates', (tester) async {
    final values = <double>[];
    final handle = plugin.add(CounterOptions(
      to: 100,
      duration: const Duration(milliseconds: 200),
      onUpdate: values.add,
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    handle.cancel();
    final countAfterCancel = values.length;

    await tester.pump(const Duration(milliseconds: 200));
    Countman.destroy();

    expect(values.length, countAfterCancel);
  });

  // ── ticker integration ────────────────────────────────────────────

  testWidgets('ticker auto-stops when all tasks complete', (tester) async {
    plugin.add(CounterOptions(
      to: 10,
      duration: const Duration(milliseconds: 50),
    ));

    await tester.pump();                                   // frame 1: start
    await tester.pump(const Duration(milliseconds: 200)); // frame 2: done → idle
    expect(Countman.isRunning, isFalse);
  });

  testWidgets('multiple tasks run concurrently', (tester) async {
    final a = <double>[], b = <double>[];
    plugin.add(CounterOptions(to: 100, duration: const Duration(milliseconds: 100), onUpdate: a.add));
    plugin.add(CounterOptions(to: 200, duration: const Duration(milliseconds: 100), onUpdate: b.add));

    await tester.pump();                                   // frame 1: both at from=0
    await tester.pump(const Duration(milliseconds: 50));  // frame 2: both progressing

    expect(a.last, greaterThan(0));
    expect(b.last, greaterThan(0));
    Countman.destroy();
  });

  // ── top-level counter() ───────────────────────────────────────────

  testWidgets('counter() auto-bootstraps default plugin', (tester) async {
    double? result;
    counter(CounterOptions(
      to: 77,
      duration: const Duration(milliseconds: 50),
      onComplete: (v) => result = v,
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    Countman.destroy();

    expect(result, 77.0);
  });

  testWidgets('counter() re-registers after destroy()', (tester) async {
    double? first, second;

    counter(CounterOptions(to: 1, duration: const Duration(milliseconds: 50), onComplete: (v) => first = v));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    Countman.destroy();
    expect(first, 1.0);

    counter(CounterOptions(to: 2, duration: const Duration(milliseconds: 50), onComplete: (v) => second = v));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    Countman.destroy();
    expect(second, 2.0);
  });
}
