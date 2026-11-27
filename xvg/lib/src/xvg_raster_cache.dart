import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'pixel_snap_layer.dart';

/// Shared bitmap tile budget and statistics. / 静态 SVG 位图分块的共享预算和统计。
abstract final class XvgRasterCache {
  /// Prevents instantiation. / 禁止实例化。
  XvgRasterCache._();

  /// Default tile core edge in image texels. / 默认图片分块内核边长，以纹素计。
  static const tileSize = 256;

  /// Enough for about two tall 1080p RGBA8 viewports including tile overhead.
  /// 可容纳约两个 1080p 长屏视口及分块开销。
  static const defaultByteBudget = 32 * 1024 * 1024;

  /// Shared RGBA8 byte limit per isolate. Set to
  /// zero to use vectors until the budget is raised.
  /// 同一 isolate 共用的 RGBA8 字节上限。设为 0 时回退向量。
  static int get byteBudget => _TileCache.instance.budget;

  /// Changes the shared budget and immediately trims resident tiles. / 更新预算并立即裁减驻留块。
  static set byteBudget(int value) {
    RangeError.checkNotNegative(value, 'byteBudget');
    _TileCache.instance.setBudget(value);
  }

  /// Ready image bytes, estimated as width × height × 4. / 已就绪图像的估算字节数。
  static int get bytesUsed => _TileCache.instance.bytesUsed;

  /// Number of ready tiles across all static widgets. / 所有静态组件中已就绪的块数。
  static int get tileCount => _TileCache.instance.tileCount;

  /// Tile image handles disposed since isolate start. / isolate 启动后已释放的块图像句柄数。
  static int get disposedTileCount => _TileCache.instance.disposedCount;
}

/// Minimum parsed path count for automatic caching. / 自动缓存所需的最少路径数。
const xvgRasterMinPaths = 100;

/// Minimum parsed point count for automatic caching. / 自动缓存所需的最少坐标点数。
const xvgRasterMinPoints = 15000;

/// Cache overrides used by tests and benchmarks. / 测试与基准使用的缓存覆盖。
enum XvgRasterCacheOverride {
  /// Paint vectors only. / 仅绘制向量。
  disabled,

  /// Bypass the complexity gate. / 跳过复杂度门槛。
  enabled,
}

/// Observes raster requests and their handle completion for benchmarks. / 为基准记录生成请求及句柄完成。
@visibleForTesting
void Function(bool started, int width, int height)? debugXvgRasterRequest;

/// Stores the testing policy for the next widget build. / 保存下次构建使用的测试覆盖模式。
XvgRasterCacheOverride? _cacheOverride;

/// The policy for the next build. / 下次构建使用的策略。
XvgRasterCacheOverride? get xvgRasterCacheOverride => _cacheOverride;

/// Null runs automatic admission. / 为 null 时按库规则自动判断。
@visibleForTesting
set debugXvgRasterCacheOverride(XvgRasterCacheOverride? value) =>
    _cacheOverride = value;

/// Whether a visible raster grid is complete. / 是否有在屏的栅格网格已齐备。
@visibleForTesting
bool get debugXvgRasterTilesReady => _TileCache.instance._layers.any(
  (layer) => layer.attached && (layer._current?.ready ?? false),
);

/// A childless paint box that supplies a composition-aware cache layer.
/// 提供合成期缓存层的无子节点绘制盒。
class XvgRasterPaint extends LeafRenderObjectWidget {
  /// Creates a box with the original vector painter as its fallback. / 创建带原始向量回退的绘制盒。
  const XvgRasterPaint({
    super.key,
    required this.preferredSize,
    required this.intrinsicSize,
    required this.fit,
    required this.alignment,
    required this.painter,
    this.contentBounds,
    this.colorFilter,
  });

  /// Preferred size under loose constraints. / 松约束下的首选尺寸。
  final Size preferredSize;

  /// Intrinsic picture size. / Picture 的固有尺寸。
  final Size intrinsicSize;

  /// Conservative bounds, or null for full viewport coverage. / 保守绘制边界，null 表示覆盖完整视口。
  final Rect? contentBounds;

  /// Recoloring applied inside the visible viewport. / 在可见视口内应用的重着色滤镜。
  final ColorFilter? colorFilter;

  /// How to fit the picture. / Picture 的适配方式。
  final BoxFit fit;

  /// Alignment of the fitted picture. / 适配后 Picture 的位置。
  final Alignment alignment;

  /// Original vector painting logic. / 原有向量绘制逻辑。
  final CustomPainter painter;

  /// Creates the paint box. / 创建绘制盒。
  @override
  RenderBox createRenderObject(BuildContext context) =>
      _RenderRasterPaint(this, View.of(context));

  /// Applies changes to the paint box. / 将更新传给绘制盒。
  @override
  void updateRenderObject(BuildContext context, RenderBox renderObject) =>
      (renderObject as _RenderRasterPaint).configure(this, View.of(context));
}

/// Mirrors a childless RenderCustomPaint's sizing and hit behavior.
/// 沿用无子节点 RenderCustomPaint 的布局和命中语义。
class _RenderRasterPaint extends RenderBox {
  /// Stores the paint inputs until the first layout. / 保存绘制参数等待首次布局。
  _RenderRasterPaint(this._options, this._view);

