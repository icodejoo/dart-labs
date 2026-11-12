import 'package:flutter/foundation.dart';

import '../../core/foundation/constants.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/text.dart';
import '../../core/motion/motion_options.dart';
import 'wheel_parts.dart';

/// 大转盘的不可变配置；例如 `const WheelConfig(prizes: [WheelPrize()])`。
@immutable
final class WheelConfig {
  /// 创建配置；奖品按顺时针排列，尺寸由宿主决定。
  const WheelConfig(
      {this.blocks = const [],
      this.prizes = const [],
      this.buttons = const [],
      this.options = const WheelOptions(),
      this.style = const WheelStyle()});

  /// 由外到内的圆环。
  final List<WheelBlock> blocks;

  /// 顺时针排列的奖品，第零项从指针处开始。
  final List<WheelPrize> prizes;

  /// 按绘制顺序排列的同心按钮。
  final List<WheelButton> buttons;

  /// 行为参数。
  final WheelOptions options;

  /// 奖品默认样式。
  final WheelStyle style;

  /// 返回替换非 null 参数的副本，例如 `config.copyWith(prizes: [])`。
  WheelConfig copyWith(
          {List<WheelBlock>? blocks,
          List<WheelPrize>? prizes,
          List<WheelButton>? buttons,
          WheelOptions? options,
          WheelStyle? style}) =>
      WheelConfig(
          blocks: blocks ?? this.blocks,
          prizes: prizes ?? this.prizes,
          buttons: buttons ?? this.buttons,
          options: options ?? this.options,
          style: style ?? this.style);

  /// 按配置字段比较。
  @override
  bool operator ==(Object other) =>
      other is WheelConfig &&
      listEquals(other.blocks, blocks) &&
      listEquals(other.prizes, prizes) &&
      listEquals(other.buttons, buttons) &&
      other.options == options &&
      other.style == style;

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(Object.hashAll(blocks),
      Object.hashAll(prizes), Object.hashAll(buttons), options, style);
}

/// 转盘行为参数，默认采用有效时间与单调停止求解。
@immutable
final class WheelOptions {
  /// 创建参数；[stopRange] 应在 0–1 内，[offsetDegree] 为顺时针角度。
  const WheelOptions(
      {this.gutter = 0,
      this.offsetDegree = 0,
      this.stopRange = 0,
      this.motion = const LuckyMotionOptions()});

  /// 扇区间隙，单位为逻辑像素。
  final double gutter;

  /// 起始偏移角度。
  final double offsetDegree;

  /// 停点随机偏移占扇区宽度的比例。
  final double stopRange;

  /// 动画参数。
  final LuckyMotionOptions motion;

  /// 返回仅替换非 null 参数的副本。
  WheelOptions copyWith(
          {double? gutter,
          double? offsetDegree,
          double? stopRange,
          LuckyMotionOptions? motion}) =>
      WheelOptions(
          gutter: gutter ?? this.gutter,
          offsetDegree: offsetDegree ?? this.offsetDegree,
          stopRange: stopRange ?? this.stopRange,
          motion: motion ?? this.motion);

  /// 按全部参数比较。
  @override
  bool operator ==(Object other) =>
      other is WheelOptions &&
      other.gutter == gutter &&
      other.offsetDegree == offsetDegree &&
      other.stopRange == stopRange &&
      other.motion == motion;

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(gutter, offsetDegree, stopRange, motion);
}

/// 转盘奖品默认样式。
@immutable
final class WheelStyle {
  /// 创建样式；透明背景仍视为有背景，null 表示不填充。
  const WheelStyle(
      {this.background = const LuckyFill.color(kLuckyTransparent),
      this.text = const LuckyTextDefaults()});

  /// 奖品缺省背景。
  final LuckyFill? background;

  /// 文字缺省值。
  final LuckyTextDefaults text;

  /// 替换非 null 字段；[clearBackground] 显式清除背景。
  WheelStyle copyWith(
          {LuckyFill? background,
          LuckyTextDefaults? text,
          bool clearBackground = false}) =>
      WheelStyle(
          background: clearBackground ? null : background ?? this.background,
          text: text ?? this.text);

  /// 按背景和文字比较。
  @override
  bool operator ==(Object other) =>
      other is WheelStyle &&
      other.background == background &&
      other.text == text;

  /// 与值相等性一致的哈希。
  @override
  int get hashCode => Object.hash(background, text);
}
