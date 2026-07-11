import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart' show DigitColumn;

// AnimatedCounter (painter-only fast path) and CustomDigitCounter (widget-tree
// path) tests.
//
// AnimatedCounter uses CounterPainter for all transitions — zero widget builds
// per frame. CustomDigitCounter is needed when digitBuilder /
// digitTransitionBuilder supply arbitrary widgets.
//
// Both widgets animate only on a VALUE CHANGE (didUpdateWidget) — they display
// the initial value on mount with no transition. Tests mount at one value, then
// change it via setState.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  tearDown(Countman.destroy);

  /// Mounts at [from], pumps one frame, then changes to [to] and settles.
  /// Uses [CustomDigitCounter] when [digitBuilder] is supplied, otherwise
  /// [AnimatedCounter] (painter-only fast path).
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
        if (digitBuilder != null) {
          return CustomDigitCounter(
            value: value,
            duration: const Duration(milliseconds: 200),
            transitionType: transitionType,
            digitBuilder: digitBuilder,
            onAnimationEnd: onAnimationEnd,
          );
        }
        return AnimatedCounter(
          value: value,
          duration: const Duration(milliseconds: 200),
          transitionType: transitionType,
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
