import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 将 [child] 放入具有文本方向的测试环境。
Widget _host(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

/// 读取 [tester] 中正在使用的数字画笔。
CounterPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<CounterPainter>()
    .single;

void main() {
  tearDown(Countman.destroy);

  test('CounterFormat 集合按值比较，函数按引用比较，copyWith 保留未指定字段', () {
    String mapper(int digit) => '$digit';
    final a = CounterFormat(
        groupingPattern: [3, 2],
        compactAbbreviations: {1000: 'k', 100: 'h'},
        numeralMapper: mapper);
    final b = CounterFormat(
        groupingPattern: [3, 2],
        compactAbbreviations: {100: 'h', 1000: 'k'},
        numeralMapper: mapper);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.copyWith(), a);
    expect(a.copyWith(fractionDigits: 2).fractionDigits, 2);
    expect(a.copyWith(fractionDigits: 2).groupingPattern, [3, 2]);
    expect(a.copyWith(numeralMapper: (digit) => '$digit'), isNot(a));
    expect(a.copyWith(groupingPattern: [2, 3]), isNot(a));
    expect(a.copyWith(compactAbbreviations: {100: 'x'}), isNot(a));
  });

  test('CounterFormat 所有标量字段参与相等性与 copyWith', () {
    const a = CounterFormat(
        fractionDigits: 2,
        wholeDigits: 4,
        hideLeadingZeroes: false,
        thousandSeparator: ',',
        decimalSeparator: ':',
        compactNotation: true,
        compactFractionDigits: 1,
        showPositiveSign: true,
        numeralSystem: NumeralSystem.persian);
    expect(a.copyWith(), a);
    final variants = [
      a.copyWith(fractionDigits: 3),
      a.copyWith(wholeDigits: 5),
      a.copyWith(hideLeadingZeroes: true),
      a.copyWith(thousandSeparator: '_'),
      a.copyWith(decimalSeparator: '.'),
      a.copyWith(compactNotation: false),
      a.copyWith(compactFractionDigits: 0),
      a.copyWith(showPositiveSign: false),
      a.copyWith(numeralSystem: NumeralSystem.latin)
    ];
    expect(variants, everyElement(isNot(a)));
    expect(a.copyWith(fractionDigits: 0).wholeDigits, 4);
  });

  for (final builder in [false, true]) {
    testWidgets('格式改变在启动延迟期间立即重算数位 builder=$builder', (tester) async {
      Future<void> mount(int digits) => tester.pumpWidget(_host(builder
          ? AnimatedCounterBuilder(
              value: 12,
              initialValue: 12,
              startDelay: const Duration(seconds: 1),
              format: CounterFormat(fractionDigits: digits))
          : AnimatedCounter(
              value: 12,
              initialValue: 12,
              startDelay: const Duration(seconds: 1),
              format: CounterFormat(fractionDigits: digits))));
      await mount(0);
      await mount(2);
      expect(tester.takeException(), isNull);
      if (builder) {
        expect(find.byType(DigitColumn), findsNWidgets(4));
      } else {
        expect(_painter(tester).digitValues.length, 4);
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('紧凑格式、正号与字形配置到达渲染器 builder=$builder', (tester) async {
      const format = CounterFormat(
          compactNotation: true,
          compactFractionDigits: 2,
          compactAbbreviations: {1000: '千'},
          wholeDigits: 3,
          hideLeadingZeroes: false,
          showPositiveSign: true,
          numeralSystem: NumeralSystem.persian);
      await tester.pumpWidget(_host(builder
          ? const AnimatedCounterBuilder(
              value: 1234, initialValue: 1234, format: format)
          : const AnimatedCounter(
              value: 1234, initialValue: 1234, format: format)));
      expect(find.text('千'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      if (builder) {
        final columns =
            tester.widgetList<DigitColumn>(find.byType(DigitColumn));
        expect(columns.length, 5);
        expect(columns.every((c) => c.numeralSystem == NumeralSystem.persian),
            isTrue);
      } else {
        final p = _painter(tester);
        expect(p.fractionDigits, 2);
        expect(p.digitValues.length, 5);
        expect(p.hideLeadingZeroes, isFalse);
        expect(p.numeralSystem, NumeralSystem.persian);
      }
    });

    testWidgets('格式对象覆盖平铺且 null 回退 builder=$builder', (tester) async {
      final format = CounterFormat(
          fractionDigits: 2, decimalSeparator: ':', groupingPattern: [3]);
      final Widget counter = builder
          ? AnimatedCounterBuilder(
              value: 1234.25,
              initialValue: 1234.25,
              fractionDigits: 1,
              thousandSeparator: ',',
              format: format)
          : AnimatedCounter(
              value: 1234.25,
              initialValue: 1234.25,
              fractionDigits: 1,
              thousandSeparator: ',',
              format: format);
      await tester.pumpWidget(_host(counter));
      if (builder) {
        expect(find.byType(DigitColumn), findsNWidgets(6));
        expect(find.text(':'), findsOneWidget);
        expect(find.text(','), findsOneWidget);
      } else {
        final p = _painter(tester);
        expect(p.fractionDigits, 2);
        expect(p.digitValues.length, 6);
        expect(p.decimalSeparator, ':');
        expect(p.thousandSeparator, ',');
      }
    });

    testWidgets('同值更新格式重算端点，等值对象不重启动画 builder=$builder', (tester) async {
      var starts = 0;
      Future<void> mount(CounterFormat format) =>
          tester.pumpWidget(_host(builder
              ? AnimatedCounterBuilder(
                  value: 12,
                  initialValue: 12,
                  format: format,
                  onAnimationStart: () => starts++)
              : AnimatedCounter(
                  value: 12,
                  initialValue: 12,
                  format: format,
                  onAnimationStart: () => starts++)));
      await mount(CounterFormat(fractionDigits: 0, groupingPattern: [3]));
      final before = builder ? null : _painter(tester);
      await mount(CounterFormat(fractionDigits: 0, groupingPattern: [3]));
      expect(starts, 0);
      if (!builder) expect(identical(before, _painter(tester)), isTrue);
      await mount(const CounterFormat(fractionDigits: 2));
      await tester.pumpAndSettle();
      if (builder) {
        final columns =
            tester.widgetList<DigitColumn>(find.byType(DigitColumn)).toList();
        expect(columns.length, 4);
        expect(columns.last.animationValue, 1200);
      } else {
        final after = _painter(tester);
        expect(after.digitValues.length, 4);
        expect(after.digitValues.last, 1200);
        expect(after.shouldRepaint(before!), isTrue);
        await mount(CounterFormat(fractionDigits: 2));
        expect(identical(after, _painter(tester)), isTrue);
      }
      final afterStarts = starts;
      await mount(CounterFormat(fractionDigits: 2));
      expect(starts, afterStarts);
    });
  }
}
