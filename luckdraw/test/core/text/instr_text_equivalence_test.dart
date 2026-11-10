import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

import 'package:luckdraw/src/core/text/text_measurer.dart'
    show normalizeLuckyCanvasText;

/// 与优化前相同，每次完整整形而不缓存宽度，返回精确宽度。
double _referenceWidth(
    String text, TextStyle style, TextDirection direction, TextScaler scaler) {
  final painter = TextPainter(
      text: TextSpan(
          text: normalizeLuckyCanvasText(text),
          style: style.copyWith(fontSize: style.fontSize?.truncateToDouble())),
      textDirection: direction,
      textScaler: scaler)
    ..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}

/// 随机、字体整形和换行边界保持逐位一致，缓存只减少重复布局。
void main() {
  group('TextPainterMeasurer INSTR', () {
    test(
        'cached widths and lineClamp match uncached multilingual and emoji shaping',
        () {
      final random = math.Random(20261111);
      const pieces = [
        'a',
        'V',
        'fi',
        ' ',
        '中',
        '文',
        'אב',
        'مرحبا',
        '😀',
        '👩‍💻',
        'é',
        '\n',
        '\t',
        '🇨🇳'
      ];
      const style = TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20.9,
          fontFamilyFallback: ['sans-serif']);
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        for (final scaler in [
          TextScaler.noScaling,
          const TextScaler.linear(1.3)
        ]) {
          final measurer =
              TextPainterMeasurer(textDirection: direction, textScaler: scaler);
          try {
            for (var sample = 0; sample < 70; sample++) {
              final text = List.generate(random.nextInt(15),
                  (_) => pieces[random.nextInt(pieces.length)]).join();

              /// 优化前每次完整整形的测量结果。
              double reference(String value) =>
                  _referenceWidth(value, style, direction, scaler);

              /// 新实现返回同一文本和样式的精确宽度。
              double cached(String value) => measurer.measure(value, style);
              expect(cached(text), reference(text));
              for (final clamp in [null, -1, 0, 1, 2, 4]) {
                final width = random.nextInt(120).toDouble() - 5;

                /// 每行逐渐缩窄以覆盖边界和提前返回。
                double maxWidth(int line) => width - line * 3;
                expect(
                    splitLuckyText(text, cached, maxWidth, lineClamp: clamp),
                    splitLuckyText(text, reference, maxWidth,
                        lineClamp: clamp));
              }
            }
          } finally {
            measurer.dispose();
          }
        }
      }
    });
    test(
        'repeated width hits avoid layout and dispose invalidates the bounded cache',
        () {
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      const style = TextStyle(fontFamily: 'Roboto', fontSize: 20);
      final first = measurer.measure('cached', style);
      measurer.measure('last layout', style);
      expect(measurer.measure('cached', style), first);
      expect((measurer.debugPainters.single.text! as TextSpan).text,
          'last layout');
      for (var index = 0; index < 260; index++) {
        expect(
            measurer.measure('text $index', style),
            _referenceWidth(
                'text $index', style, TextDirection.ltr, TextScaler.noScaling));
      }
      final old = measurer.debugPainters.single;
      measurer.dispose();
      expect(old.debugDisposed, isTrue);
      expect(measurer.measure('cached', style), first);
      expect(measurer.debugPainters.single, isNot(same(old)));
    });
  });
}
