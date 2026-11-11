import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/kinematics/physics_options.dart';
import '../../core/motion/motion_options.dart';

/// 开奖后的排序滑动时长，按 T5.9 固定为 300ms。
const Duration kLottoSortTime = Duration(milliseconds: 300);

/// 大乐透加减速默认时长。
const Duration _motionTime = Duration(milliseconds: 800);

/// 摇奖参数；例如 `const LottoOptions(sortResults: false)` 保留展示顺序。
@immutable
final class LottoOptions {
  /// 创建参数；时长必须为正，搅拌强度在零到一之间。
  const LottoOptions({
    this.drawInterval = const Duration(milliseconds: 700),
    this.ballFlightTime = const Duration(milliseconds: 500),
    this.sortResults = true,
    this.drawMix = 0.6,
    this.ballRadiusFactor = 0.11,
    this.motion = const LuckyMotionOptions(
        speed: 12,
        accelerationTime: _motionTime,
        decelerationTime: _motionTime),
    this.physics,
  });

  /// 相邻球开始飞行的间隔。
  final Duration drawInterval;

  /// 单球从容器飞到槽内的时长。
  final Duration ballFlightTime;

  /// 每池出完球后是否升序展示，不改变结果中的抽出顺序。
  final bool sortResults;

  /// 开奖期间的搅拌强度。
  final double drawMix;

  /// 号码球半径占容器半径的比例，必须大于零且小于一。
  final double ballRadiusFactor;

  /// 加速、减速与时间基准参数。
  final LuckyMotionOptions motion;

  /// 实验性（可能调整）：物理碰撞模式参数；null 保持参数化轨迹（默认）。
  ///
  /// 例如 `LottoOptions(physics: LuckyPhysics())`，号码球从顶部落下并与容器、拨杆碰撞。
  final LuckyPhysics? physics;

  /// 返回替换非空参数的副本，例如 `options.copyWith(drawMix: 0.5)`；
  /// 无法用 null 清除 [physics]，需要关闭物理模式时重新构造。
  LottoOptions copyWith(
          {Duration? drawInterval,
          Duration? ballFlightTime,
          bool? sortResults,
          double? drawMix,
          double? ballRadiusFactor,
          LuckyMotionOptions? motion,
          LuckyPhysics? physics}) =>
      LottoOptions(
          drawInterval: drawInterval ?? this.drawInterval,
          ballFlightTime: ballFlightTime ?? this.ballFlightTime,
          sortResults: sortResults ?? this.sortResults,
          drawMix: drawMix ?? this.drawMix,
          ballRadiusFactor: ballRadiusFactor ?? this.ballRadiusFactor,
          motion: motion ?? this.motion,
          physics: physics ?? this.physics);

  /// 返回去掉物理模式、其余字段不变的副本，例如关闭 `LottoOptions(physics: ...)`。
  LottoOptions withoutPhysics() => LottoOptions(
      drawInterval: drawInterval,
      ballFlightTime: ballFlightTime,
      sortResults: sortResults,
      drawMix: drawMix,
      ballRadiusFactor: ballRadiusFactor,
      motion: motion);

  /// 按所有动画参数比较。
  @override
  bool operator ==(Object other) =>
      other is LottoOptions &&
      other.drawInterval == drawInterval &&
      other.ballFlightTime == ballFlightTime &&
      other.sortResults == sortResults &&
      other.drawMix == drawMix &&
      other.ballRadiusFactor == ballRadiusFactor &&
      other.motion == motion &&
      other.physics == physics;

  /// 与相等性一致的哈希。
  @override
  int get hashCode => Object.hash(drawInterval, ballFlightTime, sortResults,
      drawMix, ballRadiusFactor, motion, physics);
}

/// 摇奖机配色；例如 `const LottoStyle(buttonText: '开奖')`。
@immutable
final class LottoStyle {
  /// 创建样式；号码球颜色由每个号码池单独指定。
  const LottoStyle({
    this.drumColor = const Color(0xFFE8F2FA),
    this.rimColor = const Color(0xFF7893A7),
    this.slotColor = const Color(0xFFCFD8DC),
    this.buttonColor = const Color(0xFFFFB300),
    this.buttonTextColor = const Color(0xFF263238),
    this.buttonText = '开始',
  });

  /// 透明容器背板色。
  final Color drumColor;

  /// 容器边缘与出口色。
  final Color rimColor;

  /// 结果槽背景色。
  final Color slotColor;

  /// 开始按钮背景色。
  final Color buttonColor;

  /// 开始按钮文字色。
  final Color buttonTextColor;

  /// 开始按钮文案。
  final String buttonText;

  /// 返回替换非空参数的副本，例如 `style.copyWith(buttonText: '开奖')`。
  LottoStyle copyWith(
          {Color? drumColor,
          Color? rimColor,
          Color? slotColor,
          Color? buttonColor,
          Color? buttonTextColor,
          String? buttonText}) =>
      LottoStyle(
          drumColor: drumColor ?? this.drumColor,
          rimColor: rimColor ?? this.rimColor,
          slotColor: slotColor ?? this.slotColor,
          buttonColor: buttonColor ?? this.buttonColor,
          buttonTextColor: buttonTextColor ?? this.buttonTextColor,
          buttonText: buttonText ?? this.buttonText);

  /// 按所有样式字段比较。
  @override
  bool operator ==(Object other) =>
      other is LottoStyle &&
      other.drumColor == drumColor &&
      other.rimColor == rimColor &&
      other.slotColor == slotColor &&
      other.buttonColor == buttonColor &&
      other.buttonTextColor == buttonTextColor &&
      other.buttonText == buttonText;

  /// 与相等性一致的哈希。
  @override
  int get hashCode => Object.hash(
      drumColor, rimColor, slotColor, buttonColor, buttonTextColor, buttonText);
}
