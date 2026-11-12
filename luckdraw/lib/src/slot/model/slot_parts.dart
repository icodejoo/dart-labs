import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/foundation/cell_style.dart';
import '../../core/foundation/constants.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/text.dart';
import '../../core/motion/motion_options.dart';

/// 列配置；例如 `const SlotReel(order: [2, 0, 1], direction: -1)`。
@immutable
final class SlotReel {
  /// 创建列；null 的顺序、速度、方向分别继承奖品顺序和全局参数。
  const SlotReel(
      {this.order, this.speed, this.direction, this.stopDelay = Duration.zero});

  /// 条带位置对应的奖品下标；越界值保留为空格。
  final List<int>? order;

  /// 每参考帧像素速度；运行取绝对值，停止求解保留符号。
  final double? speed;

  /// 滚动方向，调用方应使用 1 或 −1。
  final int? direction;

  /// 相对整体减速开始的延迟；零表示同时停止。
  final Duration stopDelay;

  /// 返回仅替换非 null 参数的副本；例如 `value.copyWith()` 保留全部配置。
  SlotReel copyWith(
          {List<int>? order,
          double? speed,
          int? direction,
          Duration? stopDelay}) =>
      SlotReel(
          order: order ?? this.order,
          speed: speed ?? this.speed,
          direction: direction ?? this.direction,
          stopDelay: stopDelay ?? this.stopDelay);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is SlotReel &&
      listEquals(order, other.order) &&
      speed == other.speed &&
      direction == other.direction &&
      stopDelay == other.stopDelay;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      Object.hashAll(order ?? const <int>[]), speed, direction, stopDelay);
}

/// 滚动的轴向。
enum SlotMode {
  /// 纵向滚动，各列左右排列。
  vertical,

  /// 横向滚动，各列上下排列。
  horizontal,
}

/// 行为参数；例如 `const SlotOptions(cellAspectRatio: 2)`。
@immutable
final class SlotOptions {
  /// 创建参数；比例为 null 时格子为正方形。
  const SlotOptions(
      {this.mode = SlotMode.vertical,
      this.direction = 1,
      this.rowSpacing = 0,
      this.colSpacing = kLuckySlotDefaultColSpacing,
      this.cellAspectRatio,
      this.motion = const LuckyMotionOptions()});

  /// 滚动轴向。
  final SlotMode mode;

  /// 默认方向，1 或 −1。
  final int direction;

  /// 行间距，逻辑像素。
  final double rowSpacing;

  /// 列间距，逻辑像素。
  final double colSpacing;

  /// 格子宽高比，应为有限正数。
  final double? cellAspectRatio;

  /// 加减速、时基和停止求解策略。
  final LuckyMotionOptions motion;

  /// 返回仅替换非 null 参数的副本；例如 `value.copyWith()` 保留全部配置。
  SlotOptions copyWith(
          {SlotMode? mode,
          int? direction,
          double? rowSpacing,
          double? colSpacing,
          double? cellAspectRatio,
          LuckyMotionOptions? motion}) =>
      SlotOptions(
          mode: mode ?? this.mode,
          direction: direction ?? this.direction,
          rowSpacing: rowSpacing ?? this.rowSpacing,
          colSpacing: colSpacing ?? this.colSpacing,
          cellAspectRatio: cellAspectRatio ?? this.cellAspectRatio,
          motion: motion ?? this.motion);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is SlotOptions &&
      mode == other.mode &&
      direction == other.direction &&
      rowSpacing == other.rowSpacing &&
      colSpacing == other.colSpacing &&
      cellAspectRatio == other.cellAspectRatio &&
      motion == other.motion;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      mode, direction, rowSpacing, colSpacing, cellAspectRatio, motion);
}

/// 默认格子和文字样式。
@immutable
final class SlotStyle {
  /// 创建样式；格子默认透明、无圆角。
  const SlotStyle(
      {this.cell = const LuckyCellStyle(
          background: LuckyFill.color(kLuckyTransparent), borderRadius: 0),
      this.text = const LuckyTextDefaults()});

  /// 格子装饰。
  final LuckyCellStyle cell;

  /// 默认文字样式。
  final LuckyTextDefaults text;

  /// 返回仅替换非 null 参数的副本；例如 `value.copyWith()` 保留全部配置。
  SlotStyle copyWith({LuckyCellStyle? cell, LuckyTextDefaults? text}) =>
      SlotStyle(cell: cell ?? this.cell, text: text ?? this.text);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is SlotStyle && cell == other.cell && text == other.text;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(cell, text);
}

/// 自定义格子绘制；原点在格子左上，尺寸为逻辑像素。
typedef SlotCellPainter = void Function(
    Canvas canvas, Size cellSize, int prizeIndex);

/// 奖品格；例如 `const SlotPrize(weight: 1)` 可参与默认选奖。
@immutable
final class SlotPrize {
  /// 创建奖品；可选样式为 null 时继承默认值，圆角零也生效。
  const SlotPrize(
      {this.background,
      this.borderRadius,
      this.texts = const [],
      this.images = const [],
      this.weight,
      this.disabled = false,
      this.painter});

  /// 格子背景。
  final LuckyFill? background;

  /// 圆角半径，逻辑像素。
  final double? borderRadius;

  /// 文字列表，保留空行。
  final List<LuckyText> texts;

  /// 图片列表。
  final List<LuckyImage> images;

  /// 默认选奖权重，null 不可选。
  final double? weight;

  /// 是否排除默认选奖；显式停止仍可指定。
  final bool disabled;

  /// 格子局部绘制回调。
  final SlotCellPainter? painter;

  /// 返回仅替换非 null 参数的副本；例如 `value.copyWith()` 保留全部配置。
  SlotPrize copyWith(
          {LuckyFill? background,
          double? borderRadius,
          List<LuckyText>? texts,
          List<LuckyImage>? images,
          double? weight,
          bool? disabled,
          SlotCellPainter? painter}) =>
      SlotPrize(
          background: background ?? this.background,
          borderRadius: borderRadius ?? this.borderRadius,
          texts: texts ?? this.texts,
          images: images ?? this.images,
          weight: weight ?? this.weight,
          disabled: disabled ?? this.disabled,
          painter: painter ?? this.painter);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is SlotPrize &&
      background == other.background &&
      borderRadius == other.borderRadius &&
      listEquals(texts, other.texts) &&
      listEquals(images, other.images) &&
      weight == other.weight &&
      disabled == other.disabled &&
      painter == other.painter;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(background, borderRadius,
      Object.hashAll(texts), Object.hashAll(images), weight, disabled, painter);
}
