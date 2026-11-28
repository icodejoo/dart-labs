import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'cache_repro.dart';

/// 验证坐标采样、像素差和路径轮廓回放。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('等相位贴回时读取同一个不透明纹素', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(158, 255, 5, 25),
      ui.Paint()..color = const ui.Color(0xff2864dc),
    );
    final picture = recorder.endRecording();
    try {
      final row = await capturePair(picture, targetFor(false), scene: false);
      expect(row['texel_xy'], [160, 134]);
      expect(row['direct'], [40, 100, 220, 255]);
      expect(row['texel'], row['direct']);
      expect(row['pasted'], row['direct']);
      expect(row['changed'], 0);
    } finally {
      picture.dispose();
    }
  });

  test('像素工具按行计算索引，按像素计变化并取最大通道差', () {
    final a = Uint8List.fromList([0, 0, 0, 0, 3, 9, 14, 255]);
    final b = Uint8List.fromList([0, 0, 0, 0, 23, 1, 20, 255]);
    expect(pixel(a, 1, 0, 1), [3, 9, 14, 255]);
    expect(diff(a, b), (changed: 1, maxDelta: 20));
  });

  test('复合路径保留相离轮廓，轮廓之间没有填充', () {
    final path = ui.Path();
    appendPath(path, [0, 1, 1, 4], [1, 1, 4, 1, 1, 4]);
    appendPath(path, [0, 1, 1, 4], [9, 9, 13, 9, 9, 13]);
    expect(path.contains(const ui.Offset(2, 2)), isTrue);
    expect(path.contains(const ui.Offset(10, 10)), isTrue);
    expect(path.contains(const ui.Offset(5, 5)), isFalse);
  });
}
