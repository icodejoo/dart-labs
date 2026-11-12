import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// 真画布与引擎光栅化，确保测试覆盖实际合成和裁切。
Future<List<int>> raster(
  WidgetTester tester,
  void Function(ui.Canvas) draw, {
  int width = 160,
  int height = 160,
}) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    draw(ui.Canvas(recorder));
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        return (await image.toByteData())!.buffer.asUint8List().toList();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }))!;
}

// 透视纹理采样和矢量抗锯齿允许小幅差异，但不能丢失可见区域。
void expectPixelsClose(
  List<int> actual,
  List<int> expected, {
  double meanTolerance = 1,
}) {
  expect(actual.length, expected.length);
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference += (actual[i] - expected[i]).abs();
  }
  expect(difference / actual.length, lessThanOrEqualTo(meanTolerance));
}
