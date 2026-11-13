import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/foundation/constants.dart';
import 'package:luckdraw/src/core/foundation/fill.dart';
import 'package:luckdraw/src/core/render/paint_helpers.dart';

/// 回归绘制资源的复用、复位和圆形路径隔离。
void main() {
  group('paint helpers', () {
    test('shared paint preserves identity and resets all six properties', () {
      const color = Color(0xFF123456);
      const width = 3.0;
      final paint = luckyScratchPaint(
          color: color,
          style: PaintingStyle.stroke,
          strokeWidth: width,
          filterQuality: FilterQuality.high);
      expect(paint.color, isSameColorAs(color));
      expect(paint.style, PaintingStyle.stroke);
      expect(paint.strokeWidth, width);
      expect(paint.filterQuality, FilterQuality.high);
      paint.shader = ui.Gradient.linear(
          Offset.zero, const Offset(10, 10), [color, kLuckyDefaultFontColor]);
      paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, width);

      final reset = luckyScratchPaint();
      expect(reset, same(paint));
      expect(reset.color, isSameColorAs(kLuckyDefaultFontColor));
      expect(reset.style, PaintingStyle.fill);
      expect(reset.strokeWidth, 0);
      expect(reset.filterQuality, FilterQuality.none);
      expect(reset.shader, isNull);
      expect(reset.maskFilter, isNull);
    });

    test('successive ovals match independent paths without retained geometry',
        () async {
      const size = 32;
      const bounds = [
        Rect.fromLTWH(1, 2, 10, 12),
        Rect.fromLTWH(16, 14, 14, 16)
      ];
      const colors = [Color(0xFFFF0000), Color(0xFF0000FF)];
      final actualRecorder = ui.PictureRecorder();
      final expectedRecorder = ui.PictureRecorder();
      final actualCanvas = Canvas(actualRecorder);
      final expectedCanvas = Canvas(expectedRecorder);
      for (var i = 0; i < bounds.length; i++) {
        paintLuckyOval(actualCanvas, bounds[i], LuckyFill.color(colors[i]));
        expectedCanvas.drawPath(
            Path()..addOval(bounds[i]), Paint()..color = colors[i]);
      }
      final actualPicture = actualRecorder.endRecording();
      final expectedPicture = expectedRecorder.endRecording();
      addTearDown(actualPicture.dispose);
      addTearDown(expectedPicture.dispose);
      final actual = await actualPicture.toImage(size, size);
      final expected = await expectedPicture.toImage(size, size);
      addTearDown(actual.dispose);
      addTearDown(expected.dispose);
      expect((await actual.toByteData())!.buffer.asUint8List(),
          (await expected.toByteData())!.buffer.asUint8List());
    });
  });
}
