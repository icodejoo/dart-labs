// Per-frame painter for the original SMIL animation engine: walks the parsed
// [SvgNode] tree, samples every attached `<animate>` at the current timeline
// position, resolves presentation attributes (inheritance + `currentColor`),
// and draws shapes — dashed strokes included. Original implementation.
//
// 原创 SMIL 动画引擎的逐帧绘制器：遍历解析出的 [SvgNode] 树，在当前时间线
// 位置对每个挂载的 `<animate>` 采样，解析表现属性（继承 + `currentColor`），
// 并绘制形状——含虚线描边。原创实现。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../svg_affine.dart';
import 'smil_animation.dart';

import 'svg_dom.dart';
import 'svg_gradient.dart';
import 'svg_path_data.dart';
import 'svg_style.dart';
import 'svg_theme.dart';
import 'svgx_animation_quality.dart';

/// Paints an [SvgDocument]'s (see `svg_document_parser.dart`) element tree at
/// a given [time] on the animation timeline, scaled from the document's
/// intrinsic size to the paint box.
///
/// A fresh recording every frame is intentional (not a regression from the
/// static path's cached-`ui.Picture` optimization): caching a `Picture` only
/// pays off for content that doesn't change between frames, and an active
/// animation's whole point is to change every frame — see svgx CLAUDE.md
/// architecture notes.
///
/// 在动画时间线上给定的 [time] 时刻，绘制 [SvgDocument]（见
/// `svg_document_parser.dart`）的元素树，并从文档固有尺寸缩放到绘制盒。
///
/// 每帧都重新录制是故意的（并非相对静态路径 `ui.Picture` 缓存优化的倒退）：
/// 缓存 `Picture`只对帧间不变的内容划算，而正在播放的动画本质就是每帧都在
/// 变——见 svgx CLAUDE.md 架构说明。
class AnimatedSvgPainter extends CustomPainter {
  /// Creates the painter, sampling the timeline at whatever [clock] currently
  /// holds.
  ///
  /// [clock] is handed to [CustomPainter.repaint], so a [CustomPaint] using
  /// this painter repaints on every tick **without the owning widget
  /// rebuilding** — the framework skips the build and layout phases entirely
  /// (see the [CustomPainter] class docs). For a one-off render at a fixed
  /// position (tests, offline recording) pass a `ValueNotifier(someDuration)`.
  ///
  /// 创建绘制器，按 [clock] 当前的值对时间线采样。
  ///
  /// [clock] 会交给 [CustomPainter.repaint]，因此使用本绘制器的 [CustomPaint]
  /// 每次 tick 都会重绘，**而持有它的控件不会重建**——框架会完整跳过 build 与
  /// layout 两个阶段（见 [CustomPainter] 类文档）。若只需在固定时刻渲染一次
  /// （测试、离屏录制），传入 `ValueNotifier(某个Duration)` 即可。
  AnimatedSvgPainter({
    required this.root,
    required this.intrinsicSize,
    required this.clock,
    required this.theme,
    required this.fit,
    required this.alignment,
    this.gradients = const {},
    this.clipPaths = const {},
    this.masks = const {},
    this.approximateMasks = _neverApproximate,
    this.quality = SvgXAnimationQuality.exact,
  }) : super(repaint: clock);

  /// Default for [approximateMasks]: never approximate. Keeps every direct
  /// construction of this painter (tests, offline rendering) on the exact
  /// mask pipeline unless a caller deliberately opts in.
  ///
  /// [approximateMasks] 的默认值：永不近似。使本绘制器的每一处直接构造（测试、
  /// 离屏渲染）都走精确 mask 管线，除非调用方明确选择开启。
  static bool _neverApproximate() => false;

  /// Consulted at paint time (not at construction) to decide whether an
  /// eligible `<mask>` may be drawn as a clip path instead of via two
  /// `saveLayer` offscreen passes — see
  /// [SvgXAnimationQuality.approximatesMasksAt].
  ///
  /// A callback rather than a bool because the answer depends on how many
  /// icons are animating *right now*, which changes as cells scroll in and
  /// out without this painter being rebuilt.
  ///
  /// 在绘制时（而非构造时）被询问，用于决定一个合格的 `<mask>` 是否可以改画成
  /// 裁剪路径，而不走两个 `saveLayer` 离屏通道——见
  /// [SvgXAnimationQuality.approximatesMasksAt]。
  ///
  /// 用回调而不是 bool，是因为答案取决于*当下*有多少图标在播放动画，而这个数量
  /// 会随着格子滚进滚出而变化，且不会重建本绘制器。
  final bool Function() approximateMasks;

  /// The quality profile [approximateMasks] resolves against, carried purely
  /// so [shouldRepaint] can notice it changing.
  ///
  /// [approximateMasks] is a closure, and a closure is a fresh object on every
  /// build — comparing it would force a repaint on every rebuild, while
  /// ignoring it would miss a genuine change (reassigning
  /// [SvgXAnimationQuality.defaultQuality] at runtime alters what gets
  /// painted). The immutable profile has value equality, so comparing it
  /// answers "could the painting differ?" correctly in both directions.
  ///
  /// [approximateMasks] 所依据的画质配置，携带它的唯一目的是让 [shouldRepaint]
  /// 能察觉到它发生了变化。
  ///
  /// [approximateMasks] 是闭包，而闭包每次 build 都是新对象——拿它做比较会导致每次
  /// 重建都强制重绘，而完全忽略它则会漏掉真实变化（运行时重新赋值
  /// [SvgXAnimationQuality.defaultQuality] 会改变画出来的东西）。这份不可变配置
  /// 有值相等语义，因此比较它能在两个方向上都正确回答"绘制结果是否可能不同"。
  final SvgXAnimationQuality quality;

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

  /// The animation clock this painter samples. Also drives repaints — see the
  /// constructor.
  ///
  /// 本绘制器采样的动画时钟，同时驱动重绘——见构造函数。
  final ValueListenable<Duration> clock;

