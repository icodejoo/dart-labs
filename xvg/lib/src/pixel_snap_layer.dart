import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Aligns the painted SVG viewport to physical pixels during composition.
/// Defaults to [auto], which aligns mask/clip documents and cached static art.
/// Only translation and positive axis-aligned scaling are supported. Visual
/// edges move by less than one physical pixel; layout, hits and semantics keep
/// their original coordinates. Use [never] for independent subtree captures.
///
/// 合成时将 SVG 绘制视口对齐物理像素；默认 [auto] 对遮罩/裁剪文档和已进入位图缓存的静态插画启用。
/// 仅支持平移与轴对齐正缩放；边缘视觉修正小于一个物理像素，布局、点击及语义
/// 仍使用原坐标。独立子树截图可使用 [never]。
///
/// ```dart
/// Xvg.string(source, pixelSnap: XvgPixelSnap.never)
/// ```
enum XvgPixelSnap {
  /// Enable for mask/clip risk or cached static art. / 有遮罩、裁剪风险或静态位图分块就绪时启用。
  auto,

  /// Enable for every document under supported transforms. / 支持的变换下始终启用。
  always,

  /// Keep the original painted geometry. / 保持原始绘制几何。
  never,
}

/// The viewport shared by layout and both painters. / 布局及两条 painter 共用的视口。
Rect svgPaintViewport(
  Size intrinsic,
  Size size,
  BoxFit fit,
  Alignment alignment,
) {
  if (intrinsic.isEmpty || size.isEmpty) return Rect.zero;
  final fitted = applyBoxFit(fit, intrinsic, size);
  final destination = fitted.destination;
  // Cropping fits describe a source subset; map the whole viewport at that scale.
  // 裁剪型适配返回源子区域，按同一比例映射完整视口。
  final viewport = fitted.source == intrinsic
      ? destination
      : Size(
          intrinsic.width * (destination.width / fitted.source.width),
          intrinsic.height * (destination.height / fitted.source.height),
        );
  return alignment.inscribe(viewport, Offset.zero & size);
}

