// Minimal SVG element tree for the animation engine: just enough shape/group
// vocabulary to render icon-sized animated SVGs (line-md style), each node
// carrying its own raw presentation attributes plus any attached
// `<animate>` timelines. Original implementation.
//
// 动画引擎用的最小 SVG 元素树：仅覆盖渲染图标级动画 SVG（line-md 风格）所需的
// 形状/分组词汇，每个节点携带自身原始表现属性及挂载的 `<animate>` 时间线。
// 原创实现。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'smil_animation.dart';

/// The element kinds this engine understands.
///
/// `<use>` doesn't appear here: it is resolved away at parse time into a
/// [group] wrapping a copy of its target (see `svg_document_parser.dart`).
///
/// **Filters**: only a Gaussian blur is supported, via
/// [SvgNode.blurSigma] (`filter="blur(Npx)"` or `filter="url(#id)"` pointing
/// at a `<filter><feGaussianBlur stdDeviation="N"/></filter>`) — everything
/// else in the SVG filter spec (composite ops, other primitives, filter
/// regions/chains) remains unsupported, legitimate future work, not faked
/// here. `<clipPath>`/`<mask>` content itself is *not* a node
/// kind — it is parsed into [SvgNode] subtrees held on `SvgDocument.clipPaths`/
/// `SvgDocument.masks` and referenced by id (see [SvgNode.clipPathId]/
/// [SvgNode.maskId]), the same way gradients are.
///
/// 本引擎能理解的元素种类。
///
/// `<use>` 不在此列：它在解析阶段就被消解为一个包裹目标副本的 [group]
/// （见 `svg_document_parser.dart`）。
///
/// **不支持**（明确的范围限制）：filter——合理的未来工作，此处不做假支持。
/// `<clipPath>`/`<mask>` 本身不是一种节点种类——它们被解析为 [SvgNode] 子树，
/// 挂在 `SvgDocument.clipPaths`/`SvgDocument.masks` 上按 id 索引，并被引用（见
/// [SvgNode.clipPathId]/[SvgNode.maskId]），与渐变的处理方式一致。
enum SvgNodeKind {
  /// The document root, `<svg>`. / 文档根节点 `<svg>`。
  root,

  /// `<g>` grouping element. / `<g>` 分组元素。
  group,

  /// `<path>` with a `d` attribute. / 带 `d` 属性的 `<path>`。
  path,

  /// `<circle>` with `cx`/`cy`/`r`. / 带 `cx`/`cy`/`r` 的 `<circle>`。
  circle,

  /// `<rect>` with `x`/`y`/`width`/`height` and optional `rx`/`ry`.
  ///
  /// 带 `x`/`y`/`width`/`height` 及可选 `rx`/`ry` 的 `<rect>`。
  rect,

  /// `<ellipse>` with `cx`/`cy`/`rx`/`ry`. / 带 `cx`/`cy`/`rx`/`ry` 的 `<ellipse>`。
  ellipse,

  /// `<line>` with `x1`/`y1`/`x2`/`y2`. / 带 `x1`/`y1`/`x2`/`y2` 的 `<line>`。
  line,

  /// `<polyline>` with a `points` attribute (not auto-closed).
  ///
  /// 带 `points` 属性的 `<polyline>`（不自动闭合）。
  polyline,

  /// `<polygon>` with a `points` attribute (auto-closed).
  ///
  /// 带 `points` 属性的 `<polygon>`（自动闭合）。
  polygon,

  /// `<image>` embedding a base64 `data:` URI raster bitmap via `href`
  /// (or `xlink:href`). Only raster bitmaps — a nested-SVG `href` is not
  /// supported (out of scope, see `resolveImageNodes` in
  /// `svg_document_parser.dart`).
  ///
  /// `<image>`，通过 `href`（或 `xlink:href`）内嵌 base64 `data:` URI 位图。
  /// 仅支持位图——嵌套 SVG 的 `href` 不支持（超出范围，见
  /// `svg_document_parser.dart` 的 `resolveImageNodes`）。
  image,

  /// `<text>` with its plain text content, `x`/`y`, and basic font attributes
  /// (`font-size`/`font-family`/`text-anchor`). No `<tspan>`, no textPath, and
  /// the text content itself cannot be animated (documented scope limit).
  ///
  /// `<text>`，含其纯文本内容、`x`/`y`，及基础字体属性
  /// （`font-size`/`font-family`/`text-anchor`）。不支持 `<tspan>`、textPath，
  /// 也不支持对文本内容本身做动画（明确的范围限制）。
  text,
}

