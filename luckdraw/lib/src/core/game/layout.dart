import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../text/text_measurer.dart';

/// 与渲染后端无关的不可变布局。
@immutable
abstract class LuckyLayout {
  /// 指定布局盒子逻辑尺寸。
  const LuckyLayout({required this.size});

  /// 布局盒子逻辑尺寸。
  final Size size;

  /// 是否没有可绘制或命中的内容。
  bool get isEmpty;

  /// 布局为空时是否仍要绘制装饰（如 blocks 外框）；默认不绘制。
  bool get paintsWhenEmpty => false;
}

/// 布局环境；例如 `LuckyLayoutInput.headless(const Size(300, 300))`。
@immutable
final class LuckyLayoutInput {
  /// 创建环境，调用方负责释放 [measurer]。
  const LuckyLayoutInput(
      {required this.size,
      required this.devicePixelRatio,
      required this.measurer,
      this.textDirection = TextDirection.ltr,
      this.alignment = Alignment.topLeft});

  /// 创建无头布局环境，用完须调用 `input.measurer.dispose()`。
  factory LuckyLayoutInput.headless(Size size, {double devicePixelRatio = 1}) =>
      LuckyLayoutInput(
          size: size,
          devicePixelRatio: devicePixelRatio,
          measurer: TextPainterMeasurer());

  /// 盒子尺寸。
  final Size size;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 文字测量器。
  final LuckyTextMeasurer measurer;

  /// 文字整形方向。
  final TextDirection textDirection;

  /// 非正方形盒子的对齐。
  final AlignmentGeometry alignment;
}
