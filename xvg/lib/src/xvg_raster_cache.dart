import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'pixel_snap_layer.dart';

/// Shared bitmap tile budget and statistics. / 静态 SVG 位图分块的共享预算和统计。
abstract final class XvgRasterCache {
  /// Prevents instantiation. / 禁止实例化。
  XvgRasterCache._();

  /// Edge of a tile before downsampling, in physical pixels. / 降采样前的物理分块边长。
  static const tileSize = 512;

  /// Enough for about two tall 1080p RGBA8 viewports including tile overhead.
  /// 可容纳约两个 1080p 长屏视口及分块开销。
  static const defaultByteBudget = 32 * 1024 * 1024;

  /// Shared RGBA8 byte limit per isolate, including work in flight. Set to
  /// zero to use vectors until the budget is raised.
  /// 同一 isolate 共用的 RGBA8 字节上限，含生成中的块。设为 0 时回退向量。
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

/// Consecutive stable replays before requesting tiles. / 请求分块前需连续稳定重放的帧数。
const _stableReplayFrames = 32;

/// Per-artwork RGBA8 limit, including prefetch and padding. / 单图 RGBA8 上限，含预取和采样边。
const _maxArtworkBytes = 12 * 1024 * 1024;

/// Full physical resolution for automatic tiles. / 自动缓存分块使用原物理分辨率。
const _resolutionScale = 1.0;

/// Cache modes used by tests and historical benchmarks. / 测试与历史基准使用的缓存模式。
enum XvgRasterCacheOverride {
  /// Paint vectors only. / 仅绘制向量。
  disabled,

  /// Generate tiles immediately at full resolution. / 立即生成原分辨率分块。
  enabled,

