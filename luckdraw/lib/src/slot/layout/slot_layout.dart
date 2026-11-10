import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/foundation/box_block.dart';
import '../../core/foundation/constants.dart';
import '../../core/foundation/fill.dart';
import '../../core/foundation/image.dart';
import '../../core/game/layout.dart';
import '../../core/geometry/image_box.dart';
import '../../core/render/perf_trace.dart';
import '../../core/text/text_line.dart';
import '../model/slot_config.dart';
import '../model/slot_parts.dart';

/// 图片槽分组：奖品。
const String slotPrizeImageGroup = 'prizes';

/// 图片槽分组：装饰块。
const String slotBlockImageGroup = 'blocks';

/// 一个奖品的局部内容，供录制阶段使用。
@immutable
final class SlotCellContent {
  /// 保存局部盒子、背景、圆角、文字和图片规则。
  const SlotCellContent(
      {required this.rect,
      required this.background,
      required this.borderRadius,
      required this.lines,
      required this.images});

  /// 格子局部矩形。
  final Rect rect;

  /// 解析后的背景。
  final LuckyFill? background;

  /// 解析后的圆角，显式零有效。
  final double borderRadius;

  /// 已排版文字。
  final List<LuckyTextLine> lines;

  /// 图片摆放规则。
  final List<LuckyImagePlacement> images;
}

/// 装饰块布局。
@immutable
final class SlotBlockLayout {
  /// 保存块配置、矩形及回退后的背景。
  const SlotBlockLayout(this.block, this.rect, this.background, this.images);

  /// 原块配置。
  final LuckyBoxBlock block;

  /// 盒子坐标矩形。
  final Rect rect;

  /// 缺省时继承默认格子背景。
  final LuckyFill? background;

  /// 图片布局。
  final List<LuckyImagePlacement> images;
}

/// 一列的环形条带布局，不持有离屏长图。
@immutable
final class SlotReelLayout {
  /// 创建条带几何；洞使用 −1。
  const SlotReelLayout(
      {required this.clipRect,
      required this.stripPrizes,
      required this.period,
      required this.stripStart,
      required this.maxVisibleCells});

  /// 预计算列裁剪矩形。
  final Rect clipRect;

  /// 各条带位置对应的奖品下标。
  final List<int> stripPrizes;

  /// 包含洞在内的周期长度。
  final double period;

  /// 各位置在条带中的起点。
  final List<double> stripStart;

  /// 可见窗口容量上界，与奖品总数无关。
  final int maxVisibleCells;
}

/// 与滚动帧无关的老虎机布局。
@immutable
final class SlotLayout extends LuckyLayout {
  /// 创建布局；通常调用 [computeSlotLayout]。
  const SlotLayout(
      {required super.size,
      this.mode = SlotMode.vertical,
      required this.prizeArea,
      required this.cellWidth,
      required this.cellHeight,
      required this.widthAndSpacing,
      required this.heightAndSpacing,
      required this.cellAndSpacing,
      required this.windowStart,
      required this.windowLength,
      required this.reels,
      required this.cells,
      required this.blocks});

  /// 滚动方向；几何叠加层需要区分单轮方形窗口的横纵滚动。
  final SlotMode mode;

  /// 装饰块内的可见窗口。
  final Rect prizeArea;

  /// 格子宽。
  final double cellWidth;

  /// 格子高。
  final double cellHeight;

  /// 格子宽加列间距。
  final double widthAndSpacing;

  /// 格子高加行间距。
  final double heightAndSpacing;

  /// 滚动轴上的格距。
  final double cellAndSpacing;

  /// 令条带首格中心对准窗口中心的偏移。
  final double windowStart;

  /// 滚动轴上的窗口长度。
  final double windowLength;

  /// 各列几何。
  final List<SlotReelLayout> reels;

  /// 按奖品下标缓存的局部内容。
  final List<SlotCellContent> cells;

  /// 由外到内的装饰块。
  final List<SlotBlockLayout> blocks;

  /// 是否无法绘制有效格子。
  @override
  bool get isEmpty =>
      cellWidth <= 0 || cellHeight <= 0 || reels.isEmpty || cells.isEmpty;
}

