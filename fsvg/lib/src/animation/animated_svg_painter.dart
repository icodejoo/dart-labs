// Per-frame painter for the original SMIL animation engine: walks the parsed
// [SvgNode] tree, samples every attached `<animate>` at the current timeline
// position, resolves presentation attributes (inheritance + `currentColor`),
// and draws shapes — dashed strokes included. Original implementation.
//
// 原创 SMIL 动画引擎的逐帧绘制器：遍历解析出的 [SvgNode] 树，在当前时间线
// 位置对每个挂载的 `<animate>` 采样，解析表现属性（继承 + `currentColor`），
// 并绘制形状——含虚线描边。原创实现。

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'smil_animation.dart';

import 'svg_dom.dart';
import 'svg_gradient.dart';
import 'svg_path_data.dart';
import 'svg_style.dart';
import 'svg_theme.dart';

/// Paints an [SvgDocument]'s (see `svg_document_parser.dart`) element tree at
/// a given [time] on the animation timeline, scaled from the document's
/// intrinsic size to the paint box.
///
/// A fresh recording every frame is intentional (not a regression from the
/// static path's cached-`ui.Picture` optimization): caching a `Picture` only
/// pays off for content that doesn't change between frames, and an active
/// animation's whole point is to change every frame — see fsvg CLAUDE.md
/// architecture notes.
///
/// 在动画时间线上给定的 [time] 时刻，绘制 [SvgDocument]（见
/// `svg_document_parser.dart`）的元素树，并从文档固有尺寸缩放到绘制盒。
///
/// 每帧都重新录制是故意的（并非相对静态路径 `ui.Picture` 缓存优化的倒退）：
/// 缓存 `Picture`只对帧间不变的内容划算，而正在播放的动画本质就是每帧都在
/// 变——见 fsvg CLAUDE.md 架构说明。
class AnimatedSvgPainter extends CustomPainter {
  /// Creates the painter for one frame. / 为一帧创建绘制器。
  AnimatedSvgPainter({
    required this.root,
    required this.intrinsicSize,
    required this.time,
    required this.theme,
    required this.fit,
    required this.alignment,
    this.gradients = const {},
    this.clipPaths = const {},
    this.masks = const {},
  }) : super();

  /// `<clipPath>` definitions by id — see `SvgDocument.clipPaths`.
  ///
  /// 按 id 索引的 `<clipPath>` 定义——见 `SvgDocument.clipPaths`。
  final Map<String, SvgNode> clipPaths;

  /// `<mask>` definitions by id — see `SvgDocument.masks`.
  ///
  /// 按 id 索引的 `<mask>` 定义——见 `SvgDocument.masks`。
  final Map<String, SvgNode> masks;

  /// The document's `<linearGradient>`/`<radialGradient>` table, for elements
  /// painted with `fill`/`stroke="url(#id)"`. Static definitions only — see
  /// `svg_gradient.dart`.
  ///
  /// 文档的 `<linearGradient>`/`<radialGradient>` 表，供
  /// `fill`/`stroke="url(#id)"` 的元素使用。仅静态定义——见 `svg_gradient.dart`。
  final Map<String, SvgGradientDef> gradients;

  /// The document's root node. / 文档根节点。
  final SvgNode root;

  /// The document's intrinsic (viewBox) size. / 文档固有（viewBox）尺寸。
  final Size intrinsicSize;

  /// Current position on the animation timeline. / 当前所处的动画时间线位置。
  final Duration time;

  /// Theme resolving `currentColor`. / 解析 `currentColor` 的主题。
  final SvgTheme theme;

  /// How the document is inscribed into the paint box. / 文档如何适配绘制盒。
  final BoxFit fit;