  /// Current widget inputs. / 当前组件参数。
  XvgRasterPaint _options;

  /// Display containing this render object. / 渲染对象所在的显示视图。
  ui.FlutterView _view;

  /// Owned scene layer, reused across paints. / 跨 paint 复用的场景图层。
  final _handle = LayerHandle<_RasterTileLayer>(_RasterTileLayer());

  /// Retains the optional filter layer across paints. / 跨绘制保留可选的滤镜图层。
  final _filterLayer = LayerHandle<ColorFilterLayer>();

  /// Scene layer kept alive across parent repaints. / 跨父级重绘保留的场景图层。
  _RasterTileLayer get _layer => _handle.layer!;

  /// A layer is needed even under a hard-edge ancestor clip. / 硬裁剪祖先也须通过图层合成。
  @override
  bool get alwaysNeedsCompositing => true;

  /// Updates the cache only when vector content or raster geometry changes. / 向量内容或栅格几何变化时更新缓存。
  void configure(XvgRasterPaint options, ui.FlutterView view) {
    final old = _options;
    final geometryChanged =
        old.intrinsicSize != options.intrinsicSize ||
        old.fit != options.fit ||
        old.alignment != options.alignment;
    final contentChanged = options.painter.shouldRepaint(old.painter);
    final invalidate = geometryChanged || contentChanged || _view != view;
    _options = options;
    _view = view;
    if (old.preferredSize != options.preferredSize) markNeedsLayout();
    if (invalidate) _layer.clear();
    // Coverage changes only affect tile selection. / 覆盖范围变化只影响分块选择。
    if (invalidate ||
        old.contentBounds != options.contentBounds ||
        old.colorFilter != options.colorFilter) {
      markNeedsPaint();
    }
  }

  /// Uses the same constrained preferred size as CustomPaint. / 与 CustomPaint 一样约束首选尺寸。
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_options.preferredSize);

  /// Resolves the paint size. / 计算绘制尺寸。
  @override
  void performLayout() {
    final next = computeDryLayout(constraints);
    if (!hasSize || size != next) {
      _layer._discardVector();
      markNeedsPaint();
    }
    size = next;
  }

  /// A background painter is hit across the box by default. / 背景画笔默认在盒内均可命中。
  @override
  bool hitTestSelf(Offset position) => true;

  /// Intrinsic width follows CustomPaint. / 固有宽度沿用 CustomPaint。
  @override
  double computeMinIntrinsicWidth(double height) {
    final width = _options.preferredSize.width;
    return width.isFinite ? width : 0;
  }

  /// Intrinsic width follows CustomPaint. / 固有宽度沿用 CustomPaint。
  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeMinIntrinsicWidth(height);

  /// Intrinsic height follows CustomPaint. / 固有高度沿用 CustomPaint。
  @override
  double computeMinIntrinsicHeight(double width) {
    final height = _options.preferredSize.height;
    return height.isFinite ? height : 0;
  }

  /// Intrinsic height follows CustomPaint. / 固有高度沿用 CustomPaint。
  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  /// Inserts the scene layer, which can re-evaluate visibility without repaint.
  /// 插入场景图层，使可见区域可在无需 repaint 时重新计算。
  @override
  void paint(PaintingContext context, Offset offset) {
    _layer.update(_options, _view, size, offset);
    final filter = _options.colorFilter;
    if (filter == null) {
      layer = null;
      _filterLayer.layer = null;
      _paintArtwork(context, offset);
      return;
    }
    layer = context.pushClipRect(needsCompositing, offset, _layer._viewport, (
      context,
      offset,
    ) {
      _filterLayer.layer = context.pushColorFilter(
        offset,
        filter,
        _paintArtwork,
        oldLayer: _filterLayer.layer,
      );
    }, oldLayer: layer as ClipRectLayer?);
  }

  /// Inserts the retained vector and tile compositor. / 插入保留的向量及分块合成层。
  void _paintArtwork(PaintingContext context, Offset offset) {
    context.addLayer(_layer);
  }

  /// Repaints cleared layers and tracks memory pressure. / 重绘已清空的图层，并监听内存压力。
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _TileCache.instance.attach(_layer);
    markNeedsPaint();
  }

  /// Releases image handles on unmount. / 卸载时释放图像句柄。
  @override
  void detach() {
    _TileCache.instance.detach(_layer);
    _layer.clear();
    super.detach();
  }

  /// Releases the last vector display list owned by the layer. / 释放图层拥有的最后一张向量显示列表。
  @override
  void dispose() {
    _layer.clear();
    _handle.layer = null;
    _filterLayer.layer = null;
    super.dispose();
  }
}

/// Sampling border shared by adjacent cores. / 相邻分块共用的采样边。
const _tileBorder = 2.0;

/// RGBA8 bytes per texel. / 每个 RGBA8 纹素的字节数。
const _bytesPerPixel = 4;

/// Tolerates floating-point arithmetic in scene matrices. / 容忍场景矩阵的浮点误差。
const _gridTolerance = 1e-7;

/// Whole texture limits in texels and bytes. / 整图纹理的纹素边长与字节上限。
const _wholeImageEdge = 2048;
const _wholeImageBytes = 4 * 1024 * 1024;

