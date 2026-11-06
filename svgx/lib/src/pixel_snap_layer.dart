import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Aligns the painted SVG viewport to physical pixels during composition.
/// Defaults to [auto], which enables alignment for mask/clip documents.
/// Only translation and positive axis-aligned scaling are supported. Visual
/// edges move by less than one physical pixel; layout, hits and semantics keep
/// their original coordinates. Use [never] for independent subtree captures.
///
/// 合成时将 SVG 绘制视口对齐物理像素；默认 [auto] 仅对遮罩/裁剪文档启用。
/// 仅支持平移与轴对齐正缩放；边缘视觉修正小于一个物理像素，布局、点击及语义
/// 仍使用原坐标。独立子树截图可使用 [never]。
///
/// ```dart
/// Svgx.string(source, pixelSnap: SvgxPixelSnap.never)
/// ```
enum SvgxPixelSnap {
  /// Enable for parsed mask/clip risk. / 解析结果有遮罩/裁剪风险时启用。
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
  return alignment.inscribe(
    applyBoxFit(fit, intrinsic, size).destination,
    Offset.zero & size,
  );
}

/// Replaces the existing boundary only when enabled. / 仅启用时替换原有边界。
Widget pixelSnapBoundary({
  required Widget child,
  required SvgxPixelSnap mode,
  required bool hasRisk,
  required Size intrinsicSize,
  required BoxFit fit,
  required Alignment alignment,
}) => mode == SvgxPixelSnap.always || (mode == SvgxPixelSnap.auto && hasRisk)
    ? PixelSnapBoundary(
        intrinsicSize: intrinsicSize,
        fit: fit,
        alignment: alignment,
        child: child,
      )
    : RepaintBoundary(child: child);

/// A repaint boundary with a composition-time viewport. / 持有合成期视口的重绘边界。
class PixelSnapBoundary extends SingleChildRenderObjectWidget {
  const PixelSnapBoundary({
    super.key,
    required this.intrinsicSize,
    required this.fit,
    required this.alignment,
    required super.child,
  });

  final Size intrinsicSize;
  final BoxFit fit;
  final Alignment alignment;

  @override
  RenderPixelSnapBoundary createRenderObject(BuildContext context) =>
      RenderPixelSnapBoundary()..configure(intrinsicSize, fit, alignment);

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

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout() {
    super.performLayout();
    final viewport = svgPaintViewport(_intrinsicSize, size, _fit, _alignment);
    if (_viewport == viewport) return;
    _viewport = viewport;
    markNeedsCompositedLayerUpdate();
  }

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
  Rect viewport = Rect.zero;
  Offset _sceneOffset = Offset.zero;
  Matrix4 _effectiveLocal = Matrix4.identity();

  // The default setter marks dirty, forbidden with alwaysNeedsAddToScene.
  // 默认 setter 会标脏，与 alwaysNeedsAddToScene 的断言冲突；本层每帧都合成。
  @override
  Offset get offset => _sceneOffset;
  @override
  set offset(Offset value) => _sceneOffset = value;

  @override
  bool get alwaysNeedsAddToScene => true;

  @visibleForTesting
  bool debugDidSnap = false;
  @visibleForTesting
  String? debugSkipReason;
  @visibleForTesting
  Matrix4 debugCorrection = Matrix4.identity();
  @visibleForTesting
  int debugSceneCount = 0;

  static bool _positiveScaleTranslation(Matrix4 matrix) {
    final m = matrix.storage;
    return m.every((v) => v.isFinite) &&
        m[0] > 0 &&
        m[5] > 0 &&
        _zeroEntries.every((i) => m[i].abs() <= _matrixTolerance) &&
        (m[10] - 1).abs() <= _matrixTolerance &&
        (m[15] - 1).abs() <= _matrixTolerance;
  }

  static Matrix4? _localTransform(Layer layer) {
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

  Matrix4 _correction() {
    final ancestors = <Layer>[];
    for (Layer? node = parent; node != null; node = node.parent) {
      ancestors.add(node);
    }
    final world = Matrix4.identity();
    for (final ancestor in ancestors.reversed) {
      final local = _localTransform(ancestor);
      if (local == null || !_positiveScaleTranslation(local)) {
        debugSkipReason =
            '${local == null ? 'unknown' : 'non-axis'}:${ancestor.runtimeType}';
        return Matrix4.identity();
      }
      world.multiply(local);
    }
    world.translateByDouble(offset.dx, offset.dy, 0, 1);
    if (!_positiveScaleTranslation(world) ||
        !viewport.isFinite ||
        viewport.isEmpty) {
      debugSkipReason = 'invalid-viewport';
      return Matrix4.identity();
    }
    final physical = MatrixUtils.transformRect(world, viewport);
    if (!physical.isFinite ||
        physical.width.round() <= 0 ||
        physical.height.round() <= 0) {
      debugSkipReason = 'degenerate-size';
      return Matrix4.identity();
    }
    final sx = physical.width.roundToDouble() / physical.width;
    final sy = physical.height.roundToDouble() / physical.height;
    final dx =
        (_roundedOrigin(physical.left) - physical.left) / world.storage[0];
    final dy = (_roundedOrigin(physical.top) - physical.top) / world.storage[5];
    debugDidSnap = true;
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