  /// Alignment within the paint box. / 在绘制盒内的对齐方式。
  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || intrinsicSize.isEmpty) return;
    final fitted = applyBoxFit(fit, intrinsicSize, size);
    final dest = fitted.destination;
    final sx = dest.width / intrinsicSize.width;
    final sy = dest.height / intrinsicSize.height;
    final dx = (size.width - dest.width) * ((alignment.x + 1) / 2);
    final dy = (size.height - dest.height) * ((alignment.y + 1) / 2);

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(sx, sy);
    _paintNode(canvas, root, ResolvedStyle.initial);
    canvas.restore();
  }

  /// Paints [node] at its position in the tree, resolving its animated style
  /// and any static/animated transforms.
  ///
  /// [nested] marks content being painted *as* a `<clipPath>`/`<mask>`
  /// definition's body (via [clipPaths]/[masks]): SVG's nested-mask/clip is
  /// out of scope, so nested content never itself looks up a further
  /// `clip-path`/`mask` reference (the nearest ancestor's clip/mask already
  /// won) — see fsvg CLAUDE.md task notes.
  ///
  /// 在树中的位置绘制 [node]，解析其动画样式及任何静态/动画变换。
  ///
  /// [nested] 标记正在作为 `<clipPath>`/`<mask>` 定义体（经
  /// [clipPaths]/[masks]）绘制的内容：SVG 的嵌套 mask/clip 不在范围内，因此
  /// 嵌套内容自身永不再查找 `clip-path`/`mask` 引用（最近祖先的裁剪/遮罩已经
  /// 生效）——见 fsvg CLAUDE.md 任务记录。
  void _paintNode(Canvas canvas, SvgNode node, ResolvedStyle inherited, {bool nested = false}) {
    final effectiveAttributes = Map<String, String>.of(node.attributes);
    for (final animation in node.animations) {
      final sampled = animation.sample(time);
      if (sampled != null) {
        effectiveAttributes[animation.attributeName] = sampled.toString();
      }
    }
    final style = inherited.inherit(effectiveAttributes, theme);

    final clipDef = nested ? null : clipPaths[node.clipPathId];
    final maskDef = nested ? null : masks[node.maskId];
    final blurSigma = node.blurSigma;
    final needsClipMaskSave = clipDef != null || maskDef != null;
    if (needsClipMaskSave) canvas.save();
    if (clipDef != null) canvas.clipPath(_resolveClipPath(clipDef, time));
    // feGaussianBlur: paint this node (and its subtree) into an offscreen
    // layer, then blur the whole layer on composite — rather than blurring
    // each stroke/fill individually, which is what SVG's filter semantics
    // require (the filter applies to the element's *rendered result*, not
    // its paint).
    //
    // feGaussianBlur：把本节点（含子树）绘制进一个离屏图层，合成时对整个图层
    // 做模糊——而非逐笔画/填充分别模糊，这才符合 SVG 滤镜语义（滤镜作用于元素
    // 的*渲染结果*，而非其涂料本身）。
    if (blurSigma != null && blurSigma > 0) {
      canvas.saveLayer(
        null,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      );
    }
    // The destination layer mask content composites into via BlendMode.dstIn
    // (see _maskCoveragePaint) — opened now so it wraps everything painted
    // below, including any transform this node applies.
    //
    // mask 内容经 BlendMode.dstIn（见 _maskCoveragePaint）合成进的目标图层——
    // 现在开启，使其包裹下方绘制的一切，包括本节点应用的任何变换。
    if (maskDef != null) canvas.saveLayer(null, Paint());

    if (node.transformAnimations.isEmpty &&
        node.motionAnimations.isEmpty &&
        node.transform == null) {
      _paintNodeContent(canvas, node, style, effectiveAttributes);
      if (blurSigma != null && blurSigma > 0) canvas.restore();
      if (maskDef != null) _applyMaskLayer(canvas, maskDef);
      if (needsClipMaskSave) canvas.restore();
      return;
    }
    // Multiple <animateTransform> on the same element compose in document
    // order (SVG semantics); sequential canvas.translate/rotate/scale calls
    // naturally accumulate in that order without needing a matrix type.
    //
    // 同一元素上多个 <animateTransform> 按文档顺序叠加（SVG 语义）；依次调用
    // canvas.translate/rotate/scale 天然按该顺序累积，无需引入矩阵类型。
    canvas.save();
    // The element's own static transform="..." goes first; SVG composes any
    // <animateTransform> on top of it.
    //
    // 元素自身的静态 transform="..." 先应用；SVG 语义下 <animateTransform>
    // 叠加在它之上。
    final staticTransform = node.transform;
    if (staticTransform != null) canvas.transform(_affineToMatrix4(staticTransform));
    for (final transformAnimation in node.transformAnimations) {
      final sampled = transformAnimation.sample(time);
      if (sampled == null) continue; // not started / ended without freeze
      switch (transformAnimation.type) {
        case SmilTransformType.translate:
          canvas.translate(sampled[0], sampled[1]);
        case SmilTransformType.scale:
          canvas.scale(sampled[0], sampled[1]);
        case SmilTransformType.rotate:
          // rotate(angle, cx, cy): rotate about the given pivot, defaulting
          // to the origin (0, 0) when cx/cy weren't specified — see
          // _normalizeTransformComponents in svg_document_parser.dart.
          final cx = sampled[1], cy = sampled[2];
          canvas.translate(cx, cy);
          canvas.rotate(sampled[0] * math.pi / 180);
          canvas.translate(-cx, -cy);
        case SmilTransformType.skewX:
          // skewX(a) = matrix(1, 0, tan(a), 1, 0, 0)
          canvas.transform(_affineToMatrix4([1, 0, math.tan(sampled[0] * math.pi / 180), 1, 0, 0]));
        case SmilTransformType.skewY:
          // skewY(a) = matrix(1, tan(a), 0, 1, 0, 0)
          canvas.transform(_affineToMatrix4([1, math.tan(sampled[0] * math.pi / 180), 0, 1, 0, 0]));
      }
    }
    // <animateMotion> composes on top of the element's other transforms (SVG
    // treats it as supplemental), so it is applied last.
    //
    // <animateMotion> 叠加在元素其它变换之上（SVG 视其为追加变换），因此最后
    // 应用。
    for (final motion in node.motionAnimations) {
      final sampled = motion.sample(time);
      if (sampled == null) continue;
      canvas.translate(sampled.x, sampled.y);
      if (sampled.angleDegrees != 0) canvas.rotate(sampled.angleDegrees * math.pi / 180);
    }
    _paintNodeContent(canvas, node, style, effectiveAttributes);
    canvas.restore(); // closes the transform save() a few lines above

    if (blurSigma != null && blurSigma > 0) canvas.restore();
    if (maskDef != null) _applyMaskLayer(canvas, maskDef);
    if (needsClipMaskSave) canvas.restore();
  }

  /// Composites [maskDef]'s content (sampled at [time]) as coverage over
  /// whatever was just painted into the current destination layer, then
  /// closes that layer — the second half of the mask machinery `_paintNode`
  /// opens with `canvas.saveLayer(null, Paint())`.
  ///
  /// 把 [maskDef] 的内容（在 [time] 采样）作为覆盖度合成到刚绘制进当前目标图层
  /// 的内容之上，然后关闭该图层——是 `_paintNode` 用
  /// `canvas.saveLayer(null, Paint())` 开启的 mask 机制的后半段。
  void _applyMaskLayer(Canvas canvas, SvgNode maskDef) {
    canvas.saveLayer(null, _maskCoveragePaint());
    _paintNode(canvas, maskDef, ResolvedStyle.initial, nested: true);
    canvas
      ..restore()
      ..restore();
  }

  /// SVG `luminanceToAlpha` coefficients turning a `<mask>`'s rendered
  /// content into coverage. Approach (`dstIn` + [ColorFilter.matrix])
  /// cross-checked against `rust_static_svg.dart`'s equivalent for the
  /// static path (see its doc comment for the coefficient provenance) —
  /// same algorithm, independently written for this xml-based engine.
  ///
  /// 把 `<mask>` 渲染内容转成覆盖度的 SVG `luminanceToAlpha` 系数。做法
  /// （`dstIn` + [ColorFilter.matrix]）与 `rust_static_svg.dart` 静态路径的
  /// 等价实现交叉核对过（系数出处见其文档注释）——同一算法，为本 xml 引擎
  /// 独立编写。
  Paint _maskCoveragePaint() => Paint()
    ..blendMode = BlendMode.dstIn
    ..colorFilter = const ColorFilter.matrix(<double>[
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0, //
      0.2125, 0.7154, 0.0721, 0, 0,
    ]);

  /// Builds the union clip path for a `<clipPath>` definition, sampling any
  /// `<animate>`/`<animateTransform>` on its content at [time] — this is what
  /// makes an animated clip path actually animate, rather than clipping by
  /// its resting-state geometry.
  ///
  /// Walks [defRoot]'s subtree accumulating each node's static/animated
  /// transform into an affine matrix, applying it to that node's own geometry
  /// path (via [_geometryPath]) before adding it into the union. `<image>`/
  /// `<text>` content is not geometry and contributes nothing (documented
  /// scope limit).
  ///
  /// 构建 `<clipPath>` 定义的并集裁剪路径，在 [time] 对其内容上的
  /// `<animate>`/`<animateTransform>` 采样——这正是"动画裁剪路径真的会动"而非
  /// "按静止状态几何裁剪"的关键。
  ///
  /// 遍历 [defRoot] 子树，把每个节点的静态/动画变换累积成仿射矩阵，应用到该
  /// 节点自身的几何路径（经 [_geometryPath]）上后再并入总路径。`<image>`/
  /// `<text>` 内容不是几何图形，不参与（明确的范围限制）。
  ui.Path _resolveClipPath(SvgNode defRoot, Duration time) {
    final union = ui.Path();
    void walk(SvgNode node, List<double> matrix) {
      final effectiveAttributes = Map<String, String>.of(node.attributes);
      for (final animation in node.animations) {
        final sampled = animation.sample(time);
        if (sampled != null) effectiveAttributes[animation.attributeName] = sampled.toString();
      }
      var accum = matrix;
      if (node.transform != null) accum = _concatAffine(accum, node.transform!);
      for (final transformAnimation in node.transformAnimations) {
        final sampled = transformAnimation.sample(time);
        if (sampled == null) continue;
        accum = _concatAffine(accum, _transformSampleToAffine(transformAnimation.type, sampled));
      }

      if (node.kind == SvgNodeKind.root || node.kind == SvgNodeKind.group) {
        for (final child in node.children) {
          walk(child, accum);
        }
        return;
      }
      final geometry = _geometryPath(node.kind, effectiveAttributes);
      if (geometry == null) return;
      geometry.transform(_affineToMatrix4(accum));
      union.addPath(geometry, Offset.zero);
    }

    walk(defRoot, const [1, 0, 0, 1, 0, 0]);
    return union;
  }

  /// Expands one sampled `<animateTransform>` component list into an affine
  /// `[a, b, c, d, e, f]`, matching the per-`type` canvas calls `_paintNode`
  /// makes (see that method's `switch (transformAnimation.type)`), just as a
  /// composable matrix instead of direct canvas calls — needed for
  /// [_resolveClipPath], which builds a `ui.Path` rather than issuing canvas
  /// commands.
  ///
  /// 把一个已采样的 `<animateTransform>` 分量列表展开为仿射矩阵
  /// `[a, b, c, d, e, f]`，与 `_paintNode` 按 `type` 发出的 canvas 调用（见该方法
  /// 的 `switch (transformAnimation.type)`）等价，只是以可组合矩阵而非直接
  /// canvas 调用的形式——[_resolveClipPath] 需要它，因为它构建的是 `ui.Path`
  /// 而非发出 canvas 指令。
  static List<double> _transformSampleToAffine(SmilTransformType type, List<double> sampled) {
    switch (type) {
      case SmilTransformType.translate:
        return [1, 0, 0, 1, sampled[0], sampled[1]];
      case SmilTransformType.scale:
        return [sampled[0], 0, 0, sampled[1], 0, 0];
      case SmilTransformType.rotate:
        final rad = sampled[0] * math.pi / 180;
        final cosr = math.cos(rad), sinr = math.sin(rad);
        final cx = sampled[1], cy = sampled[2];
        final rotation = _concatAffine([1, 0, 0, 1, cx, cy], [cosr, sinr, -sinr, cosr, 0, 0]);
        return _concatAffine(rotation, [1, 0, 0, 1, -cx, -cy]);
      case SmilTransformType.skewX:
        return [1, 0, math.tan(sampled[0] * math.pi / 180), 1, 0, 0];
      case SmilTransformType.skewY:
        return [1, math.tan(sampled[0] * math.pi / 180), 0, 1, 0, 0];
    }
  }

  /// Affine `a * b` in SVG's `[a, b, c, d, e, f]` convention — same formula as
  /// `svg_gradient.dart`'s private `_concat`, kept separate since it's a
  /// six-line self-contained formula not worth threading a shared-utility
  /// import for.
  ///
  /// SVG `[a, b, c, d, e, f]` 约定下的仿射矩阵乘法 `a * b`——与
  /// `svg_gradient.dart` 私有的 `_concat` 公式相同，单独保留是因为这是六行的
  /// 自包含公式，不值得为此引入共享工具导入。
  static List<double> _concatAffine(List<double> a, List<double> b) => [
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5],
      ];

  // [attributes] is the element's *animated* attribute map (node.attributes
  // with any sampled <animate> values overlaid — see _paintNode) — geometry
  // must read from it, not node.attributes directly, or an <animate> whose
  // attributeName targets geometry (x/y/cx/cy/r/width/height/...) silently
  // has no visual effect.
  //
  // [attributes] 是元素*动画后*的属性表（node.attributes 叠加了已采样的
  // <animate> 值——见 _paintNode）——几何读取必须用它，不能直接读
  // node.attributes，否则 attributeName 指向几何属性
  // （x/y/cx/cy/r/width/height/……）的 <animate> 会被静默地画不出效果。
  void _paintNodeContent(Canvas canvas, SvgNode node, ResolvedStyle style, Map<String, String> attributes) {
    switch (node.kind) {
      case SvgNodeKind.root:
      case SvgNodeKind.group:
        for (final child in node.children) {
          _paintNode(canvas, child, style);
        }
      case SvgNodeKind.path:
      case SvgNodeKind.circle:
      case SvgNodeKind.rect:
      case SvgNodeKind.ellipse:
      case SvgNodeKind.line:
      case SvgNodeKind.polyline:
      case SvgNodeKind.polygon:
        final path = _geometryPath(node.kind, attributes);
        if (path != null) _paintShape(canvas, path, style);
      case SvgNodeKind.text:
        _paintText(canvas, node, style, attributes);
      case SvgNodeKind.image:
        final img = node.resolvedImage;
        if (img == null) return; // not yet decoded / failed to decode: skip silently
        final x = double.tryParse(attributes['x'] ?? '0') ?? 0;
        final y = double.tryParse(attributes['y'] ?? '0') ?? 0;
        final w = double.tryParse(attributes['width'] ?? '0') ?? 0;
        final h = double.tryParse(attributes['height'] ?? '0') ?? 0;
        if (w <= 0 || h <= 0) return;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(x, y, w, h),
          Paint()..color = Color.fromRGBO(0, 0, 0, style.opacity),
        );
    }
  }

  /// Builds the plain `ui.Path` for a geometry shape kind (`path`/`circle`/
  /// `rect`/`ellipse`/`line`/`polyline`/`polygon`), reading [attributes]
  /// (already animation-overlaid — see [_paintNodeContent]'s doc comment).
  /// Returns null for a shape that can't be built (missing `d`) and for any
  /// non-geometry kind (`root`/`group`/`image`/`text`).
  ///
  /// Shared by [_paintNodeContent] (actual painting) and [_resolveClipPath]
  /// (building a `<clipPath>`'s union path) so both read exactly the same
  /// geometry logic — no separate "geometry for clipping" implementation to
  /// drift out of sync with the paint path.
  ///
  /// 构建几何形状种类（`path`/`circle`/`rect`/`ellipse`/`line`/`polyline`/
  /// `polygon`）的纯 `ui.Path`，读取 [attributes]（已叠加动画——见
  /// [_paintNodeContent] 的文档注释）。无法构建时（缺 `d`）及非几何种类
  /// （`root`/`group`/`image`/`text`）返回 null。
  ///
  /// 由 [_paintNodeContent]（实际绘制）与 [_resolveClipPath]（构建
  /// `<clipPath>` 的并集路径）共用，使两者读取完全相同的几何逻辑——不存在一份
  /// 会与绘制路径走岔的"裁剪专用几何"实现。
  ui.Path? _geometryPath(SvgNodeKind kind, Map<String, String> attributes) {
    switch (kind) {
      case SvgNodeKind.path:
        final d = attributes['d'];
        return d == null ? null : parseSvgPathData(d);
      case SvgNodeKind.circle:
        final cx = double.tryParse(attributes['cx'] ?? '0') ?? 0;
        final cy = double.tryParse(attributes['cy'] ?? '0') ?? 0;
        final r = double.tryParse(attributes['r'] ?? '0') ?? 0;
        return ui.Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case SvgNodeKind.rect:
        final x = double.tryParse(attributes['x'] ?? '0') ?? 0;
        final y = double.tryParse(attributes['y'] ?? '0') ?? 0;
        final w = double.tryParse(attributes['width'] ?? '0') ?? 0;
        final h = double.tryParse(attributes['height'] ?? '0') ?? 0;
        if (w <= 0 || h <= 0) return null; // SVG: non-positive size renders nothing
        var rx = double.tryParse(attributes['rx'] ?? '');
        var ry = double.tryParse(attributes['ry'] ?? '');
        rx ??= ry;
        ry ??= rx;
        final path = ui.Path();
        if (rx != null && ry != null && rx > 0 && ry > 0) {
          final clampedRx = rx > w / 2 ? w / 2 : rx;
          final clampedRy = ry > h / 2 ? h / 2 : ry;
          path.addRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.elliptical(clampedRx, clampedRy)),
          );
        } else {
          path.addRect(Rect.fromLTWH(x, y, w, h));
        }
        return path;
      case SvgNodeKind.ellipse:
        final cx = double.tryParse(attributes['cx'] ?? '0') ?? 0;
        final cy = double.tryParse(attributes['cy'] ?? '0') ?? 0;
        final rx = double.tryParse(attributes['rx'] ?? '0') ?? 0;
        final ry = double.tryParse(attributes['ry'] ?? '0') ?? 0;
        return ui.Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2));
      case SvgNodeKind.line:
        final x1 = double.tryParse(attributes['x1'] ?? '0') ?? 0;
        final y1 = double.tryParse(attributes['y1'] ?? '0') ?? 0;
        final x2 = double.tryParse(attributes['x2'] ?? '0') ?? 0;
        final y2 = double.tryParse(attributes['y2'] ?? '0') ?? 0;
        return ui.Path()
          ..moveTo(x1, y1)
          ..lineTo(x2, y2);
      case SvgNodeKind.polyline:
      case SvgNodeKind.polygon:
        final points = parseSvgPoints(attributes['points'] ?? '');
        if (points.length < 2) return null;
        final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
        for (final p in points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        if (kind == SvgNodeKind.polygon) path.close();
        return path;
      case SvgNodeKind.root:
      case SvgNodeKind.group:
      case SvgNodeKind.image:
      case SvgNodeKind.text:
        return null;
    }
  }

  /// Paints a `<text>` node's flat content (no `<tspan>`) at `x`/`y`, honoring
  /// `font-size`/`font-family`/`text-anchor` and the already-resolved [style]
  /// (`fill`/`opacity` — the same generic animation mechanism every other
  /// node kind uses, see [_paintNode]).
  ///
  /// `x`/`y` is SVG's text-anchor point on the *baseline*; [TextPainter]
  /// paints from a top-left origin, so the vertical offset is corrected via
  /// [TextPainter.computeDistanceToActualBaseline].
  ///
  /// 在 `x`/`y` 处绘制 `<text>` 节点的纯文本内容（不支持 `<tspan>`），遵循
  /// `font-size`/`font-family`/`text-anchor` 及已解析好的 [style]
  /// （`fill`/`opacity`——与其它任何节点种类相同的通用动画机制，见
  /// [_paintNode]）。
  ///
  /// `x`/`y` 是 SVG 文本在*基线*上的锚点；[TextPainter] 从左上角原点开始绘制，
  /// 因此垂直偏移通过 [TextPainter.computeDistanceToActualBaseline] 校正。
  void _paintText(Canvas canvas, SvgNode node, ResolvedStyle style, Map<String, String> attributes) {
    final content = node.textContent;
    if (content == null || content.isEmpty || style.opacity <= 0) return;
    final fill = style.fill;
    if (fill == null) return; // fill="none": SVG renders no glyphs

    final x = double.tryParse(attributes['x'] ?? '0') ?? 0;
    final y = double.tryParse(attributes['y'] ?? '0') ?? 0;
    final fontSize = double.tryParse(attributes['font-size'] ?? '') ?? 16;

    final painter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: attributes['font-family'],
          color: fill.withValues(alpha: fill.a * style.opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final dx = switch (attributes['text-anchor']) {
      'middle' => -painter.width / 2,
      'end' => -painter.width,
      _ => 0.0,
    };
    final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(canvas, Offset(x + dx, y - baseline));
  }

  /// Shader for a `url(#id)` paint over [path]'s bounds, or null when the id
  /// names no gradient this document defines (in which case the caller falls
  /// back to the solid colour, or paints nothing).
  ///
  /// The definition is resampled at [time] first (see
  /// `svg_gradient.dart`'s `resampleGradientAtTime`) so an animated gradient's
  /// stops/geometry reflect the current frame — a no-op for the common static
  /// case.
  ///
  /// [path] 包围盒上 `url(#id)` 涂料对应的 shader；id 在本文档中没有对应渐变时
  /// 返回 null（此时调用方回退到纯色，或什么都不画）。
  ///
  /// 先在 [time] 对定义做重采样（见 `svg_gradient.dart` 的
  /// `resampleGradientAtTime`），使动画渐变的色标/几何反映当前帧——对常见的
  /// 静态场景是空操作。
  ui.Shader? _gradientShader(String? id, ui.Path path, double opacity) {
    if (id == null) return null;
    final def = gradients[id];
    if (def == null) return null;
    return buildGradientShader(resampleGradientAtTime(def, time), path.getBounds(), opacity);
  }

  /// Expands an SVG affine `[a, b, c, d, e, f]` into the column-major 4x4
  /// matrix `Canvas.transform` wants.
  ///
  /// 把 SVG 仿射矩阵 `[a, b, c, d, e, f]` 展开为 `Canvas.transform` 需要的
  /// 列主序 4x4 矩阵。
  static Float64List _affineToMatrix4(List<double> m) {
    final out = Float64List(16);
    out[0] = m[0]; // a
    out[1] = m[1]; // b
    out[4] = m[2]; // c
    out[5] = m[3]; // d
    out[10] = 1;
    out[12] = m[4]; // e
    out[13] = m[5]; // f
    out[15] = 1;
    return out;
  }

  void _paintShape(Canvas canvas, ui.Path path, ResolvedStyle style) {
    if (style.opacity <= 0) return;
    final fillShader = _gradientShader(style.fillGradientId, path, style.opacity);
    if (fillShader != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = fillShader,
      );
    } else if (style.fill != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = style.fill!.withValues(alpha: style.fill!.a * style.opacity),
      );
    }
    final strokeShader = _gradientShader(style.strokeGradientId, path, style.opacity);
    if (strokeShader != null && style.strokeWidth > 0) {
      canvas.drawPath(
        style.strokeDasharray.isEmpty
            ? path
            : dashPath(path, dashArray: style.strokeDasharray, dashOffset: style.strokeDashoffset),
        Paint()
          ..style = PaintingStyle.stroke
          ..shader = strokeShader
          ..strokeWidth = style.strokeWidth
          ..strokeCap = style.strokeLinecap
          ..strokeJoin = style.strokeLinejoin,
      );
      return;
    }
    if (style.stroke != null && style.strokeWidth > 0) {
      final strokePath =
          style.strokeDasharray.isEmpty
              ? path
              : dashPath(
                  path,
                  dashArray: style.strokeDasharray,
                  dashOffset: style.strokeDashoffset,
                );
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = style.stroke!.withValues(alpha: style.stroke!.a * style.opacity)
          ..strokeWidth = style.strokeWidth
          ..strokeCap = style.strokeLinecap
          ..strokeJoin = style.strokeLinejoin,
      );
    }
  }

  @override
  bool shouldRepaint(AnimatedSvgPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.root != root ||
      oldDelegate.theme != theme ||
      oldDelegate.fit != fit ||
      oldDelegate.alignment != alignment ||
      oldDelegate.gradients != gradients ||
      oldDelegate.clipPaths != clipPaths ||
      oldDelegate.masks != masks;
}
