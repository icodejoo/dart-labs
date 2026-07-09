import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart' show DigitColumn;

// AnimatedCounter had no test coverage before this file. These tests focus
// on what changed here: CounterTransitionType.flip now renders via the
// CustomPainter fast path (CounterPainter._flip, a Canvas rotateX
// perspective transform) instead of always forcing the DigitColumn widget
// fallback. digit_column.dart's flip case is still exercised — and still
// needed — whenever digitBuilder/digitTransitionBuilder is supplied, since
// those return arbitrary widgets that can't be paragraph-cached on Canvas.
//
// AnimatedCounter only animates on a VALUE CHANGE (didUpdateWidget) — it
// displays the initial `value` directly on mount with no transition. So
// every test that wants to exercise a transition mounts at one value, then
// changes it via setState.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  tearDown(Countman.destroy);

  /// Mounts at [from], pumps one frame, then changes to [to] and settles.
  Future<void> Function() animateTo(
    WidgetTester t, {
    required double from,
    required double to,
    required CounterTransitionType transitionType,
    Widget Function(BuildContext, int, TextStyle)? digitBuilder,
    VoidCallback? onAnimationEnd,
  }) {
    return () async {
      double value = from;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return AnimatedCounter(
          value: value,
          duration: const Duration(milliseconds: 200),
          transitionType: transitionType,
          digitBuilder: digitBuilder,
          onAnimationEnd: onAnimationEnd,
        );
      })));
      await t.pump();

      setState(() => value = to);
      await t.pumpAndSettle();
    };
  }

  group('AnimatedCounter transitions animate without throwing', () {
    for (final type in CounterTransitionType.values) {
      testWidgets('transitionType=$type animates 3 -> 42', (t) async {
        await animateTo(t, from: 3, to: 42, transitionType: type)();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('CounterTransitionType.flip', () {
    testWidgets('fast path (no digitBuilder) uses CustomPaint and settles cleanly', (t) async {
      await animateTo(t, from: 0, to: 7, transitionType: CounterTransitionType.flip)();

      expect(t.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets); // fast path uses CustomPaint
      expect(find.byType(DigitColumn), findsNothing); // fast path skips the widget fallback
    });

    testWidgets('slow path (with digitBuilder) still renders without throwing', (t) async {
      await animateTo(
        t,
        from: 0,
        to: 7,
        transitionType: CounterTransitionType.flip,
        digitBuilder: (_, digit, style) => Text('$digit', style: style),
      )();

      expect(t.takeException(), isNull);
      expect(find.byType(DigitColumn), findsWidgets); // digitBuilder forces the widget path
    });

    testWidgets('decreasing value (7 -> 2) animates without throwing', (t) async {
      await animateTo(t, from: 7, to: 2, transitionType: CounterTransitionType.flip)();
      expect(t.takeException(), isNull);
    });

    testWidgets('onAnimationEnd fires on a value change', (t) async {
      var ended = false;
      await animateTo(
        t,
        from: 0,
        to: 9,
        transitionType: CounterTransitionType.flip,
        onAnimationEnd: () => ended = true,
      )();

      expect(t.takeException(), isNull);
      expect(ended, isTrue);
    });

    testWidgets('disposes cleanly when removed mid-flip', (t) async {
      double value = 0;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        return AnimatedCounter(
          value: value,
          duration: const Duration(milliseconds: 300),
          transitionType: CounterTransitionType.flip,
        );
      })));
      await t.pump();

      setState(() => value = 88);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100)); // mid-flip

      await t.pumpWidget(_wrap(const SizedBox())); // remove while animating
      await t.pump(const Duration(milliseconds: 300));

      expect(t.takeException(), isNull);
    });
  });
}
