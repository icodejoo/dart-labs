import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../core/foundation/constants.dart';
import '../../core/foundation/options.dart';
import '../../core/geometry/image_box.dart';
import '../../core/geometry/round_rect.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_parts.dart';
import '../motion/slot_motion.dart';
import 'slot_atlas.dart';

/// 奖品显示列表编号起点（任务卡 T3.3）。
const int _cellPictureBase = 2000;

/// 装饰块显示列表编号。
const int _blockPicture = 0;

/// 静态层显示列表编号起点。
const int _layerPictureBase = -1;

/// 单格直边的覆盖余量，单位为设备像素。
const double _seamOverlapPixels = 1;

/// 阴影边距采用三倍模糊 sigma。
const double _shadowSigmaExtent = 3;

/// 可见窗口回放绘制器；缓存由 surface State 持有并负责释放。
final class SlotPainter extends CustomPainter {
  /// 创建并准备显示列表；调用者在布局、图片或静态层变化时失效 [cache]。
  SlotPainter(this.data, this.cache, {this.atlas})
      : _imagesGeneration = data.images.generation,
        super(
            repaint: Listenable.merge(
                [data.frameListenable, data.imagesListenable])) {
    luckyTraceStart('luckdraw.slot.record');
    try {
      _context
        ..size = data.layout.size
        ..layout = data.layout
        ..frame = data.frame
        ..devicePixelRatio = data.devicePixelRatio;
      _blocks = cache.picture(_blockPicture, _recordBlocks);
      _cells = [
        for (var i = 0; i < data.layout.cells.length; i++)
          cache.picture(
              _cellPictureBase + i, (canvas) => _recordCell(canvas, i))
      ];
      _useAtlas = data.performance.cacheMode == LuckyCacheMode.raster &&
          atlas != null &&
          atlas!.prepare(_cells, data.layout, data.devicePixelRatio,
              data.performance.maxRasterSide, data.performance.filterQuality,
              maxRasterBytes: data.performance.maxRasterBytes,
              padding: _rasterPadding);
      if (!_useAtlas) atlas?.dispose();
      _staticLayers = [
        for (var i = 0; i < data.layers.length; i++)
          data.layers[i].isStatic
              ? cache.picture(_layerPictureBase - i,
                  (canvas) => data.layers[i].paint(canvas, _context))
              : null
      ];
    } finally {
      luckyTraceEnd();
    }
  }

  /// 阴影完整包围盒所需的逻辑边距，模糊按三倍 sigma 预算。
  double get _rasterPadding {
    final shadow = data.config.style.cell.shadow;
    if (shadow == null) return _seamOverlapPixels / data.devicePixelRatio;
    return math.max(shadow.offsetX.abs(), shadow.offsetY.abs()) +
        _shadowSigmaExtent * shadow.sigma(data.devicePixelRatio);
  }

  /// 已应用绘制数据。
  final LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> data;

  /// 表面拥有的分页图集，raster 模式需要提供并最终释放。
  final SlotAtlas? atlas;

  /// 本次布局是否使用图集。
  late final bool _useAtlas;

  /// 宿主缓存。
  final LuckyPictureCache cache;

  /// 记录创建时图片版本，避免共享图片视图更新后旧委托也读到新版本。
  final int _imagesGeneration;

  /// 装饰块显示列表。
  late final ui.Picture _blocks;

  /// 单格显示列表，无离屏长图。
  late final List<ui.Picture> _cells;

  /// 静态层显示列表。
  late final List<ui.Picture?> _staticLayers;

  /// 每帧复用的层上下文。
  final LuckyLayerContext<SlotLayout, SlotFrame> _context = LuckyLayerContext();

  /// 在录制阶段绘制已解析图片；未到达的槽位跳过。
  void _images(Canvas canvas, List<LuckyImagePlacement> placements) {
    for (final placement in placements) {
      final resolved = data.images[placement.slot];
      if (resolved == null) continue;
      drawLuckyImage(
          canvas, resolved.image, placement.place(resolved.naturalSize),
          borderRadius: placement.image.borderRadius,
          opacity: placement.image.opacity,
          filterQuality: data.performance.filterQuality);
    }
  }

  /// 录制全部装饰块，不与动态条带混合。
  void _recordBlocks(Canvas canvas) {
    for (final block in data.layout.blocks) {
      final path = buildRoundRectPath(block.rect, block.block.borderRadius);
      final background = block.background;
      if (background != null) {
        paintLuckyFill(canvas, path, background, block.rect,
            dpr: data.devicePixelRatio);
      }
      _images(canvas, block.images);
      final border = block.block.border;
      if (border != null) {
        strokeLuckyBorder(canvas, block.rect, block.block.borderRadius, border);
      }
    }
  }