/// Tests rectangle containment including shared edges. / 判断矩形包含关系，允许共用边界。
bool svgRectEncloses(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

/// Applies recoloring inside the fitted SVG viewport. / 在适配后的 SVG 视口内重着色。
Widget svgViewportColorFiltered({
  required Widget child,
  required ColorFilter filter,
  required Size intrinsicSize,
  required BoxFit fit,
  required Alignment alignment,
}) => ClipRect(
  clipper: _SvgViewportClipper(intrinsicSize, fit, alignment),
  child: ColorFiltered(colorFilter: filter, child: child),
);

/// Bounds filters that can give transparent pixels alpha. / 限制可给透明像素着色的滤镜范围。
class _SvgViewportClipper extends CustomClipper<Rect> {
  /// Stores the viewport fitting inputs. / 保存视口适配参数。
  const _SvgViewportClipper(this.intrinsicSize, this.fit, this.alignment);

  /// Root viewport dimensions. / 根视口尺寸。
  final Size intrinsicSize;

  /// Viewport fitting mode. / 视口适配方式。
  final BoxFit fit;

  /// Placement within the layout box. / 视口在布局盒内的位置。
  final Alignment alignment;

  /// Clips the filtered output to the visible artwork. / 将滤镜输出裁到可见插画区域。
  @override
  Rect getClip(Size size) => svgPaintViewport(
    intrinsicSize,
    size,
    fit,
    alignment,
  ).intersect(Offset.zero & size);

  /// Recomputes the clip when fitting changes. / 适配参数变化时重新计算裁剪。
  @override
  bool shouldReclip(_SvgViewportClipper oldClipper) =>
      oldClipper.intrinsicSize != intrinsicSize ||
      oldClipper.fit != fit ||
      oldClipper.alignment != alignment;
}

/// Replaces the existing boundary only when enabled. / 仅启用时替换原有边界。
Widget pixelSnapBoundary({
  required Widget child,
  required XvgPixelSnap mode,
  required bool hasRisk,
  required Size intrinsicSize,
  required BoxFit fit,
  required Alignment alignment,
}) => mode == XvgPixelSnap.always || (mode == XvgPixelSnap.auto && hasRisk)
    ? PixelSnapBoundary(
        intrinsicSize: intrinsicSize,
        fit: fit,
        alignment: alignment,
        child: child,
      )
    : RepaintBoundary(child: child);

/// A repaint boundary with a composition-time viewport. / 持有合成期视口的重绘边界。
class PixelSnapBoundary extends SingleChildRenderObjectWidget {
  /// Creates the boundary for a picture of [intrinsicSize]. / 为固有尺寸为 [intrinsicSize] 的 picture 创建边界。
  const PixelSnapBoundary({
    super.key,
    required this.intrinsicSize,
    required this.fit,
    required this.alignment,
    required super.child,
  });

  /// Intrinsic picture size. / picture 的固有尺寸。
  final Size intrinsicSize;

  /// How the picture is inscribed into the box. / picture 如何适配到盒子。
  final BoxFit fit;

  /// Alignment within the box. / 在盒子内的对齐方式。
  final Alignment alignment;

  /// Creates the render object. / 创建渲染对象。
  @override
  RenderPixelSnapBoundary createRenderObject(BuildContext context) =>
      RenderPixelSnapBoundary()..configure(intrinsicSize, fit, alignment);

  /// Applies new geometry inputs. / 应用新的几何输入。
  @override
  void updateRenderObject(
    BuildContext context,
    RenderPixelSnapBoundary renderObject,
  ) => renderObject.configure(intrinsicSize, fit, alignment);
}

/// Keeps picture recording independent of scene correction. / 将 picture 录制与场景修正分离。
class RenderPixelSnapBoundary extends RenderProxyBox {
  Size _intrinsicSize = Size.zero;
  BoxFit _fit = BoxFit.contain;
  Alignment _alignment = Alignment.center;
  Rect _viewport = Rect.zero;

  /// Updates the viewport inputs and relayouts when they change. / 更新视口输入，变化时重新布局。
  void configure(Size intrinsicSize, BoxFit fit, Alignment alignment) {
    if (_intrinsicSize == intrinsicSize &&
        _fit == fit &&
        _alignment == alignment) {
      return;
    }
    _intrinsicSize = intrinsicSize;
    _fit = fit;
    _alignment = alignment;
    markNeedsLayout();
  }

  /// Always a repaint boundary. / 始终是重绘边界。
  @override
  bool get isRepaintBoundary => true;

  /// Lays out the child and refreshes the viewport. / 布局子节点并刷新视口。
  @override
  void performLayout() {
    super.performLayout();
    final viewport = svgPaintViewport(
      _intrinsicSize,
      size,
      _fit,
      _alignment,
    ).intersect(Offset.zero & size);
    if (_viewport == viewport) return;
    _viewport = viewport;
    markNeedsCompositedLayerUpdate();
  }

  /// Reuses or creates the snapping layer. / 复用或创建对齐图层。
  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) =>
      ((oldLayer as PixelSnapLayer?) ?? PixelSnapLayer())..viewport = _viewport;
}

const _matrixTolerance = 1e-10;
const _zeroEntries = <int>[1, 2, 3, 4, 6, 7, 8, 9, 11, 14];

// Exact generic specializations: Dart has no generic-class reflection. Never
// accept subclasses via `is`, or inspect runtime type names (unsafe in release).
// 精确泛型实例类型：Dart 无泛型类反射；不以 is 接受子类，也不解析发布版类型名。
final _annotationTypes = <Type>{
  AnnotatedRegionLayer<SystemUiOverlayStyle>,
  AnnotatedRegionLayer<MouseCursor>,
  AnnotatedRegionLayer<Object>,
  AnnotatedRegionLayer<String>,
  AnnotatedRegionLayer<int>,
  AnnotatedRegionLayer<double>,
  AnnotatedRegionLayer<bool>,
};

