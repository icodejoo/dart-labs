import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart' show DigitColumn;

// AnimatedCounter (painter-only fast path) and AnimatedCounterBuilder (widget-tree
// path) tests.
//
// AnimatedCounter uses CounterPainter for all transitions — zero widget builds
// per frame. AnimatedCounterBuilder is needed when digitBuilder /
// digitTransitionBuilder supply arbitrary widgets.
//
// Both widgets animate only on a VALUE CHANGE (didUpdateWidget) — they display
// the initial value on mount with no transition. Tests mount at one value, then
// change it via setState.

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  tearDown(Countman.destroy);

  /// Mounts at [from], pumps one frame, then changes to [to] and settles.
  /// Uses [AnimatedCounterBuilder] when [digitBuilder] is supplied, otherwise
  /// [AnimatedCounter] (painter-only fast path).
  Future<void> Function() animateTo(
    WidgetTester t, {
    required double from,
    required double to,
    required CounterTransition transition,
    Widget Function(BuildContext, int, TextStyle)? digitBuilder,
    VoidCallback? onAnimationEnd,
  }) {
    return () async {
      double value = from;
      late StateSetter setState;

      await t.pumpWidget(_wrap(StatefulBuilder(builder: (_, s) {
        setState = s;
        if (digitBuilder != null) {
          return AnimatedCounterBuilder(
            value: value,
            duration: const Duration(milliseconds: 200),
            transition: transition,
            digitBuilder: digitBuilder,
            onAnimationEnd: onAnimationEnd,
          );
        }
        return AnimatedCounter(
          value: value,
          duration: const Duration(milliseconds: 200),
          transition: transition,
          onAnimationEnd: onAnimationEnd,
        );
      })));
      await t.pump();

      setState(() => value = to);
      await t.pumpAndSettle();
    };
  }

  group('AnimatedCounter transitions animate without throwing', () {
    const transitions = <CounterTransition>[
      CounterTransition.slide,
      CounterTransition.slideScale,
      CounterTransition.slideBlur,
      CounterTransition.rotate,
      CounterTransition.flip,
      CounterTransition.flipFade,
      CounterTransition(motion: CounterMotion.none),                 // pure fade
      CounterTransition(motion: CounterMotion.none, scale: true),    // scale in place
    ];
    for (final type in transitions) {
      testWidgets('transition=$type animates 3 -> 42', (t) async {
        await animateTo(t, from: 3, to: 42, transition: type)();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('CounterTransition.flip', () {
    testWidgets('fast path (no digitBuilder) uses CustomPaint and settles cleanly', (t) async {
      await animateTo(t, from: 0, to: 7, transition: CounterTransition.flip)();

      expect(t.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets); // fast path uses CustomPaint
      expect(find.byType(DigitColumn), findsNothing); // fast path skips the widget fallback
    });

    testWidgets('slow path (with digitBuilder) still renders without throwing', (t) async {
      await animateTo(
        t,
        from: 0,
        to: 7,
        transition: CounterTransition.flip,
        digitBuilder: (_, digit, style) => Text('$digit', style: style),
      )();

      expect(t.takeException(), isNull);
      expect(find.byType(DigitColumn), findsWidgets); // digitBuilder forces the widget path
    });

    testWidgets('decreasing value (7 -> 2) animates without throwing', (t) async {
      await animateTo(t, from: 7, to: 2, transition: CounterTransition.flip)();
      expect(t.takeException(), isNull);
    });

    testWidgets('onAnimationEnd fires on a value change', (t) async {
      var ended = false;
      await animateTo(
        t,
        from: 0,
        to: 9,
        transition: CounterTransition.flip,
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
          transition: CounterTransition.flip,
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

  // Regression: the per-digit prototype cell must be measured with the strings
  // the counter actually renders (numeralMapper / numeralSystem), not the Latin
  // '0'. Wider output — circled numbers ①–⑨ in production, or multi-character
  // mapper strings — used to overflow a '0'-sized cell and get clipped in half.
  //
  // Note: the widget-test font renders every glyph as a uniform square, so a
  // single wide glyph can't be distinguished from '0' by width here. These
  // tests use multi-character mapper output, which is wider in any font and so
  // exercises the same "measure the real rendered string" code path.
  //
  // 回归测试：每个数字的原型单元格必须用计数器真正渲染的字符串（numeralMapper /
  // numeralSystem）来测量，而不是拉丁 '0'。更宽的输出——生产中的圆圈数字 ①–⑨，
  // 或多字符 mapper 字符串——以前会溢出按 '0' 尺寸计算的单元格并被裁掉一半。
  //
  // 注意：widget 测试字体把每个字形都渲染成统一方块，因此这里无法凭宽度区分单个
  // 宽字形与 '0'。这些测试改用多字符 mapper 输出（在任何字体下都更宽），从而覆盖
  // 同一条“按真正渲染的字符串来测量”的代码路径。
  group('prototype cell sizing', () {
    const style = TextStyle(fontSize: 40);

    // Render a single-digit AnimatedCounter and return its laid-out size.
    //
    // 渲染单个数字的 AnimatedCounter 并返回其布局尺寸。
    Future<Size> sizeOf(WidgetTester t, {String Function(int)? mapper}) async {
      // Unique key ⇒ a fresh State each call, matching the real case of two
      // independent AnimatedCounters (never a live mapper swap on one widget).
      // 唯一 key ⇒ 每次调用得到全新 State，对应两个独立 AnimatedCounter 的真实
      // 场景（而非在同一 widget 上热切换 mapper）。
      await t.pumpWidget(_wrap(AnimatedCounter(
        key: UniqueKey(),
        value: 9,
        duration: const Duration(milliseconds: 1),
        textStyle: style,
        numeralMapper: mapper,
      )));
      await t.pump();
      return t.getSize(find.byType(AnimatedCounter));
    }

    testWidgets('wide mapper output widens the digit cell (no clip)', (t) async {
      final plain = await sizeOf(t);
      // Every digit maps to a 3-char string → cell must be ~3× wider.
      // 每个数字都映射为 3 字符字符串 → 单元格宽度需约为 3 倍。
      final wide = await sizeOf(t, mapper: (d) => '[$d]');

      expect(wide.width, greaterThan(plain.width),
          reason: 'cell must widen to fit the mapped string');
    });

    testWidgets('cell fits the widest digit among 0–9, not just the shown one',
        (t) async {
      // Only digit 4 maps to a wide string; showing digit 9 (narrow) must still
      // reserve the wide cell so an animation rolling through 4 never clips.
      // 只有数字 4 映射为宽字符串；即便显示数字 9（窄）也要预留宽单元格，
      // 使滚动经过 4 时不会被裁剪。
      final narrowOnly = await sizeOf(t, mapper: (d) => '$d');
      final oneWide = await sizeOf(t, mapper: (d) => d == 4 ? 'WWWW' : '$d');

      expect(oneWide.width, greaterThan(narrowOnly.width),
          reason: 'cell must fit the widest of 0–9, not just the shown digit');
    });
  });
}