/// Reuse band for desired versus cached texel density. / 目标与缓存纹素密度之比的复用区间。
const _imageScaleMin = 0.8;
const _imageScaleMax = 1.25;

/// Relative jitter ignored while waiting for the new density. / 等待新密度时忽略的相对抖动。
const _imageScaleJitter = 0.005;

/// Time without a material resolution change before resampling. / 分辨率无明显变化后等待重采样的时长。
const _imageScaleSettle = Duration(milliseconds: 150);

/// A fixed core in raster coordinates, with padding sampled from the same picture.
/// 栅格坐标中的固定内块，采样边缘来自同一张 Picture。
class _Tile {
  /// Creates an image tile with a sampling border. / 创建带采样边的图片块。
  _Tile(this.grid, this.core, this.samples);

  /// Owning image grid. / 所属图片网格。
  final _ImageGrid grid;

  /// Raster image, when ready. / 已生成的栅格图像。
  ui.Image? image;

  /// Whether to skip future attempts after a raster failure. / 生成失败后是否跳过重试。
  bool failed = false;

  /// Tile core in physical coordinates relative to the component's grid origin.
  /// 以组件网格原点为基准的物理坐标内块。
  final Rect core;

  /// Bounds in a global texel grid, including padding. / 含采样边的全局纹素网格边界。
  final Rect samples;

  /// Resident RGBA8 bytes. / 驻留的 RGBA8 字节数。
  int get bytes =>
      samples.width.toInt() * samples.height.toInt() * _bytesPerPixel;

  /// Whether this tile is used on screen in the current layer tree. / 当前图层树中该块是否在屏。
  bool get visible => grid.layer.attached && grid.visible.overlaps(core);

  /// Releases the handle once. / 释放图像句柄。
  void release() {
    image?.dispose();
    image = null;
  }
}

/// Texel bounds of a tile core. / 分块内核的纹素边界。
Rect _tileRect((int, int) cell, int edge) {
  return Rect.fromLTWH(
    (cell.$1 * edge).toDouble(),
    (cell.$2 * edge).toDouble(),
    edge.toDouble(),
    edge.toDouble(),
  );
}

/// Tile coordinates overlapping a rectangle. / 与矩形相交的分块坐标。
Iterable<(int, int)> _cells(Rect region, int edge) sync* {
  final right = (region.right / edge).ceil();
  final bottom = (region.bottom / edge).ceil();
  for (var y = (region.top / edge).floor(); y < bottom; y++) {
    for (var x = (region.left / edge).floor(); x < right; x++) {
      yield (x, y);
    }
  }
}

/// A fixed grid in layout-local texels. / 固定在布局局部纹素中的网格。
class _ImageGrid {
  /// Selects a whole texture for small content and tiles for larger content. / 为较小内容选用整图纹理，为较大内容分块。
  _ImageGrid(this.layer, this.layout, this.density, this.phase, Rect content)
    : extent = Rect.fromLTRB(
        (content.left * density.dx + phase.dx).floorToDouble(),
        (content.top * density.dy + phase.dy).floorToDouble(),
        (content.right * density.dx + phase.dx).ceilToDouble(),
        (content.bottom * density.dy + phase.dy).ceilToDouble(),
      );

  /// Layer owning the vector source. / 持有向量源的图层。
  final _RasterTileLayer layer;

  /// Layout at the time of capture. / 生成时的布局。
  final Size layout;

  /// Texture pixels per logical pixel on each axis. / 两轴每逻辑像素对应的纹素数。
  final Offset density;

  /// Fractional physical translation baked into the texture. / 烘入纹理的物理平移小数部分。
  final Offset phase;

  /// Integer texel bounds enclosing the recorded content. / 包围已录制内容的整数纹素范围。
  final Rect extent;

  /// Whether this grid needs tiles. / 此网格是否需要分块。
  late final bool tiled =
      extent.width > _wholeImageEdge ||
      extent.height > _wholeImageEdge ||
      extent.width * extent.height * _bytesPerPixel > _wholeImageBytes;

  /// Uses larger cores on long, narrow content to reduce draw calls. / 狭长内容使用较大分块，以减少绘制调用。
  late final int tileEdge =
      extent.height > _wholeImageEdge &&
          extent.width <= _wholeImageEdge &&
          extent.height >= 2 * extent.width
      ? 2 * XvgRasterCache.tileSize
      : XvgRasterCache.tileSize;

  /// Retained cells shared with the global LRU. / 受全局 LRU 管理的驻留块。
  final tiles = <(int, int), _Tile>{};

  /// Visible texels selected for drawing and generation. / 选中用于绘制及生成的可见纹素。
  Rect visible = Rect.zero;

  /// Whether all visible cells have image handles. / 所有在屏块是否都有图像句柄。
  bool get ready =>
      !visible.isEmpty &&
      cells(visible).every((cell) => tiles[cell]?.image != null);

  /// Lists cells in a texel rectangle. / 列出纹素矩形内的块。
  Iterable<(int, int)> cells(Rect region) => region.isEmpty
      ? const []
      : tiled
      ? _cells(region, tileEdge)
      : const [(0, 0)];

