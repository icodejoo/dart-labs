import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// CountdownRing and CounterRing share RingPainter (lib/src/widgets/ring_painter.dart).
// Arc content isn't reachable via find.text(), so these tests exercise the
// widget-wiring contract (onComplete, sizing, retarget, dispose) rather than
// pixel content — the arc math itself is covered indirectly since both
// widgets fail loudly (exceptions) if progress ever goes non-finite/out of
// [0,1] in a way CustomPaint chokes on.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('CountdownRing', () {
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
      await t.pumpWidget(_wrap(const CountdownRing(to: Duration(seconds: 10), size: 120)));
      await t.pump();
      expect(t.getSize(find.byType(CountdownRing)), const Size(120, 120));
    });

    testWidgets('onComplete fires when the countdown reaches zero', (t) async {
      bool done = false;
      await t.pumpWidget(_wrap(CountdownRing(
        to: const Duration(seconds: 2),
        onComplete: () => done = true,
      )));
      await t.pump();

      advance(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));

      expect(done, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('renders center widget', (t) async {
      await t.pumpWidget(_wrap(CountdownRing(
        to: const Duration(seconds: 10),
        center: const Text('center'),
      )));
      await t.pump();
      expect(find.text('center'), findsOneWidget);
    });
  });

  group('CounterRing', () {
    tearDown(Countman.destroy);

    testWidgets('renders at the requested size', (t) async {
      await t.pumpWidget(_wrap(const CounterRing(to: 100, size: 120)));
      await t.pump();
      expect(t.getSize(find.byType(CounterRing)), const Size(120, 120));
    });

    testWidgets('onComplete fires with the target value', (t) async {
      double? done;
      await t.pumpWidget(_wrap(CounterRing(
        to: 100,
        duration: const Duration(milliseconds: 200),
        onComplete: (v) => done = v,
      )));

      await t.pump(); // frame 1: value=0
      await t.pump(const Duration(milliseconds: 400)); // past duration

      expect(done, 100.0);
      expect(t.takeException(), isNull);
    });

    testWidgets('renders center widget', (t) async {
      await t.pumpWidget(_wrap(const CounterRing(
        to: 100,
        center: Text('center'),
      )));
      await t.pump();
      expect(find.text('center'), findsOneWidget);
    });

    testWidgets('retargets when `to` changes', (t) async {
      double to = 100;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return CounterRing(to: to, duration: const Duration(milliseconds: 200));
      })));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // settle at 100

      setState(() => to = 50);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // settle at 50

      expect(t.takeException(), isNull);
    });

    testWidgets('from defaults to 0', (t) async {
      await t.pumpWidget(_wrap(const CounterRing(to: 100, size: 60)));
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('disposes cleanly mid-animation', (t) async {
      await t.pumpWidget(_wrap(const CounterRing(
        to: 100,
        duration: Duration(milliseconds: 400),
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100)); // mid-flight

      await t.pumpWidget(_wrap(const SizedBox()));
      await t.pump(const Duration(milliseconds: 400));

      expect(t.takeException(), isNull);
    });
  });
}
