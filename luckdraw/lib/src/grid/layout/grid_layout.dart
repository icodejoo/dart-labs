import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/border.dart';
import '../../core/foundation/box_block.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/foundation/shadow.dart';
import '../../core/game/layout.dart';
import '../../core/geometry/image_box.dart';
import '../../core/render/perf_trace.dart';
import '../../core/text/text_line.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';

/// 图片槽分组：背景块。
const String kLuckyGridBlocksGroup = 'blocks';

/// 图片槽分组：奖品。
const String kLuckyGridPrizesGroup = 'prizes';

/// 图片槽分组：按钮。
const String kLuckyGridButtonsGroup = 'buttons';

/// 九宫格布局；格子下标依次对应奖品和按钮。
@immutable
final class GridLayout extends LuckyLayout {
  /// 创建预算完成的布局；列表须保持不可变。
  const GridLayout(
      {required super.size,
      required this.prizeArea,
      required this.cellWidth,
      required this.cellHeight,
      required this.blocks,
      required this.cells,
      required this.prizeCount,
      required this.isEmpty});

  /// 逐层扣除背景内边距后的奖品区。
  final Rect prizeArea;

  /// 单列宽度。
  final double cellWidth;

  /// 单行高度。
  final double cellHeight;

  /// 背景块几何。
  final List<GridBlockLayout> blocks;

  /// 每格的普通态与激活态几何。
  final List<GridCellGeometry> cells;

  /// 奖品数量。
  final int prizeCount;

  /// 行列或尺寸无效时为真。
  @override
  final bool isEmpty;

  /// 返回第 [cellIndex] 个格子的完整命中矩形，不包含阴影收缩。
  Rect hitRect(int cellIndex) => cells[cellIndex].hitRect;
}

/// 背景块使用收缩前区域绘制，内边距只影响下一层。
@immutable
final class GridBlockLayout {
  /// 创建背景块布局。
  const GridBlockLayout(this.rect, this.block, this.images);

  /// 绘制区域。
  final Rect rect;

  /// 背景块配置。
  final LuckyBoxBlock block;

  /// 图片摆放。
  final List<LuckyImagePlacement> images;
}

/// 单格两个状态及其未收缩的命中矩形。
@immutable
final class GridCellGeometry {
  /// 创建完整格子几何。
  const GridCellGeometry(
      {required this.normal, required this.active, required this.hitRect});

  /// 普通态视觉。
  final GridCellVisual normal;

  /// 激活态视觉；按钮与普通态相同。
  final GridCellVisual active;

  /// 未经阴影收缩的矩形。
  final Rect hitRect;
}

/// 格子在某个状态下的完整视觉。
@immutable
final class GridCellVisual {
  /// 创建视觉，所有坐标均为逻辑像素。
  const GridCellVisual(
      {required this.rect,
      required this.borderRadius,
      required this.background,
      required this.shadow,
      required this.border,
      required this.foreground,
      required this.images,
      required this.texts});

  /// 阴影偏移收缩后的矩形。
  final Rect rect;

  /// 圆角半径，允许显式为零。
  final double borderRadius;

  /// 背景；null 才表示没有背景。
  final LuckyFill? background;

  /// 阴影；没有背景时不参与绘制。
  final LuckyShadow? shadow;

  /// 内描边。
  final LuckyBorder? border;

  /// 内容之上的前景。
  final LuckyFill? foreground;

  /// 图片摆放规则。
  final List<LuckyImagePlacement> images;

  /// 文字行，保留空行。
  final List<LuckyTextLine> texts;
}

