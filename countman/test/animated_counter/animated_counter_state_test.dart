// ignore_for_file: deprecated_member_use_from_same_package
import 'package:countman/countman.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 为回归用例提供布局和文字环境。
Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

/// 记录两张数位字形的实际画布坐标。
class _MotionCanvas implements Canvas {
  /// 绘制字形时的坐标。
  final offsets = <Offset>[];

  /// 记录字形而无需光栅化。
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    offsets.add(offset);
  }

  /// 其他画布操作不参与位移验证。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 从两条渲染路径读取个位的累计位置。
double position(WidgetTester t, bool usePainter) => usePainter
    ? t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<CounterPainter>()
        .single
        .digitValues
        .last
    : t.widgetList<DigitColumn>(find.byType(DigitColumn)).last.animationValue;

/// 验证中断、跳转和完成后的控制命令。
void main() {
  tearDown(Countman.destroy);
  testWidgets('fast 静态非零端点正确初始化', (t) async {
    await t.pumpWidget(wrap(
        const AnimatedCounterBuilder(value: 42, initialValue: 42, fast: true)));
    expect(find.text('4'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });
  testWidgets('中途更新沿用当前屏幕值且方向正确', (t) async {
    final c = AnimatedCounterController();
    await t.pumpWidget(wrap(AnimatedCounterBuilder(
        controller: c, duration: const Duration(seconds: 1))));
    c.animateTo(100);
    await t.pump();
    await t.pump(const Duration(milliseconds: 233));
    final before =
        t.widgetList<DigitColumn>(find.byType(DigitColumn)).last.animationValue;
    c.animateTo(50);
    await t.pump();
    final after = t.widgetList<DigitColumn>(find.byType(DigitColumn)).last;
    expect(after.animationValue, closeTo(before, 1e-6));
    expect(after.increasing, isTrue);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('同目标 jumpTo 跳过延迟错峰回弹且 resume 不重播', (t) async {
    final c = AnimatedCounterController();
    var ends = 0;
    await t.pumpWidget(wrap(AnimatedCounterBuilder(
        controller: c,
        startDelay: const Duration(milliseconds: 100),
        staggerDelay: const Duration(milliseconds: 50),
        bounceOvershoot: .3,
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
    await t.pumpWidget(wrap(const AnimatedCounter(
        value: 1200000, initialValue: 1200000, compactNotation: true)));
    expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '1.2M'),
        findsOneWidget);
  });
  testWidgets('startDelay 内 restart 保留目标端点', (t) async {
    final c = AnimatedCounterController();
    await t.pumpWidget(wrap(AnimatedCounterBuilder(
        controller: c, startDelay: const Duration(seconds: 1))));
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
    await t.pumpWidget(wrap(AnimatedCounterBuilder(
        controller: c,
        onAnimationStart: () {
          if (!entered) {
            entered = true;
            c.jumpTo(7);
          }
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
    await t.pumpWidget(wrap(const AnimatedCounterBuilder(
        value: 50, initialValue: 50, maxValue: 100)));
    await t.pumpWidget(wrap(const AnimatedCounterBuilder(
        value: 50, initialValue: 50, maxValue: 10, duration: Duration.zero)));
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
    expect(
        statuses,
        containsAllInOrder([
          AnimationStatus.forward,
          AnimationStatus.reverse,
          AnimationStatus.dismissed
        ]));
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final usePainter in [false, true]) {
    testWidgets('0→100 中途改到 200 连续单调 painter=$usePainter', (t) async {
      final c = AnimatedCounterController();
      await t.pumpWidget(wrap(usePainter
          ? AnimatedCounter(controller: c, duration: const Duration(seconds: 1))
          : AnimatedCounterBuilder(
              controller: c, duration: const Duration(seconds: 1))));
      c.animateTo(100);
      await t.pump();
      await t.pump(const Duration(milliseconds: 233));
      var before = position(t, usePainter);
      expect(before, inInclusiveRange(15, 25));
      c.animateTo(200);
      await t.pump();
      expect(position(t, usePainter), closeTo(before, 1e-6));
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 100));
        final current = position(t, usePainter);
        expect(current, greaterThanOrEqualTo(before - 1));
        before = current;
      }
      expect(before, 200);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
    testWidgets('fast 收起旧高位并隐藏分组符 painter=$usePainter', (t) async {
      final c = AnimatedCounterController(initialValue: 1000);
      final Widget child = usePainter
          ? AnimatedCounter(
              controller: c,
              initialValue: 1000,
              fast: true,
              thousandSeparator: ',')
          : AnimatedCounterBuilder(
              controller: c,
              initialValue: 1000,
              fast: true,
              thousandSeparator: ',');
      await t.pumpWidget(wrap(child));
      c.animateTo(7);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      if (usePainter) {
        final p = t
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<CounterPainter>()
            .single;
        expect(p.buildColumns().length, 1);
      } else {
        expect(find.text(','), findsNothing);
        expect(
            t
                .widgetList<DigitColumn>(find.byType(DigitColumn))
                .where((w) => w.visible)
                .length,
            1);
      }
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
    testWidgets('方向颜色作用到数字 painter=$usePainter', (t) async {
      final c = AnimatedCounterController();
      const style = AnimatedCounterStyle(
          textStyle: TextStyle(color: Colors.black),
          increasingColor: Colors.green);
      await t.pumpWidget(wrap(usePainter
          ? AnimatedCounter(controller: c, style: style)
          : AnimatedCounterBuilder(controller: c, style: style)));
      c.animateTo(20);
      await t.pump();
      if (usePainter) {
        final p = t
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((w) => w.painter)
            .whereType<CounterPainter>()
            .single;
        expect(p.digitColorFor(1).toARGB32(), Colors.green.toARGB32());
      } else {
        expect(
            t
                .widgetList<DigitColumn>(find.byType(DigitColumn))
                .first
                .color
                .toARGB32(),
            Colors.green.toARGB32());
      }
      await t.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  test('小数位大于 20 在构造时拒绝', () {
    expect(() => AnimatedCounter(value: 1, fractionDigits: 21),
        throwsAssertionError);
    expect(
        () => CounterFormat(compactFractionDigits: 21), throwsAssertionError);
  });
  testWidgets('非有限值按零显示', (t) async {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      await t.pumpWidget(wrap(AnimatedCounterBuilder(
          key: ValueKey(value), value: value, initialValue: value)));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('0'), findsOneWidget);
    }
  });
  testWidgets('运行中 resume 不回退且完成后 resume 不重复回调', (t) async {
    final c = AnimatedCounterController();
    var ends = 0;
    await t.pumpWidget(wrap(
        AnimatedCounterBuilder(controller: c, onAnimationEnd: () => ends++)));
    c.animateTo(100);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final before = position(t, false);
    c.resume();
    await t.pump(const Duration(milliseconds: 16));
    expect(position(t, false), greaterThanOrEqualTo(before));
    await t.pump(const Duration(seconds: 1));
    expect(ends, 1);
    c.resume();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(ends, 1);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('reverse 已在起点时立即报告 dismissed 并结束一次', (t) async {
    final c = AnimatedCounterController();
    final statuses = <AnimationStatus>[];
    var ends = 0;
    c.addStatusListener(statuses.add);
    await t.pumpWidget(wrap(
        AnimatedCounterBuilder(controller: c, onAnimationEnd: () => ends++)));
    c.animateTo(100);
    c.reverse();
    await t.pump();
    expect(statuses.last, AnimationStatus.dismissed);
    expect(ends, 1);
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('紧凑格式中途更新保留数值数量级', (t) async {
    final c = AnimatedCounterController(initialValue: 1000000);
    await t.pumpWidget(wrap(AnimatedCounterBuilder(
        controller: c,
        initialValue: 1000000,
        compactNotation: true,
        duration: const Duration(seconds: 1),
        autoEaseThreshold: double.infinity)));
    c.animateTo(2000000);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    final before = position(t, false);
    c.animateTo(3000000);
    await t.pump();
    expect(position(t, false), closeTo(before, 1));
    expect(position(t, false), greaterThanOrEqualTo(10));
    await t.pumpWidget(const SizedBox());
    c.dispose();
  });
  test('横向 slide 使用宽度沿 x 轴且匹配 widget 方向约定', () {
    final notifier = ChangeNotifier();
    for (final direction in [AxisDirection.left, AxisDirection.right]) {
      final p = CounterPainter(
          repaint: notifier,
          digitValues: [1.25],
          style: const TextStyle(fontSize: 20),
          digitSize: const Size(20, 30),
          transition: CounterTransition.slide,
          flipDirection: direction,
          increasing: true,
          fractionDigits: 0,
          groupingPattern: const [3],
          hideLeadingZeroes: true,
          numeralSystem: NumeralSystem.latin);
      final canvas = _MotionCanvas();
      p.paintTransition(canvas, 1, 2, .25, 0, 30, 20);
      expect(
          canvas.offsets.first.dx, direction == AxisDirection.right ? 5 : -5);
      expect(canvas.offsets.first.dy, 0);
      p.disposeCache();
    }
    notifier.dispose();
  });
  testWidgets('Builder 保留自定义分隔符和符号淡入例外', (t) async {
    const sign = SizedBox(key: ValueKey('sign'), width: 8, height: 8);
    await t.pumpWidget(wrap(const AnimatedCounterBuilder(
        value: -1234.5,
        initialValue: -1234.5,
        fractionDigits: 1,
        thousandSeparator: ',',
        thousandSeparatorWidget: Text('group'),
        decimalSeparatorWidget: Text('decimal'),
        negativeSignWidget: sign)));
    expect(find.text('group'), findsOneWidget);
    expect(find.text('decimal'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('sign')),
            matching: find.byType(Opacity)),
        findsOneWidget);
    final source =
        File('lib/src/widgets/animated_counter/animated_counter.dart')
            .readAsStringSync();
    expect('painter 路径不支持分隔符 widget'.allMatches(source).length,
        greaterThanOrEqualTo(2));
  });
}
