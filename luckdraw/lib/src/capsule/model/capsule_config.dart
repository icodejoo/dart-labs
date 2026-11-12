import 'package:flutter/foundation.dart';

import 'capsule_parts.dart';

/// 扭蛋机配置；例如 `const CapsuleConfig(capsulesPerPrize: 3)`。
@immutable
final class CapsuleConfig {
  /// 创建不可变配置；列表由调用方保持不可变。
  const CapsuleConfig(
      {this.prizes = const [],
      this.capsules,
      this.capsulesPerPrize = 3,
      this.options = const CapsuleOptions(),
      this.style = const CapsuleStyle()});

  /// 奖品列表，每种奖品一种配色。
  final List<CapsulePrize> prizes;

  /// 球内胶囊对应奖品下标；空时按每奖数量生成。
  final List<int>? capsules;

  /// 每种奖品的默认胶囊数量。
  final int capsulesPerPrize;

  /// 布局和动画参数。
  final CapsuleOptions options;

  /// 外观配置。
  final CapsuleStyle style;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留全部字段。
  CapsuleConfig copyWith(
          {List<CapsulePrize>? prizes,
          List<int>? capsules,
          int? capsulesPerPrize,
          CapsuleOptions? options,
          CapsuleStyle? style}) =>
      CapsuleConfig(
          prizes: prizes ?? this.prizes,
          capsules: capsules ?? this.capsules,
          capsulesPerPrize: capsulesPerPrize ?? this.capsulesPerPrize,
          options: options ?? this.options,
          style: style ?? this.style);

  /// 按字段值比较，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is CapsuleConfig &&
      listEquals(other.prizes, prizes) &&
      listEquals(other.capsules, capsules) &&
      other.capsulesPerPrize == capsulesPerPrize &&
      other.options == options &&
      other.style == style;

  /// 与字段值一致的哈希。
  @override
  int get hashCode => Object.hashAll([
        Object.hashAll(prizes),
        Object.hashAll(capsules ?? const <int>[]),
        capsulesPerPrize,
        options,
        style
      ]);
}