  /// Returns the integer bounds used for sampling a cell. / 返回块采样用的整数边界。
  Rect _samples((int, int) cell) =>
      _tileRect(cell, tileEdge).inflate(_tileBorder).intersect(extent);

  /// Creates the next missing cell in the visible window. / 创建在屏范围内下一缺失块。
  _Tile? nextTile() {
    for (final cell in cells(visible)) {
      final tile = tiles.putIfAbsent(
        cell,
        () => _Tile(
          this,
          tiled ? _tileRect(cell, tileEdge).intersect(extent) : extent,
          tiled ? _samples(cell) : extent,
        ),
      );
      if (tile.image == null && !tile.failed) return tile;
    }
    return null;
  }

  /// Counts exact visible texture bytes and stops when the budget is exceeded. / 精确统计可见纹理字节数，超出预算时提前结束。
  bool fits(int budget) {
    if (visible.isEmpty) return true;
    if (!tiled) return extent.width * extent.height * _bytesPerPixel <= budget;
    var remaining = budget;
    for (final cell in cells(visible)) {
      final samples = _samples(cell);
      remaining -=
          samples.width.toInt() * samples.height.toInt() * _bytesPerPixel;
      if (remaining < 0) return false;
    }
    return true;
  }

  /// Releases all resident images. / 释放所有驻留图像。
  void clear() {
    for (final tile in tiles.values) {
      _TileCache.instance.remove(tile);
    }
    tiles.clear();
  }
}

/// Records and composites fixed image textures under the Flutter transform. / 在 Flutter 变换下录制及合成固定的图片纹理。
class _RasterTileLayer extends Layer {
  /// Paint for exact texel alignment. / 对齐纹素时使用的画笔。
  static final _alignedPaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none;

  /// Paint for transformed textures. / 变换纹理时使用的画笔。
  static final _linearPaint = Paint()..filterQuality = FilterQuality.low;

  /// Original vector drawing in logical box coordinates. / 逻辑绘制盒坐标中的原始向量图。
  ui.Picture? _vector;

  /// Painting context offset within the parent layer. / 父图层内的绘制偏移。
  Offset _offset = Offset.zero;

  /// Logical paint viewport. / 逻辑绘制视口。
  Rect _viewport = Rect.zero;

  /// Content mapped into the logical paint box. / 映射到逻辑绘制盒的内容边界。
  Rect _content = Rect.zero;

  /// Current view's screen bounds and DPR. / 当前显示视图的屏幕边界与 DPR。
  ui.FlutterView? _view;

  /// Accumulated clip in physical scene coordinates. / 物理场景坐标下的累积裁剪。
  Rect _clip = Rect.zero;

  /// Reuses the clip visitor across scenes. / 跨场景复用裁剪回调。
  late final void Function(Layer, Matrix4) _clipVisitor = _intersectClip;

  /// Latest layout dimensions. / 最新布局尺寸。
  Size _layout = Size.zero;

  /// Grid currently used for drawing. / 当前用于绘制的网格。
  _ImageGrid? _current;

  /// Grid being built at a new density. / 待生成的新密度网格。
  _ImageGrid? _replacement;

  /// Earlier whole texture that can cover regions revealed while zooming out. / 缩小时覆盖新露出区域的早期整图纹理。
  _Tile? _overview;

  /// Latest settled target candidate. / 当前等待停稳的目标。
  (Size, Offset)? _target;

  /// Sends a scene update at the end of the stability window. / 停稳窗口结束时请求合成。
  Timer? _settle;

  /// Textures sampled by the retained composition. / 保留合成图采样的纹理。
  List<_Tile> _drawn = const [];

  /// Recorded composite reused while its inputs remain valid. / 输入有效时复用的合成录制。
  ui.Picture? _painted;

  /// Vector recording used in the retained composition. / 保留合成图所用的向量录制。
  ui.Picture? _paintedVector;

  /// Layout used to map texture destinations in the retained composition. / 保留合成图映射纹理目标时的布局。
  Size? _paintedLayout;

  /// Whether the retained composition samples texels at exact alignment. / 保留合成图是否精确对齐纹素。
  bool? _paintedAligned;

  /// Whether the retained composition covers the entire visible region. / 保留合成图是否覆盖完整可见区域。
  bool? _paintedFull;

  /// Tracks composition through retained ancestors. / 通过保留祖先图层跟踪合成状态。
  @override
  bool get alwaysNeedsAddToScene => true;

  /// Records the fallback using the same painter as the default path. / 通过默认路径的同一画笔录制回退向量。
  void update(
    XvgRasterPaint options,
    ui.FlutterView view,
    Size size,
    Offset offset,
  ) {
    _view = view;
    _offset = offset;
    _layout = size;
    final viewport = svgPaintViewport(
      options.intrinsicSize,
      size,
      options.fit,
      options.alignment,
    );
    _viewport = viewport.intersect(Offset.zero & size);
    final bounds = options.contentBounds;
    _content = _viewport;
    if (bounds != null && bounds.isFinite && !options.intrinsicSize.isEmpty) {
      final sx = viewport.width / options.intrinsicSize.width;
      final sy = viewport.height / options.intrinsicSize.height;
      _content = Rect.fromLTRB(
        viewport.left + bounds.left * sx,
        viewport.top + bounds.top * sy,
        viewport.left + bounds.right * sx,
        viewport.top + bounds.bottom * sy,
      ).intersect(_viewport);
    }
    if (_vector != null) return;
    final recorder = ui.PictureRecorder();
    options.painter.paint(Canvas(recorder), size);
    _vector = recorder.endRecording();
  }