/// Audited layer coordinates; unknown classes fall back. / 经审计的图层坐标；未知类回退。
class PixelSnapLayer extends OffsetLayer {
  /// Painted viewport in local coordinates. / 局部坐标下的绘制视口。
  Rect viewport = Rect.zero;
  Offset _sceneOffset = Offset.zero;
  Matrix4 _effectiveLocal = Matrix4.identity();

  // The default setter marks dirty, forbidden with alwaysNeedsAddToScene.
  // 默认 setter 会标脏，与 alwaysNeedsAddToScene 的断言冲突；本层每帧都合成。
  /// Scene offset after correction. / 修正后的场景偏移。
  @override
  Offset get offset => _sceneOffset;

  /// Stores the offset without marking dirty. / 保存偏移但不标脏。
  @override
  set offset(Offset value) => _sceneOffset = value;

  /// Recomposited every frame. / 每帧重新合成。
  @override
  bool get alwaysNeedsAddToScene => true;

  /// Whether the last composition snapped. / 最近一次合成是否对齐。
  @visibleForTesting
  bool debugDidSnap = false;

  /// Why the last composition skipped snapping. / 最近一次合成跳过对齐的原因。
  @visibleForTesting
  String? debugSkipReason;

  /// Last applied correction matrix. / 最近一次应用的修正矩阵。
  @visibleForTesting
  Matrix4 debugCorrection = Matrix4.identity();

  /// Number of scenes composed. / 已合成的场景数。
  @visibleForTesting
  int debugSceneCount = 0;

  /// Whether the matrix supports physical pixel alignment. / 矩阵是否支持物理像素对齐。
  static bool isPositiveScaleTranslation(Matrix4 matrix) {
    final m = matrix.storage;
    for (final i in _zeroEntries) {
      if (!(m[i].abs() <= _matrixTolerance)) return false;
    }
    final scaleX = m[0];
    final scaleY = m[5];
    return scaleX.isFinite &&
        scaleX > 0 &&
        scaleY.isFinite &&
        scaleY > 0 &&
        m[12].isFinite &&
        m[13].isFinite &&
        (m[10] - 1).abs() <= _matrixTolerance &&
        (m[15] - 1).abs() <= _matrixTolerance;
  }

  /// Returns the audited layer transform. / 返回已审核的图层变换。
  static Matrix4? sceneTransform(Layer layer) {
    final type = layer.runtimeType;
    if (type == PixelSnapLayer) {
      return (layer as PixelSnapLayer)._effectiveLocal;
    }
    if (type == TransformLayer) {
      final transform = layer as TransformLayer;
      final matrix = transform.transform;
      if (matrix == null) return null;
      return Matrix4.translationValues(
        transform.offset.dx,
        transform.offset.dy,
        0,
      )..multiply(matrix);
    }
    if (type == OffsetLayer ||
        type == OpacityLayer ||
        type == ImageFilterLayer) {
      final offset = (layer as OffsetLayer).offset;
      return Matrix4.translationValues(offset.dx, offset.dy, 0);
    }
    // SDK layer.dart: these pushes clip/filter only; annotations inherit the
    // ContainerLayer scene walk and their offset bounds metadata only.
    // SDK layer.dart：以下 push 仅裁剪/滤镜；注释继承容器合成，offset 仅限制元数据。
    if (type == ContainerLayer ||
        type == ClipRectLayer ||
        type == ClipRRectLayer ||
        type == ClipRSuperellipseLayer ||
        type == ClipPathLayer ||
        type == ColorFilterLayer ||
        type == ShaderMaskLayer ||
        type == BackdropFilterLayer ||
        _annotationTypes.contains(type)) {
      return Matrix4.identity();
    }
    return null;
  }

  /// Accumulates root-to-leaf transforms and returns the first unsupported layer with its reason. / 从根累乘变换并返回首个不支持的图层及原因。
  static (Layer, bool isUnknown)? accumulateSceneTransform(
    Layer? ancestor,
    Matrix4 world, {
    void Function(Layer, Matrix4)? onLayer,
  }) {
    if (ancestor == null) return null;
    final failure = accumulateSceneTransform(
      ancestor.parent,
      world,
      onLayer: onLayer,
    );
    if (failure != null) return failure;
    final local = sceneTransform(ancestor);
    if (local == null) return (ancestor, true);
    if (!isPositiveScaleTranslation(local)) return (ancestor, false);
    world.multiply(local);
    onLayer?.call(ancestor, world);
    return null;
  }

