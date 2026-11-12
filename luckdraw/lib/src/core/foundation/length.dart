import 'package:flutter/foundation.dart';

import 'constants.dart';

/// 逻辑像素或相对指定基准的百分比长度，可保留负值。
///
/// 例如 `const LuckyLength.percent(50)` 表示基准的 50%。
@immutable
sealed class LuckyLength {
  /// 供长度子类调用的常量构造。
  const LuckyLength();

  /// 创建逻辑像素长度 [value]，不受解析基准影响。
  const factory LuckyLength.px(double value) = LuckyPx;

  /// 创建百分比长度，[value] 为百分数，例如 50 表示 50%。
  const factory LuckyLength.percent(double value) = LuckyPercent;

  /// 零逻辑像素长度。
  static const LuckyLength zero = LuckyPx(0);

  /// 根据 [base] 返回逻辑像素值；百分比遵循 `value * (base / 100)`。
  double resolve(double base);
}

/// 不随基准变化的逻辑像素长度。
final class LuckyPx extends LuckyLength {
  /// 以逻辑像素 [value] 创建长度。
  const LuckyPx(this.value);

  /// 逻辑像素值。
  final double value;

  /// 返回像素值，忽略 [base]。
  @override
  double resolve(double base) => value;

  /// 返回替换 [value] 的长度；未提供时保留原值。
  LuckyPx copyWith({double? value}) => LuckyPx(value ?? this.value);

  /// 比较像素长度值。
  @override
  bool operator ==(Object other) => other is LuckyPx && other.value == value;

  /// 与像素长度值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(LuckyPx, value);
}

/// 相对基准的百分比长度。
final class LuckyPercent extends LuckyLength {
  /// 以百分数 [value] 创建长度，例如 25 表示 25%。
  const LuckyPercent(this.value);

  /// 百分数值。
  final double value;

  /// 返回基准 [base] 的指定百分比，保留上游 changeUnits 运算顺序。
  @override
  double resolve(double base) => value * (base / kLuckyPercentScale);

  /// 返回替换 [value] 的长度；未提供时保留原值。
  LuckyPercent copyWith({double? value}) => LuckyPercent(value ?? this.value);

  /// 比较百分比长度值。
  @override
  bool operator ==(Object other) =>
      other is LuckyPercent && other.value == value;

  /// 与百分比长度值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(LuckyPercent, value);
}
