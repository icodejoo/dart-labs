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
import '../pixel_snap_layer.dart';
import 'smil_animation.dart';

import 'svg_dom.dart';
import 'svg_gradient.dart';
import 'svg_lengths.dart';
import 'svg_path_data.dart';
import 'svg_path_morph.dart';
import 'svg_style.dart';
import 'svg_theme.dart';
import 'xvg_animation_quality.dart';

/// Paints an [SvgDocument]'s (see `svg_document_parser.dart`) element tree at
/// a given [time] on the animation timeline, scaled from the document's
/// intrinsic size to the paint box.
///
/// A fresh recording every frame is intentional (not a regression from the
/// static path's cached-`ui.Picture` optimization): caching a `Picture` only
/// pays off for content that doesn't change between frames, and an active
/// animation's whole point is to change every frame — see xvg CLAUDE.md
/// architecture notes.
///
/// 在动画时间线上给定的 [time] 时刻，绘制 [SvgDocument]（见
/// `svg_document_parser.dart`）的元素树，并从文档固有尺寸缩放到绘制盒。
///
/// 每帧都重新录制是故意的（并非相对静态路径 `ui.Picture` 缓存优化的倒退）：
/// 缓存 `Picture`只对帧间不变的内容划算，而正在播放的动画本质就是每帧都在
/// 变——见 xvg CLAUDE.md 架构说明。
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
    this.quality = XvgAnimationQuality.exact,
    this.backgroundColor,
    this.rootViewBoxTransform,
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
  /// [XvgAnimationQuality.approximatesMasksAt].
  ///
  /// A callback rather than a bool because the answer depends on how many
  /// icons are animating *right now*, which changes as cells scroll in and
  /// out without this painter being rebuilt.
  ///
  /// 在绘制时（而非构造时）被询问，用于决定一个合格的 `<mask>` 是否可以改画成
  /// 裁剪路径，而不走两个 `saveLayer` 离屏通道——见
  /// [XvgAnimationQuality.approximatesMasksAt]。
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
  /// [XvgAnimationQuality.defaultQuality] at runtime alters what gets
  /// painted). The immutable profile has value equality, so comparing it
  /// answers "could the painting differ?" correctly in both directions.
  ///
  /// [approximateMasks] 所依据的画质配置，携带它的唯一目的是让 [shouldRepaint]
  /// 能察觉到它发生了变化。
  ///
  /// [approximateMasks] 是闭包，而闭包每次 build 都是新对象——拿它做比较会导致每次
  /// 重建都强制重绘，而完全忽略它则会漏掉真实变化（运行时重新赋值
  /// [XvgAnimationQuality.defaultQuality] 会改变画出来的东西）。这份不可变配置
  /// 有值相等语义，因此比较它能在两个方向上都正确回答"绘制结果是否可能不同"。
  final XvgAnimationQuality quality;

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

  /// The document's intrinsic viewport size. / 文档的固有视口尺寸。
  final Size intrinsicSize;

  /// Root user-to-viewport affine; null means identity.
  /// 根用户坐标到视口的仿射矩阵；null 表示恒等映射。
  final List<double>? rootViewBoxTransform;

  /// Expands the root affine once per painter, outside the per-frame work.
  /// 每个 painter 只展开一次根仿射矩阵，避免逐帧分配。
  late final _rootViewBoxMatrix = rootViewBoxTransform == null
      ? null
      : affineToMatrix4(rootViewBoxTransform!);

  /// The animation clock this painter samples. Also drives repaints — see the
  /// constructor.
  ///
  /// 本绘制器采样的动画时钟，同时驱动重绘——见构造函数。
  final ValueListenable<Duration> clock;

  /// Current position on the animation timeline. / 当前所处的动画时间线位置。
  Duration get time => clock.value;

  /// Theme resolving `currentColor`. / 解析 `currentColor` 的主题。
  final XvgTheme theme;

  /// How the document is inscribed into the paint box. / 文档如何适配绘制盒。
  final BoxFit fit;

  /// Alignment within the paint box. / 在绘制盒内的对齐方式。
  final Alignment alignment;

  /// Root background fills the fitted viewport. / 根背景填满适配后的视口。
  final Color? backgroundColor;

  /// [backgroundColor] 对应的画笔，构造后只建一次，逐帧复用。
  late final Paint? _backgroundPaint = backgroundColor == null
      ? null
      : (Paint()..color = backgroundColor!);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || intrinsicSize.isEmpty) return;
    final viewport = svgPaintViewport(intrinsicSize, size, fit, alignment);
    final sx = viewport.width / intrinsicSize.width;
    final sy = viewport.height / intrinsicSize.height;

    // The outer clip also bounds offscreen targets for masks and blur.
    // 外层裁剪也限制遮罩和模糊的离屏目标尺寸。
    canvas
      ..save()
      ..clipRect(viewport.intersect(Offset.zero & size), doAntiAlias: false);
    final background = _backgroundPaint;
    if (background != null) canvas.drawRect(viewport, background);
    canvas
      ..translate(viewport.left, viewport.top)
      ..scale(sx, sy);
    final rootMatrix = _rootViewBoxMatrix;
    if (rootMatrix != null) canvas.transform(rootMatrix);
    _paintNode(canvas, root, ResolvedStyle.initial);
    canvas.restore();
  }

  /// Current SVG viewport in user units. / 当前 SVG 视口的用户坐标尺寸。
  late Size _userViewport = _rootUserViewport;

  /// The root viewBox defines the percentage bases when present. / 根 viewBox 存在时提供百分比基准。
  late final Size _rootUserViewport = root.viewportBox == null
      ? intrinsicSize
      : Size(root.viewportBox![2], root.viewportBox![3]);

  /// Resolves a geometry length against the relevant viewport axis. / 按对应视口轴换算几何长度。
  double? _length(Map<String, String> attributes, String key, double fontSize) {
    final raw = attributes[key];
    if (raw == null) return null;
    final basis = raw.endsWith('%') || raw.trimRight().endsWith('%')
        ? switch (key) {
            'x' ||
            'x1' ||
            'x2' ||
            'cx' ||
            'width' ||
            'rx' ||
            'dx' => _userViewport.width,
            'y' ||
            'y1' ||
            'y2' ||
            'cy' ||
            'height' ||
            'ry' ||
            'dy' => _userViewport.height,
            _ => svgNormalizedDiagonal(
              _userViewport.width,
              _userViewport.height,
            ),
          }
        : null;
    return resolveSvgLength(raw, percentageBase: basis, fontSize: fontSize);
  }

  /// Reads a geometry length with a zero default. / 读取默认值为零的几何长度。
  double _num(Map<String, String> attributes, String key, double fontSize) =>
      _length(attributes, key, fontSize) ?? 0;

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
  /// computation into two identity checks and a cheap theme comparison for
  /// the static majority.
  ///
  /// Inherited styles and attribute maps use identity; themes use identity
  /// first, then value equality, so equal themes from separate widgets reuse
  /// the same shared document's cached styles. See [SvgNode.cachedStyle] for
  /// the validity of these keys.
  ///
  /// 返回把 [inherited] 折叠进去后 [node] 的表现样式；当解析它所依赖的三个输入
  /// 都没变时，直接复用挂在节点上的缓存结果（见 [SvgNode.cachedStyle]）。
  ///
  /// 对一个"每节点每帧都要跑一次"的操作来说，`ResolvedStyle.inherit` 并不便宜：
  /// 大约十几次以字符串为键的 map 查找、最多四次颜色/url/虚线解析，以及一次
  /// 全新的 [ResolvedStyle] 分配。然而真实动画图标里几乎每个节点的样式都是
  /// *恒定*的——line-md 风格图标动的是 `stroke-dashoffset` 或某个变换，而
  /// `fill`、`stroke`、`stroke-width` 之类从不变化。这个缓存把静态的大多数节点
  /// 的整套计算压成两次身份比较和一次廉价的主题比较。
  ///
  /// 继承样式和属性表按身份比较；主题先比较身份，再比较值，使不同控件创建的
  /// 等值主题能复用同一共享文档的样式缓存。这些键的有效性见
  /// [SvgNode.cachedStyle]。
  ResolvedStyle _resolveStyle(
    SvgNode node,
    ResolvedStyle inherited,
    Map<String, String> attributes,
  ) {
    final cached = node.cachedStyle;
    if (cached != null &&
        identical(node.styleInheritedKey, inherited) &&
        identical(node.styleAttributesKey, attributes) &&
        node.styleViewportKey == _userViewport &&
        (identical(node.styleThemeKey, theme) || node.styleThemeKey == theme)) {
      return cached as ResolvedStyle;
    }
    final resolved = inherited.inherit(
      attributes,
      theme,
      viewport: _userViewport,
    );
    node
      ..cachedStyle = resolved
      ..styleInheritedKey = inherited
      ..styleAttributesKey = attributes
      ..styleViewportKey = _userViewport
      ..styleThemeKey = theme;
    return resolved;
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
  /// A node WITH `<animate>`s gets the map cached on it from the previous
  /// frame for as long as **every** one of its timelines samples to the value
  /// it sampled to last frame, and a genuinely fresh [Map] the instant any of
  /// them moves — see [SvgNode.cachedAnimatedAttributes] for why reusing the
  /// instance is what matters (it is what keeps [_resolveStyle]'s and
  /// [_geometryPath]'s identity-keyed caches alive through the settled steady
  /// state that dominates real icons) and for how this differs from the
  /// mutated-in-place reuse that was tried here and reverted — that one held
  /// the identity stable while the contents changed, silently freezing
  /// animated `<rect>`/`<circle>`/etc. geometry at the first frame's shape,
  /// caught by `test/animation/effective_attributes_reuse_test.dart`.
  ///
  /// [node] 的属性表，叠加本帧已采样的 `<animate>` 值。
  ///
  /// 节点自身没有 `<animate>` 时直接返回 [SvgNode.attributes] 本身——不拷贝；
  /// 真实动画图标里大多数节点都属于这种情况（根节点、各分组，以及所有只是被
  /// 继承而非被动画驱动的形状）。调用方只读使用返回值，因此共享节点自身的表是
  /// 安全的。被省掉的这次拷贝原本是每节点每帧一次。
  ///
  /// 带 `<animate>` 的节点：只要它**每一条**时间线本帧采样到的值都与上一帧相同，
  /// 就拿回上一帧缓存在它身上的那张表；一旦任意一条发生变化，立刻拿到一份真正
  /// 全新的 [Map]——为什么"复用同一个实例"才是关键（正是它让
  /// [_resolveStyle] 与 [_geometryPath] 那两个以身份为键的缓存能在真实图标占
  /// 绝大多数时间的"已定格稳态"里持续命中），以及它与此前试过又回滚的"原地修改
  /// 式复用"差别在哪（那次是身份稳定而内容在变，悄悄把带动画的
  /// `<rect>`/`<circle>` 等几何冻结在第一帧的形状上，由
  /// `test/animation/effective_attributes_reuse_test.dart` 捕获），见
  /// [SvgNode.cachedAnimatedAttributes]。
  ///
  /// [node] — the node whose attributes to resolve. / 要解析属性的节点。
  ///
  /// Returns a read-only attribute map with sampled overrides applied.
  ///
  ///   返回叠加了采样覆盖值的只读属性表。
  Map<String, String> _effectiveAttributes(SvgNode node) {
    final animations = node.animations;
    final pathAnimations = node.pathAnimations;
    final colorAnimations = node.colorAnimations;
    final listAnimations = node.listAnimations;
    if (animations.isEmpty &&
        pathAnimations.isEmpty &&
        colorAnimations.isEmpty &&
        listAnimations.isEmpty) {
      return node.attributes;
    }
    // Sample every timeline into the node's sample key, noting whether any of
    // them moved since the last frame. Sampling has to happen either way — it
    // is the only way to know whether anything changed — so the comparison
    // rides along on a pass that was already being made, and costs one double
    // compare per animation.
    //
    // 把每条时间线采样进本节点的采样键，同时记录是否有任何一条相对上一帧发生了
    // 变化。无论如何都得采样——这是判断"有没有变"的唯一途径——因此比较只是搭在
    // 一趟本来就要走的遍历上，每条动画多付一次 double 比较。
    // 采样键布局：数值、路径、颜色、列表四段依次排布，见 [SvgNode.animatedSampleKey]。
    // 各段起点：路径段 numericCount，颜色段 pathEnd，列表段 colorEnd。
    final numericCount = animations.length;
    final pathEnd = numericCount + pathAnimations.length;
    final colorEnd = pathEnd + colorAnimations.length;
    var count = colorEnd;
    for (var i = 0; i < listAnimations.length; i++) {
      count += listAnimations[i].width;
    }
    var key = node.animatedSampleKey;
    var changed = false;
    if (key == null || key.length != count) {
      key = Float64List(count);
      node.animatedSampleKey = key;
      changed = true;
    }
    for (var i = 0; i < colorEnd; i++) {
      // See [SvgNode.animatedSampleKey]: negative infinity marks "this
      // timeline produced no value at this instant". It has to be a non-finite
      // marker because every finite number is a legitimate sample, and it has
      // to be an infinity rather than NaN because NaN compares unequal to
      // itself, which would report a change on every single frame.
      //
      // 见 [SvgNode.animatedSampleKey]：负无穷标记"该时间线在此刻没有产出值"。
      // 它必须是非有限值，因为任何有限数都是合法采样；又必须用无穷而不是 NaN，
      // 因为 NaN 与自身比较不相等，会导致每一帧都被判为"有变化"。
      final double sampled;
      if (i < numericCount) {
        sampled = animations[i].sample(time) ?? _kNoSample;
      } else if (i < pathEnd) {
        sampled = pathAnimations[i - numericCount].sample(time) ?? _kNoSample;
      } else {
        // 颜色：0xAARRGGBB 小于 2^32，转 double 精确；none 哨兵 -1 保持为有限的
        // -1.0，与代表"缺失"的负无穷区分开。
        final color = colorAnimations[i - pathEnd].sample(time);
        sampled = color == null ? _kNoSample : color.toDouble();
      }
      if (sampled != key[i]) {
        key[i] = sampled;
        changed = true;
      }
    }
    // 列表段：每条动画占 width 个槽位，缺失时整段记负无穷。
    var slot = colorEnd;
    for (var i = 0; i < listAnimations.length; i++) {
      final animation = listAnimations[i];
      final sampledList = animation.sample(time);
      final width = animation.width;
      for (var j = 0; j < width; j++) {
        final sampled = sampledList == null ? _kNoSample : sampledList[j];
        if (sampled != key[slot + j]) {
          key[slot + j] = sampled;
          changed = true;
        }
      }
      slot += width;
    }
    final cached = node.cachedAnimatedAttributes;
    if (!changed &&
        cached != null &&
        (!node.hasAdditiveNumericAnimation ||
            node.additiveViewportKey == _userViewport)) {
      return cached;
    }

    // 只在真要改属性（数值覆盖，或整数位置的 `d`）时才拷贝属性表；纯路径变形
    // 的插值帧属性内容不变，直接复用节点自己的表，不击穿 [_resolveStyle] 的缓存。
    Map<String, String>? overlaid;
    // 路径动画：整数位置（离散，或恰在关键帧上）直接覆盖为原始 `d` 字符串，
    // 同一实例使几何缓存可命中；可插值的非整数位置则现建路径，放在
    // [SvgNode.animatedMorphPath]，由 [_geometryPath] 优先使用。
    ui.Path? morphPath;
    for (var i = 0; i < pathAnimations.length; i++) {
      final position = key[numericCount + i];
      if (position == _kNoSample) continue;
      final animation = pathAnimations[i];
      final index = position.floor();
      if (animation.interpolates && position != index) {
        morphPath = buildMorphedPath(animation.morph!, position);
      } else {
        morphPath = null;
        (overlaid ??= Map<String, String>.of(node.attributes))['d'] =
            animation.frames[index];
      }
    }
    node.animatedMorphPath = morphPath;
    for (var i = 0; i < numericCount; i++) {
      final sampled = key[i];
      // A timeline with no value at this instant contributes no override, so
      // the element's own static attribute shows through — this is what makes
      // an `<animate>` that ended *without* `fill="freeze"` snap back to the
      // static value instead of leaking its last sampled one.
      //
      // 此刻没有值的时间线不贡献任何覆盖，于是元素自身的静态属性显现出来——这正是
      // 一个结束时*未*设置 `fill="freeze"` 的 `<animate>` 会弹回静态值、而不是
      // 残留最后一次采样值的原因。
      if (sampled != _kNoSample) {
        final animation = animations[i];
        final attributes = overlaid ??= Map<String, String>.of(node.attributes);
        final base = animation.additiveBase;
        final value = base == null
            ? sampled
            : sampled +
                  (_length(
                        attributes,
                        animation.attributeName,
                        svgInitialFontSize,
                      ) ??
                      base);
        attributes[animation.attributeName] = value.toString();
      }
    }
    // 颜色覆盖：哨兵 -1.0 写成 `none`，其余把 0xAARRGGBB 重排成 `#RRGGBBAA`。
    // 同一属性被多条动画覆盖时后写者胜，与数值通道一致。
    for (var i = 0; i < colorAnimations.length; i++) {
      final sampled = key[pathEnd + i];
      if (sampled == _kNoSample) continue;
      (overlaid ??= Map<String, String>.of(
        node.attributes,
      ))[colorAnimations[i].attributeName] = sampled == kSmilColorNone
          ? _kNone
          : smilColorToHex(sampled.toInt());
    }
    // 列表覆盖：把该动画的各槽位用空格连接（`double.toString`，最短往返）。
    slot = colorEnd;
    for (var i = 0; i < listAnimations.length; i++) {
      final animation = listAnimations[i];
      final width = animation.width;
      if (width > 0 && key[slot] != _kNoSample) {
        final frames = animation.serializedFrames;
        final suffixes = animation.unitSuffixes;
        final attributes = overlaid ??= Map<String, String>.of(node.attributes);
        attributes[animation.attributeName] = frames != null
            ? frames[key[slot].toInt()]
            : suffixes == null
            ? key.sublist(slot, slot + width).join(' ')
            : [for (var j = 0; j < width; j++) '${key[slot + j]}${suffixes[j]}']
                  .join(' ');
      }
      slot += width;
    }
    final result = overlaid ?? node.attributes;
    node.cachedAnimatedAttributes = result;
    if (node.hasAdditiveNumericAnimation) {
      node.additiveViewportKey = _userViewport;
    }
    return result;
  }

  /// Paints [node] at its position in the tree, resolving its animated style
  /// and any static/animated transforms.
  ///
  /// [nested] marks content being painted *as* a `<clipPath>`/`<mask>`
  /// definition's body (via [clipPaths]/[masks]): SVG's nested-mask/clip is
  /// out of scope, so nested content never itself looks up a further
  /// `clip-path`/`mask` reference (the nearest ancestor's clip/mask already
  /// won) — see xvg CLAUDE.md task notes.
  ///
  /// 在树中的位置绘制 [node]，解析其动画样式及任何静态/动画变换。
  ///
  /// [nested] 标记正在作为 `<clipPath>`/`<mask>` 定义体（经
  /// [clipPaths]/[masks]）绘制的内容：SVG 的嵌套 mask/clip 不在范围内，因此
  /// 嵌套内容自身永不再查找 `clip-path`/`mask` 引用（最近祖先的裁剪/遮罩已经
  /// 生效）——见 xvg CLAUDE.md 任务记录。
  void _paintNode(
    Canvas canvas,
    SvgNode node,
    ResolvedStyle inherited, {
    bool nested = false,
    double opacityMultiplier = 1,
  }) {
    final effectiveAttributes = _effectiveAttributes(node);
    // `display="none"` 时整棵子树都不绘制。
    if (effectiveAttributes[_kDisplayAttribute]?.trim() == _kNone) {
      return;
    }
    var style = _resolveStyle(node, inherited, effectiveAttributes);
    // This is a frame-local sampled value; never mark the node as hidden.
    // 当前帧采样为零时跳过，不缓存隐藏状态，后续动画帧仍可恢复。
    if (style.opacity <= 0) return;
    if (opacityMultiplier != 1) {
      style = style.withOpacity(style.opacity * opacityMultiplier);
    }

    // The id checks come first so the overwhelming majority of nodes — which
    // reference neither a `<clipPath>` nor a `<mask>` — skip two map lookups
    // per node per frame instead of hashing a null key twice.
    //
    // 先做 id 判空，使绝大多数既不引用 `<clipPath>` 也不引用 `<mask>` 的节点
    // 每帧省掉两次 map 查找，而不是拿 null 键去哈希两次。
    final clipPathId = node.clipPathId;
    final maskId = node.maskId;
    final clipDef = clipPathId == null ? null : clipPaths[clipPathId];
    var maskDef = nested || maskId == null ? null : masks[maskId];
    if (maskDef != null && _activeMasks.contains(maskDef)) maskDef = null;
    final clipUsesBounds =
        clipDef?.attributes['clipPathUnits'] == _objectBoundingBox;
    final maskUsesBounds =
        maskDef != null &&
        (maskDef.attributes['maskUnits'] != _userSpaceOnUse ||
            maskDef.attributes['maskContentUnits'] == _objectBoundingBox);
    final bounds = clipUsesBounds || maskUsesBounds
        ? _objectBounds(node, effectiveAttributes, style)
        : Rect.zero;
    final maskRegion = maskDef == null ? null : _maskRegion(maskDef, bounds);
    if (maskRegion != null && maskRegion.isEmpty) return;
    final maskContentBox =
        maskDef?.attributes['maskContentUnits'] == _objectBoundingBox
        ? bounds
        : null;
    if (maskContentBox != null && maskContentBox.isEmpty) return;
    // LOSSY FAST PATH, off by default and concurrency-gated by the caller
    // (see [approximateMasks]): a `<mask>` whose content is nothing but
    // fully-opaque pure-black/pure-white fills expresses a *binary* coverage
    // region, and a binary coverage region is exactly what a clip path is.
    // Drawing it as a clip removes both of this mask's `saveLayer`s — measured
    // on a Huawei STG-AL00 (Impeller GLES) at ~221us of GPU render-pass time
    // each, the single largest line item in the batch-animation raster budget
    // (see doc/performance-benchmarks.md).
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
    // doc/performance-benchmarks.md）。
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
    // The Skia pixel probe in group_opacity_test shows that a clip installed
    // outside a blur layer trims the filtered result: Clip(Blur(content)).
    // It does not demonstrate pre-filter clipping. Retain !hasBlur because
    // mask-to-clip equivalence with blur is unverified on real Impeller devices.
    // Blur inside mask definitions is rejected separately by _maskSubtreeIsBinary.
    //
    // group_opacity_test 的 Skia 像素探针表明：在模糊层外安装 clip，裁剪的是
    // 模糊后的结果 Clip(Blur(content))，并非先裁剪再模糊。保留 !hasBlur：
    // mask 转 clip 与 blur 组合的等价性尚未在 Impeller 真机验证。
    // mask 定义内部的 blur 另由 _maskSubtreeIsBinary 拒绝。
    if (maskDef != null && !hasBlur) {
      final asClip = approximateMasks();
      if (asClip && _maskIsClipEligible(maskDef)) {
        final viewport = _userViewport;
        if (maskContentBox != null) _userViewport = const Size.square(1);
        maskClip = _resolveMaskClipPath(maskDef, time);
        _userViewport = viewport;
        if (maskContentBox != null) {
          maskClip = _mapToBounds(maskClip, maskContentBox);
        }
        maskDef = null;
      }
    }
    // Opacity is applied last: Opacity(Mask(Clip(Filter(content)))).
    // A single paint can fold opacity into its alpha; overlapping children or
    // fill + stroke must first composite at full element opacity.
    final pushOpacity =
        style.opacity < 1 &&
        !hasBlur &&
        clipDef == null &&
        maskDef == null &&
        maskClip == null &&
        _canPushOpacity(node, style);
    // With no mask between filter and opacity, both can use the filter paint.
    // 无 mask 隔在 filter 与 opacity 之间时，二者共用模糊层的 Paint。
    final blurOpacity = hasBlur && maskDef == null;
    final opacityLayer =
        style.opacity < 1 &&
        !pushOpacity &&
        !blurOpacity &&
        (node.children.isNotEmpty ||
            hasBlur ||
            ((style.fill != null || style.fillGradientId != null) &&
                style.fillOpacity > 0 &&
                (style.stroke != null || style.strokeGradientId != null) &&
                style.strokeOpacity > 0 &&
                style.strokeWidth > 0));
    final needsClipMaskSave =
        clipDef != null || maskDef != null || maskClip != null;
    if (needsClipMaskSave) canvas.save();
    final hasOwnTransform =
        node.transformAnimations.isNotEmpty ||
        node.motionAnimations.isNotEmpty ||
        node.transform != null ||
        node.dynamicUsePlacement;
    if (hasOwnTransform) {
      canvas.save();
      _applyOwnTransform(canvas, node);
      if (node.dynamicUsePlacement) {
        canvas.translate(
          _num(effectiveAttributes, 'x', style.fontSize),
          _num(effectiveAttributes, 'y', style.fontSize),
        );
      }
    }
    // Install clips before ALL effect layers, in the node's coordinate system.
    // A layer's final composite uses the clip active when it was opened; a clip
    // added inside the layer only constrains its draws. No render pass is added.
    // 在节点坐标系中先装裁剪，再开所有效果图层。图层最终合成使用开层时的父级
    // 裁剪；层内追加的裁剪只约束层内绘制。不增加渲染通道。
    if (clipDef != null) canvas.clipPath(_resolveClipPath(clipDef, bounds));
    if (maskRegion != null) canvas.clipRect(maskRegion, doAntiAlias: false);
    if (maskClip != null) canvas.clipPath(maskClip);
    if (opacityLayer) {
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromRGBO(0, 0, 0, style.opacity),
      );
    }
    if (maskDef != null) canvas.saveLayer(null, Paint());
    if (hasBlur) {
      canvas.saveLayer(
        null,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, blurOpacity ? style.opacity : 1)
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
      );
    }
    _paintNodeContent(
      canvas,
      node,
      style,
      effectiveAttributes,
      applyOpacity: !opacityLayer && !blurOpacity,
      childOpacity: pushOpacity ? style.opacity : 1,
    );
    if (hasBlur) canvas.restore();
    if (maskDef != null) _applyMaskLayer(canvas, maskDef, maskContentBox);
    if (opacityLayer) canvas.restore();
    if (hasOwnTransform) canvas.restore();
    if (needsClipMaskSave) canvas.restore();
  }

  /// 判断组的 opacity 能否下推到单笔叶子而不开 saveLayer。
  /// 仅单笔几何叶子可下推；每帧检查含继承 fill/stroke 的采样样式。
  ///
  /// Only a single geometry paint can absorb its wrapper's opacity without
  /// changing overlap or effect isolation. Resolve the child's sampled style,
  /// including inherited fill/stroke, on every frame before deciding.
  bool _canPushOpacity(SvgNode node, ResolvedStyle style) {
    if ((node.kind != SvgNodeKind.group && node.kind != SvgNodeKind.root) ||
        node.children.length != 1) {
      return false;
    }
    final child = node.children.single;
    if (child.children.isNotEmpty ||
        child.maskId != null ||
        child.clipPathId != null ||
        (child.blurSigma ?? 0) > 0 ||
        child.kind == SvgNodeKind.group ||
        child.kind == SvgNodeKind.root ||
        child.kind == SvgNodeKind.text ||
        child.kind == SvgNodeKind.image) {
      return false;
    }
    final childStyle = _resolveStyle(child, style, _effectiveAttributes(child));
    final fill =
        (childStyle.fill != null || childStyle.fillGradientId != null) &&
        childStyle.fillOpacity > 0;
    final stroke =
        (childStyle.stroke != null || childStyle.strokeGradientId != null) &&
        childStyle.strokeOpacity > 0 &&
        childStyle.strokeWidth > 0;
    return fill != stroke;
  }

  /// 把节点自身的变换（静态 `transform`、各 `animateTransform`、`animateMotion`）
  /// 依次右乘到 [parent] 上，返回新的累计仿射矩阵。
  ///
  /// 供 clipPath、mask 的几何遍历使用，与 [_applyOwnTransform] 的顺序一致。
  List<double> _concatOwnTransform(List<double> parent, SvgNode node) {
    var accum = parent;
    final start = _activeSmilTransformStart(node);
    final staticTransform = start == null ? _activeStaticTransform(node) : null;
    if (staticTransform != null) accum = concatAffine(accum, staticTransform);
    for (var i = start ?? 0; i < node.transformAnimations.length; i++) {
      final transformAnimation = node.transformAnimations[i];
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
      if (sampled.angleDegrees != 0) {
        final radians = sampled.angleDegrees * math.pi / 180;
        final cos = math.cos(radians), sin = math.sin(radians);
        accum = concatAffine(accum, [cos, sin, -sin, cos, 0, 0]);
      }
    }
    return accum;
  }

  /// 把节点自身的变换依次应用到 [canvas]：静态 `transform`、各 `animateTransform`，
  /// 最后是 `animateMotion`。绘制内容与遮罩共用，保证两者在同一坐标系。
  void _applyOwnTransform(Canvas canvas, SvgNode node) {
    final start = _activeSmilTransformStart(node);
    final staticTransform = start == null ? _activeStaticTransform(node) : null;
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
    for (var i = start ?? 0; i < node.transformAnimations.length; i++) {
      final transformAnimation = node.transformAnimations[i];
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
  }

  /// Composites [maskDef]'s content (sampled at [time]) as coverage over
  /// whatever was just painted into the current destination layer, then
  /// closes that layer — the second half of the mask machinery `_paintNode`
  /// opens with `canvas.saveLayer(null, Paint())`.
  ///
  /// 把 [maskDef] 的内容（在 [time] 采样）作为覆盖度合成到刚绘制进当前目标图层
  /// 的内容之上，然后关闭该图层——是 `_paintNode` 用
  /// `canvas.saveLayer(null, Paint())` 开启的 mask 机制的后半段。
  void _applyMaskLayer(Canvas canvas, SvgNode maskDef, Rect? contentBox) {
    _activeMasks.add(maskDef);
    final alpha = _isAlphaMask(maskDef);
    canvas.saveLayer(null, _maskCoveragePaint(alpha));
    // Flatten luminance content over black so unpremultiplied RGB includes
    // its alpha before the matrix reads it, matching the static renderer.
    // 亮度内容先合成到黑底，使矩阵读取的非预乘 RGB 包含内容 alpha，与静态路径一致。
    if (!alpha) canvas.drawColor(const Color(0xff000000), BlendMode.src);
    // 当前画布已位于被遮罩节点自己的坐标系（含其自身 transform）。
    canvas.save();
    final viewport = _userViewport;
    if (contentBox != null) {
      canvas.translate(contentBox.left, contentBox.top);
      canvas.scale(contentBox.width, contentBox.height);
      _userViewport = const Size.square(1);
    }
    _paintNode(canvas, maskDef, ResolvedStyle.initial, nested: true);
    _userViewport = viewport;
    _activeMasks.remove(maskDef);
    canvas
      ..restore()
      ..restore()
      ..restore();
  }

  /// In-progress masks used to bound nested references. / 用于阻断嵌套引用环的绘制中遮罩。
  final _activeMasks = <SvgNode>{};

  /// Current clip reference chain used to detect cycles. / 用于检测引用环的裁剪链。
  final _activeClips = <SvgNode>{};

  /// Computes a target's geometry box before its own transform or effects. / 计算目标自身变换与效果之前的几何包围盒。
  Rect _objectBounds(
    SvgNode node,
    Map<String, String> attributes,
    ResolvedStyle style,
  ) {
    final geometry = _geometryPath(node, attributes, style.fontSize);
    if (geometry != null) return geometry.getBounds();
    if (node.kind == SvgNodeKind.image) {
      return Rect.fromLTWH(
        _num(attributes, 'x', style.fontSize),
        _num(attributes, 'y', style.fontSize),
        _length(attributes, 'width', style.fontSize) ??
            node.resolvedImage?.width.toDouble() ??
            0,
        _length(attributes, 'height', style.fontSize) ??
            node.resolvedImage?.height.toDouble() ??
            0,
      );
    }
    if (node.kind == SvgNodeKind.text) {
      return _paintText(null, node, style, attributes) ?? Rect.zero;
    }
    if (node.children.isEmpty) return Rect.zero;
    final parent = _userViewport;
    List<double>? viewportTransform;
    if (node.isViewport) {
      final width =
          _length(attributes, 'width', style.fontSize) ?? parent.width;
      final height =
          _length(attributes, 'height', style.fontSize) ?? parent.height;
      if (width <= 0 || height <= 0) return Rect.zero;
      final box = node.viewportBox;
      viewportTransform = concatAffine(
        [
          1,
          0,
          0,
          1,
          _num(attributes, 'x', style.fontSize),
          _num(attributes, 'y', style.fontSize),
        ],
        svgViewportTransform(
              box,
              width,
              height,
              attributes['preserveAspectRatio'],
            ) ??
            _identityAffine,
      );
      _userViewport = box == null ? Size(width, height) : Size(box[2], box[3]);
    }
    Rect? bounds;
    for (final child in node.children) {
      final attrs = _effectiveAttributes(child);
      if (attrs[_kDisplayAttribute] == _kNone) continue;
      final childStyle = _resolveStyle(child, style, attrs);
      var matrix = _concatOwnTransform(
        viewportTransform ?? _identityAffine,
        child,
      );
      if (child.dynamicUsePlacement) {
        matrix = _concatUsePlacement(matrix, attrs, childStyle.fontSize);
      }
      final shape = _geometryPath(child, attrs, childStyle.fontSize);
      final Rect childBounds;
      if (shape != null) {
        childBounds = identical(matrix, _identityAffine)
            ? shape.getBounds()
            : shape.transform(affineToMatrix4(matrix)).getBounds();
      } else if (child.children.isNotEmpty ||
          child.kind == SvgNodeKind.image ||
          child.kind == SvgNodeKind.text) {
        childBounds = MatrixUtils.transformRect(
          Matrix4.fromFloat64List(affineToMatrix4(matrix)),
          _objectBounds(child, attrs, childStyle),
        );
      } else {
        continue;
      }
      bounds = bounds?.expandToInclude(childBounds) ?? childBounds;
    }
    _userViewport = parent;
    return bounds ?? Rect.zero;
  }

  /// Converts a unit-box path to target user space. / 将单位盒路径变换到目标用户坐标空间。
  static ui.Path _mapToBounds(ui.Path path, Rect bounds) => path.transform(
    affineToMatrix4([
      bounds.width,
      0,
      0,
      bounds.height,
      bounds.left,
      bounds.top,
    ]),
  );

  /// Resolves the mask region independently of the mask content units. / 独立于内容单位解析遮罩区域。
  Rect _maskRegion(SvgNode mask, Rect target) {
    final attrs = _effectiveAttributes(mask);
    final bbox = attrs['maskUnits'] != _userSpaceOnUse;
    final width = bbox ? 1.0 : _userViewport.width;
    final height = bbox ? 1.0 : _userViewport.height;
    final font = _resolveStyle(mask, ResolvedStyle.initial, attrs).fontSize;
    final x =
        resolveSvgLength(attrs['x'], percentageBase: width, fontSize: font) ??
        -.1 * width;
    final y =
        resolveSvgLength(attrs['y'], percentageBase: height, fontSize: font) ??
        -.1 * height;
    final w =
        resolveSvgLength(
          attrs['width'],
          percentageBase: width,
          fontSize: font,
        ) ??
        1.2 * width;
    final h =
        resolveSvgLength(
          attrs['height'],
          percentageBase: height,
          fontSize: font,
        ) ??
        1.2 * height;
    return bbox
        ? Rect.fromLTWH(
            target.left + x * target.width,
            target.top + y * target.height,
            w * target.width,
            h * target.height,
          )
        : Rect.fromLTWH(x, y, w, h);
  }

  /// Appends a use placement resolved in the current viewport. / 附加在当前视口解析的 use 位置。
  List<double> _concatUsePlacement(
    List<double> matrix,
    Map<String, String> attributes,
    double fontSize,
  ) => concatAffine(matrix, [
    1,
    0,
    0,
    1,
    _num(attributes, 'x', fontSize),
    _num(attributes, 'y', fontSize),
  ]);

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
  ///
  /// [alpha] 为 true（`mask-type="alpha"`）时不做亮度换算：`dstIn` 本就以源的
  /// alpha 为覆盖度，所以不挂颜色滤镜。
  Paint _maskCoveragePaint(bool alpha) {
    final paint = Paint()..blendMode = BlendMode.dstIn;
    if (!alpha) {
      paint.colorFilter = const ColorFilter.matrix(<double>[
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 0, //
        0.2125, 0.7154, 0.0721, 0, 0,
      ]);
    }
    return paint;
  }

  /// [maskDef]（`<mask>` 定义根）是否声明了 `mask-type="alpha"`：取值大小写不敏感、
  /// 忽略首尾空白，缺失或非法值一律按默认的 luminance，返回 false。
  static bool _isAlphaMask(SvgNode maskDef) {
    final raw = maskDef.attributes[_kMaskTypeAttribute];
    return raw != null && raw.trim().toLowerCase() == _kMaskTypeAlpha;
  }

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
      defRoot.maskClipEligible ??= _maskSubtreeIsBinary(
        defRoot,
        null,
        _isAlphaMask(defRoot),
      );

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
  /// [alpha] — whether the mask is `mask-type="alpha"` (coverage is judged by
  ///   alpha, not luminance). / 遮罩是否为 `mask-type="alpha"`（按 alpha 而非亮度判定覆盖度）。
  ///
  /// Returns true when every node in the subtree is binary-safe.
  ///
  ///   子树内每个节点都二值安全时返回 true。
  static bool _maskSubtreeIsBinary(
    SvgNode node,
    String? inheritedFill,
    bool alpha,
  ) {
    // A nested clip/mask/blur inside the mask means coverage this flat clip
    // path cannot represent.
    //
    // mask 内部嵌套 clip/mask/模糊，意味着这条扁平裁剪路径无法表达的覆盖度。
    if (node.clipPathId != null ||
        node.maskId != null ||
        node.isViewport ||
        node.dynamicUsePlacement ||
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
        attributes.containsKey('style') ||
        attributes.containsKey('font-size')) {
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
    if (stroke != null && stroke != _kNone) return false;

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
        if (_maskFillCoverage(fill, alpha) == _MaskCoverage.notBinary) {
          return false;
        }
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
      if (!_maskSubtreeIsBinary(child, fill, alpha)) return false;
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
  /// [alpha] — `mask-type="alpha"`: only opacity matters, colour is ignored.
  ///   Opaque paint is [_MaskCoverage.shows]; fully transparent paint covers
  ///   nothing and, unlike black under luminance, erases nothing
  ///   ([_MaskCoverage.paintsNothing]); anything between is partial.
  ///
  ///   `mask-type="alpha"`：只看不透明度，颜色无关。不透明为 shows；全透明什么都
  ///   不覆盖，也不像亮度模式下的黑色那样擦掉别的覆盖（paintsNothing）；介于两者
  ///   之间为部分覆盖。
  ///
  /// Returns the coverage classification. / 返回覆盖度分类。
  static _MaskCoverage _maskFillCoverage(String? fill, bool alpha) {
    // `fill="none"` paints nothing at all. That is NOT the same as painting
    // black: black *removes* coverage where it overlaps something white,
    // whereas an unpainted shape leaves whatever is underneath alone. Folding
    // the two together would punch phantom holes wherever a `fill="none"`
    // outline crossed a white region.
    //
    // `fill="none"` 什么都不画。这与"画黑色"**不是**一回事：黑色会在与白色重叠处
    // *去掉*覆盖度，而未被绘制的形状则不影响其下方的任何东西。把两者混为一谈，
    // 会在每一处 `fill="none"` 轮廓穿过白色区域的地方打出不该有的洞。
    if (fill == _kNone) return _MaskCoverage.paintsNothing;
    // No `fill` anywhere up the chain: SVG's initial value is black, which in
    // a mask means "hide".
    //
    // 整条继承链上都没有 `fill`：SVG 的初始值是黑色，在 mask 里意味着"隐藏"。
    //
    // alpha 型遮罩里没写 fill 就是不透明黑色，覆盖度为 1。
    if (fill == null) return alpha ? _MaskCoverage.shows : _MaskCoverage.hides;
    final color = parseSvgHexColor(fill);
    // A gradient, `currentColor`, or anything unparseable: not binary.
    // 渐变、`currentColor`，或任何解析不出来的东西：不是二值。
    if (color == null) return _MaskCoverage.notBinary;
    if (alpha) {
      if (color.a >= 0.999) return _MaskCoverage.shows;
      if (color.a <= 0.001) return _MaskCoverage.paintsNothing;
      return _MaskCoverage.notBinary;
    }
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
        defRoot.maskClipViewportKey == _userViewport &&
        _sameSignature(defRoot.maskClipSampleKey, signature)) {
      return cachedPath;
    }
    final shown = _RegionBuilder();
    final hidden = _RegionBuilder();
    var anyHidden = false;
    final alpha = _isAlphaMask(defRoot);

    void walk(
      SvgNode node,
      List<double> matrix,
      String? inheritedFill,
      ui.PathFillType inheritedRule,
    ) {
      final effectiveAttributes = _effectiveAttributes(node);
      final accum = _concatOwnTransform(matrix, node);
      final fill = effectiveAttributes['fill'] ?? inheritedFill;
      // mask 内容按普通填充绘制，所以遵守 fill-rule（继承）。
      final rule = parseSvgFillRule(
        effectiveAttributes[kFillRuleAttribute],
        inheritedRule,
      );

      if (node.kind == SvgNodeKind.root || node.kind == SvgNodeKind.group) {
        for (final child in node.children) {
          walk(child, accum, fill, rule);
        }
        return;
      }
      final coverage = _maskFillCoverage(fill, alpha);
      // Nothing is painted, so nothing is contributed — in particular this
      // shape must NOT be subtracted. See [_maskFillCoverage].
      //
      // 什么都没画，因此什么都不贡献——尤其是这个形状**不能**被减掉。见
      // [_maskFillCoverage]。
      if (coverage == _MaskCoverage.paintsNothing) return;
      final geometry = _geometryPath(node, effectiveAttributes);
      if (geometry == null) return;
      if (coverage == _MaskCoverage.shows) {
        shown.add(geometry, accum, rule);
      } else {
        hidden.add(geometry, accum, rule);
        anyHidden = true;
      }
    }

    walk(defRoot, const [1, 0, 0, 1, 0, 0], null, ui.PathFillType.nonZero);
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
    final shownPath = shown.build();
    var built = shownPath;
    if (anyHidden) {
      try {
        built = ui.Path.combine(
          ui.PathOperation.difference,
          shownPath,
          hidden.build(),
        );
      } on StateError {
        built = shownPath;
      }
    }
    defRoot
      ..cachedMaskClip = built
      ..maskClipSampleKey = signature
      ..maskClipViewportKey = _userViewport;
    return built;
  }

  /// Finds the last active replacement in the SMIL transform stack. / 查找 SMIL 变换栈中最后一条生效的替换轨道。
  int? _activeSmilTransformStart(SvgNode node) {
    if ((node.transform == null && node.transformAnimations.length <= 1) ||
        !node.hasSmilTransformReplacement) {
      return null;
    }
    for (var i = node.transformAnimations.length - 1; i >= 0; i--) {
      final animation = node.transformAnimations[i];
      if (animation.replacesTransformStack && animation.isActiveAt(time)) {
        return i;
      }
    }
    return null;
  }

  /// 本帧该节点应叠加的静态 transform；被 CSS transform 动画替换期间返回 null。
  List<double>? _activeStaticTransform(SvgNode node) {
    final staticTransform = node.transform;
    if (staticTransform == null || !node.replacesStaticTransform) {
      return staticTransform;
    }
    for (final a in node.transformAnimations) {
      if (a.replacesStaticTransform && a.isActiveAt(time)) return null;
    }
    return staticTransform;
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
    const absent = _kNoSample;
    final signature = <double>[];
    void walk(SvgNode node) {
      for (final animation in node.animations) {
        final sampled = animation.sample(time);
        signature.add(sampled ?? absent);
      }
      for (final pathAnimation in node.pathAnimations) {
        signature.add(pathAnimation.sample(time) ?? absent);
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
  ui.Path _resolveClipPath(SvgNode defRoot, Rect bounds) {
    if (!_activeClips.add(defRoot)) return ui.Path();
    final viewport = _userViewport;
    final objectUnits =
        defRoot.attributes['clipPathUnits'] == _objectBoundingBox;
    if (objectUnits) _userViewport = const Size.square(1);
    final union = _RegionBuilder();
    _appendClipGeometry(
      defRoot,
      _identityAffine,
      ResolvedStyle.initial,
      ui.PathFillType.nonZero,
      union,
    );
    final path = union.build();
    _userViewport = viewport;
    _activeClips.remove(defRoot);
    return objectUnits
        ? (bounds.isEmpty ? ui.Path() : _mapToBounds(path, bounds))
        : path;
  }

  /// Collects clip geometry, intersecting each explicit local clip before its transform. / 收集裁剪几何，并在变换前与各节点自己的裁剪相交。
  void _appendClipGeometry(
    SvgNode node,
    List<double> matrix,
    ResolvedStyle inherited,
    ui.PathFillType inheritedRule,
    _RegionBuilder output,
  ) {
    final attributes = _effectiveAttributes(node);
    if (attributes[_kDisplayAttribute] == _kNone) return;
    final style = _resolveStyle(node, inherited, attributes);
    var transform = _concatOwnTransform(matrix, node);
    if (node.dynamicUsePlacement) {
      transform = _concatUsePlacement(transform, attributes, style.fontSize);
    }
    final rule = parseSvgFillRule(
      attributes[kClipRuleAttribute],
      inheritedRule,
    );
    final clip = node.clipPathId == null ? null : clipPaths[node.clipPathId];
    if (clip == null) {
      _appendClipContent(node, attributes, transform, style, rule, output);
      return;
    }
    final local = _RegionBuilder();
    _appendClipContent(node, attributes, _identityAffine, style, rule, local);
    final shape = local.build();
    final intersection = _resolveClipPath(clip, shape.getBounds());
    try {
      final clipped = ui.Path.combine(
        ui.PathOperation.intersect,
        shape,
        intersection,
      );
      output.add(clipped, transform, ui.PathFillType.nonZero);
    } on StateError {
      // A degenerate intersection contributes no clip geometry. / 退化交集不贡献裁剪几何。
    }
  }

  /// Appends a clip node's own geometry or its children. / 追加裁剪节点的几何或子节点。
  void _appendClipContent(
    SvgNode node,
    Map<String, String> attributes,
    List<double> matrix,
    ResolvedStyle style,
    ui.PathFillType rule,
    _RegionBuilder output,
  ) {
    if (node.kind == SvgNodeKind.root || node.kind == SvgNodeKind.group) {
      for (final child in node.children) {
        _appendClipGeometry(child, matrix, style, rule, output);
      }
      return;
    }
    final geometry = _geometryPath(node, attributes, style.fontSize);
    if (geometry != null) output.add(geometry, matrix, rule);
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
    Map<String, String> attributes, {
    bool applyOpacity = true,
    double childOpacity = 1,
  }) {
    switch (node.kind) {
      case SvgNodeKind.root:
      case SvgNodeKind.group:
        if (node.isViewport) {
          _paintViewport(canvas, node, style, attributes, childOpacity);
          return;
        }
        // Indexed rather than `for (final child in ...)`: the latter allocates
        // a list iterator per group per frame, and a real icon's tree is
        // mostly groups.
        //
        // 用下标而非 `for (final child in ...)`：后者每个分组每帧都要分配一个
        // 列表迭代器，而真实图标的树里分组占多数。
        final children = node.children;
        for (var i = 0; i < children.length; i++) {
          _paintNode(
            canvas,
            children[i],
            style,
            opacityMultiplier: childOpacity,
          );
        }
      case SvgNodeKind.path:
      case SvgNodeKind.circle:
      case SvgNodeKind.rect:
      case SvgNodeKind.ellipse:
      case SvgNodeKind.line:
      case SvgNodeKind.polyline:
      case SvgNodeKind.polygon:
        final path = _geometryPath(node, attributes, style.fontSize);
        if (path != null) {
          _paintShape(canvas, node, path, style, applyOpacity: applyOpacity);
        }
      case SvgNodeKind.text:
        _paintText(canvas, node, style, attributes, applyOpacity: applyOpacity);
      case SvgNodeKind.image:
        final img = node.resolvedImage;
        if (img == null) {
          return; // not yet decoded / failed to decode: skip silently
        }
        final x = _num(attributes, 'x', style.fontSize);
        final y = _num(attributes, 'y', style.fontSize);
        final w =
            _length(attributes, 'width', style.fontSize) ??
            img.width.toDouble();
        final h =
            _length(attributes, 'height', style.fontSize) ??
            img.height.toDouble();
        if (w <= 0 || h <= 0) return;
        final source = Rect.fromLTWH(
          0,
          0,
          img.width.toDouble(),
          img.height.toDouble(),
        );
        final mapping = svgViewportTransform(
          [0, 0, source.width, source.height],
          w,
          h,
          attributes['preserveAspectRatio'],
        );
        final dest = mapping == null
            ? source.shift(Offset(x, y))
            : Rect.fromLTWH(
                x + mapping[4],
                y + mapping[5],
                source.width * mapping[0],
                source.height * mapping[3],
              );
        final viewport = Rect.fromLTWH(x, y, w, h);
        final clip =
            !viewport.contains(dest.topLeft) ||
            dest.right > viewport.right ||
            dest.bottom > viewport.bottom;
        if (clip) {
          canvas.save();
          canvas.clipRect(viewport, doAntiAlias: false);
        }
        canvas.drawImageRect(
          img,
          source,
          dest,
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, applyOpacity ? style.opacity : 1),
        );
        if (clip) canvas.restore();
    }
  }

  /// Paints children in a nested viewport. / 在嵌套视口中绘制子节点。
  void _paintViewport(
    Canvas canvas,
    SvgNode node,
    ResolvedStyle style,
    Map<String, String> attributes,
    double childOpacity,
  ) {
    final parent = _userViewport;
    final width = _length(attributes, 'width', style.fontSize) ?? parent.width;
    final height =
        _length(attributes, 'height', style.fontSize) ?? parent.height;
    if (width <= 0 || height <= 0) return;
    final x = _num(attributes, 'x', style.fontSize);
    final y = _num(attributes, 'y', style.fontSize);
    final box = node.viewportBox;
    final transform = svgViewportTransform(
      box,
      width,
      height,
      attributes['preserveAspectRatio'],
    );
    canvas.save();
    if (attributes['overflow'] != 'visible') {
      canvas.clipRect(Rect.fromLTWH(x, y, width, height), doAntiAlias: false);
    }
    canvas.translate(x, y);
    if (transform != null) canvas.transform(affineToMatrix4(transform));
    _userViewport = box == null ? Size(width, height) : Size(box[2], box[3]);
    for (final child in node.children) {
      _paintNode(canvas, child, style, opacityMultiplier: childOpacity);
    }
    _userViewport = parent;
    canvas.restore();
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
  ui.Path? _geometryPath(
    SvgNode node,
    Map<String, String> attributes, [
    double fontSize = svgInitialFontSize,
  ]) {
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
    // `XvgDocumentCache`): both keys are time-independent, so two widgets
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
    // 文档在多个控件间共享（见 `XvgDocumentCache`）时的正确性：两个键都与时间
    // 无关，所以在不同时间线位置绘制同一文档的两个控件，要么共享一个有效条目，
    // 要么未命中后重建——绝不会读到过期结果。
    final morphPath = node.animatedMorphPath;
    if (morphPath != null && node.kind == SvgNodeKind.path) return morphPath;
    final Object? cacheKey = node.kind == SvgNodeKind.path
        ? attributes['d']
        : attributes;
    final lengthKey = node.kind == SvgNodeKind.path
        ? null
        : (_userViewport.width, _userViewport.height, fontSize);
    if (cacheKey != null &&
        identical(node.geometryCacheKey, cacheKey) &&
        node.geometryLengthKey == lengthKey) {
      return node.cachedGeometry;
    }
    final built = _buildGeometryPath(node.kind, attributes, fontSize);
    if (cacheKey != null) {
      node.geometryCacheKey = cacheKey;
      node.geometryLengthKey = lengthKey;
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
    double fontSize,
  ) {
    switch (kind) {
      case SvgNodeKind.path:
        final d = attributes['d'];
        return d == null ? null : parseSvgPathData(d);
      case SvgNodeKind.circle:
        final cx = _num(attributes, 'cx', fontSize);
        final cy = _num(attributes, 'cy', fontSize);
        final r = _num(attributes, 'r', fontSize);
        if (r <= 0) return null;
        return ui.Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      case SvgNodeKind.rect:
        final x = _num(attributes, 'x', fontSize);
        final y = _num(attributes, 'y', fontSize);
        final w = _num(attributes, 'width', fontSize);
        final h = _num(attributes, 'height', fontSize);
        if (w <= 0 || h <= 0) {
          return null; // SVG: non-positive size renders nothing
        }
        var rx = _length(attributes, 'rx', fontSize);
        var ry = _length(attributes, 'ry', fontSize);
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
        final cx = _num(attributes, 'cx', fontSize);
        final cy = _num(attributes, 'cy', fontSize);
        final rx = _num(attributes, 'rx', fontSize);
        final ry = _num(attributes, 'ry', fontSize);
        if (rx <= 0 || ry <= 0) return null;
        return ui.Path()..addOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: rx * 2,
            height: ry * 2,
          ),
        );
      case SvgNodeKind.line:
        final x1 = _num(attributes, 'x1', fontSize);
        final y1 = _num(attributes, 'y1', fontSize);
        final x2 = _num(attributes, 'x2', fontSize);
        final y2 = _num(attributes, 'y2', fontSize);
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

  /// Lays out a line of positioned text chunks, painting or measuring its bounds. / 布置单行文字定位块，并绘制或测量其包围盒。
  Rect? _paintText(
    Canvas? canvas,
    SvgNode node,
    ResolvedStyle style,
    Map<String, String> attributes, {
    bool applyOpacity = true,
  }) {
    var cursor = Offset.zero;
    _SvgTextChunk? currentChunk;
    final chunks = <_SvgTextChunk>[];

    void collect(
      SvgNode current,
      ResolvedStyle style,
      Map<String, String> attrs,
      double opacity,
    ) {
      final fontSize = style.fontSize;
      final x = _length(attrs, 'x', fontSize);
      final y = _length(attrs, 'y', fontSize);
      if (x != null || y != null) currentChunk = null;
      cursor = Offset(
        (x ?? cursor.dx) + _num(attrs, 'dx', fontSize),
        (y ?? cursor.dy) + _num(attrs, 'dy', fontSize),
      );
      for (final child in current.children) {
        final childAttrs = _effectiveAttributes(child);
        if (childAttrs[_kDisplayAttribute] == _kNone) continue;
        final childStyle = _resolveStyle(child, style, childAttrs);
        collect(child, childStyle, childAttrs, opacity * childStyle.opacity);
      }
      final content = current.textContent;
      if (content == null || content.isEmpty || fontSize <= 0) return;
      final alpha = opacity * style.fillOpacity;
      final painter = _layoutText(current, content, style, alpha);
      var chunk = currentChunk;
      if (chunk == null) {
        chunk = _SvgTextChunk(cursor.dx, style.textAnchor);
        currentChunk = chunk;
        chunks.add(chunk);
      }
      chunk.runs.add((
        painter: painter,
        origin: cursor.translate(
          0,
          -painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
        ),
        visible: style.fill != null && alpha > 0,
      ));
      cursor = cursor.translate(painter.width, 0);
      chunk.end = cursor.dx;
    }

    collect(node, style, attributes, applyOpacity ? style.opacity : 1);
    Rect? bounds;
    for (final chunk in chunks) {
      final advance = chunk.end - chunk.start;
      final dx = switch (chunk.anchor) {
        'middle' => -advance / 2,
        'end' => -advance,
        _ => 0.0,
      };
      for (final run in chunk.runs) {
        final origin = run.origin.translate(dx, 0);
        if (canvas != null) {
          if (run.visible) run.painter.paint(canvas, origin);
        } else {
          final rect = origin & run.painter.size;
          bounds = bounds?.expandToInclude(rect) ?? rect;
        }
      }
    }
    return bounds;
  }

  /// Caches paragraph layout while font, paint and content are unchanged. / 在字体、涂料和内容不变时复用段落布局。
  TextPainter _layoutText(
    SvgNode node,
    String content,
    ResolvedStyle style,
    double alpha,
  ) {
    final cached = node.cachedTextPainter as TextPainter?;
    if (cached != null &&
        identical(node.textPainterStyleKey, style) &&
        node.textPainterOpacityKey == alpha) {
      return cached;
    }
    final fill = style.fill;
    cached?.dispose();
    final painter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          fontSize: style.fontSize,
          fontFamily: style.fontFamily,
          color: fill == null ? const Color(0x00000000) : _fade(fill, alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    node
      ..cachedTextPainter = painter
      ..textPainterStyleKey = style
      ..textPainterOpacityKey = alpha;
    return painter;
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
  /// default for each node unless its own `opacity` attribute says otherwise.
  ///
  /// [color] 按 [opacity] 淡化后的颜色；完全不透明时原样返回 [color]。
  ///
  /// `Color.withValues` 会用四个浮点分量构造一个全新的 [Color]；当
  /// `opacity == 1` 时新颜色与原颜色相等，这次分配纯属浪费——而完全不透明正是
  /// 每个节点在没有自身 `opacity` 属性时的默认值。
  static Color _fade(Color color, double opacity) =>
      opacity == 1 ? color : color.withValues(alpha: color.a * opacity);

  /// The stroke path to draw for [node]: [path] itself for a solid stroke, or
  /// its dashed derivative, reusing the one cached on the node when all three
  /// inputs `dashPath` reads are unchanged (see [SvgNode.cachedDashedPath]).
  ///
  /// 为 [node] 绘制描边时应使用的路径：实线描边直接用 [path] 本身，否则用它的
  /// 虚线派生路径；当 `dashPath` 读取的三个输入都没变时，复用缓存在节点上的那条
  /// （见 [SvgNode.cachedDashedPath]）。
  ///
  /// [node] — the node being stroked, which owns the cache.
  ///
  ///   正在被描边的节点，缓存挂在它身上。
  ///
  /// [path] — the node's solid geometry path. / 节点的实线几何路径。
  ///
  /// [style] — the resolved style carrying the dash pattern and phase.
  ///
  ///   携带虚线图案与相位的已解析样式。
  ///
  /// Returns the path to hand to `drawPath`. / 返回交给 `drawPath` 的路径。
  ui.Path _strokePath(SvgNode node, ui.Path path, ResolvedStyle style) {
    final dashArray = style.strokeDasharray;
    if (dashArray.isEmpty) return path;
    final dashOffset = style.strokeDashoffset;
    final pathLength = resolveSvgLength(
      (node.cachedAnimatedAttributes ?? node.attributes)['pathLength'],
    );
    final cached = node.cachedDashedPath;
    if (cached != null &&
        identical(node.dashedPathSourceKey, path) &&
        identical(node.dashedPathArrayKey, dashArray) &&
        node.dashedPathOffsetKey == dashOffset &&
        node.dashedPathLengthKey == pathLength) {
      return cached;
    }
    final dashed = dashPath(
      path,
      dashArray: dashArray,
      dashOffset: dashOffset,
      pathLength: pathLength,
    );
    node
      ..cachedDashedPath = dashed
      ..dashedPathSourceKey = path
      ..dashedPathArrayKey = dashArray
      ..dashedPathOffsetKey = dashOffset
      ..dashedPathLengthKey = pathLength;
    return dashed;
  }

  /// Paints fill and stroke in the resolved SVG order. / 按 SVG 样式指定的顺序绘制填充和描边。
  void _paintShape(
    Canvas canvas,
    SvgNode node,
    ui.Path path,
    ResolvedStyle style, {
    bool applyOpacity = true,
  }) {
    final fillAlpha = applyOpacity ? style.fillAlpha : style.fillOpacity;
    final strokeAlpha = applyOpacity ? style.strokeAlpha : style.strokeOpacity;
    if (style.strokeFirst) _paintStroke(canvas, node, path, style, strokeAlpha);
    _paintFill(canvas, path, style, fillAlpha);
    if (!style.strokeFirst) {
      _paintStroke(canvas, node, path, style, strokeAlpha);
    }
  }

  /// Paints the fill with its rule and solid fallback. / 根据填充规则与回退色绘制形状。
  void _paintFill(
    Canvas canvas,
    ui.Path path,
    ResolvedStyle style,
    double fillAlpha,
  ) {
    if (fillAlpha > 0) {
      // fill-rule：几何 Path 是挂在节点上的共享缓存，默认且始终保持 nonZero。
      // 只有 evenodd 的节点才临时改写，填充画完立刻还原——默认节点只多一次字段
      // 比较、不碰原生调用、不分配对象，描边/虚线/包围盒也不会读到被改过的值。
      final evenOdd = style.fillRule == ui.PathFillType.evenOdd;
      if (evenOdd) path.fillType = ui.PathFillType.evenOdd;
      final fillShader = _gradientShader(style.fillGradientId, path, fillAlpha);
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
            ..color = _fade(style.fill!, fillAlpha),
        );
      }
      if (evenOdd) path.fillType = ui.PathFillType.nonZero;
    }
  }

  /// Paints the stroke with its dash pattern and paint fallback. / 使用虚线图案与回退涂料绘制描边。
  void _paintStroke(
    Canvas canvas,
    SvgNode node,
    ui.Path path,
    ResolvedStyle style,
    double strokeAlpha,
  ) {
    if (strokeAlpha <= 0 || style.strokeWidth <= 0) return;
    final strokeShader = _gradientShader(
      style.strokeGradientId,
      path,
      strokeAlpha,
    );
    if (strokeShader != null) {
      canvas.drawPath(
        _strokePath(node, path, style),
        Paint()
          ..style = PaintingStyle.stroke
          ..shader = strokeShader
          ..strokeWidth = style.strokeWidth
          ..strokeCap = style.strokeLinecap
          ..strokeJoin = style.strokeLinejoin,
      );
      return;
    }
    if (style.stroke != null) {
      canvas.drawPath(
        _strokePath(node, path, style),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _fade(style.stroke!, strokeAlpha)
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
      oldDelegate.intrinsicSize != intrinsicSize ||
      !listEquals(oldDelegate.rootViewBoxTransform, rootViewBoxTransform) ||
      oldDelegate.theme != theme ||
      oldDelegate.fit != fit ||
      oldDelegate.alignment != alignment ||
      oldDelegate.gradients != gradients ||
      oldDelegate.clipPaths != clipPaths ||
      oldDelegate.masks != masks ||
      oldDelegate.quality != quality ||
      oldDelegate.backgroundColor != backgroundColor;
}

/// `<mask>` 上的 `mask-type` 属性名。
/// Text runs that share a text-anchor shift. / 共享文字锚点位移的一组文字段。
class _SvgTextChunk {
  /// Starts a chunk at the first glyph origin. / 从首个字符原点开始定位块。
  _SvgTextChunk(this.start, this.anchor) : end = start;

  /// The first glyph's baseline x. / 首个字符的基线横坐标。
  final double start;

  /// Computed text-anchor of the first run. / 首段的计算文字锚点。
  final String? anchor;

  /// The cursor after the final run. / 最后一段之后的光标位置。
  double end;

  /// Paragraphs in document order. / 按文档顺序排列的段落。
  final runs = <({TextPainter painter, Offset origin, bool visible})>[];
}

const _objectBoundingBox = 'objectBoundingBox';
const _userSpaceOnUse = 'userSpaceOnUse';
const _identityAffine = <double>[1, 0, 0, 1, 0, 0];

const String _kMaskTypeAttribute = 'mask-type';

/// `mask-type` 的 alpha 取值（小写，比较前已转小写）。
const String _kMaskTypeAlpha = 'alpha';

/// `display` 属性名与隐藏取值。
const String _kDisplayAttribute = 'display';
const String _kNone = 'none';

/// 采样键里"该时间线此刻没有值"的哨兵；必须是无穷而非 NaN，否则每帧都判为变化。
const double _kNoSample = double.negativeInfinity;

/// 把若干带各自填充规则的子形状合成一个区域路径，供 `<clipPath>` 与 mask 的裁剪
/// 近似使用。
///
/// 单个 [ui.Path] 只有一个 fillType，所以 nonzero 子形状照旧并入 [_base]（与引入
/// 规则前的合成方式逐位一致），evenodd 子形状先各自带着 fillType 存成独立副本，
/// [build] 时用 `Path.combine(union, …)` 逐个并入——它对每个输入各自按其 fillType
/// 求区域，规则不会丢。没有 evenodd 子形状时 [build] 直接返回 [_base]，没有额外开销。
class _RegionBuilder {
  /// 全部 nonzero 子形状累加成的路径。
  final ui.Path _base = ui.Path();

  /// evenodd 子形状的独立副本（已变换、已设 fillType）；首次需要时才分配。
  List<ui.Path>? _evenOdd;

  /// 把 [geometry] 经仿射矩阵 [affine] 变换后，按 [rule] 加入区域。
  ///
  /// [geometry] 可能是节点上的共享缓存，这里不会改写它。
  void add(ui.Path geometry, List<double> affine, ui.PathFillType rule) {
    final matrix4 = affineToMatrix4(affine);
    if (rule == ui.PathFillType.nonZero) {
      _base.addPath(geometry, Offset.zero, matrix4: matrix4);
      return;
    }
    // transform 返回的是新副本，可以放心写 fillType。
    (_evenOdd ??= <ui.Path>[]).add(
      geometry.transform(matrix4)..fillType = rule,
    );
  }

  /// 返回合成后的区域路径。
  ///
  /// `Path.combine` 遇到退化输入会抛 [StateError]；此时退回把该子形状直接并入
  /// （按 nonzero 填满，宁可多裁出一点也不把整个形状丢掉）。
  ui.Path build() {
    final evenOdd = _evenOdd;
    if (evenOdd == null) return _base;
    var region = _base;
    for (final path in evenOdd) {
      try {
        region = ui.Path.combine(ui.PathOperation.union, region, path);
      } on StateError {
        region.addPath(path, Offset.zero);
      }
    }
    return region;
  }
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