  /// Releases the compositor's extra image references. / 释放合成图持有的额外图像引用。
  void _forgetPicture() {
    _painted?.dispose();
    _painted = null;
    _paintedVector = null;
    _drawn = const [];
  }

  /// Discards a retained picture referencing an evicted texture. / 丢弃引用了已淘汰纹理的保留合成图。
  void evicted(_Tile tile) {
    if (_drawn.contains(tile)) _forgetPicture();
  }

  /// Releases grids and any pending timer. / 释放网格并取消计时器。
  void clear() {
    _discardVector();
    _forgetPicture();
    _cancelTarget();
    _replacement?.clear();
    _replacement = null;
    _current?.clear();
    _current = null;
    _dropOverview();
  }

  /// Discards the layout-specific vector recording. / 丢弃当前布局专用的向量录制。
  void _discardVector() {
    _vector?.dispose();
    _vector = null;
  }

  /// Marks an omitted layer as offscreen so the shared LRU can reclaim it. / 将离开场景的图层标为屏外，供共享 LRU 回收。
  void hide() {
    _cancelTarget();
    _replacement?.clear();
    _replacement = null;
    if (_current case final grid?) grid.visible = Rect.zero;
    if (_overview case final overview?) overview.grid.visible = Rect.zero;
    _forgetPicture();
  }

  /// Releases the old whole texture when another full view replaces it. / 新的全景替代后释放旧整图。
  void _dropOverview() {
    _overview?.grid.clear();
    _overview = null;
  }

  /// Cancels the last scale candidate. / 取消上次候选缩放。
  void _cancelTarget() {
    _settle?.cancel();
    _settle = null;
    _target = null;
  }

  /// Traverses the existing snap layer transforms and composited clips. / 遍历现有像素对齐变换和合成裁剪。
  Matrix4? _sceneGeometry() {
    _clip = Offset.zero & _view!.physicalSize;
    final world = Matrix4.identity();
    final failure = PixelSnapLayer.accumulateSceneTransform(
      parent,
      world,
      onLayer: _clipVisitor,
    );
    if (failure != null) return null;
    world.translateByDouble(_offset.dx, _offset.dy, 0, 1);
    return world;
  }

  /// Intersects a layer's clip in physical scene coordinates. / 在物理场景坐标中累积该层裁剪。
  void _intersectClip(Layer layer, Matrix4 world) {
    final bounds = switch (layer) {
      ClipRectLayer(:final clipRect) => clipRect,
      ClipRRectLayer(:final clipRRect) => clipRRect?.outerRect,
      ClipRSuperellipseLayer(:final clipRSuperellipse) =>
        clipRSuperellipse?.outerRect,
      ClipPathLayer(:final clipPath) => clipPath?.getBounds(),
      OpacityLayer(alpha: 0) => Rect.zero,
      _ => null,
    };
    if (bounds != null) {
      _clip = _clip.intersect(MatrixUtils.transformRect(world, bounds));
    }
  }

  /// Creates a grid using the phase of this composition. / 用本次合成的像素相位创建网格。
  _ImageGrid _newGrid(Offset density, Offset origin) => _ImageGrid(
    this,
    _layout,
    density,
    Offset(
      origin.dx - origin.dx.roundToDouble(),
      origin.dy - origin.dy.roundToDouble(),
    ),
    _content,
  );

  /// Compares the density ratios on both axes. / 比较两轴纹素密度之比。
  bool _within(Offset desired, Offset old, double lower, double upper) {
    final x = desired.dx / old.dx;
    final y = desired.dy / old.dy;
    return x >= lower && x <= upper && y >= lower && y <= upper;
  }

  /// Keeps the old grid until the target density has settled. / 目标密度停稳前保留旧网格。
  void _selectDensity(Offset desired, Offset origin) {
    final current = _current ??= _newGrid(desired, origin);
    if (current.layout == _layout &&
        _within(desired, current.density, _imageScaleMin, _imageScaleMax)) {
      _cancelTarget();
      _replacement?.clear();
      _replacement = null;
      return;
    }
    final previous = _target;
    if (previous == null ||
        previous.$1 != _layout ||
        !_within(
          desired,
          previous.$2,
          1 - _imageScaleJitter,
          1 + _imageScaleJitter,
        )) {
      _cancelTarget();
      _replacement?.clear();
      _replacement = null;
      _target = (_layout, desired);
      _settle = Timer(_imageScaleSettle, () {
        _settle = null;
        if (attached) SchedulerBinding.instance.ensureVisualUpdate();
      });
    } else if (_settle == null) {
      _replacement ??= _newGrid(desired, origin);
    }
  }

