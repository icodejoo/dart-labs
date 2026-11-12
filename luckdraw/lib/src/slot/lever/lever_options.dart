import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 默认回弹和错峰时间。
const Duration _defaultDuration = Duration(milliseconds: 300);

/// 拉杆位置。
enum LeverSide {
  /// 右侧（默认）。
  right,

  /// 左侧。
  left,
}

/// 拉杆外观、触发阈值和错峰设置，例如 `const LeverOptions(autoPlay: false)`。
@immutable
final class LeverOptions {
  /// 创建参数；宽度比例须为正，阈值须在 0 到 1 之间。
  const LeverOptions(
      {this.side = LeverSide.right,
      this.widthFactor = 0.18,
      this.pullThreshold = 0.6,
      this.springBack = _defaultDuration,
      this.autoPlay = true,
      this.staggerStop = _defaultDuration,
      this.knobColor = const Color(0xFFE53935),
      this.shaftColor = const Color(0xFF9E9E9E)})
      : assert(widthFactor > 0),
        assert(pullThreshold >= 0 && pullThreshold <= 1);

  /// 拉杆位于老虎机哪一侧。
  final LeverSide side;

  /// 拉杆区宽度为总高度乘此比例。
  final double widthFactor;

  /// 松手时达到此比例即触发有效拉杆。
  final double pullThreshold;

  /// 松手后的回弹时长。
  final Duration springBack;

  /// 有效拉杆且阶段允许时自动开始。
  final bool autoPlay;

  /// 默认零延迟的列按列下标乘此时长填充。
  final Duration staggerStop;

  /// 拉杆头颜色。
  final Color knobColor;

  /// 杆身颜色。
  final Color shaftColor;

  /// 返回替换指定字段的副本；例如 `lever.copyWith(side: LeverSide.left)`。
  LeverOptions copyWith(
          {LeverSide? side,
          double? widthFactor,
          double? pullThreshold,
          Duration? springBack,
          bool? autoPlay,
          Duration? staggerStop,
          Color? knobColor,
          Color? shaftColor}) =>
      LeverOptions(
          side: side ?? this.side,
          widthFactor: widthFactor ?? this.widthFactor,
          pullThreshold: pullThreshold ?? this.pullThreshold,
          springBack: springBack ?? this.springBack,
          autoPlay: autoPlay ?? this.autoPlay,
          staggerStop: staggerStop ?? this.staggerStop,
          knobColor: knobColor ?? this.knobColor,
          shaftColor: shaftColor ?? this.shaftColor);

  /// 全部字段按值比较。
  @override
  bool operator ==(Object other) =>
      other is LeverOptions &&
      side == other.side &&
      widthFactor == other.widthFactor &&
      pullThreshold == other.pullThreshold &&
      springBack == other.springBack &&
      autoPlay == other.autoPlay &&
      staggerStop == other.staggerStop &&
      knobColor == other.knobColor &&
      shaftColor == other.shaftColor;

  /// 与相等性一致的哈希。
  @override
  int get hashCode => Object.hash(side, widthFactor, pullThreshold, springBack,
      autoPlay, staggerStop, knobColor, shaftColor);
}
