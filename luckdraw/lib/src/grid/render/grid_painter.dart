import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../core/foundation/constants.dart';
import '../../core/foundation/options.dart';
import '../../core/geometry/image_box.dart';
import '../../core/geometry/round_rect.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/timebase.dart';
import '../../core/render/cached_picture.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/grid_layout.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';
import '../motion/grid_motion.dart';

/// 每格缓存起始编号，上游分段方案保留前面的编号给背景与扩展层。
const int _cellPictureBase = 1000;

/// 每格包含普通与激活两种状态。
const int _cellPictureStates = 2;

/// 带阴影背景缓存编号起点。
const int _backgroundBase = 100000;

/// 格子内容缓存编号起点。
const int _contentBase = 200000;

/// 高斯核保留三个 sigma 的可见范围。
const double _shadowExtent = 3;

/// 九宫格分段录制与回放；绘制帧只选择已缓存的格子 Picture。
final class GridPainter extends CustomPainter {
  /// 绑定 [data] 的帧监听器；[cache] 由渲染表面持有并释放。
  GridPainter(
      {required LuckySurfaceData<GridConfig, GridLayout, GridFrame> data,
      required this.cache,
      Listenable? updates})
      : _data = data,
        super(
            repaint: Listenable.merge(
                [data.frameListenable, data.imagesListenable, updates])) {
    rebuildSegments(data);
  }

  /// 渲染表面拥有的缓存。
  final LuckyPictureCache cache;

  /// 当前渲染数据。
  LuckySurfaceData<GridConfig, GridLayout, GridFrame> _data;

  /// 背景块录制结果。
  late ui.Picture _blocks;

  /// 按格子和状态预算的显示列表，避免帧内创建回调。
  final List<ui.Picture> _cells = [];

  /// 带阴影格子的运动缓存，普通格子保留矢量。
  final List<LuckyCachedPicture?> _cellPlayback = [];

  /// 与阴影分离的格子内容，保留文字、图片和用户回调的矢量边界。
  final List<ui.Picture?> _cellContents = [];

  /// 各插入位置的扩展层绘制段。
  final Map<LuckyLayerPosition, List<_GridLayerSegment>> _layers = {};

  /// 跨帧复用的扩展层上下文。
  final LuckyLayerContext<GridLayout, GridFrame> _context = LuckyLayerContext();

  /// 应用新布局、图片或扩展层并重录静态内容。
  void rebuildSegments(
      LuckySurfaceData<GridConfig, GridLayout, GridFrame> data) {
    luckyTraceStart('luckdraw.grid.record');
    try {
      _data = data;
      cache.invalidateAll();
      _cells.clear();
      _cellPlayback.clear();
      _cellContents.clear();
      _layers.clear();
      _context
        ..size = data.layout.size
        ..layout = data.layout
        ..frame = data.frame
        ..devicePixelRatio = data.devicePixelRatio;
      _blocks = cache.picture(0, _recordBlocks);
      for (var i = 0; i < data.layout.cells.length; i++) {
        for (var state = 0; state < _cellPictureStates; state++) {
          final active = state != 0 && i < data.layout.prizeCount;
          final visual = active
              ? data.layout.cells[i].active
              : data.layout.cells[i].normal;
          final shadow = visual.shadow;
          final performance =
              data.performance.cacheMode == LuckyCacheMode.auto &&
                      data.config.options.motion.timebase == LuckyTimebase.frame
                  ? data.performance.copyWith(cacheMode: LuckyCacheMode.picture)
                  : data.performance;
          final padding = shadow == null
              ? 0.0
              : shadow.sigma(data.devicePixelRatio) * _shadowExtent +
                  shadow.offsetX.abs() +
                  shadow.offsetY.abs() +
                  1;
          final index = i * _cellPictureStates + state;
          if (shadow != null &&
              visual.background != null &&
              performance.cacheMode != LuckyCacheMode.picture) {
            final background = LuckyCachedPicture(
                cache,
                _backgroundBase + index,
                visual.rect.inflate(padding),
                data.devicePixelRatio,
                (canvas) => _recordBackground(canvas, visual),
                performance);
            final content = cache.picture(
                _contentBase + index,
                (canvas) =>
                    recordCell(canvas, i, active, includeBackground: false));
            _cellPlayback.add(background);
            _cellContents.add(content);
            _cells.add(cache.picture(_cellPictureBase + index, (canvas) {
              canvas.drawPicture(background.picture);
              canvas.drawPicture(content);
            }));
          } else {
            _cellPlayback.add(null);
            _cellContents.add(null);
            _cells.add(cache.picture(_cellPictureBase + index,
                (canvas) => recordCell(canvas, i, active)));
          }
        }
      }
      for (var i = 0; i < data.layers.length; i++) {
        final layer = data.layers[i];
        final picture = layer.isStatic
            ? cache.picture(i + 1, (canvas) => layer.paint(canvas, _context))
            : null;
        (_layers[layer.position] ??= []).add(_GridLayerSegment(layer, picture));
      }
    } finally {
      luckyTraceEnd();
    }
  }

  /// 更新纯动态参数；静态内容不受影响时无需重新录制。
  void updateData(LuckySurfaceData<GridConfig, GridLayout, GridFrame> data) {
    _data = data;
    _context.frame = data.frame;
  }

