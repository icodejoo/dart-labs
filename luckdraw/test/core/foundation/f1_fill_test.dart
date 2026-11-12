import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 像素断言使用的色标。
const List<LuckyColorStop> _stops = [
  LuckyColorStop(Color(0xffff0000)),
  LuckyColorStop(Color(0xff0000ff))
];

/// 验证 Canvas 的退化渐变空绘制语义。
void main() {
  test(
      'LuckyLegacyLinearFill > coincident endpoints paint transparent pixels for none and truncated subpixels',
      () async {
    for (final (direction, rect) in [
      (
        const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword.none),
        const Rect.fromLTWH(0, 0, 100, 1)
      ),
      (
        const LuckyLegacyGradientDirection.angle(0),
        const Rect.fromLTWH(0, 0, 0.5, 0.5)
      ),
    ]) {
      final paint = Paint();
      const LuckyLegacyLinearFill(LuckyLegacyGradientDirection.angle(0), _stops)
          .applyTo(paint, const Rect.fromLTWH(0, 0, 100, 1));
      LuckyLegacyLinearFill(direction, _stops).applyTo(paint, rect);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 100, 1), paint);
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 1);
      try {
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        expect(bytes, everyElement(0));
        expect(paint.shader, isNull);
      } finally {
        image.dispose();
        picture.dispose();
      }
    }
  });
}
