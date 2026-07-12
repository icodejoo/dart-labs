import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

/// Tests for the G4–G7 API expansion: widget lifecycle callbacks, property
/// overrides, CounterValueController, and the scope providers.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // ── G4: widget lifecycle callbacks ─────────────────────────────────────────
  group('G4 lifecycle callbacks', () {
    tearDown(Countman.destroy);

    testWidgets('counter widget fires onReady / onStart', (t) async {
      final events = <String>[];
      await t.pumpWidget(wrap(CounterText(
        to: 100,
        duration: const Duration(milliseconds: 100),
        onReady: () => events.add('ready'),
        onStart: () => events.add('start'),
      )));
      // onReady is synchronous at enqueue (first build).
      expect(events, contains('ready'));
      await t.pump(); // first rendered frame → onStart
      expect(events, contains('start'));
      Countman.destroy();
    });

    testWidgets('counter widget fires onCancel when removed early', (t) async {
      var cancelled = false;
      await t.pumpWidget(wrap(CounterText(
        to: 100,
        duration: const Duration(seconds: 10),
        onCancel: () => cancelled = true,
      )));
      await t.pump();
      await t.pumpWidget(wrap(const SizedBox())); // dispose before completion
      expect(cancelled, isTrue);
      Countman.destroy();
    });

    testWidgets('countdown widget fires onPause / onResume via controller', (t) async {
      final events = <String>[];
      final ctrl = CountdownController();
      await t.pumpWidget(wrap(CountdownText(
        to: const Duration(seconds: 30),
        controller: ctrl,
        onPause: () => events.add('pause'),
        onResume: () => events.add('resume'),
      )));
      await t.pump();
      ctrl.pause();
      ctrl.resume();
      expect(events, ['pause', 'resume']);
      Countman.destroy();
    });
  });

  // ── G5: property overrides ──────────────────────────────────────────────────
  group('G5 property overrides', () {
    tearDown(Countman.destroy);

    test('RingPainter shouldRepaint reacts to new style params', () {
      const base = RingPainter(
          progress: 0.5, color: Color(0xFF000000), trackColor: Color(0xFF111111),
          strokeWidth: 8, clockwise: true);
      const diffAngle = RingPainter(
          progress: 0.5, color: Color(0xFF000000), trackColor: Color(0xFF111111),
          strokeWidth: 8, clockwise: true, startAngle: 0);
      const diffCap = RingPainter(
          progress: 0.5, color: Color(0xFF000000), trackColor: Color(0xFF111111),
          strokeWidth: 8, clockwise: true, strokeCap: StrokeCap.butt);
      expect(base.shouldRepaint(diffAngle), isTrue);
      expect(base.shouldRepaint(diffCap), isTrue);
    });

    test('BarPainter shouldRepaint reacts to fillFromStart / per-corner radius', () {
      const base = BarPainter(
          progress: 0.5, color: Color(0xFF000000), trackColor: Color(0xFF111111));
      const fromEnd = BarPainter(
          progress: 0.5, color: Color(0xFF000000), trackColor: Color(0xFF111111),
          fillFromStart: false);
      final perCorner = BarPainter(
          progress: 0.5, color: const Color(0xFF000000), trackColor: const Color(0xFF111111),
          borderRadiusGeometry: BorderRadius.circular(6));
      expect(base.shouldRepaint(fromEnd), isTrue);
      expect(base.shouldRepaint(perCorner), isTrue);
    });

    testWidgets('CounterText fractionDigits formats without a formatter', (t) async {
      await t.pumpWidget(wrap(const CounterText(from: 1.25, to: 1.25, fractionDigits: 2)));
      await t.pump();
      expect(find.text('1.25'), findsOneWidget);
      Countman.destroy();
    });

    testWidgets('CounterRing gradient + custom startAngle render without throwing', (t) async {
      await t.pumpWidget(wrap(CounterRing(
        to: 100,
        duration: const Duration(milliseconds: 100),
        style: const CounterRingStyle(
          gradient: SweepGradient(colors: [Colors.red, Colors.blue]),
          startAngle: 0,
          trackStrokeWidth: 4,
        ),
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(testerOk, isTrue);
      Countman.destroy();
    });

    testWidgets('AnimatedCounter honors curveForDigit / interpolation / colorResolver / painterBuilder', (t) async {
      var builderCalled = false;
      var resolverCalled = false;
      await t.pumpWidget(wrap(AnimatedCounter(
        value: 1234,
        initialValue: 0,
        duration: const Duration(milliseconds: 100),
        curveForDigit: (_) => Curves.easeIn,
        interpolation: (from, to, tt) => from + (to - from) * tt,
        colorResolver: (v) { resolverCalled = true; return v > 0 ? Colors.green : null; },
        painterBuilder: ({
          required repaint, required digitValues, required style, required digitSize,
          required transitionType, required flipDirection, required increasing,
          required fractionDigits, required groupingPattern, required hideLeadingZeroes,
          required numeralSystem, numeralMapper, thousandSeparator,
          decimalSeparator = '.', separatorStyle,
          padding = EdgeInsets.zero, numberAlignment = 0.0,
        }) {
          builderCalled = true;
          return CounterPainter(
            repaint: repaint, digitValues: digitValues, style: style, digitSize: digitSize,
            transitionType: transitionType, flipDirection: flipDirection, increasing: increasing,
            fractionDigits: fractionDigits, groupingPattern: groupingPattern,
            hideLeadingZeroes: hideLeadingZeroes, numeralSystem: numeralSystem,
            numeralMapper: numeralMapper, thousandSeparator: thousandSeparator,
            decimalSeparator: decimalSeparator, separatorStyle: separatorStyle, padding: padding,
          );
        },
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 200));
      expect(builderCalled, isTrue);
      expect(resolverCalled, isTrue);
      Countman.destroy();
    });

    testWidgets('CounterOdometer slideCurve / fadeEnabled render without throwing', (t) async {
      await t.pumpWidget(wrap(const CounterOdometer(
        to: 42, slideCurve: Curves.easeOut,
        style: CounterOdometerStyle(
          fadeEnabled: false,
          crossAxisAlignment: CrossAxisAlignment.center,
        ),
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1200));
      expect(testerOk, isTrue);
      Countman.destroy();
    });
  });

  // ── G6: CounterValueController ─────────────────────────────────────────────────
  group('G6 CounterValueController', () {
    tearDown(Countman.destroy);

    testWidgets('value tracks animation; cancel stops updates', (t) async {
      final ctrl = CounterValueController();
      await t.pumpWidget(wrap(CounterText(
        to: 100, duration: const Duration(milliseconds: 400), controller: ctrl,
      )));
      await t.pump();                                  // value = 0
      expect(ctrl.value, 0);
      await t.pump(const Duration(milliseconds: 200)); // mid
      expect(ctrl.value, greaterThan(0));

      final mid = ctrl.value;
      ctrl.cancel();
      await t.pump(const Duration(milliseconds: 400));
      expect(ctrl.value, mid); // no further updates after cancel
      Countman.destroy();
    });

    testWidgets('update retargets from the current value', (t) async {
      final ctrl = CounterValueController();
      await t.pumpWidget(wrap(CounterText(
        to: 100, duration: const Duration(milliseconds: 200), controller: ctrl,
      )));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      ctrl.update(to: 500);
      await t.pump();                                  // anchor retarget (dt=0)
      await t.pump(const Duration(milliseconds: 400)); // finish
      expect(ctrl.value, 500);
      Countman.destroy();
    });
  });

  // ── G7: providers ───────────────────────────────────────────────────────────
  group('G7 providers', () {
    tearDown(Countman.destroy);

    testWidgets('CounterProvider supplies textStyle; widget value wins', (t) async {
      await t.pumpWidget(wrap(CounterProvider(
        textStyle: const TextStyle(fontSize: 40),
        child: Column(children: const [
          CounterText(to: 10, key: Key('inherit')),
          CounterText(to: 10, style: CounterTextStyle(textStyle: TextStyle(fontSize: 12)), key: Key('override')),
        ]),
      )));
      await t.pump();

      Text textOf(Key k) => t.widget<Text>(
          find.descendant(of: find.byKey(k), matching: find.byType(Text)));
      expect(textOf(const Key('inherit')).style?.fontSize, 40);
      expect(textOf(const Key('override')).style?.fontSize, 12);
      Countman.destroy();
    });

    testWidgets('CounterProvider group callbacks fire on ready / drain', (t) async {
      final events = <String>[];
      await t.pumpWidget(wrap(CounterProvider(
        onGroupReady: () => events.add('ready'),
        onAllComplete: () => events.add('drained'),
        child: const CounterText(to: 5, duration: Duration(milliseconds: 100)),
      )));
      await t.pump();                                  // enqueue + first frame
      expect(events, contains('ready'));
      await t.pump(const Duration(milliseconds: 300)); // complete → drain
      expect(events, contains('drained'));
      Countman.destroy();
    });

    testWidgets('CountdownProvider supplies textStyle to CountdownText', (t) async {
      await t.pumpWidget(wrap(CountdownProvider(
        textStyle: const TextStyle(fontSize: 33),
        child: const CountdownText(to: Duration(minutes: 1), key: Key('cd')),
      )));
      await t.pump();
      final text = t.widget<Text>(
          find.descendant(of: find.byKey(const Key('cd')), matching: find.byType(Text)));
      expect(text.style?.fontSize, 33);
      Countman.destroy();
    });

    testWidgets('ElapsedProvider supplies textStyle to ElapsedText', (t) async {
      await t.pumpWidget(wrap(ElapsedProvider(
        textStyle: const TextStyle(fontSize: 21),
        child: const ElapsedText(key: Key('el')),
      )));
      await t.pump();
      final text = t.widget<Text>(
          find.descendant(of: find.byKey(const Key('el')), matching: find.byType(Text)));
      expect(text.style?.fontSize, 21);
      Countman.destroy();
    });
  });
}

/// Sentinel used by "renders without throwing" cases — reaching the assertion
/// means no exception was thrown during pump.
const bool testerOk = true;
