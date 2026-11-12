import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/fill.dart';
import '../../core/motion/motion_options.dart';

/// T5.5 的默认盘速比例与落袋比例。
const double _defaultRatio = 0.35;

/// T5.5 的外轨与标签环边界。
const double _trackBoundary = 0.86;

/// T5.5 的标签与格子环边界。
const double _pocketBoundary = 0.76;

/// T5.5 的默认速度和标签字号。
const double _defaultSpeed = 12;

/// 默认格子配色，只表示交替色，不包含任何号码顺序。
const List<LuckyFill> kNumberWheelDefaultPalette = [
  LuckyFill.color(Color(0xFFC62828)),
  LuckyFill.color(Color(0xFF212121))
];

/// 数字转盘配置；第零格中线从正上方开始，按顺时针排列。
@immutable
final class NumberWheelConfig {
  /// 创建配置；列表在使用期间不可修改。
  const NumberWheelConfig(
      {required this.pockets,
      this.options = const NumberWheelOptions(),
      this.style = const NumberWheelStyle()});

  /// 按闭区间生成号码；步长须为正且配色不可为空，否则抛出 ArgumentError。
  /// 例如 `NumberWheelConfig.range(0, 36)` 生成递增的三十七个号码。
  factory NumberWheelConfig.range(int min, int max,
      {int step = 1,
      List<LuckyFill> palette = kNumberWheelDefaultPalette,
      NumberWheelOptions options = const NumberWheelOptions(),
      NumberWheelStyle style = const NumberWheelStyle()}) {
    if (step <= 0 || min > max || palette.isEmpty) {
      throw ArgumentError('区间、步长或配色无效');
    }
    final pockets = <NumberWheelPocket>[];
    for (var number = min; number <= max; number += step) {
      pockets.add(NumberWheelPocket(number,
          fill: palette[pockets.length % palette.length]));
    }
    return NumberWheelConfig(
        pockets: List.unmodifiable(pockets), options: options, style: style);
  }

  /// 显式格子列表。
  final List<NumberWheelPocket> pockets;

  /// 布局和运动参数。
  final NumberWheelOptions options;

  /// 绘制样式。
  final NumberWheelStyle style;

  /// 返回只替换非空参数的副本。
  NumberWheelConfig copyWith(
          {List<NumberWheelPocket>? pockets,
          NumberWheelOptions? options,
          NumberWheelStyle? style}) =>
      NumberWheelConfig(
          pockets: pockets ?? this.pockets,
          options: options ?? this.options,
          style: style ?? this.style);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is NumberWheelConfig &&
      listEquals(other.pockets, pockets) &&
      other.options == options &&
      other.style == style;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([Object.hashAll(pockets), options, style]);
}

/// 一个可选号码格。
@immutable
final class NumberWheelPocket {
  /// 创建配置；列表在使用期间不可修改。
  const NumberWheelPocket(this.number,
      {this.label, this.fill, this.weight, this.disabled = false});

  /// 结果号码。
  final int number;

  /// 显示文字；空时使用号码。
  final String? label;

  /// 格子填充；空时使用交替配色。
  final LuckyFill? fill;

  /// 选奖权重；空值不参与随机选奖。
  final double? weight;

  /// 是否禁止随机选中。
  final bool disabled;

  /// 返回只替换非空参数的副本。
  NumberWheelPocket copyWith(
          {int? number,
          String? label,
          LuckyFill? fill,
          double? weight,
          bool? disabled}) =>
      NumberWheelPocket(number ?? this.number,
          label: label ?? this.label,
          fill: fill ?? this.fill,
          weight: weight ?? this.weight,
          disabled: disabled ?? this.disabled);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is NumberWheelPocket &&
      other.number == number &&
      other.label == label &&
      other.fill == fill &&
      other.weight == weight &&
      other.disabled == disabled;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([number, label, fill, weight, disabled]);
}

/// 数字转盘布局与运动参数；半径因子相对于盒子的内切圆半径。
@immutable
final class NumberWheelOptions {
  /// 创建配置；列表在使用期间不可修改。
  const NumberWheelOptions(
      {this.discSpeedRatio = _defaultRatio,
      this.trackOuterFactor = 1.0,
      this.trackInnerFactor = _trackBoundary,
      this.labelOuterFactor = _trackBoundary,
      this.labelInnerFactor = _pocketBoundary,
      this.pocketOuterFactor = _pocketBoundary,
      this.pocketInnerFactor = 0.64,
      this.hubFactor = 0.3,
      this.ballRadiusFactor = 0.035,
      this.dropFraction = _defaultRatio,
      this.bounceCount = 2,
      this.bounceAmplitudeFactor = 0.25,
      this.offsetDegree = 0,
      this.motion = const LuckyMotionOptions(speed: _defaultSpeed)});

  /// 盘速与球速的比值，二者方向相反。
  final double discSpeedRatio;

  /// 外轨外半径比例。
  final double trackOuterFactor;

  /// 外轨内半径比例。
  final double trackInnerFactor;

  /// 标签环外半径比例。
  final double labelOuterFactor;

  /// 标签环内半径比例。
  final double labelInnerFactor;

  /// 格子环外半径比例。
  final double pocketOuterFactor;

  /// 格子环内半径比例。
  final double pocketInnerFactor;

  /// 中心按钮半径比例。
  final double hubFactor;