/// One node in the parsed SVG tree.
///
/// Presentation attributes (`fill`, `stroke`, `stroke-width`, ...) are kept
/// as raw strings in [attributes] and resolved (inheritance + `currentColor`
/// + animation overrides) at paint time — see `svg_style.dart`.
///
/// 解析后 SVG 树中的一个节点。
///
/// 表现属性（`fill`、`stroke`、`stroke-width` 等）以原始字符串形式保存在
/// [attributes] 中，在绘制时才做解析（继承 + `currentColor` + 动画覆盖）——
/// 见 `svg_style.dart`。
class SvgNode {
  /// Creates a node. / 创建一个节点。
  SvgNode({
    required this.kind,
    required this.attributes,
    this.children = const [],
    this.animations = const [],
    this.transformAnimations = const [],
    this.motionAnimations = const [],
    this.colorAnimations = const [],
    this.transform,
    this.clipPathId,
    this.maskId,
    this.textContent,
    this.blurSigma,
  });

  /// Gaussian blur sigma (in user-space px) from `filter="blur(Npx)"` or an
  /// `stdDeviation` referenced via `filter="url(#id)"` pointing at a
  /// `<filter><feGaussianBlur stdDeviation="N"/></filter>`, or null when the
  /// node has no blur. `stdDeviation` in SVG *is* the Gaussian sigma (not a
  /// radius), so it is used directly as `ui.ImageFilter.blur`'s sigma — see
  /// `animated_svg_painter.dart`'s `_paintNode`, which wraps this node's paint
  /// in a `saveLayer` with that filter when non-null.
  ///
  /// 来自 `filter="blur(Npx)"`，或经 `filter="url(#id)"` 引用的
  /// `<filter><feGaussianBlur stdDeviation="N"/></filter>` 的高斯模糊 sigma
  /// （用户空间像素），无模糊时为 null。SVG 的 `stdDeviation` 本身就是高斯
  /// sigma（不是半径），因此直接作为 `ui.ImageFilter.blur` 的 sigma 使用——见
  /// `animated_svg_painter.dart` 的 `_paintNode`，非 null 时会用该滤镜把本节点的
  /// 绘制包进一个 `saveLayer`。
  final double? blurSigma;

  /// `<animate attributeName="stop-color">` (or similar colour-valued)
  /// timelines attached directly to this node — kept separate from
  /// [animations] because colour keyframes interpolate per-channel, not as a
  /// single number. Currently only produced for `<stop>` nodes inside a
  /// gradient definition (see `svg_document_parser.dart`'s
  /// `_parseGradientStopNode`); the generic render tree does not populate
  /// this (animating `fill`/`stroke` via `<animate>` remains a documented gap).
  ///
  /// 直接挂载在本节点上的 `<animate attributeName="stop-color">`（或类似颜色值）
  /// 时间线——与 [animations] 分开存放，因为颜色关键帧是按通道插值，不是单一
  /// 数值。当前仅在渐变定义内的 `<stop>` 节点上产出（见
  /// `svg_document_parser.dart` 的 `_parseGradientStopNode`）；普通渲染树不会
  /// 填充此字段（用 `<animate>` 驱动 `fill`/`stroke` 仍是已记录的缺口）。
  final List<SmilColorAnimation> colorAnimations;

  /// Id of a `<clipPath>` this node's `clip-path="url(#id)"` references, or
  /// null. Resolved against `SvgDocument.clipPaths` at paint time; the
  /// referenced content may itself carry `<animate>`s, sampled at the current
  /// frame — see `animated_svg_painter.dart`.
  ///
  /// 本节点 `clip-path="url(#id)"` 引用的 `<clipPath>` 的 id，或 null。绘制时
  /// 在 `SvgDocument.clipPaths` 中查找；被引用的内容自身也可能带
  /// `<animate>`，在当前帧被采样——见 `animated_svg_painter.dart`。
  final String? clipPathId;

  /// Id of a `<mask>` this node's `mask="url(#id)"` references, or null. Same
  /// resolution/animation semantics as [clipPathId] but against
  /// `SvgDocument.masks`.
  ///
  /// 本节点 `mask="url(#id)"` 引用的 `<mask>` 的 id，或 null。解析/动画语义与
  /// [clipPathId] 相同，只是查表对象是 `SvgDocument.masks`。
  final String? maskId;

  /// Plain text content for a [SvgNodeKind.text] node (no `<tspan>` support);
  /// always null for every other kind.
  ///
  /// [SvgNodeKind.text] 节点的纯文本内容（不支持 `<tspan>`）；其它种类始终为
  /// null。
  final String? textContent;

  /// `<animateMotion>` timelines attached directly to this node.
  ///
  /// Applied after [transformAnimations] (SVG treats motion as supplemental to
  /// the element's other transforms) — see `animated_svg_painter.dart`.
  ///
  /// 直接挂载在本节点上的 `<animateMotion>` 时间线。
  ///
  /// 在 [transformAnimations] 之后应用（SVG 语义中运动是对元素其它变换的追加）
  /// ——见 `animated_svg_painter.dart`。
  final List<SmilMotionAnimation> motionAnimations;

