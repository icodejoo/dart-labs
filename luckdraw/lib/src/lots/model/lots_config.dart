import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/fill.dart';
import '../../core/motion/motion_options.dart';

import 'lots_parts.dart';

/// T5.7 的默认摇角和可见签槽数量。
const int _defaultVisible = 12;

/// T5.7 的升签与加速时长。
const Duration _defaultRiseTime = Duration(milliseconds: 600);

/// 抽签配置；签与选奖权重一一对应。
@immutable
final class LotsConfig {
  /// 创建配置；列表在使用期间不可修改。
  const LotsConfig(
      {this.sticks = const [],
      this.options = const LotsOptions(),
      this.style = const LotsStyle()});

  /// 候选签列表。
  final List<LotsStick> sticks;

  /// 运动和布局参数。
  final LotsOptions options;

  /// 签筒和展示卡样式。
  final LotsStyle style;

  /// 返回只替换非空参数的副本。
  LotsConfig copyWith(
          {List<LotsStick>? sticks, LotsOptions? options, LotsStyle? style}) =>
      LotsConfig(
          sticks: sticks ?? this.sticks,
          options: options ?? this.options,
          style: style ?? this.style);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsConfig &&
      listEquals(other.sticks, sticks) &&
      other.options == options &&
      other.style == style;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([Object.hashAll(sticks), options, style]);
}

/// 抽签参数；升签与展示都属于减速收尾阶段。
@immutable
final class LotsOptions {
  /// 创建配置；列表在使用期间不可修改。
  const LotsOptions(
      {this.maxShakeDeg = _defaultVisible * 1.0,
      this.visibleSticks = _defaultVisible,
      this.riseTime = _defaultRiseTime,
      this.revealTime = const Duration(milliseconds: 400),
      this.revealOnSettle = true,
      this.motion = const LuckyMotionOptions(
          accelerationTime: _defaultRiseTime,
          decelerationTime: Duration(milliseconds: 900))});

  /// 最大摇动角度。
  final double maxShakeDeg;

  /// 可见签槽数量，至少一个。
  final int visibleSticks;

  /// 升签时长。
  final Duration riseTime;

  /// 展示签文时长。
  final Duration revealTime;

  /// 是否展示签文卡。
  final bool revealOnSettle;

  /// 摇动相位速度、缓动和时间基准。
  final LuckyMotionOptions motion;

  /// 返回只替换非空参数的副本。
  LotsOptions copyWith(
          {double? maxShakeDeg,
          int? visibleSticks,
          Duration? riseTime,
          Duration? revealTime,
          bool? revealOnSettle,
          LuckyMotionOptions? motion}) =>
      LotsOptions(
          maxShakeDeg: maxShakeDeg ?? this.maxShakeDeg,
          visibleSticks: visibleSticks ?? this.visibleSticks,
          riseTime: riseTime ?? this.riseTime,
          revealTime: revealTime ?? this.revealTime,
          revealOnSettle: revealOnSettle ?? this.revealOnSettle,
          motion: motion ?? this.motion);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsOptions &&
      other.maxShakeDeg == maxShakeDeg &&
      other.visibleSticks == visibleSticks &&
      other.riseTime == riseTime &&
      other.revealTime == revealTime &&
      other.revealOnSettle == revealOnSettle &&
      other.motion == motion;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        maxShakeDeg,
        visibleSticks,
        riseTime,
        revealTime,
        revealOnSettle,
        motion
      ]);
}

/// 签筒、签和展示卡的样式。
@immutable
final class LotsStyle {
  /// 创建配置；列表在使用期间不可修改。
  const LotsStyle(
      {this.background = const LuckyFill.color(Color(0xFFF7EBD6)),
      this.cylinderFill = const LuckyFill.color(Color(0xFF9E342B)),
      this.backFill = const LuckyFill.color(Color(0xFF592820)),
      this.stickFill = const LuckyFill.color(Color(0xFFEBC582)),
      this.cardFill = const LuckyFill.color(Color(0xFFFFF8E1)),
      this.textColor = const Color(0xFF4E261B),
      this.fontSize = 18,
      this.fontFamily});

  /// 盒子背景。
  final LuckyFill background;

  /// 签筒前壁填充。
  final LuckyFill cylinderFill;

  /// 签筒后壁填充。
  final LuckyFill backFill;

  /// 无字签填充。
  final LuckyFill stickFill;

  /// 签文卡填充。
  final LuckyFill cardFill;

  /// 默认文字颜色。
  final Color textColor;

  /// 默认字号。
  final double fontSize;

  /// 默认字体；空时使用平台默认字体。
  final String? fontFamily;

  /// 返回只替换非空参数的副本。
  LotsStyle copyWith(
          {LuckyFill? background,
          LuckyFill? cylinderFill,
          LuckyFill? backFill,
          LuckyFill? stickFill,
          LuckyFill? cardFill,
          Color? textColor,
          double? fontSize,
          String? fontFamily}) =>
      LotsStyle(
          background: background ?? this.background,
          cylinderFill: cylinderFill ?? this.cylinderFill,
          backFill: backFill ?? this.backFill,
          stickFill: stickFill ?? this.stickFill,
          cardFill: cardFill ?? this.cardFill,
          textColor: textColor ?? this.textColor,
          fontSize: fontSize ?? this.fontSize,
          fontFamily: fontFamily ?? this.fontFamily);

  /// 按全部字段比较值。
  @override
  bool operator ==(Object other) =>
      other is LotsStyle &&
      other.background == background &&
      other.cylinderFill == cylinderFill &&
      other.backFill == backFill &&
      other.stickFill == stickFill &&
      other.cardFill == cardFill &&
      other.textColor == textColor &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        background,
        cylinderFill,
        backFill,
        stickFill,
        cardFill,
        textColor,
        fontSize,
        fontFamily
      ]);
}
