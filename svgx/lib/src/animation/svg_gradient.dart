// Gradient paint for the animation engine: a plain data model for
// `<linearGradient>`/`<radialGradient>` definitions (filled in by
// `svg_document_parser.dart`) plus the functions that turn a definition into a
// `dart:ui` Shader at paint time.
//
// `<animate>` on gradient attributes (x1/y1/x2/y2/cx/cy/r/fx/fy) and on
// `<stop>` children (stop-color/stop-opacity/offset) IS supported: each
// [SvgGradientDef] optionally carries [animatedNode]/[stopNodes] — plain
// [SvgNode]s holding those elements' own `<animate>` timelines — and
// [resampleGradientAtTime] resamples them into a fresh [SvgGradientDef] every
// frame, which `animated_svg_painter.dart` then turns into a shader via
// [buildGradientShader] as usual. A def built without [animatedNode] (e.g.
// constructed directly in a test) is untouched by the resample — same as
// having no matching animations.
//
// 动画引擎的渐变涂料：`<linearGradient>`/`<radialGradient>` 定义的纯数据模型
// （由 `svg_document_parser.dart` 填充），以及在绘制时把定义变成 `dart:ui`
// Shader 的若干函数。
//
// 支持渐变属性（x1/y1/x2/y2/cx/cy/r/fx/fy）以及 `<stop>` 子元素
// （stop-color/stop-opacity/offset）上的 `<animate>`：每个 [SvgGradientDef]
// 可选携带 [animatedNode]/[stopNodes]——承载这些元素自身 `<animate>` 时间线的
// 纯 [SvgNode]——[resampleGradientAtTime] 逐帧把它们重采样成一份全新的
// [SvgGradientDef]，`animated_svg_painter.dart` 再照常用 [buildGradientShader]
// 转成 shader。未携带 [animatedNode] 构建出的定义（例如测试里直接构造）不受
// 重采样影响——效果等同于没有匹配的动画。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'svg_dom.dart';
import 'svg_style.dart';

/// One `<stop>`: a position along the gradient and the colour there.
///
/// 单个 `<stop>`：沿渐变轴的位置及该处的颜色。
class SvgGradientStop {
  /// Creates a stop. / 创建一个色标。
  const SvgGradientStop(this.offset, this.color);

  /// Position in `[0, 1]` (SVG `offset`). / 位置，取值 `[0, 1]`（SVG `offset`）。
  final double offset;

  /// Colour at this position, `stop-opacity` already folded into its alpha.
  ///
  /// 该位置的颜色，`stop-opacity` 已并入其 alpha。
  final Color color;
}

/// A parsed `<linearGradient>`/`<radialGradient>` definition.
///
/// Geometry is kept exactly as authored (in the gradient's own units); the
/// mapping into the painted element's space happens in [buildGradientShader],
/// which is the only place that needs to know about
/// `gradientUnits="objectBoundingBox"` vs `"userSpaceOnUse"`.
///
/// 已解析的 `<linearGradient>`/`<radialGradient>` 定义。
///
/// 几何按书写原样保留（使用渐变自身的单位）；映射到被绘制元素坐标空间的工作在
/// [buildGradientShader] 中完成——那里是唯一需要区分
/// `gradientUnits="objectBoundingBox"` 与 `"userSpaceOnUse"` 的地方。
class SvgGradientDef {
  /// Creates a gradient definition. / 创建一个渐变定义。
  const SvgGradientDef({
    required this.radial,
    required this.stops,
    required this.objectBoundingBox,
    required this.tileMode,
    this.x1 = 0,
    this.y1 = 0,
    this.x2 = 1,
    this.y2 = 0,
    this.cx = 0.5,
    this.cy = 0.5,
    this.r = 0.5,
    this.fx,
    this.fy,
    this.gradientTransform,
    this.stopNodes = const [],
    this.animatedNode,
  });

  /// Radial (`<radialGradient>`) vs linear (`<linearGradient>`).
  ///
  /// 径向（`<radialGradient>`）还是线性（`<linearGradient>`）。
  final bool radial;

  /// Colour stops, in ascending offset order. / 色标，按 offset 升序排列。
  final List<SvgGradientStop> stops;

