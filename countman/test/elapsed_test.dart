import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Same fake-clock approach as countdown_test.dart — countdownClock is shared
// by Countdown and Elapsed (both are wall-clock engines), so no separate
// injectable clock was needed for this feature.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late DateTime now;
  late void Function(Duration) advance;

  setUp(() {
    now = DateTime(2024, 1, 1, 12, 0, 0);
    countdownClock = () => now;
    advance = (d) => now = now.add(d);
  });

  tearDown(() {
    countdownClock = DateTime.now;
  });

  // ── Elapsed.tick() direct unit tests ──────────────────────────────────────

  group('Elapsed.tick direct', () {
    late Elapsed plugin;

    setUp(() {
      plugin = Elapsed(name: 'direct', interval: 1000);
      plugin.onAttach(CountmanContext(requestFrame: () {}));
    });

    test('first frame renders zero elapsed', () {
      TimeParts? got;
      plugin.add(ElapsedOptions(onUpdate: (e) => got = e));
      plugin.tick(Duration.zero, Duration.zero);
      expect(got?.value, Duration.zero);
    });

    test('interval=1000: onUpdate fires after 1s accumulates', () {
      final calls = <TimeParts>[];
      plugin.add(ElapsedOptions(onUpdate: calls.add));

      plugin.tick(Duration.zero, Duration.zero); // started: 0s
      expect(calls.length, 1);

      advance(const Duration(seconds: 1));
      plugin.tick(const Duration(seconds: 1), const Duration(seconds: 1));
      expect(calls.length, 2);
      expect(calls.last.inSeconds, 1);
    });

    test('never completes on its own — stays busy indefinitely', () {
      plugin.add(ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      advance(const Duration(hours: 100));
      final busy = plugin.tick(const Duration(hours: 100), const Duration(hours: 100));
      expect(busy, isTrue);
    });

    test('onThreshold fires once when elapsed crosses threshold', () {
      var count = 0;
      plugin.add(ElapsedOptions(
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      ));

      plugin.tick(Duration.zero, Duration.zero); // 0s
      advance(const Duration(seconds: 2));
      plugin.tick(const Duration(seconds: 2), const Duration(seconds: 2)); // 2s
      expect(count, 0);

      advance(const Duration(seconds: 2));
      plugin.tick(const Duration(seconds: 4), const Duration(seconds: 2)); // 4s — crosses
      expect(count, 1);

      advance(const Duration(seconds: 2));
      plugin.tick(const Duration(seconds: 6), const Duration(seconds: 2)); // 6s — already fired
      expect(count, 1);
    });

    test('returns false when all tasks paused', () {
      final handle = plugin.add(ElapsedOptions());
      plugin.tick(Duration.zero, Duration.zero);
      handle.pause();
      final busy = plugin.tick(const Duration(milliseconds: 16), const Duration(milliseconds: 16));
      expect(busy, isFalse);
    });
  });

  // ── ElapsedHandle ─────────────────────────────────────────────────────────

  group('ElapsedHandle', () {
    late Elapsed plugin;

    setUp(() {
      plugin = Elapsed(name: 'handle_test', interval: 1000);
      Countman.use(plugin);
    });

    testWidgets('pause freezes elapsed', (t) async {
      final handle = plugin.add(ElapsedOptions());
      await t.pump(); // 0s

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3)); // 3s
      handle.pause();
      final frozen = handle.elapsed;

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3)); // still frozen
      expect(handle.elapsed, frozen);
      Countman.destroy();
    });

    testWidgets('resume continues from paused elapsed', (t) async {
      final calls = <int>[];
      final handle = plugin.add(ElapsedOptions(onUpdate: (e) => calls.add(e.inSeconds)));

      await t.pump(); // 0s
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2)); // 2s
      handle.pause();

      advance(const Duration(seconds: 5)); // time passes while paused — must not count
      handle.resume();
      await t.pump(); // re-anchor frame

      advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1)); // 3s (2s + 1s), not 8s
      expect(calls.last, 3);
      Countman.destroy();
    });

    testWidgets('reset restarts from zero', (t) async {
      final calls = <int>[];
      final handle = plugin.add(ElapsedOptions(onUpdate: (e) => calls.add(e.inSeconds)));

      await t.pump();
      advance(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5)); // 5s

      handle.reset();
      await t.pump(); // re-anchor: back to 0s
      expect(calls.last, 0);
      Countman.destroy();
    });

    testWidgets('cancel stops updates', (t) async {
      final calls = <TimeParts>[];
      final handle = plugin.add(ElapsedOptions(onUpdate: calls.add));

      await t.pump();
      handle.cancel();
      final countBefore = calls.length;

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      expect(calls.length, countBefore);
      Countman.destroy();
    });
  });

  // ── elapsed() top-level ───────────────────────────────────────────────────

  group('elapsed() top-level', () {
    tearDown(Countman.destroy);

    testWidgets('auto-bootstraps default Elapsed instance', (t) async {
      var count = 0;
      elapsed(ElapsedOptions(onUpdate: (_) => count++));
      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      Countman.destroy(); // Elapsed never auto-completes — must stop the ticker explicitly
      expect(count, greaterThan(0));
    });
  });

  // ── ElapsedText ───────────────────────────────────────────────────────────

  group('ElapsedText', () {
    tearDown(Countman.destroy);

    testWidgets('renders 00:00 on first frame', (t) async {
      await t.pumpWidget(_wrap(const ElapsedText()));
      await t.pump();
      Countman.destroy();
      expect(find.text('00:00.0'), findsOneWidget); // auto formatter: <10s → msTenths
    });

    testWidgets('counts up with a custom formatter', (t) async {
      await t.pumpWidget(_wrap(ElapsedText(formatter: CountdownFormat.ms)));
      await t.pump();
      expect(find.text('00:00'), findsOneWidget);

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      Countman.destroy();
      expect(find.text('00:03'), findsOneWidget);
    });

    testWidgets('controller pause/resume/reset work', (t) async {
      final ctrl = ElapsedController();
      await t.pumpWidget(_wrap(ElapsedText(controller: ctrl, formatter: CountdownFormat.ms)));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      ctrl.pause();
      expect(ctrl.isPaused, isTrue);
      final frozen = ctrl.elapsed;

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      expect(ctrl.elapsed, frozen);

      ctrl.resume();
      await t.pump();
      expect(ctrl.isPaused, isFalse);

      ctrl.reset();
      await t.pump();
      expect(ctrl.elapsed, Duration.zero);
      Countman.destroy();
    });

    testWidgets('onThreshold fires once', (t) async {
      var count = 0;
      await t.pumpWidget(_wrap(ElapsedText(
        threshold: const Duration(seconds: 3),
        onThreshold: () => count++,
      )));
      await t.pump();
      expect(count, 0);

      advance(const Duration(seconds: 4));
      await t.pump(const Duration(seconds: 4));
      Countman.destroy();
      expect(count, 1);
    });

    testWidgets('custom plugin (group) is used', (t) async {
      final group = Elapsed(name: 'custom_elapsed_group', interval: 0);
      Countman.use(group);

      await t.pumpWidget(_wrap(ElapsedText(plugin: group, formatter: CountdownFormat.ms)));
      await t.pump();

      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));
      Countman.destroy();
      expect(find.text('00:02'), findsOneWidget);
    });

    testWidgets('disposes task when widget is removed', (t) async {
      final calls = <TimeParts>[];
      await t.pumpWidget(_wrap(ElapsedText(
        formatter: (d) { calls.add(d); return ''; },
      )));

      await t.pump();
      advance(const Duration(seconds: 2));
      await t.pump(const Duration(seconds: 2));

      await t.pumpWidget(_wrap(const SizedBox()));
      final countAfterRemove = calls.length;

      advance(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));
      Countman.destroy();

      expect(calls.length, countAfterRemove);
    });
  });
}