/// 计算确定性布局；零尺寸、无列或间距挤满窗口时返回空布局。
SlotLayout computeSlotLayout(SlotConfig config, LuckyLayoutInput input) {
  luckyTraceStart('luckdraw.slot.layout');
  try {
    var area = Offset.zero & input.size;
    final blocks = <SlotBlockLayout>[];
    for (var b = 0; b < config.blocks.length; b++) {
      final block = config.blocks[b];
      blocks.add(SlotBlockLayout(
          block,
          area,
          block.background ?? config.style.cell.background,
          _images(block.images, slotBlockImageGroup, b, area)));
      final pad = block.padding;
      area = Rect.fromLTWH(
          area.left + pad.left,
          area.top + pad.top,
          math.max(0, area.width - pad.left - pad.right),
          math.max(0, area.height - pad.top - pad.bottom));
    }
    final o = config.options;
    final vertical = o.mode == SlotMode.vertical;
    final n = config.reels.length;
    final ratio = o.cellAspectRatio ?? 1;
    final valid = n > 0 &&
        area.width > 0 &&
        area.height > 0 &&
        ratio.isFinite &&
        ratio > 0;
    var cw = valid
        ? (vertical
            ? (area.width - o.colSpacing * (n - 1)) / n
            : (area.height - o.rowSpacing * (n - 1)) / n * ratio)
        : 0.0;
    var ch = valid
        ? (vertical ? cw / ratio : (area.height - o.rowSpacing * (n - 1)) / n)
        : 0.0;
    if (cw <= 0 || ch <= 0) {
      cw = 0;
      ch = 0;
    }
    final ws = cw + o.colSpacing;
    final hs = ch + o.rowSpacing;
    final cs = vertical ? hs : ws;
    final length = vertical ? area.height : area.width;
    final rect = Rect.fromLTWH(0, 0, cw, ch);
    final cells = <SlotCellContent>[];
    for (var i = 0; i < config.prizes.length; i++) {
      final prize = config.prizes[i];
      cells.add(SlotCellContent(
          rect: rect,
          background: prize.background ?? config.style.cell.background,
          borderRadius:
              prize.borderRadius ?? config.style.cell.borderRadius ?? 0,
          lines: [
            for (final text in prize.texts)
              ...layoutLuckyTextLines(
                  text: text,
                  defaults: config.style.text,
                  override: config.style.cell.text,
                  measurer: input.measurer,
                  box: rect,
                  leftBase: cw,
                  topBase: ch,
                  maxWidthOf: (_, __) =>
                      (text.lengthLimit ?? config.style.text.lengthLimit)
                          .resolve(cw))
          ],
          images: _images(prize.images, slotPrizeImageGroup, i, rect)));
    }
    return SlotLayout(
        size: input.size,
        mode: o.mode,
        prizeArea: area,
        cellWidth: cw,
        cellHeight: ch,
        widthAndSpacing: ws,
        heightAndSpacing: hs,
        cellAndSpacing: cs,
        windowStart: -(length - cs) / kLuckyHalfDivisor,
        windowLength: length,
        reels: [
          for (var r = 0; r < n; r++)
            _reel(config, r, area, cw, ch, ws, hs, cs, length, vertical)
        ],
        cells: List.unmodifiable(cells),
        blocks: List.unmodifiable(blocks));
  } finally {
    luckyTraceEnd();
  }
}

/// 将图片项解析为局部摆放规则。
List<LuckyImagePlacement> _images(
        List<LuckyImage> images, String group, int item, Rect rect) =>
    [
      for (var i = 0; i < images.length; i++)
        LuckyImagePlacement(
            slot: LuckyImageSlot(group, item, i),
            image: images[i],
            box: rect,
            maxWidth: rect.width,
            maxHeight: rect.height,
            leftBase: rect.width,
            topBase: rect.height)
    ];

/// 计算一列；order 中的洞仍占据周期长度。
SlotReelLayout _reel(SlotConfig config, int r, Rect area, double cw, double ch,
    double ws, double hs, double cs, double length, bool vertical) {
  final order = config.reels[r].order ??
      List<int>.generate(config.prizes.length, (i) => i);
  final spacing =
      vertical ? config.options.rowSpacing : config.options.colSpacing;
  return SlotReelLayout(
      clipRect: vertical
          ? Rect.fromLTWH(area.left + ws * r, area.top, cw, area.height)
          : Rect.fromLTWH(area.left, area.top + hs * r, area.width, ch),
      stripPrizes: List.unmodifiable(
          [for (final i in order) i >= 0 && i < config.prizes.length ? i : -1]),
      period: cs * order.length,
      stripStart: List.unmodifiable([
        for (var j = 0; j < order.length; j++)
          cs * j + spacing / kLuckyHalfDivisor
      ]),
      maxVisibleCells:
          cs > 0 ? (length / cs).ceil() + kLuckyHalfDivisor.toInt() : 0);
}
