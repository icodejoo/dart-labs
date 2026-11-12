import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// golden 图像的默认像素通道差阈值。
const int kLuckyPixelTolerance = 32;

/// golden 图像的默认差异像素占比上限。
const double kLuckyMaxDiffRatio = 0.005;

/// golden 图像的默认全通道平均误差上限。
const double kLuckyMaxMeanError = 1.5;

/// 支持像素占比和平均通道误差的本地 golden 比较器。
class LuckyToleranceComparator extends LocalFileComparator {
  /// 使用测试文件 [testFile] 所在目录存储基线与失败图。
  LuckyToleranceComparator(
    super.testFile, {
    this.pixelTolerance = kLuckyPixelTolerance,
    this.maxDiffRatio = kLuckyMaxDiffRatio,
    this.maxMeanError = kLuckyMaxMeanError,
  })  : assert(pixelTolerance >= 0 && pixelTolerance <= 255),
        assert(maxDiffRatio >= 0 && maxDiffRatio <= 1),
        assert(maxMeanError >= 0);

  /// 沿用 [local] 的基线目录创建比较器。
  LuckyToleranceComparator.fromLocal(LocalFileComparator local)
      : this(local.basedir.resolve('flutter_test.dart'));

  /// 任一通道差严格大于此值时，该像素计为差异。
  final int pixelTolerance;

  /// 差异像素占比上限（包含边界）。
  final double maxDiffRatio;

  /// 全图 RGBA 每通道平均绝对误差上限（包含边界）。
  final double maxMeanError;

  /// 比较 PNG [imageBytes] 与基线 [golden]；失败时写出差异图并抛出错误。
  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final expected = Uint8List.fromList(await getGoldenBytes(golden));
    final actualImage = await _decode(imageBytes);
    ui.Image? expectedImage;
    try {
      expectedImage = await _decode(expected);
      var passes = false;
      if (actualImage.width == expectedImage.width &&
          actualImage.height == expectedImage.height) {
        final actual = (await actualImage.toByteData())!;
        final master = (await expectedImage.toByteData())!;
        var different = 0;
        var error = 0;
        const channels = 4;
        for (var i = 0; i < actual.lengthInBytes; i += channels) {
          var pixelDiffers = false;
          for (var c = 0; c < channels; c++) {
            final delta =
                (actual.getUint8(i + c) - master.getUint8(i + c)).abs();
            error += delta;
            pixelDiffers |= delta > pixelTolerance;
          }
          if (pixelDiffers) different++;
        }
        passes = different / (actualImage.width * actualImage.height) <=
                maxDiffRatio &&
            error / actual.lengthInBytes <= maxMeanError;
      }
      if (passes) return true;
      final result =
          await GoldenFileComparator.compareLists(imageBytes, expected);
      try {
        final message = await generateFailureOutput(result, golden, basedir);
        throw FlutterError(message);
      } finally {
        result.dispose();
      }
    } finally {
      actualImage.dispose();
      expectedImage?.dispose();
    }
  }
}

/// 解码一张 PNG 并释放临时编解码器。
Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
