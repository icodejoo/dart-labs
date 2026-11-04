import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:countman/src/widgets/painter/counter_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 为回归用例提供布局和文字环境。
Widget wrap(Widget child) => MaterialApp(home: Center(child: child));

/// 验证中断、跳转和完成后的控制命令。
void main() {
  tearDown(Countman.destroy);
  testWidgets('fast 静态非零端点正确初始化', (t) async {
    await t.pumpWidget(wrap(const AnimatedCounterBuilder(value: 42, initialValue: 42, fast: true)));
    expect(find.text('4'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });
  testWidgets('中途更新沿用当前屏幕值且方向正确', (t) async {
    final c = AnimatedCounterController();
    await t.pumpWidget(wrap(AnimatedCounterBuilder(controller: c, duration: const Duration(seconds: 1))));
    c.animateTo(100);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    final before = t.widgetList<DigitColumn>(find.byType(DigitColumn)).last.animationValue;
    c.animateTo(50);
    await t.pump();
    final after = t.widgetList<DigitColumn>(find.byType(DigitColumn)).last;
    expect(after.animationValue, closeTo(before, 3));
    expect(after.increasing, isTrue);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('同目标 jumpTo 跳过延迟错峰回弹且 resume 不重播', (t) async {
    final c = AnimatedCounterController();
    var ends = 0;
    await t.pumpWidget(wrap(AnimatedCounterBuilder(controller: c,
      startDelay: const Duration(milliseconds: 100),
      staggerDelay: const Duration(milliseconds: 50), bounceOvershoot: .3,
      onAnimationEnd: () => ends++)));
    c.animateTo(100);
    await t.pump(const Duration(milliseconds: 150));
    c.jumpTo(100);
    await t.pump();
    expect(c.status, AnimationStatus.completed);
    final count = ends;
    c.resume();
    await t.pump(const Duration(seconds: 2));
    expect(ends, count);
    expect(find.text('1'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('紧凑格式语义保留小数与后缀', (t) async {
    await t.pumpWidget(wrap(const AnimatedCounter(value: 1200000, initialValue: 1200000, compactNotation: true)));
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '1.2M'), findsOneWidget);
  });
  testWidgets('startDelay 内 restart 保留目标端点', (t) async {
    final c = AnimatedCounterController();
    await t.pumpWidget(wrap(AnimatedCounterBuilder(controller: c, startDelay: const Duration(seconds: 1))));
    c.animateTo(10);
    c.restart();
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.text('1'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('start 回调里的跳转不会被外层转换覆盖', (t) async {
    final c = AnimatedCounterController();
    var entered = false;
    await t.pumpWidget(wrap(AnimatedCounterBuilder(controller: c, onAnimationStart: () {
      if (!entered) { entered = true; c.jumpTo(7); }
    })));
    c.animateTo(100);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('仅修改 maxValue 重新钳制数位', (t) async {
    await t.pumpWidget(wrap(const AnimatedCounterBuilder(value: 50, initialValue: 50, maxValue: 100)));
    await t.pumpWidget(wrap(const AnimatedCounterBuilder(value: 50, initialValue: 50, maxValue: 10, duration: Duration.zero)));
    expect(find.text('1'), findsWidgets);
    expect(find.text('5'), findsNothing);
  });
  testWidgets('reverse 发方向和 dismissed 且暂停保持方向', (t) async {
    final c = AnimatedCounterController();
    final statuses = <AnimationStatus>[];
    c.addStatusListener(statuses.add);
    await t.pumpWidget(wrap(AnimatedCounterBuilder(controller: c)));
    c.animateTo(20);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    c.reverse();
    expect(c.status, AnimationStatus.reverse);
    c.pause();
    expect(c.status, AnimationStatus.reverse);
    c.resume();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(statuses, containsAllInOrder([AnimationStatus.forward, AnimationStatus.reverse, AnimationStatus.dismissed]));
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final usePainter in [false, true]) {
    testWidgets('fast 收起旧高位并隐藏分组符 painter=$usePainter', (t) async {
      final c = AnimatedCounterController(initialValue: 1000);
      final Widget child = usePainter
          ? AnimatedCounter(controller: c, initialValue: 1000, fast: true, thousandSeparator: ',')
          : AnimatedCounterBuilder(controller: c, initialValue: 1000, fast: true, thousandSeparator: ',');
      await t.pumpWidget(wrap(child));
      c.animateTo(7);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      if (usePainter) {
        final p = t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<CounterPainter>().single;
        expect(p.buildColumns().length, 1);
      } else {
        expect(find.text(','), findsNothing);
        expect(t.widgetList<DigitColumn>(find.byType(DigitColumn)).where((w) => w.visible).length, 1);
      }
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
    testWidgets('方向颜色作用到数字 painter=$usePainter', (t) async {
      final c = AnimatedCounterController();
      const style = AnimatedCounterStyle(textStyle: TextStyle(color: Colors.black), increasingColor: Colors.green);
      await t.pumpWidget(wrap(usePainter ? AnimatedCounter(controller: c, style: style) : AnimatedCounterBuilder(controller: c, style: style)));
      c.animateTo(20);
      await t.pump();
      if (usePainter) {
        final p = t.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<CounterPainter>().single;
        expect(p.digitColorFor(1).toARGB32(), Colors.green.toARGB32());
      } else {
        expect(t.widgetList<DigitColumn>(find.byType(DigitColumn)).first.color.toARGB32(), Colors.green.toARGB32());
      }
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  test('小数位大于 20 在构造时拒绝', () {
    expect(() => AnimatedCounter(value: 1, fractionDigits: 21), throwsAssertionError);
    expect(() => CounterFormat(compactFractionDigits: 21), throwsAssertionError);
  });
  testWidgets('非有限值按零显示', (t) async {
    for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
      await t.pumpWidget(wrap(AnimatedCounterBuilder(key: ValueKey(value), value: value, initialValue: value)));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('0'), findsOneWidget);
    }
  });
}
