// 直接读取内部数字字形表与画笔基类，验证公开格式化 API 与屏幕静止显示一致。
import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/types.dart'
    show numeralSystemDigits;
import 'package:countman/src/widgets/painter/painter.dart' show CounterPainter;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 画布上一个被绘制的元素：横坐标与对应字符串。
typedef _Drawn = ({double x, String text});

/// 记录静止时绘制的数位与分隔符，用来还原屏幕上的数字字符串。
class _RecordingPainter extends CounterPainter {
  /// 参数与默认画笔一致，由组件的 painterBuilder 转发。
  _RecordingPainter({
    required super.repaint,
    required super.digitValues,
    required super.style,
    required super.digitSize,
    required super.transition,
    required super.flipDirection,
    required super.increasing,
    required super.fractionDigits,
    required super.groupingPattern,
    required super.hideLeadingZeroes,
    required super.numeralSystem,
    super.numeralMapper,
    super.thousandSeparator,
    super.decimalSeparator,
    super.separatorStyle,
    super.padding,
    super.numberAlignment,
  });

  /// 最近一次绘制的元素，按绘制顺序。
  final drawn = <_Drawn>[];

  /// 数位绘制时的相位；静止时应恒为 0。
  final phases = <double>[];

  @override
  void paint(Canvas canvas, Size size) {
    drawn.clear();
    phases.clear();
    super.paint(canvas, size);
  }

  @override
  void paintTransition(
    Canvas canvas,
    int cur,
    int nxt,
    double p,
    double x,
    double h,
    double w,
  ) {
    phases.add(p);
    drawn.add((x: x, text: '$cur'));
  }

  @override
  void drawSeparator(Canvas c, double x, double h) =>
      drawn.add((x: x, text: thousandSeparator!));

  @override
  void drawDecimalSeparator(Canvas c, double x, double h) {
    if (fractionDigits == 0) return;
    drawn.add((x: x, text: decimalSeparator));
  }
}

/// 匹配语义文本里的数字（拉丁数字与小数点）之后的尾部缩写。
final _trailingAfterNumber = RegExp(r'[0-9.]([^0-9.]*)$');

