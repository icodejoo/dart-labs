import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/constants.dart';
import '../../core/game/layout.dart';
import '../../core/render/perf_trace.dart';
import '../model/number_wheel_config.dart';

/// 标签最小间距相对字号的比例（T5.5）。
const double _labelSpacing = 1.6;

/// 数字转盘不可变几何；全部半径使用逻辑像素。
@immutable
final class NumberWheelLayout extends LuckyLayout {
  /// 指定盒子、圆心、半径和标签抽稀间隔。
  const NumberWheelLayout(
      {required super.size,
      required this.center,
      required this.radius,
      required this.trackRadius,
      required this.pocketRadius,
      required this.labelRadius,
      required this.hubRadius,
      required this.ballSize,
      required this.labelEvery,
      required this.count});

  /// 圆心，遵循宿主对齐方式。
  final Offset center;

  /// 盘面外半径。
  final double radius;

  /// 小球外轨圆心半径。
  final double trackRadius;

  /// 格子环中线半径。
  final double pocketRadius;

  /// 标签中线半径。
  final double labelRadius;

  /// 中心按钮半径。
  final double hubRadius;

  /// 小球自身半径。
  final double ballSize;

  /// 每隔多少格显示一个标签；刻度仍然全部绘制。
  final int labelEvery;

  /// 格子数。
  final int count;

  /// 无半径或无号码时为空布局。
  @override
  bool get isEmpty => radius <= 0 || count == 0;
}

/// 为 [config] 计算盒子内布局；零尺寸返回空布局。
NumberWheelLayout computeNumberWheelLayout(
    NumberWheelConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.number_wheel.layout');
  try {
    final r = math.max(
        0.0, math.min(input.size.width, input.size.height) / kLuckyHalfDivisor);
    final o = config.options;
    final labelRadius =
        r * (o.labelInnerFactor + o.labelOuterFactor) / kLuckyHalfDivisor;
    final maxLabels = math.max(
        1,
        (kLuckyHalfDivisor *
                math.pi *
                labelRadius /
                math.max(1, config.style.fontSize * _labelSpacing))
            .floor());
    final alignment = input.alignment.resolve(input.textDirection);
    final origin = alignment.alongOffset(Offset(
        input.size.width - kLuckyHalfDivisor * r,
        input.size.height - kLuckyHalfDivisor * r));
    return NumberWheelLayout(
        size: input.size,
        center: origin + Offset(r, r),
        radius: r,
        trackRadius:
            r * (o.trackInnerFactor + o.trackOuterFactor) / kLuckyHalfDivisor,
        pocketRadius:
            r * (o.pocketInnerFactor + o.pocketOuterFactor) / kLuckyHalfDivisor,
        labelRadius: labelRadius,
        hubRadius: r * o.hubFactor,
        ballSize: r * o.ballRadiusFactor,
        labelEvery: math.max(1, (config.pockets.length / maxLabels).ceil()),
        count: config.pockets.length);
  } finally {
    luckyTraceEnd();
  }
}
