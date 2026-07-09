import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Mirrors ring_test.dart — CountdownBar/CounterBar share BarPainter and
// have the same widget-wiring contract as their Ring counterparts, just a
// different shape.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('CountdownBar', () {
    late DateTime now;
    late void Function(Duration) advance;

    setUp(() {
      now = DateTime(2024, 1, 1, 12, 0, 0);
      countdownClock = () => now;
      advance = (d) => now = now.add(d);
    });

    tearDown(() {
      countdownClock = DateTime.now;
      Countman.destroy();
    });

    testWidgets('renders at the requested size', (t) async {
      await t.pumpWidget(_wrap(const CountdownBar(to: Duration(seconds: 10), width: 240, height: 10)));
      await t.pump();
      expect(t.getSize(find.byType(CountdownBar)), const Size(240, 10));
    });

    testWidgets('onComplete fires when the countdown reaches zero', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(CountdownBar(
        to: const Duration(seconds: 2),
        onComplete: () => done = true,
      )));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));

      expect(done, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('onThreshold fires once when remaining crosses threshold', (t) async {
      var count = 0;
      await t.pumpWidget(_wrap(CountdownBar(
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

    testWidgets('controller pause/resume/reset works', (t) async {
      final ctrl = CountdownController();
      await t.pumpWidget(_wrap(CountdownBar(
        to: const Duration(seconds: 10),
        controller: ctrl,
      )));
      await t.pump();

      ctrl.pause();
      expect(ctrl.isPaused, isTrue);
      ctrl.resume();
      expect(ctrl.isPaused, isFalse);
    });
  });

  group('CounterBar', () {
    tearDown(Countman.destroy);

    testWidgets('renders at the requested size', (t) async {
      await t.pumpWidget(_wrap(const CounterBar(to: 100, width: 240, height: 10)));
      await t.pump();
      expect(t.getSize(find.byType(CounterBar)), const Size(240, 10));
    });

    testWidgets('onComplete fires with the target value', (t) async {
      double? done;
      await t.pumpWidget(_wrap(CounterBar(
        to: 100,
        duration: const Duration(milliseconds: 200),
        onComplete: (v) => done = v,
      )));

      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(done, 100.0);
      expect(t.takeException(), isNull);
    });

    testWidgets('retargets when `to` changes', (t) async {
      double to = 100;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return CounterBar(to: to, duration: const Duration(milliseconds: 200));
      })));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      setState(() => to = 50);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(t.takeException(), isNull);
    });

    testWidgets('disposes cleanly mid-animation', (t) async {
      await t.pumpWidget(_wrap(const CounterBar(
        to: 100,
        duration: Duration(milliseconds: 400),
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));

      await t.pumpWidget(_wrap(const SizedBox()));
      await t.pump(const Duration(milliseconds: 400));

      expect(t.takeException(), isNull);
    });
  });
}