/// 按 [config] 计算布局；行列或盒子非正时返回空布局，不抛异常。
///
/// 例如 `computeGridLayout(config, input)`；测量器由调用方释放。
GridLayout computeGridLayout(GridConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.grid.layout');
  try {
    var area = Offset.zero & input.size;
    final blocks = <GridBlockLayout>[];
    for (var i = 0; i < config.blocks.length; i++) {
      final block = config.blocks[i];
      blocks.add(GridBlockLayout(
          area,
          block,
          _images(block.images, area, kLuckyGridBlocksGroup, i,
              active: false)));
      final padding = block.padding;
      area = Rect.fromLTWH(
          area.left + padding.left,
          area.top + padding.top,
          math.max(0, area.width - padding.left - padding.right),
          math.max(0, area.height - padding.top - padding.bottom));
    }
    final empty = config.rows <= 0 ||
        config.cols <= 0 ||
        area.width <= 0 ||
        area.height <= 0;
    final gutter = config.options.gutter;
    final width = empty
        ? 0.0
        : math.max(
            0.0, (area.width - gutter * (config.cols - 1)) / config.cols);
    final height = empty
        ? 0.0
        : math.max(
            0.0, (area.height - gutter * (config.rows - 1)) / config.rows);
    final cells = <GridCellGeometry>[];
    final all = <GridCell>[...config.prizes, ...config.buttons];
    for (var i = 0; i < all.length; i++) {
      final cell = all[i];
      final rect = Rect.fromLTWH(
          area.left + (width + gutter) * cell.x,
          area.top + (height + gutter) * cell.y,
          empty ? 0 : math.max(0, width * cell.col + gutter * (cell.col - 1)),
          empty ? 0 : math.max(0, height * cell.row + gutter * (cell.row - 1)));
      final prize = i < config.prizes.length;
      final group = prize ? kLuckyGridPrizesGroup : kLuckyGridButtonsGroup;
      final index = prize ? i : i - config.prizes.length;
      final normal = _visual(config, input, cell, rect, group, index, false);
      cells.add(GridCellGeometry(
          normal: normal,
          active: prize
              ? _visual(config, input, cell, rect, group, index, true)
              : normal,
          hitRect: rect));
    }
    return GridLayout(
        size: input.size,
        prizeArea: area,
        cellWidth: width,
        cellHeight: height,
        blocks: List.unmodifiable(blocks),
        cells: List.unmodifiable(cells),
        prizeCount: config.prizes.length,
        isEmpty: empty || width <= 0 || height <= 0);
  } finally {
    luckyTraceEnd();
  }
}

/// 解析某格的状态；激活背景等整体替换普通态，文字与圆角非空覆盖。
GridCellVisual _visual(GridConfig config, LuckyLayoutInput input, GridCell cell,
    Rect hit, String group, int index, bool active) {
  final defaults = config.style.cell;
  final normal = cell.style;
  final style = config.activeStyle;
  final background =
      active ? style.background : normal?.background ?? defaults.background;
  final shadow = active ? style.shadow : normal?.shadow ?? defaults.shadow;
  final radius = normal?.borderRadius ?? defaults.borderRadius ?? 0;
  var rect = hit;
  // 上游 grid.ts:406-407：负偏移移动左上角，所有偏移缩小内容盒。
  if (background != null && shadow != null) {
    rect = Rect.fromLTWH(
        hit.left - math.min(0, shadow.offsetX),
        hit.top - math.min(0, shadow.offsetY),
        math.max(0, hit.width - shadow.offsetX.abs()),
        math.max(0, hit.height - shadow.offsetY.abs()));
  }
  return GridCellVisual(
      rect: rect,
      borderRadius: active ? style.borderRadius ?? radius : radius,
      background: background,
      shadow: shadow,
      border: active ? style.border : normal?.border ?? defaults.border,
      foreground:
          active ? style.foreground : normal?.foreground ?? defaults.foreground,
      images: _images(cell.images, rect, group, index, active: active),
      texts: List.unmodifiable([
        for (final text in cell.texts)
          ...layoutLuckyTextLines(
              text: text,
              defaults: config.style.text,
              override: active ? style.text : null,
              measurer: input.measurer,
              box: rect,
              leftBase: rect.width,
              topBase: rect.height,
              maxWidthOf: (_, __) =>
                  (text.lengthLimit ?? config.style.text.lengthLimit)
                      .resolve(rect.width))
      ]));
}

/// 图片尺寸使用绘制区域解析；激活槽的加载与普通图门控由绘制阶段处理。
List<LuckyImagePlacement> _images(
        List<LuckyImage> images, Rect rect, String group, int index,
        {required bool active}) =>
    List.unmodifiable([
      for (var i = 0; i < images.length; i++)
        LuckyImagePlacement(
            slot: LuckyImageSlot(group, index, i, active: active),
            image: images[i],
            box: rect,
            maxWidth: rect.width,
            maxHeight: rect.height,
            leftBase: rect.width,
            topBase: rect.height)
    ]);
