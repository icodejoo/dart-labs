import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 已加载的测试字体样式。
const TextStyle _style = TextStyle(fontFamily: 'Roboto', fontSize: 20);

/// 验证真实文字测量、缓存与释放。
void main() {
  group('TextPainterMeasurer', () {
    test('font size is truncated toward zero like fontSize >> 0', () {
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      expect(measurer.measure('Hello', _style.copyWith(fontSize: 20.9)),
          measurer.measure('Hello', _style));
      expect((measurer.debugPainters.single.text! as TextSpan).style!.fontSize,
          20);
    });
    test('measures with family weight and no text scaling by default', () {
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      final style = _style.copyWith(
          fontWeight: FontWeight.w700, fontFamilyFallback: ['sans-serif']);
      final width = measurer.measure('Hello', style);
      final painter = TextPainter(
          text: TextSpan(text: 'Hello', style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling)
        ..layout();
      addTearDown(painter.dispose);
      expect(width, painter.width);
      expect(width, greaterThan(0));
    });
    test('system text scaling multiplies font size when enabled', () {
      final normal = TextPainterMeasurer();
      final scaled =
          TextPainterMeasurer(textScaler: const TextScaler.linear(2));
      addTearDown(normal.dispose);
      addTearDown(scaled.dispose);
      expect(scaled.measure('Hello', _style),
          closeTo(normal.measure('Hello', _style) * 2, 0.001));
    });
    test('text direction follows the ambient direction for shaping only', () {
      final measurer = TextPainterMeasurer(textDirection: TextDirection.rtl);
      addTearDown(measurer.dispose);
      final width = measurer.measure('אבג abc', _style);
      expect(measurer.debugPainters.single.textDirection, TextDirection.rtl);
      final painter = TextPainter(
          text: const TextSpan(text: 'אבג abc', style: _style),
          textDirection: TextDirection.rtl)
        ..layout();
      addTearDown(painter.dispose);
      expect(width, painter.width);
    });
    test('reuses one TextPainter per style and disposes them', () {
      final measurer = TextPainterMeasurer();
      measurer.measure('a', _style);
      final first = measurer.debugPainters.single;
      measurer.measure(
          'b', const TextStyle(fontFamily: 'Roboto', fontSize: 20));
      expect(measurer.debugPainters.single, same(first));
      for (var i = 1; i < 32; i++) {
        measurer.measure('a', _style.copyWith(fontSize: 20.0 + i));
      }
      expect(measurer.debugPainters, hasLength(32));
      final old = measurer.debugPainters;
      measurer.measure('c', _style.copyWith(fontSize: 100));
      expect(measurer.debugPainters, hasLength(1));
      expect(old.every((painter) => painter.debugDisposed), isTrue);
      final last = measurer.debugPainters.single;
      measurer.dispose();
      expect(last.debugDisposed, isTrue);
      expect(measurer.debugPainters, isEmpty);
      measurer.dispose();
    });
    test(
        'trailing spaces are included in measured width like canvas measureText',
        () {
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      expect(measurer.measure('a ', _style),
          greaterThan(measurer.measure('a', _style)));
      expect(
          measurer.measure('a  ', _style),
          closeTo(
              measurer.measure('a', _style) + 2 * measurer.measure(' ', _style),
              0.001));
    });
    test('baseline offset converts a canvas baseline y into a paint offset',
        () {
      final measurer = TextPainterMeasurer();
      addTearDown(measurer.dispose);
      final baseline = measurer.baseline(_style);
      final painter = TextPainter(
          text: const TextSpan(text: ' ', style: _style),
          textDirection: TextDirection.ltr)
        ..layout();
      addTearDown(painter.dispose);
      expect(baseline,
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic));
      expect(baseline, greaterThan(0));
      expect(
          50 -
              baseline +
              painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
          50);
    });
  });
}