  /// 小球自身半径比例。
  final double ballRadiusFactor;

  /// 减速末尾落袋所占比例。
  final double dropFraction;

  /// 落袋弹跳次数。
  final int bounceCount;

  /// 弹跳幅度相对格子环宽的比例。
  final double bounceAmplitudeFactor;

  /// 第零格中线偏移角度。
  final double offsetDegree;

  /// 时间基准、速度和缓动。
  final LuckyMotionOptions motion;

  /// 返回只替换非空参数的副本。
  NumberWheelOptions copyWith(
          {double? discSpeedRatio,
          double? trackOuterFactor,
          double? trackInnerFactor,
          double? labelOuterFactor,
          double? labelInnerFactor,
          double? pocketOuterFactor,
          double? pocketInnerFactor,
          double? hubFactor,
          double? ballRadiusFactor,
          double? dropFraction,
          int? bounceCount,
          double? bounceAmplitudeFactor,
          double? offsetDegree,
          LuckyMotionOptions? motion}) =>
      NumberWheelOptions(
          discSpeedRatio: discSpeedRatio ?? this.discSpeedRatio,
          trackOuterFactor: trackOuterFactor ?? this.trackOuterFactor,
          trackInnerFactor: trackInnerFactor ?? this.trackInnerFactor,
          labelOuterFactor: labelOuterFactor ?? this.labelOuterFactor,
          labelInnerFactor: labelInnerFactor ?? this.labelInnerFactor,
          pocketOuterFactor: pocketOuterFactor ?? this.pocketOuterFactor,
          pocketInnerFactor: pocketInnerFactor ?? this.pocketInnerFactor,
          hubFactor: hubFactor ?? this.hubFactor,
          ballRadiusFactor: ballRadiusFactor ?? this.ballRadiusFactor,
          dropFraction: dropFraction ?? this.dropFraction,
          bounceCount: bounceCount ?? this.bounceCount,
          bounceAmplitudeFactor:
              bounceAmplitudeFactor ?? this.bounceAmplitudeFactor,
          offsetDegree: offsetDegree ?? this.offsetDegree,
          motion: motion ?? this.motion);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is NumberWheelOptions &&
      other.discSpeedRatio == discSpeedRatio &&
      other.trackOuterFactor == trackOuterFactor &&
      other.trackInnerFactor == trackInnerFactor &&
      other.labelOuterFactor == labelOuterFactor &&
      other.labelInnerFactor == labelInnerFactor &&
      other.pocketOuterFactor == pocketOuterFactor &&
      other.pocketInnerFactor == pocketInnerFactor &&
      other.hubFactor == hubFactor &&
      other.ballRadiusFactor == ballRadiusFactor &&
      other.dropFraction == dropFraction &&
      other.bounceCount == bounceCount &&
      other.bounceAmplitudeFactor == bounceAmplitudeFactor &&
      other.offsetDegree == offsetDegree &&
      other.motion == motion;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        discSpeedRatio,
        trackOuterFactor,
        trackInnerFactor,
        labelOuterFactor,
        labelInnerFactor,
        pocketOuterFactor,
        pocketInnerFactor,
        hubFactor,
        ballRadiusFactor,
        dropFraction,
        bounceCount,
        bounceAmplitudeFactor,
        offsetDegree,
        motion
      ]);
}

/// 数字转盘绘制样式。
@immutable
final class NumberWheelStyle {
  /// 创建配置；列表在使用期间不可修改。
  const NumberWheelStyle(
      {this.background = const LuckyFill.color(Color(0xFFB58A45)),
      this.trackFill = const LuckyFill.color(Color(0xFF49392D)),
      this.hubFill = const LuckyFill.color(Color(0xFF8D6E63)),
      this.ballFill = const LuckyFill.color(Color(0xFFFFF8E1)),
      this.textColor = const Color(0xFFFFFFFF),
      this.fontSize = _defaultSpeed,
      this.fontFamily});

  /// 盘面填充。
  final LuckyFill background;

  /// 外轨填充。
  final LuckyFill trackFill;

  /// 中心毂填充。
  final LuckyFill hubFill;

  /// 小球填充。
  final LuckyFill ballFill;

  /// 标签与刻度颜色。
  final Color textColor;

  /// 标签字号；参与标签抽稀。
  final double fontSize;

  /// 标签字体；空时使用平台默认字体。
  final String? fontFamily;

  /// 返回只替换非空参数的副本。
  NumberWheelStyle copyWith(
          {LuckyFill? background,
          LuckyFill? trackFill,
          LuckyFill? hubFill,
          LuckyFill? ballFill,
          Color? textColor,
          double? fontSize,
          String? fontFamily}) =>
      NumberWheelStyle(
          background: background ?? this.background,
          trackFill: trackFill ?? this.trackFill,
          hubFill: hubFill ?? this.hubFill,
          ballFill: ballFill ?? this.ballFill,
          textColor: textColor ?? this.textColor,
          fontSize: fontSize ?? this.fontSize,
          fontFamily: fontFamily ?? this.fontFamily);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is NumberWheelStyle &&
      other.background == background &&
      other.trackFill == trackFill &&
      other.hubFill == hubFill &&
      other.ballFill == ballFill &&
      other.textColor == textColor &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        background,
        trackFill,
        hubFill,
        ballFill,
        textColor,
        fontSize,
        fontFamily
      ]);
}
