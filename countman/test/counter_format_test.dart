import 'package:countman/countman.dart';
import 'package:countman/src/widgets/animated_counter/digit_column.dart';
import 'package:countman/src/widgets/animated_counter/number_format.dart';
import 'package:countman/src/widgets/animated_counter/digit_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 即使断言失败也释放全局调度器，避免影响后续渲染用例。
  tearDown(Countman.destroy);
  // 数值拆位和两条渲染路径必须使用同一份缩写、钳制与舍入结果。
  test('Simplify 1: formatting clamps, rounds and handles non-finite values',
      () {
    final format = CounterNumberFormat();
    expect(format.resolve(double.nan, fractionDigits: 2).scaledValue, 0);
    expect(format.resolve(double.infinity).scaledValue, 0);
    expect(format.resolve(-12.345, fractionDigits: 2).scaledValue, -1235);
    expect(format.resolve(42, minValue: 10, maxValue: 20).scaledValue, 20);
    expect(
        format.resolve(1.25, fractionDigits: 2).digits(3), [0, 0, 1, 12, 125]);
  });

  test('Simplify 2: compact defaults and custom thresholds share one ordering',
      () {
    final format = CounterNumberFormat();
    for (final entry in {1e3: 'K', 1e6: 'M', 1e9: 'B', 1e12: 'T'}.entries) {
      final result = format.resolve(-entry.key * 1.25, compactNotation: true);
      expect(result.scaledValue, -13);
      expect(result.fractionDigits, 1);
      expect(result.suffix, entry.value);
    }
    final abbreviations = <num, String>{100: 'h', 10000: 'w', 1000: 'k'};
    format.updateAbbreviations(abbreviations);
    expect(format.resolve(12345, compactNotation: true).suffix, 'w');
    expect(
        format
            .resolve(12345, compactNotation: true, compactFractionDigits: 0)
            .scaledValue,
        1);
    // 原地更新和替换字典都需刷新缓存，空字典仍表示禁用缩写。
    abbreviations[10000] = '万';
    format.updateAbbreviations(abbreviations);
    expect(format.resolve(12345, compactNotation: true).suffix, '万');
    format.updateAbbreviations({});
    expect(format.resolve(12345, compactNotation: true).suffix, isNull);
  });

  // 每次解析只扫描已排序条目，不在拆位或重建时重复排序。
  test('Simplify 2: unchanged abbreviation configuration reuses sorted entries',
      () {
    final format = CounterNumberFormat();
    format.updateAbbreviations({1000: 'k', 100: 'h'});
    final sorted = format.thresholds;
    format.resolve(1234, compactNotation: true);
    format.updateAbbreviations({100: 'h', 1000: 'k'});
    expect(identical(format.thresholds, sorted), isTrue);
    format.updateAbbreviations({100: 'hundred'});
    expect(identical(format.thresholds, sorted), isFalse);
  });

  // 共享布局只计算位次间距，保持隐藏列与完整预留宽度的分组规则一致。
  test('Simplify 1: digit spacing handles grouping and decimal boundaries', () {
    double spacing(int index, int first) => digitSpacingBefore(
          index: index,
          firstVisible: first,
          digitCount: 9,
          fractionDigits: 2,
          groupingPattern: const [3, 2],
          hasGrouping: true,
          separatorWidth: 4,
          decimalSeparatorWidth: 3,
        ).width;
    expect([for (var i = 0; i < 9; i++) spacing(i, 0)],
        [0, 0, 4, 0, 4, 0, 0, 3, 0]);
    expect(spacing(2, 2), 0);
    expect(spacing(4, 2), 4);
  });

  for (final builder in [false, true]) {
    // 同时检查渲染入口和动画端点，防止提取后的辅助类未被实际使用。
    testWidgets(
        'Simplify 1-2: shared formatting reaches renderer builder=$builder',
        (tester) async {
      final controller = AnimatedCounterController(initialValue: 1234);
      addTearDown(controller.dispose);
      final abbreviations = <num, String>{100: 'h', 1000: 'k'};
      Widget counter() => builder
          ? AnimatedCounterBuilder(
              controller: controller,
              initialValue: 1234,
              compactNotation: true,
              compactAbbreviations: abbreviations,
              duration: Duration.zero,
            )
          : AnimatedCounter(
              controller: controller,
              initialValue: 1234,
              compactNotation: true,
              compactAbbreviations: abbreviations,
              duration: Duration.zero,
            );
      Future<void> mount() => tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
                data: const MediaQueryData(), child: Center(child: counter())),
          ));
      List<double> renderedDigits() => builder
          ? tester
              .widgetList<DigitColumn>(find.byType(DigitColumn))
              .map((column) => column.animationValue)
              .toList()
          : tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((paint) => paint.painter)
              .whereType<CounterPainter>()
              .single
              .digitValues;

      await mount();
      expect(find.text('k'), findsOneWidget);
      expect(renderedDigits(), [1, 12]);
      // 原地修改字典后重建，缓存刷新；再变更数值验证动画端点仍一致。
      abbreviations[1000] = '千';
      await mount();
      expect(find.text('千'), findsOneWidget);
      controller.animateTo(2345);
      await tester.pump();
      expect(renderedDigits(), [2, 23]);
        // 不经父组件重建，控制器触发的新端点也应读取字典原地修改。
        abbreviations.remove(1000);
        controller.animateTo(3456);
        await tester.pump();
        expect(find.text('h'), findsOneWidget);
        expect(renderedDigits(), [3, 34, 346]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
