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

/// Extracts `#id` out of a `url(#id)` (or `url('#id')`/`url("#id")`)
/// paint/effect reference; returns null when [raw] isn't of that form.
///
/// Shared by parse-time `clip-path`/`mask` resolution
/// (`svg_document_parser.dart`) and per-frame `fill`/`stroke` resolution
/// (`svg_style.dart`'s `ResolvedStyle.inherit`).
///
/// 从 `url(#id)`（或 `url('#id')`/`url("#id")`）涂料/效果引用中取出 `#id`；
/// [raw] 不是此形式时返回 null。
///
/// 供解析阶段的 `clip-path`/`mask` 解析（`svg_document_parser.dart`）与逐帧的
/// `fill`/`stroke` 解析（`svg_style.dart` 的 `ResolvedStyle.inherit`）共用。
String? parseUrlId(String? raw) {
  if (raw == null) return null;
  final v = raw.trim();
  if (!v.startsWith('url(') || !v.endsWith(')')) return null;
  final inner = v
      .substring(4, v.length - 1)
      .trim()
      .replaceAll("'", '')
      .replaceAll('"', '');
  return inner.startsWith('#') ? inner.substring(1) : null;
}

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

  /// Paint-time cache of this node's resolved presentation style, together
  /// with the three identities it was resolved from
  /// ([styleInheritedKey]/[styleAttributesKey]/[styleThemeKey]). Owned
  /// entirely by `animated_svg_painter.dart`'s `_resolveStyle` — nothing else
  /// reads or writes these four fields.
  ///
  /// Typed `Object?` rather than `ResolvedStyle?` only to keep the dependency
  /// one-way: `svg_style.dart` imports this file (for [parseUrlId]), so this
  /// file cannot name `ResolvedStyle` without creating a cycle. The single
  /// owner casts on read — same arrangement as [geometryCacheKey].
  ///
  /// Why it is sound to cache: `ResolvedStyle.inherit` is a pure function of
  /// the inherited style, the attribute map, and the theme, so identity on all
  /// three is a conservative (stricter-than-needed) validity proof. A node
  /// carrying `<animate>`s gets a fresh attribute map every frame and so
  /// always misses; a node *under* an animated ancestor sees a fresh inherited
  /// style instance and so always misses. Everything else — the large static
  /// majority of a real icon's tree — hits.
  ///
  /// 本节点已解析表现样式的绘制期缓存，连同它是由哪三个身份解析出来的
  /// （[styleInheritedKey]/[styleAttributesKey]/[styleThemeKey]）。完全由
  /// `animated_svg_painter.dart` 的 `_resolveStyle` 持有——没有其它地方读写这
  /// 四个字段。
  ///
  /// 声明为 `Object?` 而非 `ResolvedStyle?`，只是为了保持依赖单向：
  /// `svg_style.dart` 会导入本文件（取 [parseUrlId]），因此本文件无法直接命名
  /// `ResolvedStyle`，否则构成循环。唯一持有者在读取时做类型转换——与
  /// [geometryCacheKey] 的安排一致。
  ///
  /// 为什么这样缓存是正确的：`ResolvedStyle.inherit` 是继承样式、属性表、主题
  /// 三者的纯函数，因此对三者做身份比较是一个保守（比必要条件更严格）的有效性
  /// 证明。带 `<animate>` 的节点每帧拿到全新属性表，必然未命中；处于动画祖先
  /// *之下*的节点每帧看到全新的继承样式实例，也必然未命中。其余节点——真实图标
  /// 树里占多数的静态部分——命中。
  Object? cachedStyle;

  /// Identity of the inherited style [cachedStyle] was resolved from — see
  /// that field.
  ///
  /// 解析出 [cachedStyle] 时所用继承样式的身份——见该字段。
  Object? styleInheritedKey;

  /// Identity of the attribute map [cachedStyle] was resolved from — see
  /// that field.
  ///
  /// 解析出 [cachedStyle] 时所用属性表的身份——见该字段。
  Object? styleAttributesKey;

  /// Identity of the theme [cachedStyle] was resolved from — see that field.
  ///
  /// 解析出 [cachedStyle] 时所用主题的身份——见该字段。
  Object? styleThemeKey;

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

  /// For a node used as a `<mask>` definition root: whether its content is
  /// simple enough that the mask can be replaced by an equivalent clip path,
  /// which needs no `saveLayer` at all. Null until first computed; owned
  /// entirely by `animated_svg_painter.dart`'s mask approximation.
  ///
  /// No cache key is needed: eligibility depends only on the parsed subtree's
  /// *structure* (which shape kinds, whether anything paints a stroke or a
  /// partial opacity, whether the fills are pure black/white), all of which
  /// is fixed at parse time. What animates inside an eligible mask is
  /// geometry and transforms, which the clip path resamples per frame just
  /// like the exact path does — so an eligible mask stays eligible for the
  /// document's whole life.
  ///
  /// 对于被用作 `<mask>` 定义根的节点：其内容是否足够简单，以至于这个 mask 可以
  /// 用等价的裁剪路径替代，从而完全不需要 `saveLayer`。首次计算前为 null；完全由
  /// `animated_svg_painter.dart` 的 mask 近似逻辑持有。
  ///
  /// 不需要缓存键：是否合格只取决于已解析子树的*结构*（有哪些形状种类、是否有任何
  /// 东西绘制描边或部分不透明度、填充是否为纯黑/纯白），这些在解析阶段就已固定。
  /// 合格 mask 内部会动的是几何与变换，而裁剪路径会像精确路径一样逐帧重新采样
  /// ——因此一个合格的 mask 在文档的整个生命周期内都保持合格。
  bool? maskClipEligible;

  /// For a node used as an eligible `<mask>` definition root: the clip path
  /// last built from its content, and the sampled-animation signature it was
  /// built from. Owned entirely by `animated_svg_painter.dart`'s
  /// `_resolveMaskClipPath`.
  ///
  /// Rebuilding the path means walking the subtree, allocating a 4x4 matrix
  /// per node, and copying every node's geometry segments into a union path —
  /// all native work, all per masked icon per frame. Yet a real icon's mask
  /// spends most of its on-screen life *not moving*: SMIL reveals are
  /// `fill="freeze"` and settle, and adjacent frames of a slow motion often
  /// sample to the same numbers. Keying on the sampled values (rather than on
  /// the timeline position) is what lets those frames reuse the path — a
  /// time-based key would miss on every single frame.
  ///
  /// 对于被用作合格 `<mask>` 定义根的节点：上一次由其内容构建出的裁剪路径，以及
  /// 构建它时所用的"已采样动画签名"。完全由 `animated_svg_painter.dart` 的
  /// `_resolveMaskClipPath` 持有。
  ///
  /// 重建这条路径意味着遍历子树、每个节点分配一个 4x4 矩阵、并把每个节点的几何
  /// 线段全部复制进一条并集路径——全是原生工作，且是每个带 mask 的图标每帧都要做
  /// 一遍。然而真实图标的 mask 在屏幕上的大部分时间是*不动*的：SMIL 揭示动画是
  /// `fill="freeze"` 会定格，而慢速运动的相邻帧也常常采样出相同的数值。以采样值
  /// （而非时间线位置）为键，正是让这些帧能复用路径的关键——用时间做键会每一帧都
  /// 未命中。
  ui.Path? cachedMaskClip;

  /// Signature of the sampled animation values [cachedMaskClip] was built
  /// from — see that field.
  ///
  /// 构建 [cachedMaskClip] 时所用的已采样动画值的签名——见该字段。
  List<double>? maskClipSampleKey;

  /// Paint-time cache of this node's attribute map with its `<animate>`
  /// overrides applied, together with the sampled values it was built from
  /// ([animatedSampleKey]). Owned entirely by
  /// `animated_svg_painter.dart`'s `_effectiveAttributes`.
  ///
  /// Why this is the *identity* of the map that matters, not just its
  /// contents: [cachedStyle] and [cachedGeometry] both prove their validity by
  /// an `identical` check against the attribute map they were resolved from. A
  /// node carrying any `<animate>` used to get a brand-new `Map` on every
  /// frame, so both of those caches missed on every frame **even when the
  /// sampled value had not actually changed** — which is the steady state of
  /// most real icons: a `fill="freeze"` reveal settles after a few hundred
  /// milliseconds and then reports the same number forever while some *other*
  /// animation (a looping rotation, a slow motion) keeps the icon repainting.
  /// Handing back the same map instance for as long as every sample is
  /// unchanged turns those permanent misses into hits, and the saving
  /// cascades: a group's reused map yields the same [ResolvedStyle] instance,
  /// which keeps its children's `styleInheritedKey` valid too.
  ///
  /// Why it is sound where the earlier reverted attempt was not: that attempt
  /// kept one map per node and **mutated it in place**, so its identity stayed
  /// stable while its contents changed — freezing animated `<rect>`/`<circle>`
  /// geometry at the first frame's shape (see
  /// `test/animation/effective_attributes_reuse_test.dart`). Here the identity
  /// is reused only while the contents are *provably* identical; the instant
  /// any sample moves, a genuinely fresh map is built and the dependent caches
  /// invalidate exactly as they always did.
  ///
  /// The key is the sampled values, never the timeline position — so a
  /// document shared between two widgets at different times (see
  /// `SvgDocumentCache`) either shares a valid entry or misses and rebuilds,
  /// and can never read a stale one. Same property [cachedMaskClip] relies on.
  ///
  /// 本节点叠加了 `<animate>` 覆盖值后的属性表的绘制期缓存，连同构建它时所用的
  /// 采样值（[animatedSampleKey]）。完全由 `animated_svg_painter.dart` 的
  /// `_effectiveAttributes` 持有。
  ///
  /// 为什么关键在于这张表的*身份*而不只是内容：[cachedStyle] 与
  /// [cachedGeometry] 都靠对"解析时所用属性表"做 `identical` 比较来证明自身有效。
  /// 而带任何 `<animate>` 的节点此前每帧都会拿到一张全新的 `Map`，于是这两个缓存
  /// 每帧都未命中——**即便采样值其实没有变化**。而后者正是多数真实图标的稳态：
  /// `fill="freeze"` 的揭示动画在几百毫秒后就定格，之后永远报同一个数，而此时
  /// *另一个*动画（循环旋转、缓慢位移）仍在让图标持续重绘。只要所有采样值都没变
  /// 就交回同一张表实例，能把这些永久未命中变成命中，而且收益会级联：分组复用了
  /// 表，就会产出同一个 [ResolvedStyle] 实例，从而让其子节点的
  /// `styleInheritedKey` 也继续有效。
  ///
  /// 为什么它成立、而此前被回滚的那次尝试不成立：那次尝试是每节点保留一张表并
  /// **原地修改**，于是身份保持稳定而内容却在变——把带动画的 `<rect>`/`<circle>`
  /// 几何冻结在第一帧的形状上（见
  /// `test/animation/effective_attributes_reuse_test.dart`）。这里只在内容
  /// *可证明*完全相同时才复用身份；任何一个采样值一动，就会构建一张真正全新的表，
  /// 依赖它的各缓存会像以往一样精确失效。
  ///
  /// 缓存键是采样值，绝不是时间线位置——因此被两个控件在不同时刻共享的文档
  /// （见 `SvgDocumentCache`）要么共享一个有效条目，要么未命中后重建，绝不会读到
  /// 过期结果。[cachedMaskClip] 依赖的正是同一个性质。
  Map<String, String>? cachedAnimatedAttributes;

  /// The values every entry of [animations] sampled to when
  /// [cachedAnimatedAttributes] was built, positionally — see that field.
  ///
  /// A timeline that produced no value (not started, or ended without
  /// freezing) is recorded as negative infinity, so "absent" can never collide
  /// with a legitimate sampled number. Overwritten in place on a miss rather
  /// than reallocated: nothing keys off this list's identity, only its
  /// contents.
  ///
  /// 构建 [cachedAnimatedAttributes] 时 [animations] 每一项各自采样到的值，按位置
  /// 对应——见该字段。
  ///
  /// 没有产出值的时间线（尚未开始，或已结束且不定格）记为负无穷，因此"缺失"绝不会
  /// 与某个合法采样数值混淆。未命中时原地覆写而非重新分配：没有任何东西以这个列表
  /// 的身份为键，只看它的内容。
  Float64List? animatedSampleKey;

  /// Paint-time cache of the dashed stroke path built from this node's
  /// geometry, with the three inputs it was built from
  /// ([dashedPathSourceKey]/[dashedPathArrayKey]/[dashedPathOffsetKey]). Owned
  /// entirely by `animated_svg_painter.dart`'s `_paintShape`.
  ///
  /// `dashPath` is the most expensive single step in painting a line-md style
  /// icon: it runs `Path.computeMetrics()` — which flattens the contour in
  /// native code — and then extracts a sub-path out of it, per dashed shape
  /// per frame. Yet its output is a pure function of the source path, the dash
  /// pattern and the dash phase, and in the steady state of a real icon all
  /// three are constant: the `stroke-dashoffset` reveal has frozen and the
  /// geometry is already cached, while the icon keeps repainting because a
  /// *transform* is animating. A rotating spinner therefore re-derived a dashed
  /// path it had already built, sixty times a second.
  ///
  /// 由本节点几何构建出的虚线描边路径的绘制期缓存，连同构建它时所用的三个输入
  /// （[dashedPathSourceKey]/[dashedPathArrayKey]/[dashedPathOffsetKey]）。完全由
  /// `animated_svg_painter.dart` 的 `_paintShape` 持有。
  ///
  /// `dashPath` 是绘制 line-md 风格图标里最贵的单个步骤：它要跑
  /// `Path.computeMetrics()`（在原生侧把轮廓展平），再从中抽取一段子路径，且是每个
  /// 虚线形状每帧一次。然而它的输出是"源路径 + 虚线图案 + 虚线相位"的纯函数，而真实
  /// 图标的稳态下这三者都是常量：`stroke-dashoffset` 揭示动画已经定格、几何本就已
  /// 缓存，图标之所以还在重绘是因为有个*变换*在动。于是一个旋转的 spinner 每秒六十次
  /// 重新推导一条它早就构建好的虚线路径。
  ui.Path? cachedDashedPath;

  /// Identity of the source geometry path [cachedDashedPath] was built from —
  /// see that field.
  ///
  /// 构建 [cachedDashedPath] 时所用源几何路径的身份——见该字段。
  Object? dashedPathSourceKey;

  /// Identity of the dash-pattern list [cachedDashedPath] was built from — see
  /// that field. Stable across frames because `ResolvedStyle`'s dash arrays
  /// come from the memo in `svg_style.dart`, which hands back the same list
  /// instance for the same attribute string.
  ///
  /// 构建 [cachedDashedPath] 时所用虚线图案列表的身份——见该字段。它跨帧稳定，
  /// 因为 `ResolvedStyle` 的虚线数组来自 `svg_style.dart` 里的记忆表，同一个属性
  /// 字符串会拿回同一个列表实例。
  Object? dashedPathArrayKey;

  /// Dash phase [cachedDashedPath] was built at — compared by value, since it
  /// is the one input of the three that a `<animate>` typically drives.
  ///
  /// 构建 [cachedDashedPath] 时所用的虚线相位——按值比较，因为三个输入里通常正是
  /// 它被 `<animate>` 驱动。
  double? dashedPathOffsetKey;
}
