import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:luckdraw/wheel.dart';

/// 标准六奖品转盘；选奖权重均为一，默认遵循 time 与单调求解。
const WheelConfig kLuckyWheelFixture = WheelConfig(prizes: [
  WheelPrize(weight: 1, texts: [LuckyText('一等奖')]),
  WheelPrize(weight: 1, texts: [LuckyText('二等奖')]),
  WheelPrize(weight: 1, texts: [LuckyText('三等奖')]),
  WheelPrize(weight: 1, texts: [LuckyText('四等奖')]),
  WheelPrize(weight: 1, texts: [LuckyText('五等奖')]),
  WheelPrize(weight: 1, texts: [LuckyText('参与奖')]),
], buttons: [
  WheelButton(radius: LuckyLength.percent(30), pointer: true)
]);

/// 标准测试画布边长；玩法配置在对应模型落地后补充。
const double kLuckyFixtureSide = 300;

/// 创建指定 [color]、[width]、[height] 的内存图像；调用者负责 dispose。
Future<ui.Image> createLuckyTestImage(
    {required ui.Color color, int width = 1, int height = 1}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

/// 将 [image] 编码为 PNG；保留原图的所有权。
Future<Uint8List> luckyTestPng(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