  /// Projects the visible logical rectangle into a fixed texel grid. / 将可见逻辑矩形投影至固定纹素网格。
  void _updateWindow(_ImageGrid grid, Rect logical) {
    final sx = grid.layout.width * grid.density.dx / _layout.width;
    final sy = grid.layout.height * grid.density.dy / _layout.height;
    grid.visible = Rect.fromLTRB(
      logical.left * sx + grid.phase.dx,
      logical.top * sy + grid.phase.dy,
      logical.right * sx + grid.phase.dx,
      logical.bottom * sy + grid.phase.dy,
    ).intersect(grid.extent);
    grid.tiles.removeWhere(
      (_, tile) => tile.image == null && !grid.visible.overlaps(tile.core),
    );
  }

  /// Returns one visible tile when the grid can fit the shared budget. / 可见网格能放入共享预算时返回一个在屏块。
  _Tile? nextTile(int budget) {
    final grid = _replacement ?? _current;
    if (grid == null ||
        (_replacement == null &&
            _overview?.image != null &&
            (_target?.$2.dx ?? grid.density.dx) < grid.density.dx) ||
        grid.ready ||
        !grid.fits(budget)) {
      return null;
    }
    return grid.nextTile();
  }

  /// Records the tile with the same texel phase as its destination. / 以与目标相同的纹素相位录制分块。
  ui.Picture record(_Tile tile) {
    final grid = tile.grid;
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..translate(
        grid.phase.dx - tile.samples.left,
        grid.phase.dy - tile.samples.top,
      )
      ..scale(grid.density.dx, grid.density.dy)
      ..drawPicture(_vector!);
    return recorder.endRecording();
  }

  /// Uses the complete new grid once all visible cells are drawable. / 新网格所有在屏块可绘制后切换。
  void _promote() {
    final next = _replacement;
    if (next == null || !next.ready) return;
    _forgetPicture();
    final previous = _current!;
    final whole = previous.tiled ? null : previous.tiles[(0, 0)];
    if (next.tiled && whole?.image != null) {
      _dropOverview();
      _overview = whole;
      previous.visible = Rect.zero;
    } else {
      previous.clear();
      if (!next.tiled) _dropOverview();
    }
    _current = next;
    _replacement = null;
    _cancelTarget();
  }

  /// Submits the vector or the visible textures with missing regions filled. / 提交向量或补齐缺失区域的可见纹理。
  @override
  void addToScene(ui.SceneBuilder builder) {
    final vector = _vector;
    if (vector == null) return;
    final cache = _TileCache.instance;
    cache.trackScene(this);
    final budget = cache.budget;
    if (budget == 0 || !_content.isFinite || _content.isEmpty) {
      hide();
      builder.addPicture(_offset, vector);
      return;
    }
    final axis = _sceneGeometry()?.storage;
    Rect? logical;
    if (axis != null) {
      final density = Offset(axis[0], axis[5]);
      final origin = Offset(axis[12], axis[13]);
      logical = Rect.fromLTRB(
        (_clip.left - origin.dx) / density.dx,
        (_clip.top - origin.dy) / density.dy,
        (_clip.right - origin.dx) / density.dx,
        (_clip.bottom - origin.dy) / density.dy,
      ).intersect(_content);
      if (logical.isEmpty) {
        hide();
        return;
      }
      if (!(density.dx * _layout.width).isFinite ||
          !(density.dy * _layout.height).isFinite ||
          !origin.isFinite) {
        hide();
        builder.addPicture(_offset, vector);
        return;
      }
      _selectDensity(density, origin);
      _updateWindow(_current!, logical);
      if (_replacement case final replacement?) {
        _updateWindow(replacement, logical);
      }
      cache.generateForScene(this);
      _promote();
    } else {
      _cancelTarget();
      _replacement?.clear();
      _replacement = null;
      if (_current == null) {
        // A small whole texture can also serve a transform we cannot project. / 小整图也可用于无法投影视口的变换。
        final dpr = _view!.devicePixelRatio;
        final grid = _newGrid(Offset(dpr, dpr), Offset.zero);
        if (!grid.tiled) {
          _current = grid;
          grid.visible = grid.extent;
        }
      }
      if (_current case final grid? when !grid.tiled) {
        grid.visible = grid.extent;
        cache.generateForScene(this);
      }
    }
    final grid = _current;
    if (grid == null) {
      builder.addPicture(_offset, vector);
      return;
    }
    final sx = _layout.width / (grid.layout.width * grid.density.dx);
    final sy = _layout.height / (grid.layout.height * grid.density.dy);
    final overBudget = logical != null && !grid.fits(budget);
    final allResident = logical == null && grid.tiled;
    final ready = overBudget
        ? <_Tile>[]
        : allResident
        ? grid.tiles.values.where((tile) => tile.image != null).toList()
        : [
            for (final cell in grid.cells(grid.visible))
              if (grid.tiles[cell] case final tile? when tile.image != null)
                tile,
          ];
    final full =
        !overBudget &&
        !allResident &&
        grid.ready &&
        (logical == null ||
            svgRectEncloses(_local(grid.extent, grid, sx, sy), logical));
    final overview = _overview;
    final backdrop = full || overview?.image == null ? null : overview;
    if (overview != null) {
      overview.grid.visible = backdrop == null ? Rect.zero : overview.core;
    }
    if (ready.isEmpty && backdrop == null) {
      _forgetPicture();
      builder.addPicture(_offset, vector);
      return;
    }
    final tx = axis == null ? 0.0 : axis[12] - grid.phase.dx;
    final ty = axis == null ? 0.0 : axis[13] - grid.phase.dy;
    final aligned =
        axis != null &&
        (axis[0] * sx - 1).abs() < _gridTolerance &&
        (axis[5] * sy - 1).abs() < _gridTolerance &&
        (tx - tx.roundToDouble()).abs() < _gridTolerance &&
        (ty - ty.roundToDouble()).abs() < _gridTolerance;
    final sampled = [?backdrop, ...ready];
    for (final tile in sampled) {
      cache.touch(tile);
    }
    if (_painted == null ||
        _paintedVector != vector ||
        _paintedLayout != _layout ||
        _paintedAligned != aligned ||
        _paintedFull != full ||
        !listEquals(_drawn, sampled)) {
      _forgetPicture();
      _painted = _compose(vector, ready, sx, sy, full, aligned, backdrop);
      _paintedVector = vector;
      _paintedLayout = _layout;
      _paintedAligned = aligned;
      _paintedFull = full;
      _drawn = _painted == null ? const [] : sampled;
    }
    builder.addPicture(_offset, _painted ?? vector);
  }