  /// Generate tiles immediately at half resolution. / 立即生成半分辨率分块。
  halfResolution,
}

/// Stores the testing policy for the next widget build. / 保存下次构建使用的测试覆盖模式。
XvgRasterCacheOverride? _cacheOverride;

/// The policy for the next build. / 下次构建使用的策略。
XvgRasterCacheOverride? get xvgRasterCacheOverride => _cacheOverride;

/// Null runs automatic admission. / 为 null 时按库规则自动判断。
@visibleForTesting
set debugXvgRasterCacheOverride(XvgRasterCacheOverride? value) =>
    _cacheOverride = value;

/// Profile A/B switch for async rasterization. / 真机基准使用的异步生成对照开关。
bool debugXvgRasterizeTilesAsync = false;

/// Whether every visible core in the benchmark scene has an image.
/// 基准场景中所有在屏内块是否已有图像。
bool get debugXvgRasterTilesReady => _TileCache.instance._layers.any(
  (layer) =>
      layer.attached &&
      !layer.visible.isEmpty &&
      _cells(layer.visible).every((cell) => layer.tiles[cell]?.image != null),
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
    required this.cacheOverride,
    required this.snapWhenCached,
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

  /// Optional benchmark policy. / 可选的基准覆盖模式。
  final XvgRasterCacheOverride? cacheOverride;

  /// Whether ready tiles activate pixel alignment. / 分块就绪后是否启用像素对齐。
  final bool snapWhenCached;

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
    final rasterChanged =
        _view != view ||
        old.cacheOverride != options.cacheOverride ||
        old.snapWhenCached != options.snapWhenCached;
    final invalidate = geometryChanged || contentChanged || rasterChanged;
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
    if (!hasSize || size != next) _layer.clear();
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

/// Tile sampling border in physical pixels, including at half scale. / 物理像素采样边，半分辨率下仍覆盖相邻像素。
const _tileBorder = 2;

/// RGBA8 channels per pixel. / 每个 RGBA8 像素的字节数。
const _bytesPerPixel = 4;

/// Retention and prefetch distance in physical pixels. / 以物理像素计的保留与预取距离。
const _overscan = 64.0;

/// Wait for scale or pixel phase to settle before replacing tiles.
/// 等待缩放或像素相位停稳，再替换分块。
const _phaseSettleTime = Duration(milliseconds: 80);

/// Tolerates floating-point arithmetic in scene matrices. / 容忍场景矩阵的浮点误差。
const _gridTolerance = 1e-7;

/// A fixed core in raster coordinates, with padding sampled from the same picture.
/// 栅格坐标中的固定内块，采样边缘来自同一张 Picture。
class _Tile {
  /// Creates a tile at a given grid coordinate. / 在指定网格坐标创建分块。
  _Tile(this.layer, this.cell, this.core)
    : samples = _sampleBounds(core, layer.resolution);

  /// Owning layer. / 所属图层。
  final _RasterTileLayer layer;

  /// Integer grid coordinate. / 整数网格坐标。
  final (int, int) cell;

  /// Raster image, when ready. / 已生成的栅格图像。
  ui.Image? image;

  /// Whether to skip future attempts after a raster failure. / 生成失败后是否跳过重试。
  bool failed = false;

  /// Tile core in physical coordinates relative to the component's grid origin.
  /// 以组件网格原点为基准的物理坐标内块。
  final Rect core;

  /// Bounds in a global texel grid, including padding. / 含采样边的全局纹素网格边界。
  final Rect samples;

  /// Reserved / resident RGBA8 bytes. / 预留或驻留的 RGBA8 字节数。
  int get bytes =>
      samples.width.toInt() * samples.height.toInt() * _bytesPerPixel;

  /// Whether this tile is used on screen in the current layer tree. / 当前图层树中该块是否在屏。
  bool get visible => layer.attached && _tileRect(cell).overlaps(layer.visible);

  /// Releases the handle once. / 释放图像句柄。
  void release() {
    image?.dispose();
    image = null;
  }
}

/// Physical bounds of a tile core. / 分块内核的物理边界。
Rect _tileRect((int, int) cell) {
  const edge = XvgRasterCache.tileSize;
  return Rect.fromLTWH(
    (cell.$1 * edge).toDouble(),
    (cell.$2 * edge).toDouble(),
    edge.toDouble(),
    edge.toDouble(),
  );
}

/// Snaps the sample window to a shared texel grid so adjacent tiles have
/// the same phase even at non-dyadic resolutions.
/// 邻块共用同一纹素网格，即便分辨率倍率无法二等分也沿用同一采样相位。
Rect _sampleBounds(Rect core, double resolution) {
  final pad = (_tileBorder * resolution).ceil();
  return Rect.fromLTRB(
    (core.left * resolution).floorToDouble() - pad,
    (core.top * resolution).floorToDouble() - pad,
    (core.right * resolution).ceilToDouble() + pad,
    (core.bottom * resolution).ceilToDouble() + pad,
  );
}

/// Floors to the physical grid while tolerating near-integer snap transforms.
/// 忽略对齐变换接近整数时的浮点误差，向下取物理像素网格。
double _pixelFloor(double value) => (value + _gridTolerance).floorToDouble();

/// Stabilizes an edge already at an integer within arithmetic tolerance.
/// 稳定浮点误差范围内的整数边界。
double _stableEdge(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < _gridTolerance ? rounded : value;
}

/// Keeps edge dimensions even so half resolution uses exactly one quarter of
/// the bytes. / 让边缘尺寸保持偶数，半分辨率下字节精确为四分之一。
double _edgeFloor(double value) =>
    (value / _tileBorder).floorToDouble() * _tileBorder - _tileBorder;

/// Includes the extra pixels on the far edge. / 在远边保留额外像素。
double _edgeCeil(double value) =>
    (value / _tileBorder).ceilToDouble() * _tileBorder + _tileBorder;

/// Tile coordinates overlapping a rectangle. / 与矩形相交的分块坐标。
Iterable<(int, int)> _cells(Rect region) sync* {
  if (region.isEmpty) return;
  const edge = XvgRasterCache.tileSize;
  final right = (region.right / edge).ceil();
  final bottom = (region.bottom / edge).ceil();
  for (var y = (region.top / edge).floor(); y < bottom; y++) {
    for (var x = (region.left / edge).floor(); x < right; x++) {
      yield (x, y);
    }
  }
}

/// Tile layer that sees the final transforms and viewport clips even when
/// a scrolling ancestor reuses an SVG repaint boundary.
/// 即使滚动祖先复用 SVG 重绘边界，分块图层也能读取实际变换和视口裁剪。
class _RasterTileLayer extends Layer {
  /// Paint for tiles sampled at full resolution. / 原分辨率分块使用的画笔。
  static final _fullResolutionPaint = Paint()
    ..filterQuality = FilterQuality.none;

  /// Paint for lower-resolution tiles. / 低分辨率分块使用的画笔。
  static final _downsampledPaint = Paint()..filterQuality = FilterQuality.low;

  /// Currently retained tile records. / 当前保留的分块记录。
  final tiles = <(int, int), _Tile>{};

  /// Original vector drawing in logical box coordinates. / 逻辑绘制盒坐标中的原始向量图。
  ui.Picture? _vector;

  /// Composite submitted by the last scene. / 上一次场景提交的合成图。
  ui.Picture? _composite;

  /// Painting context offset within the parent layer. / 父图层内的绘制偏移。
  Offset _offset = Offset.zero;

  /// Logical paint viewport. / 逻辑绘制视口。
  Rect _viewport = Rect.zero;

  /// Content mapped into the logical paint box. / 映射到逻辑绘制盒的内容边界。
  Rect _content = Rect.zero;

  /// Current view's screen bounds and DPR. / 当前显示视图的屏幕边界与 DPR。
  ui.FlutterView? _view;

  /// Configured resolution. / 配置的分辨率。
  double resolution = _resolutionScale;

  /// Whether to use the library admission rule. / 是否按库规则自动判断。
  bool _automatic = true;

  /// Whether automatic tiles align the painted viewport. / 自动分块是否对齐绘制视口。
  bool _snapWhenCached = false;

  /// Last uncorrected viewport used to detect movement. / 用于检测移动的上次未修正视口。
  Rect? _replayViewport;

  /// Number of consecutive stable compositions. / 连续稳定合成次数。
  int _replays = 0;

  /// Last scheduler frame counted for this layer. / 本图层上次计入的调度帧。
  int _lastReplayFrame = -1;

  /// Accumulated physical clip, shifted to the tile grid for painting. / 累积的物理裁剪，绘制时平移到分块网格。
  Rect _clip = Rect.zero;

  /// Reuses the clip visitor across scenes. / 跨场景复用裁剪回调。
  late final void Function(Layer, Matrix4) _clipVisitor = _intersectClip;

  /// Full fitted artwork bounds in physical grid coordinates. / 物理网格坐标中的完整适配插画边界。
  Rect _artwork = Rect.zero;

  /// Visible paint bounds mapped into the tile grid. / 映射到分块网格的可见绘制边界。
  Rect visible = Rect.zero;

  /// Bounds for retaining or prefetching adjacent tiles. / 保留、预取相邻块的范围。
  Rect _near = Rect.zero;

  /// The raster transform without whole-pixel translation. / 去掉整数平移后的栅格变换。
  Matrix4? _rasterMatrix;

  /// DPR used by the last raster transform. / 上一次栅格变换使用的 DPR。
  double? _dpr;

  /// Adjacent prefetch stays disabled after pressure until the viewport changes.
  /// 收到内存压力后暂停相邻块预取，直到视口变化。
  bool prefetch = true;

  /// Deadline for the pending grid to settle. / 等待候选网格停稳的计时器。
  Timer? _phaseTimer;

  /// Most recent candidate transform while waiting for a stable grid.
  /// 等待网格停稳时最近观测到的候选变换。
  Matrix4? _movingMatrix;

  /// DPR of the candidate grid. / 候选网格的 DPR。
  double? _movingDpr;

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
    _automatic = options.cacheOverride == null;
    _snapWhenCached = options.snapWhenCached;
    resolution = options.cacheOverride == XvgRasterCacheOverride.halfResolution
        ? _resolutionScale / 2
        : _resolutionScale;
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

  /// Drops the pictures and tile records from the previous paint inputs.
  /// 清理旧绘制输入的 Picture 和分块记录。
  void clear() {
    _resetGridMotion();
    _resetReplay();
    engineLayer = null;
    _vector?.dispose();
    _vector = null;
  }

  /// Releases an ineligible grid and restarts its replay count. / 释放失效网格并重新计数。
  void _resetReplay() {
    _replayViewport = null;
    _replays = 0;
    _lastReplayFrame = -1;
    _composite?.dispose();
    _composite = null;
    if (_snapWhenCached) engineLayer = null;
    _dropTiles();
  }

  /// Counts stable rendered frames once, ignoring independent scene captures.
  /// 每次渲染帧最多计一次，独立场景截图不计入。
  bool _replayedEnough(Rect physical) {
    if (_replays >= _stableReplayFrames) return true;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return false;
    }
    final frame = _TileCache.instance._frame;
    if (_lastReplayFrame == frame) return false;
    final last = _replayViewport;
    final stable =
        last != null &&
        (last.left - physical.left).abs() < _gridTolerance &&
        (last.top - physical.top).abs() < _gridTolerance &&
        (last.right - physical.right).abs() < _gridTolerance &&
        (last.bottom - physical.bottom).abs() < _gridTolerance;
    _replays = stable && _lastReplayFrame == frame - 1 ? _replays + 1 : 1;
    _replayViewport = physical;
    _lastReplayFrame = frame;
    return _replays >= _stableReplayFrames;
  }

  /// Cancels a pending grid change. / 取消等待中的网格切换。
  void _resetGridMotion() {
    _phaseTimer?.cancel();
    _phaseTimer = null;
    _movingMatrix = null;
    _movingDpr = null;
  }

  /// Releases tiles and resets the visibility from the previous grid. / 释放分块并重置旧网格的可见信息。
  void _dropTiles() {
    for (final tile in tiles.values) {
      _TileCache.instance.remove(tile);
    }
    tiles.clear();
    visible = _near = Rect.zero;
    _rasterMatrix = null;
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

  /// Compares the scales of two raster transforms. / 比较两个栅格变换的缩放倍率。
  bool _sameScale(Matrix4 a, Matrix4 b) =>
      (a.storage[0] - b.storage[0]).abs() < _gridTolerance &&
      (a.storage[5] - b.storage[5]).abs() < _gridTolerance;

  /// Compares the translations after grid alignment. / 比较网格对齐后的平移量。
  bool _samePhase(Matrix4 a, Matrix4 b) =>
      (a.storage[12] - b.storage[12]).abs() < _gridTolerance &&
      (a.storage[13] - b.storage[13]).abs() < _gridTolerance;

  /// Reuses the current grid or waits for a different scale or phase to settle.
  /// 复用当前网格，或等待新的缩放及像素相位停稳。
  bool _useGrid(Matrix4 next) {
    final previous = _rasterMatrix;
    final dpr = _view!.devicePixelRatio;
    if (previous != null) {
      if (_dpr == dpr &&
          _sameScale(previous, next) &&
          _samePhase(previous, next)) {
        _resetGridMotion();
        return true;
      }
      final moving = _movingMatrix;
      if (moving == null ||
          _movingDpr != dpr ||
          !_sameScale(moving, next) ||
          !_samePhase(moving, next)) {
        _movingMatrix = next;
        _movingDpr = dpr;
        _phaseTimer?.cancel();
        _phaseTimer = Timer(_phaseSettleTime, () {
          _phaseTimer = null;
          if (attached) SchedulerBinding.instance.ensureVisualUpdate();
        });
      }
      if (_phaseTimer != null) return false;
      _dropTiles();
      _resetGridMotion();
    }
    _dpr = dpr;
    _rasterMatrix = next;
    return true;
  }

  /// Re-evaluates the physical viewport and emits disjoint vector / bitmap coverage.
  /// 重新计算物理视口，合成互不重叠的向量及位图覆盖。
  @override
  void addToScene(ui.SceneBuilder builder) {
    final vector = _vector;
    if (vector == null) return;
    final previous = _composite;
    _composite = null;
    try {
      _addArtwork(builder, vector);
    } finally {
      previous?.dispose();
    }
  }

  /// Adds the original vector and whichever tiles are ready. / 加入原始向量和已就绪块。
  void _addArtwork(ui.SceneBuilder builder, ui.Picture vector) {
    /// Submits the original vector geometry. / 提交原始向量几何。
    void addVector() {
      if (_snapWhenCached) engineLayer = null;
      builder.addPicture(_offset, vector);
    }

    final axis = _sceneGeometry();
    if (axis == null || !_viewport.isFinite || _viewport.isEmpty) {
      _resetGridMotion();
      _resetReplay();
      addVector();
      return;
    }
    final uncorrected = MatrixUtils.transformRect(axis, _viewport);
    final correction = _snapWhenCached
        ? PixelSnapLayer.viewportCorrection(axis, _viewport)
        : null;
    if (correction != null) axis.multiply(correction);
    final physical = correction == null
        ? uncorrected
        : MatrixUtils.transformRect(axis, _viewport);
    if (!physical.isFinite || physical.isEmpty) {
      _resetGridMotion();
      _resetReplay();
      addVector();
      return;
    }
    final origin = Offset(
      _pixelFloor(physical.left),
      _pixelFloor(physical.top),
    );
    axis.setTranslationRaw(
      axis.storage[12] - origin.dx,
      axis.storage[13] - origin.dy,
      0,
    );
    _clip = _clip.shift(-origin);
    final left = physical.left - origin.dx;
    final top = physical.top - origin.dy;
    _artwork = Rect.fromLTRB(
      left < _gridTolerance ? 0 : left,
      top < _gridTolerance ? 0 : top,
      _stableEdge(physical.right - origin.dx),
      _stableEdge(physical.bottom - origin.dy),
    );
    final tileRegion = _artwork.intersect(
      MatrixUtils.transformRect(axis, _content),
    );
    final nextVisible = _clip.intersect(tileRegion);
    final near = _clip.inflate(_overscan).intersect(tileRegion);
    if (_automatic) {
      if (nextVisible.isEmpty || _estimatedBytes(near) > _maxArtworkBytes) {
        _resetReplay();
        addVector();
        return;
      }
      _TileCache.instance.trackReplay(this);
      final previous = _rasterMatrix;
      final dpr = _view!.devicePixelRatio;
      if (previous != null &&
          (_dpr != dpr ||
              !_sameScale(previous, axis) ||
              !_samePhase(previous, axis))) {
        _resetReplay();
      }
      if (!_replayedEnough(uncorrected)) {
        addVector();
        return;
      }
      _dpr = dpr;
      _rasterMatrix = axis;
    } else if (!_useGrid(axis)) {
      visible = Rect.zero;
      addVector();
      return;
    }
    if (nextVisible != visible) prefetch = true;
    visible = nextVisible;
    _near = near;
    tiles.removeWhere((_, tile) {
      if (!visible.isEmpty && tile.core.overlaps(_near)) return false;
      _TileCache.instance.remove(tile);
      return true;
    });
    if (visible.isEmpty) return;
    final cache = _TileCache.instance;
    List<_Tile>? ready;
    var hasMissingTiles = false;
    for (final cell in _cells(visible)) {
      final tile = tiles[cell];
      if (tile == null || tile.image == null) {
        hasMissingTiles = true;
        continue;
      }
      cache.touch(tile);
      (ready ??= []).add(tile);
    }
    cache.considerWork();
    if (ready == null) {
      addVector();
      return;
    }
    if (correction != null) {
      final local = Matrix4.translationValues(_offset.dx, _offset.dy, 0)
        ..multiply(correction)
        ..translateByDouble(-_offset.dx, -_offset.dy, 0, 1);
      engineLayer = builder.pushTransform(
        local.storage,
        oldLayer: engineLayer as ui.TransformEngineLayer?,
      );
    }
    _addTiles(builder, vector, axis, ready, hasMissingTiles);
    if (correction != null) builder.pop();
  }

  /// Estimates ready tile bytes in constant time using the same padded grid as
  /// rasterization and the R2 report. / 用与生成及第二轮报告相同的网格与采样边估算字节。
  int _estimatedBytes(Rect region) =>
      _bytesPerPixel *
      _sampledAxis(region.left, region.right, _artwork.left, _artwork.right) *
      _sampledAxis(region.top, region.bottom, _artwork.top, _artwork.bottom);

  /// Counts core pixels and both sampling borders along one tile axis. / 统计单轴内块与两侧采样边像素。
  int _sampledAxis(double start, double end, double artStart, double artEnd) {
    const edge = XvgRasterCache.tileSize;
    final first = (start / edge).floor();
    final after = (end / edge).ceil();
    final lo = first * edge;
    final hi = after * edge;
    final coreStart = lo <= artStart ? _edgeFloor(artStart).toInt() : lo;
    final coreEnd = hi >= artEnd ? _edgeCeil(artEnd).toInt() : hi;
    return coreEnd - coreStart + (after - first) * 2 * _tileBorder;
  }

  /// Draws padded textures via hard core clips and replays the vector once for holes.
  /// 硬裁剪纹理内块并使用采样边，向量只重放一次以填补剩余区域。
  void _addTiles(
    ui.SceneBuilder builder,
    ui.Picture vector,
    Matrix4 matrix,
    List<_Tile> ready,
    bool hasMissingTiles,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = RendererBinding.instance.createCanvas(recorder);
    final inverse = Matrix4.inverted(matrix);
    if (hasMissingTiles) {
      canvas.save();
      canvas.transform(inverse.storage);
      canvas.clipRect(
        Rect.fromLTRB(
          _clip.left.floorToDouble(),
          _clip.top.floorToDouble(),
          _clip.right.ceilToDouble(),
          _clip.bottom.ceilToDouble(),
        ),
        doAntiAlias: false,
      );
      for (final tile in ready) {
        canvas.clipRect(
          tile.core,
          clipOp: ui.ClipOp.difference,
          doAntiAlias: false,
        );
      }
      canvas.transform(matrix.storage);
      canvas.drawPicture(vector);
      canvas.restore();
    }
    canvas.transform(inverse.storage);
    final paint = resolution == 1 ? _fullResolutionPaint : _downsampledPaint;
    for (final tile in ready) {
      final image = tile.image!;
      final source = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final target = Rect.fromLTRB(
        tile.samples.left / resolution,
        tile.samples.top / resolution,
        tile.samples.right / resolution,
        tile.samples.bottom / resolution,
      );
      canvas.save();
      canvas.clipRect(tile.core, doAntiAlias: false);
      try {
        canvas.drawImageRect(image, source, target, paint);
      } catch (_) {
        // Deferred image rasterization can fail on the first draw. Submit
        // the original vector for this frame and stop retrying this tile.
        // 延迟栅格化可能在首次绘制时失败；本帧提交原向量，并停止重试该块。
        canvas.restore();
        recorder.endRecording().dispose();
        _TileCache.instance.remove(tile);
        tile.failed = true;
        builder.addPicture(_offset, vector);
        return;
      }
      canvas.restore();
    }
    final composite = recorder.endRecording();
    _composite = composite;
    builder.addPicture(_offset, composite);
  }

  /// Finds the next affordable tile for the current composition. / 找出当前合成可负担的下一块。
  _Tile? nextTile({required bool adjacent, required int available}) {
    if (!attached || visible.isEmpty || (adjacent && !prefetch)) return null;
    for (final cell in _cells(adjacent ? _near : visible)) {
      if (adjacent && _tileRect(cell).overlaps(visible)) continue;
      final tile = tiles.putIfAbsent(
        cell,
        () => _Tile(this, cell, _edgeCore(cell)),
      );
      if (tile.image == null && !tile.failed && tile.bytes <= available) {
        return tile;
      }
    }
    return null;
  }

  /// Trims the outermost textures to the artwork and covers subpixel clip
  /// rounding with at most one sampling border of extra artwork.
  /// 最外侧纹理裁到插画边界，并留一个采样边应对裁剪取整。
  Rect _edgeCore((int, int) cell) {
    final tile = _tileRect(cell);
    final art = _artwork;
    return Rect.fromLTRB(
      tile.left <= art.left ? _edgeFloor(art.left) : tile.left,
      tile.top <= art.top ? _edgeFloor(art.top) : tile.top,
      tile.right >= art.right ? _edgeCeil(art.right) : tile.right,
      tile.bottom >= art.bottom ? _edgeCeil(art.bottom) : tile.bottom,
    );
  }

  /// Renders a tile at the grid transform, including neighboring texels.
  /// 按网格变换生成分块，并录入相邻纹素。
  Future<ui.Image> rasterize(_Tile tile) async {
    final samples = tile.samples;
    final width = samples.width.toInt();
    final height = samples.height.toInt();
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..translate(-samples.left, -samples.top)
      ..scale(resolution, resolution)
      ..transform(_rasterMatrix!.storage)
      ..drawPicture(_vector!);
    final picture = recorder.endRecording();
    try {
      return debugXvgRasterizeTilesAsync
          ? await picture.toImage(width, height)
          : picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }
}

/// Shared byte-accounted LRU and a frame-paced generator. / 共用的字节计费 LRU 与逐帧生成器。
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

  /// One globally reserved job across all widgets. / 跨组件全局唯一的生成任务。
  bool _inFlight = false;

  /// Whether there is already a post-frame callback. / 是否已注册帧后回调。
  bool _scheduled = false;

  /// Frame serial shared by all automatic layers. / 所有自动缓存图层共用的渲染帧序号。
  int _frame = 0;

  /// Automatic layers seen this frame or the frame before it. / 本帧或上一帧合成过的自动缓存图层。
  final _replaying = <_RasterTileLayer, int>{};

  /// Whether the next post-frame replay check is queued. / 是否已安排下一次帧后重放检查。
  bool _checkingReplays = false;

  /// Tracks replay without requesting animation frames of its own. / 记录重放，不主动请求动画帧。
  void trackReplay(_RasterTileLayer layer) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      return;
    }
    _replaying[layer] = _frame;
    if (_checkingReplays) return;
    _checkingReplays = true;
    SchedulerBinding.instance.addPostFrameCallback(_finishReplayFrame);
  }

