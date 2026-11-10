import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../../core/foundation/cell_style.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/length.dart';
import '../../core/foundation/text.dart';

/// 自定义格子内容；[rect] 为阴影收缩后矩形，[active] 表示中奖高亮。
typedef GridCellPainter = void Function(Canvas canvas, Rect rect, bool active);

/// 奖品和按钮共享的格子契约。
@immutable
abstract base class GridCell {
  /// 创建格子；列表由调用方保持不可变。
  const GridCell(
      {required this.x,
      required this.y,
      this.col = 1,
      this.row = 1,
      this.style,
      this.texts = const [],
      this.images = const []});

  /// 起始列，从零开始。
  final int x;

  /// 起始行，从零开始。
  final int y;

  /// 横向占用列数。
  final int col;

  /// 纵向占用行数。
  final int row;

  /// 普通态局部样式。
  final LuckyCellStyle? style;

  /// 文字项。
  final List<LuckyText> texts;

  /// 图片项。
  final List<GridImage> images;
}

/// 可选中奖品格。
@immutable
final class GridPrize extends GridCell {
  /// 创建格子；例如 `GridPrize(x: 0, y: 0)`。
  const GridPrize(
      {required super.x,
      required super.y,
      super.col,
      super.row,
      super.style,
      super.texts,
      super.images,
      this.weight,
      this.disabled = false,
      this.painter});

  /// 选奖权重；null 使用选奖器默认值。
  final double? weight;

  /// 是否禁止被默认选奖器选中。
  final bool disabled;

  /// 图片之后、文字之前的内容回调。
  final GridCellPainter? painter;

  /// 返回替换非空参数的副本。
  GridPrize copyWith(
          {int? x,
          int? y,
          int? col,
          int? row,
          LuckyCellStyle? style,
          List<LuckyText>? texts,
          List<GridImage>? images,
          double? weight,
          bool? disabled,
          GridCellPainter? painter}) =>
      GridPrize(
          x: x ?? this.x,
          y: y ?? this.y,
          col: col ?? this.col,
          row: row ?? this.row,
          style: style ?? this.style,
          texts: texts ?? this.texts,
          images: images ?? this.images,
          weight: weight ?? this.weight,
          disabled: disabled ?? this.disabled,
          painter: painter ?? this.painter);

  /// 按格子全部字段比较。
  @override
  bool operator ==(Object other) =>
      other is GridPrize &&
      other.x == x &&
      other.y == y &&
      other.col == col &&
      other.row == row &&
      other.style == style &&
      listEquals(other.texts, texts) &&
      listEquals(other.images, images) &&
      other.weight == weight &&
      other.disabled == disabled &&
      other.painter == painter;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        x,
        y,
        col,
        row,
        style,
        Object.hashAll(texts),
        Object.hashAll(images),
        weight,
        disabled,
        painter
      ]);
}

/// 可开始抽奖的按钮格；永不激活。
@immutable
final class GridButton extends GridCell {
  /// 创建格子；例如 `GridButton(x: 0, y: 0)`。
  const GridButton(
      {required super.x,
      required super.y,
      super.col,
      super.row,
      super.style,
      super.texts,
      super.images,
      this.painter});

  /// 图片之后、文字之前的内容回调。
  final GridCellPainter? painter;

  /// 返回替换非空参数的副本。
  GridButton copyWith(
          {int? x,
          int? y,
          int? col,
          int? row,
          LuckyCellStyle? style,
          List<LuckyText>? texts,
          List<GridImage>? images,
          GridCellPainter? painter}) =>
      GridButton(
          x: x ?? this.x,
          y: y ?? this.y,
          col: col ?? this.col,
          row: row ?? this.row,
          style: style ?? this.style,
          texts: texts ?? this.texts,
          images: images ?? this.images,
          painter: painter ?? this.painter);

  /// 按格子全部字段比较。
  @override
  bool operator ==(Object other) =>
      other is GridButton &&
      other.x == x &&
      other.y == y &&
      other.col == col &&
      other.row == row &&
      other.style == style &&
      listEquals(other.texts, texts) &&
      listEquals(other.images, images) &&
      other.painter == painter;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        x,
        y,
        col,
        row,
        style,
        Object.hashAll(texts),
        Object.hashAll(images),
        painter
      ]);
}

/// 可附带激活态图片的格子图片；尺寸和偏移同时应用于两个状态。
@immutable
class GridImage extends LuckyImage {
  /// 创建图片；激活图片未提供或未加载时使用普通图。
  const GridImage(super.image,
      {super.top,
      super.left,
      super.width,
      super.height,
      super.formatter,
      super.borderRadius,
      super.opacity,
      super.fallback,
      super.semanticLabel,
      this.activeImage});

  /// 激活态图片 provider。
  final ImageProvider<Object>? activeImage;

  /// 返回替换非空参数的副本。
  @override
  GridImage copyWith(
          {ImageProvider<Object>? image,
          LuckyLength? top,
          LuckyLength? left,
          LuckyLength? width,
          LuckyLength? height,
          LuckyImageFormatter? formatter,
          double? borderRadius,
          double? opacity,
          ImageProvider<Object>? fallback,
          String? semanticLabel,
          ImageProvider<Object>? activeImage}) =>
      GridImage(image ?? this.image,
          top: top ?? this.top,
          left: left ?? this.left,
          width: width ?? this.width,
          height: height ?? this.height,
          formatter: formatter ?? this.formatter,
          borderRadius: borderRadius ?? this.borderRadius,
          opacity: opacity ?? this.opacity,
          fallback: fallback ?? this.fallback,
          semanticLabel: semanticLabel ?? this.semanticLabel,
          activeImage: activeImage ?? this.activeImage);

  /// 按普通和激活图片配置比较。
  @override
  bool operator ==(Object other) =>
      other is GridImage && super == other && other.activeImage == activeImage;

  /// 与图片配置相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(super.hashCode, activeImage);
}