/// 挂载一个 AnimatedCounter，等动画结束后返回屏幕上静止显示的字符串
/// （符号 + 数位与分隔符 + 紧凑缩写，不含 prefix/infix/suffix）。
Future<String> _shown(
  WidgetTester tester,
  num value,
  CounterFormat format, {
  num? minValue,
  num? maxValue,
}) async {
  _RecordingPainter? painter;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedCounter(
        key: UniqueKey(),
        value: value,
        initialValue: value,
        minValue: minValue,
        maxValue: maxValue,
        duration: const Duration(milliseconds: 10),
        format: format,
        painterBuilder:
            ({
              required repaint,
              required digitValues,
              required style,
              required digitSize,
              required transition,
              required flipDirection,
              required increasing,
              required fractionDigits,
              required groupingPattern,
              required hideLeadingZeroes,
              required numeralSystem,
              numeralMapper,
              thousandSeparator,
              decimalSeparator = '.',
              separatorStyle,
              padding = EdgeInsets.zero,
              numberAlignment = 0.0,
            }) => painter = _RecordingPainter(
              repaint: repaint,
              digitValues: digitValues,
              style: style,
              digitSize: digitSize,
              transition: transition,
              flipDirection: flipDirection,
              increasing: increasing,
              fractionDigits: fractionDigits,
              groupingPattern: groupingPattern,
              hideLeadingZeroes: hideLeadingZeroes,
              numeralSystem: numeralSystem,
              numeralMapper: numeralMapper,
              thousandSeparator: thousandSeparator,
              decimalSeparator: decimalSeparator,
              separatorStyle: separatorStyle,
              padding: padding,
              numberAlignment: numberAlignment,
            ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  final recorded = painter!;
  expect(recorded.phases.every((p) => p == 0), isTrue, reason: '数字应已静止');

  // 数位与分隔符按横坐标排序还原从左到右的顺序。
  final sorted = [...recorded.drawn]..sort((a, b) => a.x.compareTo(b.x));
  final system = format.numeralSystem ?? NumeralSystem.latin;
  final digits = StringBuffer();
  for (final item in sorted) {
    final digit = int.tryParse(item.text);
    final isGlyph = digit != null && item.text.length == 1;
    // 分隔符可能恰好是数字字符，因此用对象身份区分太脆弱；
    // 这里的用例不使用数字作分隔符，直接按文本判断。
    if (isGlyph) {
      digits.write(
        format.numeralMapper?.call(digit) ??
            numeralSystemDigits[system]![digit],
      );
    } else {
      digits.write(item.text);
    }
  }

  // 符号与紧凑缩写来自组件的语义文本（独立于 CounterFormat.format 的路径）。
  final label = tester
      .widget<Semantics>(
        find
            .descendant(
              of: find.byType(AnimatedCounter),
              matching: find.byType(Semantics),
            )
            .first,
      )
      .properties
      .label!;
  final sign = label.startsWith('-')
      ? '-'
      : label.startsWith('+')
      ? '+'
      : '';
  final suffix = _trailingAfterNumber.firstMatch(label)?.group(1) ?? '';
  return '$sign$digits$suffix';
}

/// 验证 CounterFormat.format 的输出与 AnimatedCounter 静止显示完全一致。
void main() {
  tearDown(Countman.destroy);

  /// 一组覆盖分组、小数、符号、缩写、字形与前导零的配置。
  final cases = <String, (num, CounterFormat)>{
    '分组与小数': (
      1234567.891,
      const CounterFormat(thousandSeparator: ',', fractionDigits: 2),
    ),
    '负数与自定义小数分隔符': (
      -1234.5,
      const CounterFormat(
        thousandSeparator: ' ',
        decimalSeparator: ',',
        fractionDigits: 1,
      ),
    ),
    '正号': (42, const CounterFormat(showPositiveSign: true)),
    '零值不加正号': (0, const CounterFormat(showPositiveSign: true)),
    '紧凑缩写': (1234567, const CounterFormat(compactNotation: true)),
    '紧凑缩写指定小数位': (
      1234567,
      const CounterFormat(compactNotation: true, compactFractionDigits: 2),
    ),
    '紧凑缩写负数': (-45000, const CounterFormat(compactNotation: true)),
    '自定义缩写表': (
      3200,
      const CounterFormat(
        compactNotation: true,
        compactAbbreviations: {1000: '千', 1000000: '百万'},
      ),
    ),
    '东阿拉伯数字': (
      2025,
      const CounterFormat(
        numeralSystem: NumeralSystem.easternArabic,
        thousandSeparator: ',',
      ),
    ),
    '自定义字形映射': (
      90210,
      CounterFormat(numeralMapper: (d) => String.fromCharCode(0x41 + d)),
    ),
    '隐藏前导零与 wholeDigits': (7, const CounterFormat(wholeDigits: 4)),
    '保留前导零': (7, const CounterFormat(wholeDigits: 4, hideLeadingZeroes: false)),
    '保留前导零且带小数': (
      3.5,
      const CounterFormat(
        wholeDigits: 3,
        hideLeadingZeroes: false,
        fractionDigits: 2,
        thousandSeparator: ',',
      ),
    ),
    '印度分组': (
      12345678,
      const CounterFormat(thousandSeparator: ',', groupingPattern: [3, 2]),
    ),
    '零带小数': (0, const CounterFormat(fractionDigits: 2)),
    '小于一的小数': (0.05, const CounterFormat(fractionDigits: 2)),
    '四舍五入进位': (0.999, const CounterFormat(fractionDigits: 2)),
    '大数分组': (9876543210, const CounterFormat(thousandSeparator: ',')),
  };

  for (final entry in cases.entries) {
    testWidgets('与屏幕静止显示一致：${entry.key}', (tester) async {
      final (value, format) = entry.value;
      final shown = await _shown(tester, value, format);
      expect(format.format(value), shown);
      Countman.destroy();
    });
  }

  testWidgets('minValue/maxValue 先钳制再格式化，与组件一致', (tester) async {
    const format = CounterFormat(fractionDigits: 1);
    final shown = await _shown(tester, 250, format, maxValue: 99.5);
    expect(format.format(250, maxValue: 99.5), shown);
    expect(shown, '99.5');
    Countman.destroy();
  });

  group('字面量输出', () {
    test('分组、小数与符号', () {
      const f = CounterFormat(thousandSeparator: ',', fractionDigits: 2);
      expect(f.format(1234.5), '1,234.50');
      expect(f.format(-1234567.891), '-1,234,567.89');
      expect(f.format(0), '0.00');
    });

    test('默认配置等同于四舍五入取整', () {
      expect(const CounterFormat().format(1234.567), '1235');
      expect(const CounterFormat().format(-0.4), '0');
    });

    test('紧凑缩写', () {
      expect(const CounterFormat(compactNotation: true).format(1500), '1.5K');
      expect(
        const CounterFormat(
          compactNotation: true,
          compactFractionDigits: 0,
        ).format(2500000),
        '3M',
      );
    });

    test('前导零与 wholeDigits', () {
      expect(const CounterFormat(wholeDigits: 3).format(5), '5');
      expect(
        const CounterFormat(wholeDigits: 3, hideLeadingZeroes: false).format(5),
        '005',
      );
    });

    test('非有限值按 0 处理，正号只对正数生效', () {
      const f = CounterFormat(showPositiveSign: true);
      expect(f.format(double.nan), '0');
      expect(f.format(double.infinity), '0');
      expect(f.format(3), '+3');
      expect(f.format(0), '0');
    });

    test('数字字形体系与自定义映射', () {
      expect(
        const CounterFormat(numeralSystem: NumeralSystem.persian).format(1204),
        '۱۲۰۴',
      );
      expect(CounterFormat(numeralMapper: (d) => '<$d>').format(10), '<1><0>');
    });
  });
}