  /// 录制单个奖品；自绘也只在录制阶段执行。
  void _recordCell(Canvas canvas, int i) {
    final cell = data.layout.cells[i];
    final style = data.config.style.cell;
    final options = data.config.options;
    final overlap = _seamOverlapPixels / data.devicePixelRatio;
    // 下一个不透明格子的抗锯齿边缘覆盖在前格完整底色上，避免混入块背景。
    // 有间距、圆角、半透明或阴影的格子保持原几何。
    final rect = cell.borderRadius == 0 &&
            style.shadow == null &&
            cell.background?.solidAlpha8 == kLuckyMaxAlpha8
        ? Rect.fromLTRB(
            cell.rect.left,
            cell.rect.top,
            cell.rect.right + (options.colSpacing == 0 ? overlap : 0),
            cell.rect.bottom + (options.rowSpacing == 0 ? overlap : 0))
        : cell.rect;
    final path = buildRoundRectPath(cell.rect, cell.borderRadius);
    final backgroundPath = buildRoundRectPath(rect, cell.borderRadius);
    final background = cell.background;
    if (background != null) {
      paintLuckyFill(canvas, backgroundPath, background, cell.rect,
          shadow: style.shadow, dpr: data.devicePixelRatio);
    }
    _images(canvas, cell.images);
    final foreground = style.foreground;
    if (foreground != null) paintLuckyFill(canvas, path, foreground, cell.rect);
    final border = style.border;
    if (border != null) {
      strokeLuckyBorder(canvas, cell.rect, cell.borderRadius, border);
    }
    paintLuckyTextLines(canvas, cell.lines, null,
        textDirection: data.textDirection, textScale: data.textScale);
    data.config.prizes[i].painter?.call(canvas, cell.rect.size, i);
  }

  /// 回放指定位置的用户层。
  void _layers(Canvas canvas, LuckyLayerPosition position) =>
      luckyReplayLayers(canvas, data.layers, _staticLayers, position, _context,
          isolate: false);

  /// 环形索引枚举窗口内格子；每帧不分配矩形、画笔或显示列表。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.slot.paint');
    try {
      final layout = data.layout;
      data.hooks.beforeDraw?.call(canvas, size);
      _layers(canvas, LuckyLayerPosition.background);
      if (layout.blocks.isNotEmpty) canvas.drawPicture(_blocks);
      _layers(canvas, LuckyLayerPosition.belowItems);
      if (!layout.isEmpty) {
        final vertical = data.config.options.mode == SlotMode.vertical;
        final spacing = vertical
            ? data.config.options.rowSpacing
            : data.config.options.colSpacing;
        final extent = vertical ? layout.cellHeight : layout.cellWidth;
        if (_useAtlas) {
          atlas!.paint(canvas, data.frame, data.config.options.mode, spacing);
        } else {
          for (var r = 0; r < layout.reels.length; r++) {
            final reel = layout.reels[r];
            final count = reel.stripPrizes.length;
            if (count == 0 || reel.period <= 0) continue;
            var s = data.frame.scroll[r] + layout.windowStart;
            if (s < 0) s = s.remainder(reel.period) + reel.period;
            if (s > reel.period) s = s.remainder(reel.period);
            final first =
                ((s - spacing / kLuckyHalfDivisor) / layout.cellAndSpacing)
                    .floor();
            canvas.save();
            canvas.clipRect(reel.clipRect, doAntiAlias: false);
            for (var j = first; j < first + reel.maxVisibleCells; j++) {
              final index = j % count;
              final start = reel.stripStart[index] +
                  ((j - index) ~/ count) * reel.period -
                  s;
              if (start >= layout.windowLength) break;
              if (start + extent <= 0) continue;
              final prize = reel.stripPrizes[index];
              if (prize < 0) continue;
              canvas.save();
              canvas.translate(reel.clipRect.left + (vertical ? 0 : start),
                  reel.clipRect.top + (vertical ? start : 0));
              canvas.drawPicture(_cells[prize]);
              canvas.restore();
            }
            canvas.restore();
          }
        }
      }
      _layers(canvas, LuckyLayerPosition.aboveItems);
      _layers(canvas, LuckyLayerPosition.foreground);
      data.hooks.afterDraw?.call(canvas, size);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 布局、图片、配置或层变化时重新绘制。
  @override
  bool shouldRepaint(covariant SlotPainter oldDelegate) =>
      data.layoutGeneration != oldDelegate.data.layoutGeneration ||
      _imagesGeneration != oldDelegate._imagesGeneration ||
      data.config != oldDelegate.data.config ||
      data.layers != oldDelegate.data.layers;
}