  /// Computes the local correction from the scene viewport. / 根据场景视口计算局部对齐修正。
  Matrix4 _correction() {
    final world = Matrix4.identity();
    final failure = accumulateSceneTransform(parent, world);
    if (failure != null) {
      final (ancestor, isUnknown) = failure;
      debugSkipReason =
          '${isUnknown ? 'unknown' : 'non-axis'}:${ancestor.runtimeType}';
      return Matrix4.identity();
    }
    world.translateByDouble(offset.dx, offset.dy, 0, 1);
    if (!isPositiveScaleTranslation(world) ||
        !viewport.isFinite ||
        viewport.isEmpty) {
      debugSkipReason = 'invalid-viewport';
      return Matrix4.identity();
    }
    final correction = viewportCorrection(world, viewport);
    debugDidSnap = correction != null;
    if (correction == null) debugSkipReason = 'degenerate-size';
    return correction ?? Matrix4.identity();
  }

  /// Computes correction for an axis-aligned physical viewport. / 计算轴对齐物理视口的局部修正。
  static Matrix4? viewportCorrection(Matrix4 world, Rect viewport) {
    final physical = MatrixUtils.transformRect(world, viewport);
    if (!physical.isFinite ||
        physical.width.round() <= 0 ||
        physical.height.round() <= 0) {
      return null;
    }
    final sx = physical.width.roundToDouble() / physical.width;
    final sy = physical.height.roundToDouble() / physical.height;
    final dx =
        (_roundedOrigin(physical.left) - physical.left) / world.storage[0];
    final dy = (_roundedOrigin(physical.top) - physical.top) / world.storage[5];
    // Scale about the viewport origin, including letterbox/alignment offsets.
    // 围绕视口原点缩放，包含留白及 alignment 偏移。
    return Matrix4.translationValues(
      dx + viewport.left * (1 - sx),
      dy + viewport.top * (1 - sy),
      0,
    )..scaleByDouble(sx, sy, 1, 1);
  }

  // At half pixels either integer is nearest. Round origin ties downward and
  // extent ties upward, keeping the far edge movement strictly below 1px too.
  // 半像素时两整数等距；原点取下界、尺寸取上界，远边移动也严格小于 1px。
  static double _roundedOrigin(double value) {
    final lower = value.floorToDouble();
    return value - lower == 0.5 ? lower : value.roundToDouble();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    debugSceneCount++;
    debugDidSnap = false;
    debugSkipReason = null;
    debugCorrection = _correction();
    _effectiveLocal = Matrix4.translationValues(offset.dx, offset.dy, 0)
      ..multiply(debugCorrection);
    // Always reuse a transform engine layer, including fallback frames.
    // 回退帧也复用同类 transform 引擎层；子容器仍走 retained 路径。
    engineLayer = builder.pushTransform(
      _effectiveLocal.storage,
      oldLayer: engineLayer as ui.TransformEngineLayer?,
    );
    addChildrenToScene(builder);
    builder.pop();
  }

  // SDK applyTransform is queried after addToScene; report that exact matrix.
  // SDK 约定在 addToScene 后查询 applyTransform，返回该次实际合成矩阵。
  @override
  void applyTransform(Layer? child, Matrix4 transform) =>
      transform.multiply(_effectiveLocal);

  @override
  bool findAnnotations<S extends Object>(
    AnnotationResult<S> result,
    Offset localPosition, {
    required bool onlyFirst,
  }) {
    final inverse = Matrix4.tryInvert(_effectiveLocal);
    if (inverse == null) return false;
    final local = MatrixUtils.transformPoint(inverse, localPosition);
    // OffsetLayer subtracts offset itself; compensate before delegating.
    // OffsetLayer 自身还会减 offset，委托前补回，避免二次平移。
    return super.findAnnotations<S>(
      result,
      local + offset,
      onlyFirst: onlyFirst,
    );
  }
}