  /// Current position on the animation timeline. / 当前所处的动画时间线位置。
  Duration get time => clock.value;

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
    // Clip to the SVG viewport before painting anything. Two reasons, the
    // second one measured:
    //
    //  1. Correctness: the outermost `<svg>` has `overflow: hidden` per the
    //     SVG spec, so content escaping the viewBox must not paint. The static
    //     (usvg) path already behaves this way; this path used to not.
    //  2. Performance — this is why it matters at scale. `_paintNode` opens
    //     `saveLayer` layers for `<mask>` and `feGaussianBlur` with a null
    //     bounds. A null bounds means "unbounded", so the renderer sizes the offscreen
    //     render target from the *current clip*, and `CustomPaint` does not
    //     clip its canvas — the clip was therefore the whole window. Every
    //     masked icon allocated two FULL-SCREEN offscreen textures and two
    //     full-screen render passes per frame, no matter that the icon draws
    //     into 32x32 logical pixels. Measured on a Huawei STG-AL00 (Android
    //     12, Impeller GLES) with ~140 visible line-md icons of which ~23 use
    //     `<mask>`: 56 `saveLayer`s became 57 `RenderPassGLES::
    //     EncodeCommandsInReactor` passes at ~43ms each = ~2450ms per frame.
    //     The screen never updated and the raster thread sat at 100% CPU —
    //     which looked like a driver hang but was simply a frame that took
    //     2.4 seconds. With this clip in place the same layers are sized to
    //     the icon box instead of the window.
    //
    // 绘制任何内容前先裁剪到 SVG 视口。两个原因，第二个是实测得出的：
    //
    //  1. 正确性：按 SVG 规范，最外层 `<svg>` 的 `overflow` 默认为 hidden，
    //     超出 viewBox 的内容不应绘制。静态（usvg）路径本来就是这个行为，
    //     而本路径此前没有。
    //  2. 性能——这才是规模化时的关键。`_paintNode` 会为 `<mask>` 与
    //     `feGaussianBlur` 开 `saveLayer(null, ...)` 图层。bounds 传 null 意味
    //     着"无界"，渲染器于是按*当前裁剪区*来决定离屏渲染目标的尺寸，而
    //     `CustomPaint` 并不裁剪自己的画布——于是裁剪区就是整个窗口。每个带
    //     mask 的图标每帧都要分配两张**全屏**离屏纹理、跑两个全屏渲染通道，
    //     哪怕这个图标只画在 32x32 逻辑像素里。在华为 STG-AL00（Android 12，
    //     Impeller GLES）上实测：约 140 个可见 line-md 图标中约 23 个用了
    //     `<mask>`，56 次 `saveLayer` 变成 57 个
    //     `RenderPassGLES::EncodeCommandsInReactor` 通道、每个约 43ms，
    //     合计每帧约 2450ms。屏幕因此始终不更新、raster 线程 100% CPU——看着
    //     像驱动挂死，实际只是一帧要画 2.4 秒。加上这个裁剪后，同样的图层会
    //     按图标盒子而不是按窗口来分配尺寸。
    canvas.clipRect(
      Rect.fromLTWH(0, 0, intrinsicSize.width, intrinsicSize.height),
    );
    _paintNode(canvas, root, ResolvedStyle.initial);
    canvas.restore();
  }

  /// [node]'s attributes with this frame's sampled `<animate>` values
  /// overlaid.
  ///
  /// Returns [SvgNode.attributes] itself — no copy — for a node carrying no
  /// `<animate>`, which is most nodes in a real animated icon (the root, the
  /// groups, and every shape that is only *inherited* into rather than
  /// animated). Callers treat the result as read-only, so sharing the node's
  /// own map is safe. The copy this avoids was allocated once per node per
  /// frame.
  ///
  /// A node WITH `<animate>`s must get a genuinely fresh [Map] every frame —
  /// [_geometryPath] relies on that fresh-instance identity as a cheap
  /// "did this shape's inputs change" cache-invalidation signal for every
  /// shape kind besides `<path>` (see its doc comment). A reused,
  /// mutated-in-place map was tried here and reverted: it broke that
  /// invalidation (the identity never changes once reused), silently
  /// freezing animated `<rect>`/`<circle>`/etc. geometry at whatever shape
  /// was cached on the first frame — caught by
  /// `test/animation/effective_attributes_reuse_test.dart`.
  ///
  /// [node] 的属性表，叠加本帧已采样的 `<animate>` 值。
  ///
  /// 节点自身没有 `<animate>` 时直接返回 [SvgNode.attributes] 本身——不拷贝；
  /// 真实动画图标里大多数节点都属于这种情况（根节点、各分组，以及所有只是被
  /// 继承而非被动画驱动的形状）。调用方只读使用返回值，因此共享节点自身的表是
  /// 安全的。被省掉的这次拷贝原本是每节点每帧一次。
  ///
  /// 带 `<animate>` 的节点每帧必须拿到一份真正全新的 [Map]——除 `<path>`
  /// 外的每种形状，[_geometryPath] 都靠这份全新实例的身份，作为"这个形状的
  /// 输入是否变了"的廉价缓存失效信号（见其文档注释）。这里曾试过跨帧复用、
  /// 原地修改的表，后来回滚：它破坏了那个失效机制（复用后身份永不再变），
  /// 悄悄把带动画的 `<rect>`/`<circle>` 等几何冻结在第一帧缓存的形状上——由
  /// `test/animation/effective_attributes_reuse_test.dart` 捕获。
  /// `attributes[key]` parsed as a double, or [fallback] when absent/invalid.
  ///
  /// `attributes[key]` 解析为 double；缺失或非法时返回 [fallback]。
  static double _num(
    Map<String, String> attributes,
    String key, [
    double fallback = 0,
  ]) => double.tryParse(attributes[key] ?? '') ?? fallback;

  /// [node]'s presentation style with [inherited] folded in, reusing the
  /// result cached on the node when the three inputs it was resolved from are
  /// unchanged (see [SvgNode.cachedStyle]).
  ///
  /// `ResolvedStyle.inherit` is not cheap for something that ran once per node
  /// per frame: roughly a dozen string-keyed map lookups, up to four colour /
  /// url / dash parses, and a fresh [ResolvedStyle] allocation. Yet in a real
  /// animated icon almost every node's style is *constant* — a line-md icon
  /// animates `stroke-dashoffset` or a transform, while `fill`, `stroke`,
  /// `stroke-width` and friends never move. The cache turns that whole
  /// computation into three [identical] checks for the static majority.
  ///
  /// Validity is proven by identity on all three inputs rather than by value
  /// equality, which is both cheaper and conservative — a false miss only
  /// costs a recompute, and a false hit is impossible. See
  /// [SvgNode.cachedStyle] for why each input's identity is stable exactly
  /// when the style genuinely cannot have changed.
  ///
  /// 返回把 [inherited] 折叠进去后 [node] 的表现样式；当解析它所依赖的三个输入
  /// 都没变时，直接复用挂在节点上的缓存结果（见 [SvgNode.cachedStyle]）。
  ///
  /// 对一个"每节点每帧都要跑一次"的操作来说，`ResolvedStyle.inherit` 并不便宜：
  /// 大约十几次以字符串为键的 map 查找、最多四次颜色/url/虚线解析，以及一次
  /// 全新的 [ResolvedStyle] 分配。然而真实动画图标里几乎每个节点的样式都是
  /// *恒定*的——line-md 风格图标动的是 `stroke-dashoffset` 或某个变换，而
  /// `fill`、`stroke`、`stroke-width` 之类从不变化。这个缓存把静态的大多数节点
  /// 的整套计算压成三次 [identical] 比较。
  ///
  /// 有效性用三个输入的身份比较来证明，而不是值相等：既更便宜，又是保守的
  /// ——误判未命中只损失一次重算，误判命中不可能发生。每个输入的身份为何恰好在
  /// "样式确实不可能变化"时保持稳定，见 [SvgNode.cachedStyle]。
  ResolvedStyle _resolveStyle(
    SvgNode node,
    ResolvedStyle inherited,
    Map<String, String> attributes,
  ) {
    final cached = node.cachedStyle;
    if (cached != null &&
        identical(node.styleInheritedKey, inherited) &&
        identical(node.styleAttributesKey, attributes) &&
        identical(node.styleThemeKey, theme)) {
      return cached as ResolvedStyle;
    }
    final resolved = inherited.inherit(attributes, theme);
    node
      ..cachedStyle = resolved
      ..styleInheritedKey = inherited
      ..styleAttributesKey = attributes
      ..styleThemeKey = theme;
    return resolved;
  }

  Map<String, String> _effectiveAttributes(SvgNode node) {
    if (node.animations.isEmpty) return node.attributes;
    final overlaid = Map<String, String>.of(node.attributes);
    for (final animation in node.animations) {
      final sampled = animation.sample(time);
      if (sampled != null) {
        overlaid[animation.attributeName] = sampled.toString();
      }
    }
    return overlaid;
  }

  /// Paints [node] at its position in the tree, resolving its animated style
  /// and any static/animated transforms.
  ///
  /// [nested] marks content being painted *as* a `<clipPath>`/`<mask>`
  /// definition's body (via [clipPaths]/[masks]): SVG's nested-mask/clip is
  /// out of scope, so nested content never itself looks up a further
  /// `clip-path`/`mask` reference (the nearest ancestor's clip/mask already
  /// won) — see svgx CLAUDE.md task notes.
  ///
  /// 在树中的位置绘制 [node]，解析其动画样式及任何静态/动画变换。
  ///
  /// [nested] 标记正在作为 `<clipPath>`/`<mask>` 定义体（经
  /// [clipPaths]/[masks]）绘制的内容：SVG 的嵌套 mask/clip 不在范围内，因此
  /// 嵌套内容自身永不再查找 `clip-path`/`mask` 引用（最近祖先的裁剪/遮罩已经
  /// 生效）——见 svgx CLAUDE.md 任务记录。
  void _paintNode(
    Canvas canvas,
    SvgNode node,
    ResolvedStyle inherited, {
    bool nested = false,
  }) {
    final effectiveAttributes = _effectiveAttributes(node);
    final style = _resolveStyle(node, inherited, effectiveAttributes);

    // The id checks come first so the overwhelming majority of nodes — which
    // reference neither a `<clipPath>` nor a `<mask>` — skip two map lookups
    // per node per frame instead of hashing a null key twice.
    //
    // 先做 id 判空，使绝大多数既不引用 `<clipPath>` 也不引用 `<mask>` 的节点
    // 每帧省掉两次 map 查找，而不是拿 null 键去哈希两次。
    final clipPathId = node.clipPathId;
    final maskId = node.maskId;
    final clipDef = (nested || clipPathId == null)
        ? null
        : clipPaths[clipPathId];
    var maskDef = (nested || maskId == null) ? null : masks[maskId];
    // LOSSY FAST PATH, off by default and concurrency-gated by the caller
    // (see [approximateMasks]): a `<mask>` whose content is nothing but
    // fully-opaque pure-black/pure-white fills expresses a *binary* coverage
    // region, and a binary coverage region is exactly what a clip path is.
    // Drawing it as a clip removes both of this mask's `saveLayer`s — measured
    // on a Huawei STG-AL00 (Impeller GLES) at ~221us of GPU render-pass time
    // each, the single largest line item in the batch-animation raster budget
    // (see docs/performance-benchmarks.md).
    //
    // What is given up, precisely: edge antialiasing. The exact pipeline
    // rasterizes the mask into a layer and multiplies its coverage into the
    // content's alpha, so an edge is a smooth alpha ramp; a clip path
    // antialiases the edge itself, which on Impeller is a slightly different
    // (marginally harder) ramp. At icon sizes this is a sub-pixel difference
    // along the mask boundary and nothing else — no geometry moves, no colour
    // shifts, and the animation of the mask's own content is still resampled
    // every frame exactly as before. Masks that would lose more than that
    // (any stroke paint, any opacity, any non-binary colour, any gradient,
    // nested clip/mask/blur) are rejected by [_maskIsClipEligible] and keep
    // the exact pipeline.
    //
    // 有损快路径，默认关闭，且由调用方做并发门控（见 [approximateMasks]）：内容
    // 只有完全不透明的纯黑/纯白填充的 `<mask>`，表达的是一个*二值*覆盖区域，而
    // 二值覆盖区域正是裁剪路径本身。把它画成裁剪可以去掉该 mask 的两个
    // `saveLayer`——在华为 STG-AL00（Impeller GLES）上实测每个约 221us 的 GPU
    // 渲染通道时间，是批量动画 raster 预算里最大的单项（见
    // docs/performance-benchmarks.md）。
    //
    // 确切放弃了什么：边缘抗锯齿。精确管线把 mask 光栅化进一个图层，再把它的覆盖度
    // 乘进内容的 alpha，因此边缘是一条平滑的 alpha 斜坡；裁剪路径则对边缘本身做
    // 抗锯齿，在 Impeller 上是一条略有不同（略硬）的斜坡。在图标尺寸下，这就是沿
    // mask 边界的一个亚像素差异，仅此而已——没有任何几何位移、没有任何颜色偏移，
    // 且 mask 自身内容的动画仍然像以前一样逐帧重采样。会损失更多的 mask（任何描边
    // 涂料、任何不透明度、任何非二值颜色、任何渐变、嵌套的 clip/mask/模糊）都会被
    // [_maskIsClipEligible] 拒掉，继续走精确管线。
    final blurSigma = node.blurSigma;
    final hasBlur = blurSigma != null && blurSigma > 0;
    ui.Path? maskClip;
    // `!hasBlur` is not a performance guard, it is a correctness one. The
    // exact pipeline nests the layers to produce `Mask(Blur(content))`; a clip
    // installed on the canvas is inherited by the blur layer opened below it,
    // which would instead produce `Blur(Mask(content))` — the blur would be
    // clipped off at the mask boundary rather than the mask being applied to
    // the already-spread blur. A node carrying both therefore keeps the exact
    // pipeline. (Rejecting blur *inside* the mask definition is a separate
    // check, in [_maskSubtreeIsBinary].)
    //
    // `!hasBlur` 不是性能护栏，是正确性护栏。精确管线通过图层嵌套产出的是
    // `Mask(Blur(content))`；而装在画布上的裁剪会被其下开启的模糊图层继承，于是
    // 产出的变成 `Blur(Mask(content))`——模糊会在 mask 边界处被切掉，而不是让
    // mask 作用于已经扩散开的模糊结果。因此同时带这两者的节点保持精确管线。
    //（拒绝 mask 定义*内部*的模糊是另一项检查，在 [_maskSubtreeIsBinary] 里。）
    if (maskDef != null && !hasBlur) {
      final asClip = approximateMasks();
      if (asClip && _maskIsClipEligible(maskDef)) {
        maskClip = _resolveMaskClipPath(maskDef, time);
        maskDef = null;
      }
    }
    final needsClipMaskSave =
        clipDef != null || maskDef != null || maskClip != null;
    if (needsClipMaskSave) canvas.save();
    if (clipDef != null) canvas.clipPath(_resolveClipPath(clipDef, time));
    if (maskClip != null) canvas.clipPath(maskClip);
    // Layer nesting follows SVG's filter -> mask pipeline: the mask
    // destination layer opens FIRST (outer) and the blur layer opens SECOND
    // (inner, nested inside it), so closing the blur layer composites
    // blurred content into the mask-destination layer, and the mask is then
    // applied to that already-blurred result — i.e. `Mask(Blur(content))`,
    // not `Blur(Mask(content))`.
    //
    // 图层嵌套遵循 SVG 的 filter -> mask 管线：遮罩目标图层*先*开（外层），
    // 模糊图层*后*开（内层，嵌套其中）——这样关闭模糊图层时，模糊后的内容
    // 会合成进遮罩目标图层，遮罩随后作用于这个已经模糊过的结果，即
    // `Mask(Blur(content))`，而非 `Blur(Mask(content))`。
    //
    // The destination layer mask content composites into via BlendMode.dstIn
    // (see _maskCoveragePaint) — opened now so it wraps everything painted
    // below, including any transform this node applies.
    //
    // mask 内容经 BlendMode.dstIn（见 _maskCoveragePaint）合成进的目标图层——
    // 现在开启，使其包裹下方绘制的一切，包括本节点应用的任何变换。
    if (maskDef != null) canvas.saveLayer(null, Paint());
    // feGaussianBlur: paint this node (and its subtree) into an offscreen
    // layer, then blur the whole layer on composite — rather than blurring
    // each stroke/fill individually, which is what SVG's filter semantics
    // require (the filter applies to the element's *rendered result*, not
    // its paint).
    //
    // feGaussianBlur：把本节点（含子树）绘制进一个离屏图层，合成时对整个图层
    // 做模糊——而非逐笔画/填充分别模糊，这才符合 SVG 滤镜语义（滤镜作用于元素
    // 的*渲染结果*，而非其涂料本身）。
    if (hasBlur) {
      canvas.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
      );
    }

    if (node.transformAnimations.isEmpty &&
        node.motionAnimations.isEmpty &&
        node.transform == null) {
      _paintNodeContent(canvas, node, style, effectiveAttributes);
      if (hasBlur) canvas.restore();
      if (maskDef != null) {
        _applyMaskLayer(canvas, maskDef);
      }
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
    if (staticTransform != null) {
      // Expanded once and kept on the node: `transform` is final and fixed at
      // parse time, so the 4x4 form can never go stale (see
      // [SvgNode.cachedTransformMatrix]). Previously every transformed node
      // allocated a fresh Float64List(16) on every frame.
      //
      // 只展开一次并挂在节点上：`transform` 是 final 且在解析阶段就固定，4x4
      // 形式不可能失效（见 [SvgNode.cachedTransformMatrix]）。此前每个带变换的
      // 节点每帧都要新分配一个 Float64List(16)。
      canvas.transform(
        node.cachedTransformMatrix ??= affineToMatrix4(staticTransform),
      );
    }
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
          canvas.transform(
            affineToMatrix4([
              1,
              0,
              math.tan(sampled[0] * math.pi / 180),
              1,
              0,
              0,
            ]),
          );
        case SmilTransformType.skewY:
          // skewY(a) = matrix(1, tan(a), 0, 1, 0, 0)
          canvas.transform(
            affineToMatrix4([
              1,
              math.tan(sampled[0] * math.pi / 180),
              0,
              1,
              0,
              0,
            ]),
          );
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
      if (sampled.angleDegrees != 0) {
        canvas.rotate(sampled.angleDegrees * math.pi / 180);
      }
    }
    _paintNodeContent(canvas, node, style, effectiveAttributes);
    canvas.restore(); // closes the transform save() a few lines above

    if (hasBlur) canvas.restore();
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

  /// Whether [defRoot], used as a `<mask>` definition, can be replaced by an
  /// equivalent clip path — cached on the node, since the answer depends only
  /// on parse-time structure (see [SvgNode.maskClipEligible]).
  ///
  /// 作为 `<mask>` 定义使用的 [defRoot] 能否用等价裁剪路径替代——结果缓存在节点
  /// 上，因为答案只取决于解析期的结构（见 [SvgNode.maskClipEligible]）。
  ///
  /// [defRoot] — the mask definition's root node. / mask 定义的根节点。
  ///
  /// Returns true when the mask is pure binary coverage.
  ///
  ///   mask 为纯二值覆盖时返回 true。
  static bool _maskIsClipEligible(SvgNode defRoot) =>
      defRoot.maskClipEligible ??= _maskSubtreeIsBinary(defRoot, null);

  /// Recursive half of [_maskIsClipEligible]. [inheritedFill] is the nearest
  /// ancestor's `fill` value, threaded down because a `<g fill="#fff">`
  /// wrapper is how real icons paint a whole mask subtree white.
  ///
  /// [_maskIsClipEligible] 的递归部分。[inheritedFill] 是最近祖先的 `fill` 值，
  /// 向下传递是因为真实图标正是用 `<g fill="#fff">` 这样的包装分组把整个 mask
  /// 子树刷白的。
  ///
  /// [node] — subtree root to inspect. / 待检查的子树根。
  ///
  /// [inheritedFill] — inherited `fill` attribute value, or null.
  ///
  ///   继承到的 `fill` 属性值，或 null。
  ///
  /// Returns true when every node in the subtree is binary-safe.
  ///
  ///   子树内每个节点都二值安全时返回 true。
  static bool _maskSubtreeIsBinary(SvgNode node, String? inheritedFill) {
    // A nested clip/mask/blur inside the mask means coverage this flat clip
    // path cannot represent.
    //
    // mask 内部嵌套 clip/mask/模糊，意味着这条扁平裁剪路径无法表达的覆盖度。
    if (node.clipPathId != null ||
        node.maskId != null ||
        (node.blurSigma != null && node.blurSigma! > 0)) {
      return false;
    }
    final attributes = node.attributes;
    // Any opacity at all makes coverage fractional; a clip is all-or-nothing.
    // `style` is rejected wholesale rather than parsed — it could carry any of
    // the above through a channel this check does not read.
    //
    // 任何不透明度都会让覆盖度变成分数值，而裁剪是全有或全无。`style` 整体拒掉而
    // 不去解析——它可能通过本检查读不到的渠道携带上述任意一项。
    if (attributes.containsKey('opacity') ||
        attributes.containsKey('fill-opacity') ||
        attributes.containsKey('stroke-opacity') ||
        attributes.containsKey('style')) {
      return false;
    }
    for (final animation in node.animations) {
      // Any opacity keyframe makes coverage fractional at some instant.
      // 任何不透明度关键帧都会让某个时刻的覆盖度变成分数值。
      if (animation.attributeName.contains('opacity')) return false;
      // A keyframe on `fill` would let the coverage class change *after* this
      // eligibility answer has been cached on the node — the cache is keyed on
      // parse-time structure precisely because nothing here may vary with
      // time. (Numeric `<animate>` on `fill` is a documented gap in this
      // engine, so such a document is malformed anyway; rejecting it keeps the
      // fast path's invariant true regardless.)
      //
      // 作用在 `fill` 上的关键帧会让覆盖度分类在这个合格性结论被缓存到节点上
      // *之后*发生变化——而缓存之所以以解析期结构为键，恰恰是因为这里的任何东西
      // 都不允许随时间变化。（数值型 `<animate>` 作用于 `fill` 是本引擎已记录的
      // 缺口，这样的文档本身就是畸形的；无论如何拒掉它都能让快路径的不变式成立。）
      if (animation.attributeName == 'fill') return false;
    }
    // Colour keyframes could animate a fill from white to a mid grey.
    // 颜色关键帧可能把填充从白色动画到中间灰。
    if (node.colorAnimations.isNotEmpty) return false;
    // Stroke paint would need a stroke outline to become a clip path, and
    // dart:ui exposes no stroke-to-path conversion — these masks keep the
    // exact pipeline. This is the single biggest reason for rejection in real
    // icon sets (34 of 65 mask definitions in the benchmark corpus).
    //
    // 描边涂料要变成裁剪路径需要 stroke outline，而 dart:ui 没有暴露
    // stroke 转 path 的能力——这类 mask 保持精确管线。这是真实图标集里最主要的
    // 拒绝原因（基准语料 65 个 mask 定义里有 34 个）。
    final stroke = attributes['stroke'];
    if (stroke != null && stroke != 'none') return false;

    final fill = attributes['fill'] ?? inheritedFill;
    switch (node.kind) {
      case SvgNodeKind.root:
      case SvgNodeKind.group:
        break; // paints nothing itself
      case SvgNodeKind.path:
      case SvgNodeKind.circle:
      case SvgNodeKind.rect:
      case SvgNodeKind.ellipse:
      case SvgNodeKind.polygon:
        if (_maskFillCoverage(fill) == _MaskCoverage.notBinary) return false;
      case SvgNodeKind.line:
      case SvgNodeKind.polyline:
        // Unclosed geometry: SVG fills it by implicit closure, and matching
        // that exactly through a clip path is not worth the risk of getting
        // the winding wrong on content that is almost always stroke-painted
        // anyway (and stroke paint is already rejected above).
        //
        // 未闭合几何：SVG 会按隐式闭合来填充，而这类内容几乎总是用描边绘制的
        // （而描边在上面已经被拒），为它精确匹配裁剪路径的绕行规则不值得冒错的
        // 风险。
        return false;
      case SvgNodeKind.text:
      case SvgNodeKind.image:
        // Glyph coverage and bitmap alpha are not geometry.
        // 字形覆盖度与位图 alpha 都不是几何图形。
        return false;
    }
    for (final child in node.children) {
      if (!_maskSubtreeIsBinary(child, fill)) return false;
    }
    return true;
  }

  /// Classifies what a mask shape's `fill` contributes to coverage.
  ///
  /// 把一个 mask 形状的 `fill` 对覆盖度的贡献分类。
  ///
  /// [fill] — the resolved `fill` attribute value, or null when neither the
  ///   shape nor any ancestor set one.
  ///
  ///   已解析的 `fill` 属性值；形状自身与所有祖先都没设置时为 null。
  ///
  /// Returns the coverage classification. / 返回覆盖度分类。
  static _MaskCoverage _maskFillCoverage(String? fill) {
    // `fill="none"` paints nothing at all. That is NOT the same as painting
    // black: black *removes* coverage where it overlaps something white,
    // whereas an unpainted shape leaves whatever is underneath alone. Folding
    // the two together would punch phantom holes wherever a `fill="none"`
    // outline crossed a white region.
    //
    // `fill="none"` 什么都不画。这与"画黑色"**不是**一回事：黑色会在与白色重叠处
    // *去掉*覆盖度，而未被绘制的形状则不影响其下方的任何东西。把两者混为一谈，
    // 会在每一处 `fill="none"` 轮廓穿过白色区域的地方打出不该有的洞。
    if (fill == 'none') return _MaskCoverage.paintsNothing;
    // No `fill` anywhere up the chain: SVG's initial value is black, which in
    // a mask means "hide".
    //
    // 整条继承链上都没有 `fill`：SVG 的初始值是黑色，在 mask 里意味着"隐藏"。
    if (fill == null) return _MaskCoverage.hides;
    final color = parseSvgHexColor(fill);
    // A gradient, `currentColor`, or anything unparseable: not binary.
    // 渐变、`currentColor`，或任何解析不出来的东西：不是二值。
    if (color == null) return _MaskCoverage.notBinary;
    if (color.a < 1) {
      return _MaskCoverage.notBinary; // translucent: fractional coverage
    }
    // SVG luminanceToAlpha, the same coefficients [_maskCoveragePaint] uses.
    // SVG 的 luminanceToAlpha，与 [_maskCoveragePaint] 用的是同一组系数。
    final luminance = 0.2125 * color.r + 0.7154 * color.g + 0.0721 * color.b;
    if (luminance >= 0.999) return _MaskCoverage.shows;
    if (luminance <= 0.001) return _MaskCoverage.hides;
    return _MaskCoverage.notBinary; // mid grey: genuinely partial coverage
  }

  /// Builds the clip path standing in for an eligible `<mask>`: the union of
  /// its full-coverage (white) geometry, minus the union of its no-coverage
  /// (black) geometry, with every node's static/animated transform sampled at
  /// [time] exactly as [_resolveClipPath] does.
  ///
  /// The subtraction approximates SVG's painting order — in the exact
  /// pipeline a black shape painted *after* a white one erases the overlap,
  /// while one painted *before* it is covered up again. Flattening both into
  /// one difference gets the common case (holes punched into a white region)
  /// right and the reversed case wrong; real mask content in icon sets does
  /// not rely on the reversed case.
  ///
  /// 构建替代合格 `<mask>` 的裁剪路径：其完全覆盖（白色）几何的并集，减去无覆盖
  /// （黑色）几何的并集，每个节点的静态/动画变换都在 [time] 采样，与
  /// [_resolveClipPath] 完全一致。
  ///
  /// 这个相减是对 SVG 绘制顺序的近似——精确管线里，画在白色形状*之后*的黑色形状
  /// 会擦掉重叠部分，而画在它*之前*的则会被重新盖住。把两者压平成一次相减，能把
  /// 常见情形（在白色区域上打洞）做对，反向情形做错；图标集里真实的 mask 内容不
  /// 依赖反向情形。
  ///
  /// [defRoot] — the mask definition's root node. / mask 定义的根节点。
  ///
  /// [time] — timeline position to sample at. / 采样的时间线位置。
  ///
  /// Returns the substitute clip path. / 返回替代用的裁剪路径。
  ui.Path _resolveMaskClipPath(SvgNode defRoot, Duration time) {
    // Cheap pass first: sample every animation in the mask subtree into a flat
    // signature, touching no attribute maps, allocating no matrices and
    // copying no path segments. If it matches the signature the cached path
    // was built from, that path is still correct and the expensive pass is
    // skipped entirely — see [SvgNode.cachedMaskClip].
    //
    // 先跑廉价的一趟：把 mask 子树里每个动画采样成一条扁平签名，不碰属性表、不分配
    // 矩阵、不复制路径线段。若它与缓存路径构建时的签名一致，那条路径依然正确，昂贵
    // 的那一趟就完全跳过——见 [SvgNode.cachedMaskClip]。
    final signature = _maskSampleSignature(defRoot, time);
    final cachedPath = defRoot.cachedMaskClip;
    if (cachedPath != null &&
        _sameSignature(defRoot.maskClipSampleKey, signature)) {
      return cachedPath;
    }
    final shown = ui.Path();
    final hidden = ui.Path();
    var anyHidden = false;

    void walk(SvgNode node, List<double> matrix, String? inheritedFill) {
      final effectiveAttributes = _effectiveAttributes(node);
      var accum = matrix;
      if (node.transform != null) accum = concatAffine(accum, node.transform!);
      for (final transformAnimation in node.transformAnimations) {
        final sampled = transformAnimation.sample(time);
        if (sampled == null) continue;
        accum = concatAffine(
          accum,
          _transformSampleToAffine(transformAnimation.type, sampled),
        );
      }
      for (final motion in node.motionAnimations) {
        final sampled = motion.sample(time);
        if (sampled == null) continue;
        accum = concatAffine(accum, [1, 0, 0, 1, sampled.x, sampled.y]);
      }
      final fill = effectiveAttributes['fill'] ?? inheritedFill;

      if (node.kind == SvgNodeKind.root || node.kind == SvgNodeKind.group) {
        for (final child in node.children) {
          walk(child, accum, fill);
        }
        return;
      }
      final coverage = _maskFillCoverage(fill);
      // Nothing is painted, so nothing is contributed — in particular this
      // shape must NOT be subtracted. See [_maskFillCoverage].
      //
      // 什么都没画，因此什么都不贡献——尤其是这个形状**不能**被减掉。见
      // [_maskFillCoverage]。
      if (coverage == _MaskCoverage.paintsNothing) return;
      final geometry = _geometryPath(node, effectiveAttributes);
      if (geometry == null) return;
      final matrix4 = affineToMatrix4(accum);
      if (coverage == _MaskCoverage.shows) {
        shown.addPath(geometry, Offset.zero, matrix4: matrix4);
      } else {
        hidden.addPath(geometry, Offset.zero, matrix4: matrix4);
        anyHidden = true;
      }
    }

    walk(defRoot, const [1, 0, 0, 1, 0, 0], null);
    // `Path.combine` allocates a fresh path and runs a real boolean op, so it
    // is skipped entirely for the common mask that only paints white.
    //
    // It is also fallible: dart:ui throws `Bad state: Path.combine() failed`
    // on degenerate input, and a mask whose geometry is driven by SMIL can be
    // degenerate at particular instants (a `<rect>` animated through zero
    // size, a transform sampled to a singular matrix). This was hit by real
    // corpus data in `benchmark/bench_app/test/mask_clip_cost_bench_test.dart`
    // while sweeping 60 consecutive frames — a single fixed sample instant had
    // not exposed it. A throw here would take down a whole frame for what is
    // only an optional fast path, so a failure falls back to the union without
    // the subtraction: the same coverage the exact pipeline would produce
    // minus the holes, which is the conservative direction (it shows slightly
    // too much rather than erasing the icon).
    //
    // `Path.combine` 会新分配一条路径并跑一次真正的布尔运算，因此对"只画白色"
    // 的常见 mask 完全跳过它。
    //
    // 它同时也是会失败的：输入退化时 dart:ui 会抛
    // `Bad state: Path.combine() failed`，而由 SMIL 驱动几何的 mask 在某些特定
    // 时刻确实可能退化（`<rect>` 被动画到零尺寸、变换被采样成奇异矩阵）。这是
    // `benchmark/bench_app/test/mask_clip_cost_bench_test.dart` 连续扫 60 帧时被
    // 真实语料数据撞出来的——只采样单个固定时刻则暴露不出来。在这里抛异常会为了
    // 一条纯属可选的快路径而毁掉一整帧，因此失败时退回"不做相减的并集"：与精确
    // 管线相同的覆盖度、只是少了那些洞，这是保守方向（宁可多显示一点，也不要把
    // 图标擦掉）。
    var built = shown;
    if (anyHidden) {
      try {
        built = ui.Path.combine(ui.PathOperation.difference, shown, hidden);
      } on StateError {
        built = shown;
      }
    }
    defRoot
      ..cachedMaskClip = built
      ..maskClipSampleKey = signature;
    return built;
  }

  /// Flattens every sampled animation value in a `<mask>` definition's subtree
  /// into one list, in a fixed document order — the cache key for
  /// [SvgNode.cachedMaskClip].
  ///
  /// Reads the timelines directly instead of going through
  /// [_effectiveAttributes], so the fast path allocates one growable list and
  /// nothing else: no per-node attribute map, no matrices, no paths. A
  /// timeline that has not begun (or ended without freezing) samples to null,
  /// which is recorded as a distinct marker so "not yet started" and "started
  /// at value 0" never collide.
  ///
  /// 把一个 `<mask>` 定义子树内所有已采样的动画值按固定的文档顺序压平成一个列表
  /// ——[SvgNode.cachedMaskClip] 的缓存键。
  ///
  /// 直接读时间线而不经过 [_effectiveAttributes]，因此快路径只分配一个可增长列表、
  /// 别无其它：没有逐节点属性表、没有矩阵、没有路径。尚未开始（或已结束且不定格）
  /// 的时间线采样为 null，会被记为一个独立标记，因此"还没开始"与"已开始且值为 0"
  /// 绝不会混淆。
  ///
  /// [defRoot] — the mask definition's root node. / mask 定义的根节点。
  ///
  /// [time] — timeline position to sample at. / 采样的时间线位置。
  ///
  /// Returns the flattened signature. / 返回压平后的签名。
  List<double> _maskSampleSignature(SvgNode defRoot, Duration time) {
    // Sentinel for "this timeline produced no value at this instant". Any
    // finite sampled number is a legitimate value, so the marker has to be a
    // non-finite one; negative infinity compares equal to itself (unlike NaN,
    // which would make every comparison miss).
    //
    // "该时间线在此刻没有产出值"的哨兵。任何有限的采样数都是合法值，所以标记必须
    // 取一个非有限值；负无穷与自身比较相等（不像 NaN，用 NaN 会让每次比较都未命中）。
    const absent = double.negativeInfinity;
    final signature = <double>[];
    void walk(SvgNode node) {
      for (final animation in node.animations) {
        final sampled = animation.sample(time);
        signature.add(sampled ?? absent);
      }
      for (final transformAnimation in node.transformAnimations) {
        final sampled = transformAnimation.sample(time);
        if (sampled == null) {
          signature.add(absent);
        } else {
          signature.addAll(sampled);
        }
      }
      for (final motion in node.motionAnimations) {
        final sampled = motion.sample(time);
        if (sampled == null) {
          signature.add(absent);
        } else {
          signature
            ..add(sampled.x)
            ..add(sampled.y)
            ..add(sampled.angleDegrees);
        }
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(defRoot);
    return signature;
  }

  /// Whether two mask sample signatures describe the same frame.
  ///
  /// 两条 mask 采样签名是否描述同一帧。
  ///
  /// [cached] — the signature the cached path was built from, or null.
  ///
  ///   缓存路径构建时所用的签名，或 null。
  ///
  /// [current] — this frame's signature. / 本帧的签名。
  ///
  /// Returns true when the cached path is still valid.
  ///
  ///   缓存路径仍然有效时返回 true。
  static bool _sameSignature(List<double>? cached, List<double> current) {
    if (cached == null || cached.length != current.length) return false;
    for (var i = 0; i < cached.length; i++) {
      if (cached[i] != current[i]) return false;
    }
    return true;
  }

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
      final effectiveAttributes = _effectiveAttributes(node);
      var accum = matrix;
      if (node.transform != null) accum = concatAffine(accum, node.transform!);
      for (final transformAnimation in node.transformAnimations) {
        final sampled = transformAnimation.sample(time);
        if (sampled == null) continue;
        accum = concatAffine(
          accum,
          _transformSampleToAffine(transformAnimation.type, sampled),
        );
      }

      if (node.kind == SvgNodeKind.root || node.kind == SvgNodeKind.group) {
        for (final child in node.children) {
          walk(child, accum);
        }
        return;
      }
      final geometry = _geometryPath(node, effectiveAttributes);
      if (geometry == null) return;
      // `Path.transform` *returns* a transformed copy and leaves the receiver
      // alone (dart:ui docs: "Returns a copy of the path with all the segments
      // of every sub-path transformed by the given matrix"). This used to be
      // written as a bare `geometry.transform(...)` statement whose result was
      // dropped, so a transform inside a `<clipPath>` was silently ignored and
      // a whole Path copy was allocated per clip node per frame for nothing.
      // `addPath`'s own `matrix4` applies the transform as the segments are
      // appended — correct, and with no intermediate copy.
      //
      // `Path.transform` 是**返回**一份变换后的副本、不动接收者的（dart:ui 文档：
      // "Returns a copy of the path with all the segments of every sub-path
      // transformed by the given matrix"）。这里原先写成了裸的
      // `geometry.transform(...)` 语句、返回值被丢弃，于是 `<clipPath>` 内部的
      // 变换被静默忽略，同时每个裁剪节点每帧还白白分配了一整份 Path 副本。
      // 改用 `addPath` 自带的 `matrix4`，在追加线段时就地应用变换——既正确，
      // 又不产生中间副本。
      union.addPath(geometry, Offset.zero, matrix4: affineToMatrix4(accum));
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
  static List<double> _transformSampleToAffine(
    SmilTransformType type,
    List<double> sampled,
  ) {
    switch (type) {
      case SmilTransformType.translate:
        return [1, 0, 0, 1, sampled[0], sampled[1]];
      case SmilTransformType.scale:
        return [sampled[0], 0, 0, sampled[1], 0, 0];
      case SmilTransformType.rotate:
        final rad = sampled[0] * math.pi / 180;
        final cosr = math.cos(rad), sinr = math.sin(rad);
        final cx = sampled[1], cy = sampled[2];
        final rotation = concatAffine(
          [1, 0, 0, 1, cx, cy],
          [cosr, sinr, -sinr, cosr, 0, 0],
        );
        return concatAffine(rotation, [1, 0, 0, 1, -cx, -cy]);
      case SmilTransformType.skewX:
        return [1, 0, math.tan(sampled[0] * math.pi / 180), 1, 0, 0];
      case SmilTransformType.skewY:
        return [1, math.tan(sampled[0] * math.pi / 180), 0, 1, 0, 0];
    }
  }

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
  void _paintNodeContent(
    Canvas canvas,
    SvgNode node,
    ResolvedStyle style,
    Map<String, String> attributes,
  ) {
    switch (node.kind) {
      case SvgNodeKind.root:
      case SvgNodeKind.group:
        // Indexed rather than `for (final child in ...)`: the latter allocates
        // a list iterator per group per frame, and a real icon's tree is
        // mostly groups.
        //
        // 用下标而非 `for (final child in ...)`：后者每个分组每帧都要分配一个
        // 列表迭代器，而真实图标的树里分组占多数。
        final children = node.children;
        for (var i = 0; i < children.length; i++) {
          _paintNode(canvas, children[i], style);
        }
      case SvgNodeKind.path:
      case SvgNodeKind.circle:
      case SvgNodeKind.rect:
      case SvgNodeKind.ellipse:
      case SvgNodeKind.line:
      case SvgNodeKind.polyline:
      case SvgNodeKind.polygon:
        final path = _geometryPath(node, attributes);
        if (path != null) _paintShape(canvas, path, style);
      case SvgNodeKind.text:
        _paintText(canvas, node, style, attributes);
      case SvgNodeKind.image:
        final img = node.resolvedImage;
        if (img == null) {
          return; // not yet decoded / failed to decode: skip silently
        }
        final x = _num(attributes, 'x');
        final y = _num(attributes, 'y');
        final w = _num(attributes, 'width');
        final h = _num(attributes, 'height');
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
  ui.Path? _geometryPath(SvgNode node, Map<String, String> attributes) {
    // Geometry is rebuilt from strings on every frame unless it can be proven
    // unchanged, and the proof is an identity check on whatever the shape is
    // built from (see [SvgNode.cachedGeometry]):
    //
    //  - `<path>`: the `d` string. `node.attributes['d']` hands back the very
    //    same String instance every frame, so a `<path>` whose `d` isn't
    //    animated — which is every real `stroke-dashoffset`/`stroke-dasharray`
    //    line-md style icon — parses its path data once instead of once per
    //    frame. This is the case worth optimizing: `d` parsing is by far the
    //    most expensive geometry build.
    //  - every other shape: the attribute map instance. A node with no
    //    `<animate>` gets `node.attributes` itself from
    //    [_effectiveAttributes], so the key is stable; a node with animations
    //    gets a fresh map per frame and simply rebuilds, which for
    //    `addOval`/`addRect`-shaped geometry costs almost nothing.
    //
    // Correctness under a document shared between widgets (see
    // `SvgDocumentCache`): both keys are time-independent, so two widgets
    // painting the same document at different timeline positions either share
    // a valid entry or miss and rebuild — never read a stale one.
    //
    // 除非能证明几何没变，否则每帧都要从字符串重建几何，而"证明"就是对构建来源
    // 做一次身份比较（见 [SvgNode.cachedGeometry]）：
    //
    //  - `<path>`：用 `d` 字符串。`node.attributes['d']` 每帧返回的是同一个
    //    String 实例，因此 `d` 未被动画驱动的 `<path>`——也就是所有真实的
    //    `stroke-dashoffset`/`stroke-dasharray` line-md 风格图标——路径数据只
    //    解析一次而不是每帧一次。这正是值得优化的情形：`d` 解析是各类几何构建
    //    里最贵的一项。
    //  - 其它形状：用属性表实例。没有 `<animate>` 的节点从
    //    [_effectiveAttributes] 拿到的就是 `node.attributes` 本身，键是稳定的；
    //    有动画的节点每帧拿到新表，于是直接重建，而 `addOval`/`addRect` 这类
    //    几何重建几乎不花钱。
    //
    // 文档在多个控件间共享（见 `SvgDocumentCache`）时的正确性：两个键都与时间
    // 无关，所以在不同时间线位置绘制同一文档的两个控件，要么共享一个有效条目，
    // 要么未命中后重建——绝不会读到过期结果。
    final Object? cacheKey = node.kind == SvgNodeKind.path
        ? attributes['d']
        : attributes;
    if (cacheKey != null && identical(node.geometryCacheKey, cacheKey)) {
      return node.cachedGeometry;
    }
    final built = _buildGeometryPath(node.kind, attributes);
    if (cacheKey != null) {
      node.geometryCacheKey = cacheKey;
      node.cachedGeometry = built;
    }
    return built;
  }

  /// Builds a geometry shape's [ui.Path] from scratch — the uncached half of
  /// [_geometryPath], which holds all the actual shape logic.
  ///
  /// 从零构建几何形状的 [ui.Path]——[_geometryPath] 的无缓存那一半，实际的形状
  /// 逻辑都在这里。
  ui.Path? _buildGeometryPath(
    SvgNodeKind kind,
    Map<String, String> attributes,
  ) {
    switch (kind) {
      case SvgNodeKind.path:
        final d = attributes['d'];
        return d == null ? null : parseSvgPathData(d);
      case SvgNodeKind.circle:
        final cx = _num(attributes, 'cx');
        final cy = _num(attributes, 'cy');
        final r = _num(attributes, 'r');
        return ui.Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case SvgNodeKind.rect:
        final x = _num(attributes, 'x');
        final y = _num(attributes, 'y');
        final w = _num(attributes, 'width');
        final h = _num(attributes, 'height');
        if (w <= 0 || h <= 0) {
          return null; // SVG: non-positive size renders nothing
        }
        var rx = double.tryParse(attributes['rx'] ?? '');
        var ry = double.tryParse(attributes['ry'] ?? '');
        rx ??= ry;
        ry ??= rx;
        final path = ui.Path();
        if (rx != null && ry != null && rx > 0 && ry > 0) {
          final clampedRx = rx > w / 2 ? w / 2 : rx;
          final clampedRy = ry > h / 2 ? h / 2 : ry;
          path.addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, h),
              Radius.elliptical(clampedRx, clampedRy),
            ),
          );
        } else {
          path.addRect(Rect.fromLTWH(x, y, w, h));
        }
        return path;
      case SvgNodeKind.ellipse:
        final cx = _num(attributes, 'cx');
        final cy = _num(attributes, 'cy');
        final rx = _num(attributes, 'rx');
        final ry = _num(attributes, 'ry');
        return ui.Path()..addOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: rx * 2,
            height: ry * 2,
          ),
        );
      case SvgNodeKind.line:
        final x1 = _num(attributes, 'x1');
        final y1 = _num(attributes, 'y1');
        final x2 = _num(attributes, 'x2');
        final y2 = _num(attributes, 'y2');
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
  void _paintText(
    Canvas canvas,
    SvgNode node,
    ResolvedStyle style,
    Map<String, String> attributes,
  ) {
    final content = node.textContent;
    if (content == null || content.isEmpty || style.opacity <= 0) return;
    final fill = style.fill;
    if (fill == null) return; // fill="none": SVG renders no glyphs

    final x = _num(attributes, 'x');
    final y = _num(attributes, 'y');
    final fontSize = double.tryParse(attributes['font-size'] ?? '') ?? 16;

    final painter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: attributes['font-family'],
          color: _fade(fill, style.opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final dx = switch (attributes['text-anchor']) {
      'middle' => -painter.width / 2,
      'end' => -painter.width,
      _ => 0.0,
    };
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
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
    return buildGradientShader(
      resampleGradientAtTime(def, time),
      path.getBounds(),
      opacity,
    );
  }

  /// [color] faded by [opacity], returning [color] untouched at full opacity.
  ///
  /// `Color.withValues` builds a whole new [Color] from four floating-point
  /// components; at `opacity == 1` that new colour is equal to the one it was
  /// derived from, so the allocation is pure waste — and full opacity is the
  /// default every node inherits unless an `opacity` attribute says otherwise.
  ///
  /// [color] 按 [opacity] 淡化后的颜色；完全不透明时原样返回 [color]。
  ///
  /// `Color.withValues` 会用四个浮点分量构造一个全新的 [Color]；当
  /// `opacity == 1` 时新颜色与原颜色相等，这次分配纯属浪费——而完全不透明正是
  /// 每个节点在没有 `opacity` 属性时继承到的默认值。
  static Color _fade(Color color, double opacity) =>
      opacity == 1 ? color : color.withValues(alpha: color.a * opacity);

  void _paintShape(Canvas canvas, ui.Path path, ResolvedStyle style) {
    if (style.opacity <= 0) return;
    final fillShader = _gradientShader(
      style.fillGradientId,
      path,
      style.opacity,
    );
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
          ..color = _fade(style.fill!, style.opacity),
      );
    }
    final strokeShader = _gradientShader(
      style.strokeGradientId,
      path,
      style.opacity,
    );
    if (strokeShader != null && style.strokeWidth > 0) {
      canvas.drawPath(
        style.strokeDasharray.isEmpty
            ? path
            : dashPath(
                path,
                dashArray: style.strokeDasharray,
                dashOffset: style.strokeDashoffset,
              ),
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
      final strokePath = style.strokeDasharray.isNotEmpty
          ? dashPath(
              path,
              dashArray: style.strokeDasharray,
              dashOffset: style.strokeDashoffset,
            )
          : path;
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _fade(style.stroke!, style.opacity)
          ..strokeWidth = style.strokeWidth
          ..strokeCap = style.strokeLinecap
          ..strokeJoin = style.strokeLinejoin,
      );
    }
  }

  @override
  bool shouldRepaint(AnimatedSvgPainter oldDelegate) =>
      oldDelegate.clock != clock ||
      oldDelegate.time != time ||
      oldDelegate.root != root ||
      oldDelegate.theme != theme ||
      oldDelegate.fit != fit ||
      oldDelegate.alignment != alignment ||
      oldDelegate.gradients != gradients ||
      oldDelegate.clipPaths != clipPaths ||
      oldDelegate.masks != masks ||
      oldDelegate.quality != quality;
}