  /// 录制背景块，块背景没有普通格子默认值回退。
  void _recordBlocks(Canvas canvas) {
    for (final block in _data.layout.blocks) {
      final path = buildRoundRectPath(block.rect, block.block.borderRadius);
      final background = block.block.background;
      if (background != null) {
        paintLuckyFill(canvas, path, background, block.rect);
      }
      final border = block.block.border;
      if (border != null) {
        strokeLuckyBorder(
            canvas,
            block.rect.deflate(border.width / kLuckyHalfDivisor),
            block.block.borderRadius,
            border);
      }
      _paintImages(canvas, block.images);
    }
  }

  /// 录制一个格子；可用于画布契约测试，不应在动画帧中调用。
  ///
  /// [index] 为布局格子下标；按钮即使传入 active 也使用普通态。
  /// [includeBackground] 为 false 时仅录制内容，用于背景缓存分离。
  void recordCell(Canvas canvas, int index, bool active,
      {bool includeBackground = true}) {
    final geometry = _data.layout.cells[index];
    final isPrize = index < _data.layout.prizeCount;
    final visual = active && isPrize ? geometry.active : geometry.normal;
    final path = buildRoundRectPath(visual.rect, visual.borderRadius);
    if (includeBackground) _recordBackground(canvas, visual);
    final border = visual.border;
    if (border != null) {
      strokeLuckyBorder(
          canvas,
          visual.rect.deflate(border.width / kLuckyHalfDivisor),
          visual.borderRadius,
          border);
    }
    _paintImages(canvas, visual.images);
    final GridCellPainter? painter = isPrize
        ? _data.config.prizes[index].painter
        : _data.config.buttons[index - _data.layout.prizeCount].painter;
    if (painter != null) {
      canvas.save();
      painter(canvas, visual.rect, active && isPrize);
      canvas.restore();
    }
    paintLuckyTextLines(canvas, visual.texts, null,
        textDirection: _data.textDirection, textScale: _data.textScale);
    final foreground = visual.foreground;
    if (foreground != null) {
      paintLuckyFill(canvas, path, foreground, visual.rect);
    }
  }

  /// 只录制格子背景及阴影，不限制文字、图片或用户回调的边界。
  void _recordBackground(Canvas canvas, GridCellVisual visual) {
    final background = visual.background;
    if (background != null) {
      paintLuckyFill(
          canvas,
          buildRoundRectPath(visual.rect, visual.borderRadius),
          background,
          visual.rect,
          shadow: visual.shadow,
          dpr: _data.devicePixelRatio);
    }
  }

  /// 只有普通图已加载才允许显示激活图；激活图缺失时回退普通图。
  void _paintImages(Canvas canvas, List<LuckyImagePlacement> placements) {
    for (final placement in placements) {
      final slot = placement.slot;
      final normal =
          _data.images[slot.active ? slot.copyWith(active: false) : slot];
      if (normal == null) continue;
      final resolved = slot.active ? _data.images[slot] ?? normal : normal;
      drawLuckyImage(
          canvas, resolved.image, placement.place(resolved.naturalSize),
          borderRadius: placement.image.borderRadius,
          opacity: placement.image.opacity,
          filterQuality: _data.performance.filterQuality);
    }
  }

  /// 回放某个插入位置的静态层，或直接绘制动态层。
  void _paintLayers(Canvas canvas, LuckyLayerPosition position) {
    final layers = _layers[position];
    if (layers == null) return;
    for (final segment in layers) {
      final picture = segment.picture;
      if (picture == null) {
        canvas.save();
        segment.layer.paint(canvas, _context);
        canvas.restore();
      } else {
        canvas.drawPicture(picture);
      }
    }
  }

  /// 回放背景及每格一张图片；不创建 Paint、Path 或布局对象。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.grid.paint');
    try {
      _data.hooks.beforeDraw?.call(canvas, size);
      _paintLayers(canvas, LuckyLayerPosition.background);
      canvas.drawPicture(_blocks);
      _paintLayers(canvas, LuckyLayerPosition.belowItems);
      for (var i = 0; i < _data.layout.prizeCount; i++) {
        final active =
            i == _data.frame.activeIndex && i < _data.layout.prizeCount;
        _paintCell(canvas, i * _cellPictureStates + (active ? 1 : 0));
      }
      _paintLayers(canvas, LuckyLayerPosition.aboveItems);
      for (var i = _data.layout.prizeCount;
          i < _data.layout.cells.length;
          i++) {
        _paintCell(canvas, i * _cellPictureStates);
      }
      _paintLayers(canvas, LuckyLayerPosition.foreground);
      _data.hooks.afterDraw?.call(canvas, size);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 按运动阶段选择带阴影格子的缓存，避免重复执行模糊。
  void _paintCell(Canvas canvas, int index) {
    final playback = _cellPlayback[index];
    if (playback == null ||
        (_data.performance.cacheMode == LuckyCacheMode.auto &&
            !_data.frame.phase.isMoving)) {
      canvas.drawPicture(_cells[index]);
    } else {
      playback.paint(canvas, isMoving: _data.frame.phase.isMoving);
      canvas.drawPicture(_cellContents[index]!);
    }
  }

  /// 缓存和数据在同一个 painter 中更新；替换 painter 时始终要求绘制。
  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) => true;
}

/// 扩展层的动态回调或预录制显示列表。
final class _GridLayerSegment {
  /// 绑定扩展层及其可选静态图片。
  const _GridLayerSegment(this.layer, this.picture);

  /// 扩展层配置。
  final LuckyLayer<GridLayout, GridFrame> layer;

  /// 静态图片，动态层为 null。
  final ui.Picture? picture;
}