  /// Releases grids omitted from the scene, even if kept alive by a parent.
  /// 释放离开场景的网格，包括父节点保持挂载的情况。
  void _finishReplayFrame(Duration _) {
    _replaying.removeWhere((layer, frame) {
      if (frame == _frame) return false;
      layer._resetReplay();
      return true;
    });
    _frame++;
    _checkingReplays = _replaying.isNotEmpty;
    if (_checkingReplays) {
      SchedulerBinding.instance.addPostFrameCallback(_finishReplayFrame);
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
    _replaying.remove(layer);
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
    disposedCount++;
  }

  /// Clears offscreen tiles and suppresses prefetch while the viewport stays put.
  /// 清理屏外块，并暂停当前视口的预取。
  @override
  void didHaveMemoryPressure() {
    for (final layer in _layers) {
      layer.prefetch = false;
    }
    for (final tile in _lru.keys.where((tile) => !tile.visible).toList()) {
      remove(tile);
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

  /// Schedules at most one tile after the vector frame has been submitted.
  /// 向量帧提交后最多调度一个分块。
  void considerWork() {
    if (_scheduled || _inFlight || budget == 0) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final tile = _nextTile();
      if (tile != null) unawaited(_generate(tile));
    });
  }

  /// Gives in-view work priority across all attached layers. / 在所有挂载图层中优先生成在屏块。
  _Tile? _nextTile() {
    final reclaimable = _lru.entries.fold(
      0,
      (total, entry) => total + (entry.key.visible ? 0 : entry.value),
    );
    for (final layer in _layers) {
      final tile = layer.nextTile(
        adjacent: false,
        available: budget - bytesUsed + reclaimable,
      );
      if (tile != null) return tile;
    }
    for (final layer in _layers) {
      final tile = layer.nextTile(
        adjacent: true,
        available: budget - bytesUsed,
      );
      if (tile != null) return tile;
    }
    return null;
  }

  /// Installs a completed tile only if the requesting grid still owns it.
  /// 请求网格仍持有该块时才接收已生成的图像。
  Future<void> _generate(_Tile tile) async {
    final layer = tile.layer;
    final bytes = tile.bytes;
    _makeRoom(bytes);
    _inFlight = true;
    try {
      final image = await layer.rasterize(tile);
      if (identical(layer.tiles[tile.cell], tile) &&
          layer.attached &&
          (tile.visible || layer.prefetch) &&
          bytesUsed + bytes <= budget) {
        tile.image = image;
        _lru[tile] = bytes;
        bytesUsed += bytes;
      } else {
        image.dispose();
        disposedCount++;
      }
    } catch (_) {
      tile.failed = true;
    } finally {
      _inFlight = false;
      if (_layers.isNotEmpty) SchedulerBinding.instance.ensureVisualUpdate();
    }
  }
}