  /// Whether coordinates are bbox fractions (SVG's default) rather than user
  /// space.
  ///
  /// 坐标是否为包围盒比例（SVG 默认）而非用户空间坐标。
  final bool objectBoundingBox;

  /// How the gradient continues past its ends (SVG `spreadMethod`).
  ///
  /// 渐变超出两端后的延展方式（SVG `spreadMethod`）。
  final TileMode tileMode;

  /// Linear start/end points. / 线性渐变的起止点。
  final double x1, y1, x2, y2;

  /// Radial centre and radius. / 径向渐变的圆心与半径。
  final double cx, cy, r;

  /// Radial focal point; defaults to the centre when absent.
  ///
  /// 径向渐变的焦点；缺省时取圆心。
  final double? fx, fy;

  /// The gradient's own `gradientTransform`, as an affine `[a, b, c, d, e, f]`.
  ///
  /// 渐变自身的 `gradientTransform`，仿射矩阵 `[a, b, c, d, e, f]`。
  final List<double>? gradientTransform;

  /// One [SvgNode] per entry in [stops], same order, carrying that `<stop>`'s
  /// own `<animate>` children (numeric via [SvgNode.animations], `stop-color`
  /// via [SvgNode.colorAnimations]) — see [resampleGradientAtTime]. Empty for
  /// a def with no animated stops, or one built without parser support (e.g.
  /// directly in a test).
  ///
  /// 与 [stops] 一一对应（顺序一致）的 [SvgNode]，携带该 `<stop>` 自身的
  /// `<animate>` 子元素（数值型经 [SvgNode.animations]，`stop-color` 经
  /// [SvgNode.colorAnimations]）——见 [resampleGradientAtTime]。无动画色标的
  /// 定义，或未经解析器支持构建的定义（如测试里直接构造）该列表为空。
  final List<SvgNode> stopNodes;

  /// An [SvgNode] carrying `<animate>` children targeting this gradient
  /// element's own `x1`/`y1`/`x2`/`y2`/`cx`/`cy`/`r`/`fx`/`fy` — see
  /// [resampleGradientAtTime]. Null for a def built without parser support.
  ///
  /// 承载作用于本渐变元素自身
  /// `x1`/`y1`/`x2`/`y2`/`cx`/`cy`/`r`/`fx`/`fy` 的 `<animate>` 子元素的
  /// [SvgNode]——见 [resampleGradientAtTime]。未经解析器支持构建的定义为 null。
  final SvgNode? animatedNode;
}

/// Builds one [SvgGradientStop] from a `<stop>`'s effective attribute map
/// (`stop-color`, already normalized to hex; `offset`; `stop-opacity`) —
/// used for the initial parse and, with an animation-overridden attribute
/// map, for [resampleGradientAtTime]'s per-frame rebuild. Returns null when
/// `stop-color` doesn't resolve.
///
/// 从 `<stop>` 的有效属性表（`stop-color`，已归一化为十六进制；`offset`；
/// `stop-opacity`）构建一个 [SvgGradientStop]——用于初始解析，以及（配合动画
/// 覆盖后的属性表）[resampleGradientAtTime] 的逐帧重建。`stop-color` 无法解析
/// 时返回 null。
SvgGradientStop? stopFromAttributes(Map<String, String> attributes) {
  final color = parseSvgHexColor(attributes['stop-color'] ?? '#000000');
  if (color == null) return null;
  final raw = (attributes['offset'] ?? '0').trim();
  final offset = raw.endsWith('%')
      ? (double.tryParse(raw.substring(0, raw.length - 1)) ?? 0) / 100
      : (double.tryParse(raw) ?? 0);
  final stopOpacity = double.tryParse(attributes['stop-opacity'] ?? '') ?? 1;
  return SvgGradientStop(
    offset.clamp(0.0, 1.0),
    color.withValues(alpha: color.a * stopOpacity.clamp(0.0, 1.0)),
  );
}