  /// Records only when the set of sampled textures or their mapping changes. / 仅在采样纹理集合或映射变化时重新录制。
  ui.Picture? _compose(
    ui.Picture vector,
    List<_Tile> ready,
    double sx,
    double sy,
    bool full,
    bool aligned,
    _Tile? backdrop,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = RendererBinding.instance.createCanvas(recorder);
    if (!full) {
      canvas.save();
      for (final tile in ready) {
        canvas.clipRect(
          _local(tile.core, tile.grid, sx, sy),
          clipOp: ui.ClipOp.difference,
          doAntiAlias: false,
        );
      }
      final old = backdrop?.grid;
      if (old == null) {
        canvas.drawPicture(vector);
      } else {
        canvas.clipRect(Offset.zero & _layout, doAntiAlias: false);
        if (!_drawTexture(
          canvas,
          backdrop!,
          _layout.width / (old.layout.width * old.density.dx),
          _layout.height / (old.layout.height * old.density.dy),
          _linearPaint,
        )) {
          recorder.endRecording().dispose();
          return null;
        }
      }
      canvas.restore();
    }
    // Aligned cores need only the source subrectangle. Linear sampling uses
    // the shared border and clips the destination back to the core.
    // 对齐时只绘制内块对应的纹理子矩形。线性采样使用共用采样边，再裁回内块。
    if (!aligned) canvas.clipRect(Offset.zero & _layout, doAntiAlias: false);
    for (final tile in ready) {
      if (!aligned) {
        canvas.save();
        canvas.clipRect(
          _local(tile.core, tile.grid, sx, sy),
          doAntiAlias: false,
        );
      }
      if (!_drawTexture(
        canvas,
        tile,
        sx,
        sy,
        aligned ? _alignedPaint : _linearPaint,
        source: aligned ? tile.core : null,
      )) {
        recorder.endRecording().dispose();
        return null;
      }
      if (!aligned) canvas.restore();
    }
    return recorder.endRecording();
  }

  /// Draws one texture and releases a deferred image if the engine rejects it. / 绘制纹理，引擎拒绝延迟图像时释放它。
  bool _drawTexture(
    Canvas canvas,
    _Tile tile,
    double sx,
    double sy,
    Paint paint, {
    Rect? source,
  }) {
    final texels = source ?? tile.samples;
    try {
      canvas.drawImageRect(
        tile.image!,
        texels.shift(-tile.samples.topLeft),
        _local(texels, tile.grid, sx, sy),
        paint,
      );
      return true;
    } catch (_) {
      _TileCache.instance.remove(tile);
      tile.failed = true;
      return false;
    }
  }

  /// Maps texels into the current layout, undoing the capture phase. / 撤销生成时的相位，将纹素映射到当前布局。
  Rect _local(Rect rect, _ImageGrid grid, double sx, double sy) =>
      Rect.fromLTRB(
        (rect.left - grid.phase.dx) * sx,
        (rect.top - grid.phase.dy) * sy,
        (rect.right - grid.phase.dx) * sx,
        (rect.bottom - grid.phase.dy) * sy,
      );
}

/// Shared LRU for resident textures. / 驻留纹理共用的 LRU。
class _TileCache with WidgetsBindingObserver {
  /// Single cache per UI isolate. / 每个 UI isolate 一个缓存。
  static final instance = _TileCache();

  /// Current shared byte cap. / 当前共用字节上限。
  int budget = XvgRasterCache.defaultByteBudget;

  /// Resident bytes. / 驻留字节。
  int bytesUsed = 0;

  /// Count of image disposal calls. / 已释放图像句柄次数。
  int disposedCount = 0;

  /// Resident tile bytes, ordered from least to most recently used. / 由最旧到最新的驻留块和字节数。
  final _lru = <_Tile, int>{};

  /// Render layers that can request tiles. / 能请求分块的渲染图层。
  final _layers = <_RasterTileLayer>{};

