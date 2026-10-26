import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// 记录调用时的画笔状态，防止复用时残留发光效果。
class _TickCanvas implements Canvas {
  final paints = <Paint>{};
  final filters = <MaskFilter?>[];
  final paragraphs = <ui.Paragraph>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    paragraphs.add(paragraph);
  }

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    paints.add(paint);
    filters.add(paint.maskFilter);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// 分组边界从整数个位向左累计，小数位不参与分组。
void main() {
  tearDown(Countman.destroy);

  testWidgets('Dial 刻度标签绘制后释放段落资源', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: DialCountdown(
        to: Duration(seconds: 3),
        style: DialCountdownStyle(ticks: DialTicksConfig(showLabels: true)),
      ),
    ));
    final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((widget) => widget.painter != null);
    final canvas = _TickCanvas();
    paint.painter!.paint(canvas, const Size.square(200));
    expect(canvas.paragraphs, hasLength(12));
    expect(canvas.paragraphs.map((p) => p.debugDisposed), everyElement(isTrue));
  });

  testWidgets('Dial 刻度复用画笔且暗刻度不残留发光', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: DialCountdown(
        to: Duration(seconds: 3),
        style: DialCountdownStyle(glow: true),
      ),
    ));
    final paint = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((widget) => widget.painter != null);
    final canvas = _TickCanvas();
    paint.painter!.paint(canvas, const Size.square(200));
    expect(canvas.filters, hasLength(60));
    expect(canvas.filters.take(3), everyElement(isNotNull));
    expect(canvas.filters.skip(3), everyElement(isNull));
    expect(canvas.paints, hasLength(1));
  });

  for (final pattern in [<int>[3], <int>[3, 2], <int>[2, 3, 1]]) {
    final boundaries = pattern.length == 1
        ? [2, 5]
        : pattern.length == 2
            ? [1, 3, 5]
            : [1, 2, 3, 6];
    testWidgets('两条渲染路径共用分组边界 $pattern', (tester) async {
      final repaint = ChangeNotifier();
      final painter = CounterPainter(
        repaint: repaint,
        digitValues: List.filled(10, 1),
        style: const TextStyle(fontSize: 20),
        digitSize: const Size(20, 24),
        transition: CounterTransition.slide,
        flipDirection: AxisDirection.up,
        increasing: true,
        fractionDigits: 2,
        groupingPattern: pattern,
        hideLeadingZeroes: false,
        numeralSystem: NumeralSystem.latin,
        thousandSeparator: ',',
      );
      addTearDown(painter.disposeCache);
      addTearDown(repaint.dispose);
      expect(
        painter.buildColumns().where((c) => c.hasSeparator).map((c) => c.index),
        boundaries,
      );
      expect(painter.computeFullWidth(),
          200 + boundaries.length * painter.separatorWidth() + painter.decimalSeparatorWidth());

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: AnimatedCounterBuilder(
          value: 12345678.12,
          initialValue: 12345678.12,
          fractionDigits: 2,
          hideLeadingZeroes: false,
          groupingPattern: pattern,
          thousandSeparator: ',',
        ),
      ));
      final row = tester.widget<Row>(find.byType(Row).first);
      var digitCount = 0;
      final actual = <int>[];
      for (final child in row.children) {
        if (child is DigitColumn) digitCount++;
        if (child is Text && child.data == ',') actual.add(digitCount);
      }
      expect(actual, boundaries);
    });
  }
}