/// What one shape inside a `<mask>` definition contributes to the mask's
/// coverage, as far as the binary clip-path approximation is concerned — see
/// `AnimatedSvgPainter._maskFillCoverage`.
///
/// 就二值裁剪路径近似而言，`<mask>` 定义内的一个形状对该 mask 覆盖度的贡献
/// ——见 `AnimatedSvgPainter._maskFillCoverage`。
enum _MaskCoverage {
  /// Fully-opaque white: the region is fully revealed.
  ///
  /// 完全不透明的白色：该区域完全显示。
  shows,

  /// Fully-opaque black (or SVG's initial `fill: black` when nothing set one):
  /// the region is fully hidden, removing coverage where it overlaps [shows].
  ///
  /// 完全不透明的黑色（或谁都没设置时 SVG 的初始值 `fill: black`）：该区域完全
  /// 隐藏，并在与 [shows] 重叠处去掉覆盖度。
  hides,

  /// `fill="none"`: the shape is not painted, so it neither reveals nor hides
  /// anything and must be ignored entirely.
  ///
  /// `fill="none"`：形状未被绘制，因此既不显示也不隐藏任何东西，必须完全忽略。
  paintsNothing,

  /// A mid grey, a translucent colour, a gradient, `currentColor`, or anything
  /// unparseable: real fractional coverage, which a clip path cannot express —
  /// the whole mask is then ineligible for the approximation.
  ///
  /// 中间灰、半透明颜色、渐变、`currentColor`，或任何解析不出来的值：真正的分数
  /// 覆盖度，裁剪路径无法表达——此时整个 mask 都不适用该近似。
  notBinary,
}