  /// Layers submitted in the previous or current frame. / 上一帧或本帧提交过的图层。
  Set<_RasterTileLayer> _previousScene = {};
  Set<_RasterTileLayer> _currentScene = {};

  /// Whether the visibility callback is queued. / 可见性回调是否已排队。
  bool _checkingScene = false;

  /// Tracks scene participation without scheduling extra frames. / 记录图层是否参与合成，无需主动请求帧。
  void trackScene(_RasterTileLayer layer) {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) return;
    _currentScene.add(layer);
    if (_checkingScene) return;
    _checkingScene = true;
    scheduler.addPostFrameCallback(_finishScene);
  }

  /// Makes omitted layers evictable, including kept-alive children. / 将未提交的图层标为可淘汰，包括仍挂载的子节点。
  void _finishScene(Duration _) {
    for (final layer in _previousScene.difference(_currentScene)) {
      layer.hide();
    }
    final previous = _previousScene;
    _previousScene = _currentScene;
    _currentScene = previous..clear();
    _checkingScene = _previousScene.isNotEmpty;
    if (_checkingScene) {
      SchedulerBinding.instance.addPostFrameCallback(_finishScene);
    }
  }

  /// Number of resident tiles. / 驻留分块数。
  int get tileCount => _lru.length;

  /// Subscribes on the first enabled widget. / 首个启用的组件挂载时订阅。
  void attach(_RasterTileLayer layer) {
    if (_layers.isEmpty) WidgetsBinding.instance.addObserver(this);
    _layers.add(layer);
  }

  /// Unsubscribes after the last enabled widget. / 最后一个启用的组件卸载后退订。
  void detach(_RasterTileLayer layer) {
    _previousScene.remove(layer);
    _currentScene.remove(layer);
    _layers.remove(layer);
    if (_layers.isEmpty) WidgetsBinding.instance.removeObserver(this);
  }

  /// Changes the budget, preferring offscreen eviction even on explicit trims.
  /// 调整预算时也优先清理屏外块。
  void setBudget(int value) {
    budget = value;
    _makeRoom(0, allowVisible: true);
    if (_layers.isNotEmpty) SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Updates the LRU position of a tile drawn by the current scene. / 更新当前场景绘制的块的访问顺序。
  void touch(_Tile tile) => _lru[tile] = _lru.remove(tile)!;

  /// Drops a resident tile and disposes its image. / 移除驻留块并释放图像。
  void remove(_Tile tile) {
    final bytes = _lru.remove(tile);
    if (bytes == null) return;
    bytesUsed -= bytes;
    tile.release();
    tile.grid.layer.evicted(tile);
    disposedCount++;
  }

  /// Clears offscreen textures when the engine reports memory pressure. / 引擎报告内存压力时清理屏外纹理。
  @override
  void didHaveMemoryPressure() {
    for (final tile in _lru.keys.where((tile) => !tile.visible).toList()) {
      remove(tile);
    }
  }

  /// Enforces a shared quota of one synchronous texture request per frame. / 同步纹理请求全局每帧最多一个。
  bool _syncRequested = false;

  /// Generates a deferred texture in time for this scene. / 在本次合成提交前创建延迟纹理。
  void generateForScene(_RasterTileLayer raster) {
    final scheduler = SchedulerBinding.instance;
    if (_syncRequested ||
        !raster.attached ||
        budget == 0 ||
        scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      return;
    }
    final tile = raster.nextTile(budget);
    if (tile == null) return;
    _makeRoom(tile.bytes);
    if (bytesUsed + tile.bytes > budget) return;
    _syncRequested = true;
    scheduler.addPostFrameCallback((_) {
      _syncRequested = false;
      scheduler.ensureVisualUpdate();
    });
    final picture = raster.record(tile);
    _reportRequest(tile, true);
    try {
      _install(
        tile,
        picture.toImageSync(
          tile.samples.width.toInt(),
          tile.samples.height.toInt(),
        ),
      );
    } catch (_) {
      tile.failed = true;
    } finally {
      _reportRequest(tile, false);
      picture.dispose();
    }
  }

  /// Makes space by evicting offscreen LRU tiles before any visible tiles.
  /// 按 LRU 顺序优先淘汰屏外块以留出空间。
  void _makeRoom(int bytes, {bool allowVisible = false}) {
    if (bytesUsed + bytes <= budget) return;
    for (final tile in _lru.keys.toList()) {
      if (!tile.visible) remove(tile);
      if (bytesUsed + bytes <= budget) return;
    }
    if (!allowVisible) return;
    while (_lru.isNotEmpty && bytesUsed + bytes > budget) {
      remove(_lru.keys.first);
    }
  }

  /// Accounts for the deferred image handle in the shared LRU. / 将延迟图像句柄计入共享 LRU。
  void _install(_Tile tile, ui.Image image) {
    tile.image = image;
    _lru[tile] = tile.bytes;
    bytesUsed += tile.bytes;
  }

  /// Reports request boundaries with dimensions to the optional observer. / 向可选观察者报告请求起止及纹理尺寸。
  void _reportRequest(_Tile tile, bool started) => debugXvgRasterRequest?.call(
    started,
    tile.samples.width.toInt(),
    tile.samples.height.toInt(),
  );
}