  /// The element's static `transform="..."` attribute, already composed into a
  /// single affine matrix `[a, b, c, d, e, f]` at document-parse time (via the
  /// Rust `parse_transform`, see `native_svg_values.dart`). Null when the
  /// element has no `transform`, or it failed to parse.
  ///
  /// Applied around this node's own paint (and its subtree, for groups),
  /// *outside* any [transformAnimations] — matching SVG, where an
  /// `<animateTransform>` composes on top of the element's static transform.
  ///
  /// 元素的静态 `transform="..."` 属性，已在文档解析阶段合成为单个仿射矩阵
  /// `[a, b, c, d, e, f]`（经 Rust 的 `parse_transform`，见
  /// `native_svg_values.dart`）。元素无 `transform` 或解析失败时为 null。
  ///
  /// 应用在本节点自身绘制（分组则含其子树）外围，且在 [transformAnimations]
  /// *之外*——与 SVG 一致：`<animateTransform>` 叠加在元素静态变换之上。
  final List<double>? transform;

  /// The node's tag kind. / 节点的标签种类。
  final SvgNodeKind kind;

  /// Raw attribute map (presentation attrs plus geometry attrs like `d`,
  /// `cx`/`cy`/`r`, `width`/`height`/`viewBox` on the root).
  ///
  /// 原始属性表（表现属性，以及 `d`、`cx`/`cy`/`r`、根节点上的
  /// `width`/`height`/`viewBox` 等几何属性）。
  final Map<String, String> attributes;

  /// Child nodes (only [SvgNodeKind.root]/[SvgNodeKind.group] have any).
  ///
  /// 子节点（只有 [SvgNodeKind.root]/[SvgNodeKind.group] 才有）。
  final List<SvgNode> children;

  /// `<animate>` timelines attached directly to this node.
  ///
  /// 直接挂载在本节点上的 `<animate>` 时间线。
  final List<SmilAnimation> animations;

  /// `<animateTransform>` timelines attached directly to this node.
  ///
  /// Applied around this node's own paint (and its subtree, for groups) in
  /// document order — see `animated_svg_painter.dart`.
  ///
  /// 直接挂载在本节点上的 `<animateTransform>` 时间线。
  ///
  /// 按文档顺序应用在本节点自身绘制（分组则含其子树）外围——见
  /// `animated_svg_painter.dart`。
  final List<SmilTransformAnimation> transformAnimations;

  /// Decoded bitmap for [SvgNodeKind.image] nodes, filled in by
  /// `resolveImageNodes` after the initial parse (decoding is async, parsing
  /// isn't). `null` until resolved, and always `null` for non-image nodes.
  ///
  /// [SvgNodeKind.image] 节点的已解码位图，由解析完成后的 `resolveImageNodes`
  /// 填入（解码是异步的，解析不是）。解析完成前为 `null`，非 image 节点始终
  /// 为 `null`。
  ui.Image? resolvedImage;

  /// Paint-time cache of this node's geometry [ui.Path], with
  /// [geometryCacheKey] identifying what it was built from. Owned entirely by
  /// `animated_svg_painter.dart`'s `_geometryPath` — nothing else reads or
  /// writes these two fields.
  ///
  /// Lives on the node rather than on the painter because a painter instance
  /// is created per frame while the node tree outlives every frame.
  ///
  /// 本节点几何 [ui.Path] 的绘制期缓存，[geometryCacheKey] 标识它是由什么构建
  /// 出来的。完全由 `animated_svg_painter.dart` 的 `_geometryPath` 持有——没有
  /// 其它地方读写这两个字段。
  ///
  /// 之所以挂在节点上而不是绘制器上：绘制器实例每帧新建一个，而节点树的寿命
  /// 长于任何一帧。
  ui.Path? cachedGeometry;

  /// Identity key for [cachedGeometry] — see that field.
  ///
  /// [cachedGeometry] 的身份键——见该字段。
  Object? geometryCacheKey;

  /// Paint-time cache of [transform] expanded into the column-major 4x4
  /// [Float64List] that `Canvas.transform` takes. Owned entirely by
  /// `animated_svg_painter.dart`'s `_paintNode`.
  ///
  /// No cache key is needed: [transform] is final and set at parse time, so
  /// the expansion can never go stale. Without it every transformed node
  /// allocated and filled a fresh 16-slot list on every frame.
  ///
  /// [transform] 展开为 `Canvas.transform` 所需列主序 4x4 [Float64List] 后的
  /// 绘制期缓存，完全由 `animated_svg_painter.dart` 的 `_paintNode` 持有。
  ///
  /// 不需要缓存键：[transform] 是 final 且在解析阶段就已确定，展开结果不可能
  /// 失效。没有它的话，每个带变换的节点每帧都要新分配并填满一个 16 槽列表。
  Float64List? cachedTransformMatrix;
}