/// Resamples [def]'s animated geometry/stops at global timeline time [time],
/// returning a fresh [SvgGradientDef]. A def with no [SvgGradientDef.animatedNode]
/// (nothing to sample) is returned unchanged — a cheap no-op for the
/// overwhelmingly common static-gradient case.
///
/// [buildGradientShader] is always called with the *result* of this function,
/// never [def] directly, so a shader rebuilt every frame from a resampled def
/// reflects the current frame's gradient — this file intentionally does no
/// shader caching that would assume gradients are static (see file doc).
///
/// 在全局时间线时刻 [time] 重采样 [def] 的动画几何/色标，返回一份全新的
/// [SvgGradientDef]。没有 [SvgGradientDef.animatedNode]（无可采样内容）的定义
/// 原样返回——对绝大多数静态渐变场景而言是低成本的空操作。
///
/// [buildGradientShader] 应始终传入本函数的*结果*，而非直接传入 [def]，这样
/// 每帧从重采样后的定义重建的 shader 才能反映当前帧的渐变——本文件刻意不做任何
/// 假设渐变静止的 shader 缓存（见文件头注释）。
SvgGradientDef resampleGradientAtTime(SvgGradientDef def, Duration time) {
  final node = def.animatedNode;
  if (node == null) return def;

  double? sampledFor(String attributeName) {
    for (final animation in node.animations) {
      if (animation.attributeName != attributeName) continue;
      final v = animation.sample(time);
      if (v != null) return v;
    }
    return null;
  }

  final hasGeometryAnimation = node.animations.isNotEmpty;
  final hasStopAnimation = def.stopNodes.any((n) => n.animations.isNotEmpty || n.colorAnimations.isNotEmpty);
  if (!hasGeometryAnimation && !hasStopAnimation) return def;

  final stops = <SvgGradientStop>[];
  for (var i = 0; i < def.stops.length; i++) {
    final original = def.stops[i];
    final stopNode = i < def.stopNodes.length ? def.stopNodes[i] : null;
    if (stopNode == null) {
      stops.add(original);
      continue;
    }
    final effective = Map<String, String>.of(stopNode.attributes);
    for (final animation in stopNode.animations) {
      final v = animation.sample(time);
      if (v != null) effective[animation.attributeName] = v.toString();
    }
    for (final colorAnimation in stopNode.colorAnimations) {
      final v = colorAnimation.sample(time);
      if (v == null) continue;
      // v is 0xAARRGGBB (see SmilColorAnimation); parseSvgHexColor wants
      // #RRGGBBAA (alpha last), hence the reorder.
      // v 是 0xAARRGGBB（见 SmilColorAnimation）；parseSvgHexColor 要的是
      // #RRGGBBAA（alpha 在末尾），因此重新排列字节顺序。
      final a = (v >> 24) & 0xFF, r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
      effective['stop-color'] =
          '#${[r, g, b, a].map((c) => c.toRadixString(16).padLeft(2, '0')).join()}'.toUpperCase();
    }
    stops.add(stopFromAttributes(effective) ?? original);
  }

  return SvgGradientDef(
    radial: def.radial,
    stops: stops,
    objectBoundingBox: def.objectBoundingBox,
    tileMode: def.tileMode,
    x1: sampledFor('x1') ?? def.x1,
    y1: sampledFor('y1') ?? def.y1,
    x2: sampledFor('x2') ?? def.x2,
    y2: sampledFor('y2') ?? def.y2,
    cx: sampledFor('cx') ?? def.cx,
    cy: sampledFor('cy') ?? def.cy,
    r: sampledFor('r') ?? def.r,
    fx: sampledFor('fx') ?? def.fx,
    fy: sampledFor('fy') ?? def.fy,
    gradientTransform: def.gradientTransform,
    stopNodes: def.stopNodes,
    animatedNode: def.animatedNode,
  );
}

