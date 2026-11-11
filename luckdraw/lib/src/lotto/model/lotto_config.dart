import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/fill.dart';
import '../../core/motion/result.dart';
import 'lotto_options.dart';

export 'lotto_options.dart';

/// 默认的白色号码文字。
const Color _white = Color(0xFFFFFFFF);

/// 号码池；调用方须保持配置列表不可变。
@immutable
final class LottoPool {
  /// 创建号码范围和抽取数量；必须满足 min ≤ max 且 0 < count ≤ 范围长度。
  const LottoPool(
      {required this.min,
      required this.max,
      required this.count,
      required this.ballFill,
      this.textColor = _white,
      this.label})
      : assert(min <= max),
        assert(count > 0),
        assert(count <= max - min + 1);

  /// 最小号码（含）。
  final int min;

  /// 最大号码（含）。
  final int max;

  /// 每局抽取数量。
  final int count;

  /// 球体填充。
  final LuckyFill ballFill;

  /// 号码文字色。
  final Color textColor;

  /// 可选号码池标签。
  final String? label;

  /// 返回替换非空参数的副本；例如 `pool.copyWith(count: 1)`。
  LottoPool copyWith(
          {int? min,
          int? max,
          int? count,
          LuckyFill? ballFill,
          Color? textColor,
          String? label}) =>
      LottoPool(
          min: min ?? this.min,
          max: max ?? this.max,
          count: count ?? this.count,
          ballFill: ballFill ?? this.ballFill,
          textColor: textColor ?? this.textColor,
          label: label ?? this.label);

  /// 按号码范围、数量与外观比较。
  @override
  bool operator ==(Object other) =>
      other is LottoPool &&
      other.min == min &&
      other.max == max &&
      other.count == count &&
      other.ballFill == ballFill &&
      other.textColor == textColor &&
      other.label == label;

  /// 与相等性一致的哈希。
  @override
  int get hashCode => Object.hash(min, max, count, ballFill, textColor, label);
}

/// 大乐透前区：35 选 5。
const LottoPool kSuperLottoFront = LottoPool(
    min: 1,
    max: 35,
    count: 5,
    ballFill: LuckyFill.color(Color(0xFFE53935)),
    label: '前区');

/// 大乐透后区：12 选 2。
const LottoPool kSuperLottoBack = LottoPool(
    min: 1,
    max: 12,
    count: 2,
    ballFill: LuckyFill.color(Color(0xFF1E88E5)),
    label: '后区');

/// 摇奖配置；例如 `LottoConfig.superLotto()`。
@immutable
final class LottoConfig {
  /// 创建一个或多个号码池；列表及其内容在使用期间应保持不可变。
  const LottoConfig(
      {required this.pools,
      this.options = const LottoOptions(),
      this.style = const LottoStyle()});

  /// 创建唯一内置预设：前区 35 选 5，后区 12 选 2。
  factory LottoConfig.superLotto(
          {LottoOptions options = const LottoOptions(),
          LottoStyle style = const LottoStyle()}) =>
      LottoConfig(
          pools: const [kSuperLottoFront, kSuperLottoBack],
          options: options,
          style: style);

  /// 按出球顺序排列的号码池。
  final List<LottoPool> pools;

  /// 动画与排序选项。
  final LottoOptions options;

  /// 机身外观。
  final LottoStyle style;

  /// 校验池与动画参数；非法配置抛出 ArgumentError。
  void validate() {
    if (pools.isEmpty ||
        pools.any((p) =>
            p.min > p.max || p.count <= 0 || p.count > p.max - p.min + 1)) {
      throw ArgumentError.value(pools, 'pools', '号码池必须非空且数量有效');
    }
    if (options.drawInterval <= Duration.zero ||
        options.ballFlightTime <= Duration.zero ||
        !options.drawMix.isFinite ||
        options.drawMix < 0 ||
        options.drawMix > 1 ||
        !options.ballRadiusFactor.isFinite ||
        options.ballRadiusFactor <= 0 ||
        options.ballRadiusFactor >= 1 ||
        !options.motion.speed.isFinite ||
        options.motion.speed <= 0 ||
        !options.motion.idleSpinSpeed.isFinite ||
        options.motion.idleSpinSpeed < 0 ||
        options.motion.maxFrameDelta < Duration.zero ||
        options.motion.accelerationTime <= Duration.zero ||
        options.motion.decelerationTime <= Duration.zero) {
      throw ArgumentError.value(options, 'options', '时长、速度、球半径与搅拌强度无效');
    }
    options.physics?.validate();
  }

  /// 返回替换非空参数的副本，例如 `config.copyWith(style: style)`。
  LottoConfig copyWith(
          {List<LottoPool>? pools, LottoOptions? options, LottoStyle? style}) =>
      LottoConfig(
          pools: pools ?? this.pools,
          options: options ?? this.options,
          style: style ?? this.style);

  /// 按池顺序与配置值比较。
  @override
  bool operator ==(Object other) =>
      other is LottoConfig &&
      listEquals(other.pools, pools) &&
      other.options == options &&
      other.style == style;

  /// 与相等性一致的哈希。
  @override
  int get hashCode => Object.hash(Object.hashAll(pools), options, style);
}

/// 按池分组、组内保留抽出顺序的号码；例如 `const LottoDraw([[1], [2]])`。
@immutable
final class LottoDraw {
  /// 创建开奖号码；调用方须保持嵌套列表不可变。
  const LottoDraw(this.numbers);

  /// 各池抽出的号码。
  final List<List<int>> numbers;

  /// 校验与 [config] 的池数、数量、范围和池内唯一性；不符抛 ArgumentError。
  void validate(LottoConfig config) {
    if (numbers.length != config.pools.length) {
      throw ArgumentError.value(numbers, 'numbers', '池数量不符');
    }
    for (var p = 0; p < numbers.length; p++) {
      final pool = config.pools[p];
      final values = numbers[p];
      if (values.length != pool.count ||
          values.toSet().length != values.length ||
          values.any((n) => n < pool.min || n > pool.max)) {
        throw ArgumentError.value(values, 'numbers', '号码数量、范围或唯一性不符');
      }
    }
  }

  /// 返回指定号码的副本，未传参数时保留当前号码。
  LottoDraw copyWith({List<List<int>>? numbers}) =>
      LottoDraw(numbers ?? this.numbers);

  /// 按池顺序和抽出顺序比较。
  @override
  bool operator ==(Object other) =>
      other is LottoDraw &&
      numbers.length == other.numbers.length &&
      List.generate(
              numbers.length, (i) => listEquals(numbers[i], other.numbers[i]))
          .every((equal) => equal);

  /// 与嵌套列表相等性一致的哈希。
  @override
  int get hashCode => Object.hashAll(numbers.map(Object.hashAll));
}

/// 一局摇奖结果，抽出顺序不受展示排序影响。
@immutable
final class LottoResult extends LuckyResult<LottoDraw> {
  /// 创建正常结果；例如 `LottoResult(draw: draw)`。
  const LottoResult({required LottoDraw draw}) : super(prize: draw);

  /// 创建没有号码的作废结果。
  const LottoResult.cancelled() : super.cancelled();

  /// 本局号码，作废时为空。
  LottoDraw? get draw => prize;
}
