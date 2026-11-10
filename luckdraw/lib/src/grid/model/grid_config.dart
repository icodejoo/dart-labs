import 'package:flutter/foundation.dart';
import '../../core/foundation/box_block.dart';
import '../../core/foundation/cell_style.dart';
import '../../core/foundation/constants.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/text.dart';
import '../../core/motion/motion_options.dart';
import 'grid_parts.dart';

/// 上游默认行列数（grid.ts:142）。
const int kLuckyGridDefaultDimension = 3;

/// 九宫格配置；默认三行三列，奖品顺序决定高亮巡游顺序。
@immutable
final class GridConfig {
  /// 创建配置；列表由调用方保持不可变。
  const GridConfig(
      {this.rows = kLuckyGridDefaultDimension,
      this.cols = kLuckyGridDefaultDimension,
      this.blocks = const [],
      this.prizes = const [],
      this.buttons = const [],
      this.options = const GridOptions(),
      this.style = const GridStyle(),
      this.activeStyle = const LuckyCellStyle(
          background: LuckyFill.color(kLuckyGridActiveBackground))});

  /// 行数，非正值生成空布局。
  final int rows;

  /// 列数，非正值生成空布局。
  final int cols;

  /// 由外向内的背景块。
  final List<LuckyBoxBlock> blocks;

  /// 按巡游顺序排列的奖品格。
  final List<GridPrize> prizes;

  /// 按点击顺序排列的按钮格。
  final List<GridButton> buttons;

  /// 布局与动画参数。
  final GridOptions options;

  /// 普通格子默认样式。
  final GridStyle style;

  /// 激活样式；背景、阴影、边框和前景整体替换，圆角和文字非空覆盖。
  final LuckyCellStyle activeStyle;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留配置。
  GridConfig copyWith(
          {int? rows,
          int? cols,
          List<LuckyBoxBlock>? blocks,
          List<GridPrize>? prizes,
          List<GridButton>? buttons,
          GridOptions? options,
          GridStyle? style,
          LuckyCellStyle? activeStyle}) =>
      GridConfig(
          rows: rows ?? this.rows,
          cols: cols ?? this.cols,
          blocks: blocks ?? this.blocks,
          prizes: prizes ?? this.prizes,
          buttons: buttons ?? this.buttons,
          options: options ?? this.options,
          style: style ?? this.style,
          activeStyle: activeStyle ?? this.activeStyle);

  /// 按所有配置字段比较。
  @override
  bool operator ==(Object other) =>
      other is GridConfig &&
      other.rows == rows &&
      other.cols == cols &&
      listEquals(other.blocks, blocks) &&
      listEquals(other.prizes, prizes) &&
      listEquals(other.buttons, buttons) &&
      other.options == options &&
      other.style == style &&
      other.activeStyle == activeStyle;

  /// 与配置相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        rows,
        cols,
        Object.hashAll(blocks),
        Object.hashAll(prizes),
        Object.hashAll(buttons),
        options,
        style,
        activeStyle
      ]);
}

/// 九宫格行为参数。
@immutable
final class GridOptions {
  /// 创建配置；列表由调用方保持不可变。
  const GridOptions(
      {this.gutter = kLuckyGridDefaultGutter,
      this.motion = const LuckyMotionOptions()});

  /// 格子间距，单位逻辑像素。
  final double gutter;

  /// 动画参数；speed 按上游除以 40。
  final LuckyMotionOptions motion;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留配置。
  GridOptions copyWith({double? gutter, LuckyMotionOptions? motion}) =>
      GridOptions(gutter: gutter ?? this.gutter, motion: motion ?? this.motion);

  /// 按所有配置字段比较。
  @override
  bool operator ==(Object other) =>
      other is GridOptions && other.gutter == gutter && other.motion == motion;

  /// 与配置相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([gutter, motion]);
}

/// 九宫格普通态默认样式。
@immutable
final class GridStyle {
  /// 创建配置；列表由调用方保持不可变。
  const GridStyle(
      {this.cell = const LuckyCellStyle(
          background: LuckyFill.color(kLuckyTransparent),
          borderRadius: kLuckyGridDefaultBorderRadius),
      this.text = const LuckyTextDefaults()});

  /// 普通格子样式；透明背景仍会触发阴影收缩。
  final LuckyCellStyle cell;

  /// 文字默认值。
  final LuckyTextDefaults text;

  /// 返回替换非空参数的副本，例如 `value.copyWith()` 保留配置。
  GridStyle copyWith({LuckyCellStyle? cell, LuckyTextDefaults? text}) =>
      GridStyle(cell: cell ?? this.cell, text: text ?? this.text);

  /// 按所有配置字段比较。
  @override
  bool operator ==(Object other) =>
      other is GridStyle && other.cell == cell && other.text == text;

  /// 与配置相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([cell, text]);
}