/// Builds the `dart:ui` shader for [def] as painted over [bounds].
///
/// Returns null — meaning "paint nothing with this gradient" — when the
/// definition can't produce a usable shader: no stops, or a degenerate
/// (zero-width/height) bounding box under `objectBoundingBox` units.
///
/// [opacity] scales every stop's alpha (the element's own `opacity`).
///
/// 为在 [bounds] 上绘制的 [def] 构建 `dart:ui` shader。
///
/// 当定义无法产出可用 shader 时返回 null（含义是"该渐变不绘制任何东西"）：没有
/// 色标，或 `objectBoundingBox` 单位下包围盒退化（宽或高为 0）。
///
/// [opacity] 会缩放每个色标的 alpha（即元素自身的 `opacity`）。
///
/// Example:
/// ```dart
/// final shader = buildGradientShader(def, path.getBounds(), 1);
/// if (shader != null) paint.shader = shader;
/// ```
ui.Shader? buildGradientShader(SvgGradientDef def, Rect bounds, double opacity) {
  if (def.stops.isEmpty) return null;
  if (def.objectBoundingBox && (bounds.width <= 0 || bounds.height <= 0)) return null;

  final colors = <Color>[];
  final offsets = <double>[];
  var previous = double.negativeInfinity;
  for (final stop in def.stops) {
    // dart:ui requires strictly increasing stops; SVG allows repeats (used for
    // hard colour boundaries), so nudge instead of rejecting the gradient.
    //
    // dart:ui 要求色标严格递增；SVG 允许重复（用于制造硬边界），因此微调而不是
    // 丢弃整个渐变。
    final offset = stop.offset <= previous ? previous + 1e-6 : stop.offset;
    previous = offset;
    offsets.add(offset.clamp(0.0, 1.0));
    colors.add(stop.color.withValues(alpha: stop.color.a * opacity));
  }
  if (colors.length == 1) {
    colors.add(colors.first);
    offsets.add(1);
  }

  final matrix = _shaderMatrix(def, bounds);
  if (def.radial) {
    final focalX = def.fx ?? def.cx;
    final focalY = def.fy ?? def.cy;
    final isFocal = focalX != def.cx || focalY != def.cy;
    return ui.Gradient.radial(
      Offset(def.cx, def.cy),
      def.r,
      colors,
      offsets,
      def.tileMode,
      matrix,
      isFocal ? Offset(focalX, focalY) : null,
      0,
    );
  }
  return ui.Gradient.linear(
    Offset(def.x1, def.y1),
    Offset(def.x2, def.y2),
    colors,
    offsets,
    def.tileMode,
    matrix,
  );
}

/// The gradient-space → paint-space matrix: the element's bounding box (for
/// `objectBoundingBox` units) with the gradient's own `gradientTransform`
/// applied inside it.
///
/// Doing the bbox mapping through the shader matrix — rather than by scaling
/// the coordinates — is what keeps a radial gradient correctly elliptical over
/// a non-square bounding box.
///
/// 渐变空间 → 绘制空间的矩阵：元素包围盒（用于 `objectBoundingBox` 单位），并在
/// 其内部应用渐变自身的 `gradientTransform`。
///
/// 用 shader 矩阵而非缩放坐标来完成包围盒映射，正是径向渐变在非正方形包围盒上
/// 仍能正确呈现为椭圆的原因。
Float64List _shaderMatrix(SvgGradientDef def, Rect bounds) {
  var matrix = def.objectBoundingBox
      ? <double>[bounds.width, 0, 0, bounds.height, bounds.left, bounds.top]
      : <double>[1, 0, 0, 1, 0, 0];
  final own = def.gradientTransform;
  if (own != null) matrix = _concat(matrix, own);

  final out = Float64List(16);
  out[0] = matrix[0];
  out[1] = matrix[1];
  out[4] = matrix[2];
  out[5] = matrix[3];
  out[10] = 1;
  out[12] = matrix[4];
  out[13] = matrix[5];
  out[15] = 1;
  return out;
}

/// Affine `a * b` in SVG's `[a, b, c, d, e, f]` convention.
///
/// SVG `[a, b, c, d, e, f]` 约定下的仿射矩阵乘法 `a * b`。
List<double> _concat(List<double> a, List<double> b) => [
      a[0] * b[0] + a[2] * b[1],
      a[1] * b[0] + a[3] * b[1],
      a[0] * b[2] + a[2] * b[3],
      a[1] * b[2] + a[3] * b[3],
      a[0] * b[4] + a[2] * b[5] + a[4],
      a[1] * b[4] + a[3] * b[5] + a[5],
    ];
