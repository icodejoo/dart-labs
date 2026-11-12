import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../foundation/constants.dart';
import '../foundation/unit_range.dart';

// 上游 utils/tween.ts:17-98；保持各公式的括号、乘法结合和时间钳制顺序。

/// 上游指数缓动的幂系数（tween.ts:80、85）。
const double _expoPower = 10;

/// 加减速曲线对；时间 t 达到时长 d 后按 d 计算，返回从 b 改变 c 的值。
///
/// 调用方须保证 d 为正；例如 `LuckyEasings.quad.easeOut(10, 0, 360, 2500)`。
abstract interface class LuckyEasing {
  /// 返回加速曲线在 [t] 时刻的值；[b] 为起点，[c] 为变化量，[d] 为正时长。
  double easeIn(double t, double b, double c, double d);

  /// 返回减速曲线在 [t] 时刻的值；参数单位须与 [d] 一致。
  double easeOut(double t, double b, double c, double d);
}

/// 上游二次缓动；例如 `const QuadEasing()`。
final class QuadEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const QuadEasing();

  /// 返回上游二次加速值。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final x = t / d;
    return c * x * x + b;
  }

  /// 返回上游二次减速值。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final x = t / d;
    return -c * x * (x - kLuckyHalfDivisor) + b;
  }
}

/// 上游三次缓动；例如 `const CubicEasing()`。
final class CubicEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const CubicEasing();

  /// 返回上游三次加速值。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final x = t / d;
    return c * x * x * x + b;
  }

  /// 返回上游三次减速值。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final y = t / d - 1;
    return c * (y * y * y + 1) + b;
  }
}

/// 上游四次缓动；例如 `const QuartEasing()`。
final class QuartEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const QuartEasing();

  /// 返回上游四次加速值。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final x = t / d;
    return c * x * x * x * x + b;
  }

  /// 返回上游四次减速值。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final y = t / d - 1;
    return -c * (y * y * y * y - 1) + b;
  }
}

/// 上游五次缓动；例如 `const QuintEasing()`。
final class QuintEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const QuintEasing();

  /// 返回上游五次加速值。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final x = t / d;
    return c * x * x * x * x * x + b;
  }

  /// 返回上游五次减速值。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final y = t / d - 1;
    return c * (y * y * y * y * y + 1) + b;
  }
}

/// 上游正弦缓动；例如 `const SineEasing()`。
final class SineEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const SineEasing();

  /// 返回上游正弦加速值。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    return -c * math.cos(t / d * (math.pi / kLuckyHalfDivisor)) + c + b;
  }

  /// 返回上游正弦减速值。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    return c * math.sin(t / d * (math.pi / kLuckyHalfDivisor)) + b;
  }
}

/// 上游指数缓动；例如 `const ExpoEasing()`。
final class ExpoEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const ExpoEasing();

  /// 返回指数加速值；t 为零时精确返回 b。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    return t == 0
        ? b
        : c * math.pow(kLuckyHalfDivisor, _expoPower * (t / d - 1)) + b;
  }

  /// 返回指数减速值；t 达到 d 时精确返回 b+c。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    return t == d
        ? b + c
        : c * (-math.pow(kLuckyHalfDivisor, -_expoPower * t / d) + 1) + b;
  }
}

/// 上游圆形缓动；例如 `const CircEasing()`。
final class CircEasing implements LuckyEasing {
  /// 创建无状态缓动。
  const CircEasing();

  /// 返回上游圆形加速值。
  @override
  double easeIn(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final x = t / d;
    return -c * (math.sqrt(1 - x * x) - 1) + b;
  }

  /// 返回上游圆形减速值。
  @override
  double easeOut(double t, double b, double c, double d) {
    if (t >= d) t = d;
    final y = t / d - 1;
    return c * math.sqrt(1 - y * y) + b;
  }
}

/// 以 Flutter Curve 适配时间与变化量；例如 `CurveEasing(Curves.easeIn)`。
final class CurveEasing implements LuckyEasing {
  /// 创建；[outCurve] 未给出时使用 [curve] 的翻转曲线。
  const CurveEasing(this.curve, {this.outCurve});

  /// 加速曲线。
  final Curve curve;

  /// 可选减速曲线。
  final Curve? outCurve;

  /// 将 t/d 限制在零到一后返回 b+c×曲线值。
  @override
  double easeIn(double t, double b, double c, double d) =>
      b + c * curve.transform(luckyUnit(t / d));

  /// 使用减速曲线返回相同单位下的值。
  @override
  double easeOut(double t, double b, double c, double d) {
    final x = luckyUnit(t / d);
    // 与 FlippedCurve.transform 相同，直接求值以保留 const API 且无需包装分配。
    final out = outCurve;
    return b +
        c * (out == null ? 1 - curve.transform(1 - x) : out.transform(x));
  }
}

/// 七个独立常量缓动的别名；例如 `LuckyEasings.quad`。
abstract final class LuckyEasings {
  /// 二次。
  static const LuckyEasing quad = QuadEasing();

  /// 三次。
  static const LuckyEasing cubic = CubicEasing();

  /// 四次。
  static const LuckyEasing quart = QuartEasing();

  /// 五次。
  static const LuckyEasing quint = QuintEasing();

  /// 正弦。
  static const LuckyEasing sine = SineEasing();

  /// 指数。
  static const LuckyEasing expo = ExpoEasing();

  /// 圆形。
  static const LuckyEasing circ = CircEasing();
}
