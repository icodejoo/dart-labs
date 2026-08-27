// Parses raw SVG source into the [SvgNode] tree using `package:xml` (a
// normal pubspec dependency, not vendored code — see svgx CLAUDE.md). Also
// computes the animated document's total timeline duration. Original
// implementation.
//
// This file is the ONLY place `package:xml` (or any other parsing-technology
// detail) is allowed to leak into: [parseAnimatedSvgDocument] is the single
// String-in / plain-data-out boundary between "how the SVG source gets
// turned into a timeline" and "how the timeline gets sampled + painted"
// (`smil_animation.dart`, `animated_svg_painter.dart`, `animated_svg_widget.dart`,
// and the `SvgX` dispatch in `svgx_widget.dart` only ever see [SvgDocument]/
// [SvgNode]/[SmilAnimation] — plain data classes, no xml types). Per
// CLAUDE.md's architecture notes, parsing + timeline-building may move to
// Rust/FFI later if profiling calls for it; that would only mean swapping
// this function's implementation, not touching the sampling/painting layers.
// This is intentionally just a function + a plain model — no interface,
// registry, or plugin scaffolding for a swap that hasn't been decided yet.
//
// 本文件是唯一允许出现 `package:xml`（或任何解析技术细节）的地方：
// [parseAnimatedSvgDocument] 是"SVG 源串如何变成时间线"与"时间线如何被采样
// 和绘制"（`smil_animation.dart`、`animated_svg_painter.dart`、
// `animated_svg_widget.dart`，以及 `svgx_widget.dart` 里的 `SvgX` 分发）之间
// 唯一的、字符串进/纯数据出的边界——下游只认 [SvgDocument]/[SvgNode]/
// [SmilAnimation] 这些纯数据类，不认识任何 xml 类型。按 CLAUDE.md 的架构
// 决策，解析 + 建时间线未来可能下沉到 Rust/FFI；届时只需替换本函数的实现，
// 采样/绘制层不用动。这里刻意只做"一个函数 + 一份纯数据模型"，不为一个还没
// 定下来的替换需求搭接口/注册表/插件脚手架。

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';

import 'native_svg_values.dart';
import 'smil_animation.dart';
import 'svg_dom.dart';
import 'svg_gradient.dart';
import 'svg_path_data.dart';
import 'svg_style.dart';

/// The result of parsing an animated SVG document: the element tree plus its
/// intrinsic size and total animation duration.
///
/// 解析动画 SVG 文档的结果：元素树，及其固有尺寸与动画总时长。
class SvgDocument {
  /// Creates a parsed document. / 创建一个已解析文档。
  const SvgDocument({
    required this.root,
    required this.width,
    required this.height,
    required this.totalDuration,
    required this.hasIndefiniteLoop,
    this.gradients = const {},
    this.clipPaths = const {},
    this.masks = const {},
    this.usesOffscreenLayers = false,
  });

  /// Whether painting this document requires at least one `canvas.saveLayer`
  /// offscreen render target — true when any element carries a `mask`
  /// reference or a Gaussian-blur `filter`.
  ///
  /// This is a *rasterization cost* signal, not a feature flag: an offscreen
  /// layer means the GPU allocates a render target, switches to it, replays
  /// the subtree into it, and composites the result back — on a mid-range
  /// GLES device that is measurably the most expensive thing this engine can
  /// ask for per frame (see `docs/performance-benchmarks.md`). It is used to
  /// let the frame-rate degradation in `SvgXAnimationQuality` treat these
  /// documents more aggressively than cheap ones.
  ///
  /// 绘制本文档是否至少需要一个 `canvas.saveLayer` 离屏渲染目标——任何元素带
  /// `mask` 引用或高斯模糊 `filter` 时为 true。
  ///
  /// 这是一个*光栅化成本*信号，不是功能开关：一个离屏图层意味着 GPU 要分配
  /// 渲染目标、切换过去、把子树重放进去、再把结果合成回来——在中端 GLES 设备上
  /// 实测这是本引擎每帧能提出的最贵请求（见 `docs/performance-benchmarks.md`）。
  /// 它的用途是让 `SvgXAnimationQuality` 里的帧率降级对这类文档比对廉价文档
  /// 更激进。
  final bool usesOffscreenLayers;

  /// `<clipPath>` definitions by id, as parsed [SvgNode] subtrees (their own
  /// `<animate>`/`<animateTransform>` children intact) — referenced by
  /// [SvgNode.clipPathId]. See `animated_svg_painter.dart` for how a
  /// referenced subtree is turned into a clip path at paint time, sampled at
  /// the current frame.
  ///
  /// 按 id 索引的 `<clipPath>` 定义，以已解析的 [SvgNode] 子树形式保存（自身的
  /// `<animate>`/`<animateTransform>` 子元素原样保留）——由
  /// [SvgNode.clipPathId] 引用。绘制时如何把被引用的子树变成裁剪路径（在当前帧
  /// 采样）见 `animated_svg_painter.dart`。
  final Map<String, SvgNode> clipPaths;

  /// `<mask>` definitions by id, same shape as [clipPaths] — referenced by
  /// [SvgNode.maskId].
  ///
  /// 按 id 索引的 `<mask>` 定义，形态与 [clipPaths] 相同——由 [SvgNode.maskId]
  /// 引用。
  final Map<String, SvgNode> masks;

  /// `<linearGradient>`/`<radialGradient>` definitions by id, for elements
  /// painted with `fill="url(#id)"` / `stroke="url(#id)"`. Static only — see
  /// `svg_gradient.dart`.
  ///
  /// 按 id 索引的 `<linearGradient>`/`<radialGradient>` 定义，供
  /// `fill="url(#id)"`/`stroke="url(#id)"` 的元素使用。仅静态渐变——见
  /// `svg_gradient.dart`。
  final Map<String, SvgGradientDef> gradients;

  /// The root `<svg>` node. / 根 `<svg>` 节点。
  final SvgNode root;

  /// Intrinsic width from `viewBox`/`width`. / 来自 `viewBox`/`width` 的固有宽度。
  final double width;

  /// Intrinsic height from `viewBox`/`height`. / 来自 `viewBox`/`height` 的固有高度。
  final double height;

  /// The latest `begin + dur * repeatCount` across every finite-repeat
  /// `<animate>`/`<animateTransform>` in the document — the point at which
  /// the whole document has settled into its final state. Meaningless (but
  /// still computed from the finite animations) when [hasIndefiniteLoop] is
  /// true, since the document then never settles.
  ///
  /// 文档内所有有限重复的 `<animate>`/`<animateTransform>` 中最晚的
  /// `begin + dur * repeatCount`——整份文档进入最终状态的时间点。当
  /// [hasIndefiniteLoop] 为 true 时此值无实际意义（仍按有限动画计算），
  /// 因为文档届时永不会安定下来。
  final Duration totalDuration;

  /// Whether any animation in the document has `repeatCount="indefinite"`,
  /// meaning the document must keep animating forever (see
  /// `animated_svg_widget.dart`'s ticker).
  ///
  /// 文档内是否存在 `repeatCount="indefinite"` 的动画，意味着必须持续播放
  /// 动画（见 `animated_svg_widget.dart` 的 ticker）。
  final bool hasIndefiniteLoop;
}

/// Parses [source] (a raw SVG string) into a [SvgDocument].
///
/// Recognizes `<svg>`, `<g>`, `<path>`, `<circle>`, `<rect>`, `<ellipse>`,
/// `<line>`, `<polyline>`, `<polygon>`, `<image>`, `<use>` and their
/// `<animate>`/`<animateTransform>`/`<animateMotion>` children, plus
/// `<linearGradient>`/`<radialGradient>` definitions — see [SvgNodeKind],
/// [SmilAnimation], [SmilTransformAnimation], [SmilMotionAnimation] and
/// [SvgGradientDef] for the exact supported subset. Unrecognized
/// elements are skipped (their children are not visited), which keeps
/// unsupported constructs invisible rather than mis-rendered.
///
/// 把 [source]（原始 SVG 字符串）解析为 [SvgDocument]。
///
/// 识别 `<svg>`、`<g>`、`<path>`、`<circle>`、`<rect>`、`<ellipse>`、
/// `<line>`、`<polyline>`、`<polygon>` 及其 `<animate>`/`<animateTransform>`
/// 子元素——具体支持范围见 [SvgNodeKind]、[SmilAnimation] 与
/// [SmilTransformAnimation]。无法识别的元素会被跳过（不遍历其子节点），使
/// 不支持的结构表现为"不可见"而非"渲染错误"。
SvgDocument parseAnimatedSvgDocument(String source) {
  final document = XmlDocument.parse(source);
  final svgElement = document.rootElement;

  final viewBox = svgElement.getAttribute('viewBox');
  double width = double.tryParse(svgElement.getAttribute('width') ?? '') ?? 0;
  double height = double.tryParse(svgElement.getAttribute('height') ?? '') ?? 0;
  if (viewBox != null) {
    final parts = viewBox
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (parts.length == 4 && parts.every((v) => v != null)) {
      width = width == 0 ? parts[2]! : width;
      height = height == 0 ? parts[3]! : height;
    }
  }
  if (width == 0) width = 24;
  if (height == 0) height = 24;

  final context = _ParseContext(
    elementsById: {
      for (final element in document.descendants.whereType<XmlElement>())
        if (element.getAttribute('id') != null)
          element.getAttribute('id')!: element,
    },
  );
  final root = _parseElement(svgElement, SvgNodeKind.root, context);
  final clipPaths = _parseDefsByTag('clipPath', context);
  final masks = _parseDefsByTag('mask', context);
  final gradients = _parseGradients(context);

  // Syncbase `begin` values ("other.end+0.2s") can only be turned into absolute
  // times once every animation in the document is known — including ones on
  // <clipPath>/<mask>/gradient <stop> content parsed just above — so this
  // happens here, once, after every subtree is built, never per frame.
  //
  // 同步基准 `begin`（"other.end+0.2s"）只有在文档内所有动画都已知后才能变成
  // 绝对时间——包括刚才解析的 <clipPath>/<mask>/渐变 <stop> 内容上的动画——因此
  // 在所有子树都构建完成后一次性在此解析，绝不逐帧解析。
  resolveSmilBeginTimes(context.animations);

  var maxEnd = Duration.zero;
  var hasIndefiniteLoop = false;
  for (final animation in context.animations) {
    if (animation.begin == kSmilNeverBegins) continue; // disabled: never fires
    if (animation.repeatCount.indefinite) {
      hasIndefiniteLoop = true;
      continue;
    }
    final activeMicros =
        (animation.duration.inMicroseconds * animation.repeatCount.count)
            .round();
    final end = animation.begin + Duration(microseconds: activeMicros);
    if (end > maxEnd) maxEnd = end;
  }

  return SvgDocument(
    root: root,
    width: width,
    height: height,
    totalDuration: maxEnd,
    hasIndefiniteLoop: hasIndefiniteLoop,
    gradients: gradients,
    clipPaths: clipPaths,
    masks: masks,
    usesOffscreenLayers: context.sawOffscreenLayer,
  );
}

/// Parses every top-level `<clipPath>`/`<mask>` element (identified by
/// [tag]) that carries an id into an [SvgNode] subtree, the same way the main
/// document tree is built — so their content's own `<animate>`/
/// `<animateTransform>` timelines are registered on [context] like any other,
/// and can themselves be sampled per-frame at paint time.
///
/// 把每个带 id 的顶层 `<clipPath>`/`<mask>` 元素（由 [tag] 指定）解析为
/// [SvgNode] 子树，方式与主文档树的构建完全相同——因此其内容自身的
/// `<animate>`/`<animateTransform>` 时间线会像其它动画一样注册到 [context]
/// 上，绘制时也能逐帧被采样。
Map<String, SvgNode> _parseDefsByTag(String tag, _ParseContext context) {
  final defs = <String, SvgNode>{};
  for (final entry in context.elementsById.entries) {
    if (entry.value.name.local != tag) continue;
    defs[entry.key] = _parseElement(entry.value, SvgNodeKind.group, context);
  }
  return defs;
}

const _gradientTags = {'linearGradient', 'radialGradient'};

/// Builds the document's gradient table from every `<linearGradient>`/
/// `<radialGradient>` that carries an id, wherever it sits in the document.
///
/// 从文档中任意位置、带 id 的每个 `<linearGradient>`/`<radialGradient>` 构建
/// 文档的渐变表。
Map<String, SvgGradientDef> _parseGradients(_ParseContext context) {
  final defs = <String, SvgGradientDef>{};
  for (final entry in context.elementsById.entries) {
    if (!_gradientTags.contains(entry.value.name.local)) continue;
    final def = _buildGradient(entry.value, context, <String>{});
    if (def != null) defs[entry.key] = def;
  }
  return defs;
}

/// Resolves one gradient element, following its `href`/`xlink:href`
/// inheritance chain for any attribute (or the stop list) it doesn't declare
/// itself.
///
/// [visiting] carries the ids already on the current chain so a cyclic
/// `href` (`a` → `b` → `a`) stops instead of recursing forever; a cycle simply
/// ends the inheritance walk, leaving whatever was resolved so far.
///
/// 解析单个渐变元素，对其自身未声明的属性（或色标列表）沿
/// `href`/`xlink:href` 继承链向上查找。
///
/// [visiting] 记录当前链上已访问的 id，使 `href` 成环（`a` → `b` → `a`）时停止
/// 而不是无限递归；成环只是结束继承查找，保留此前已解析到的内容。
SvgGradientDef? _buildGradient(
  XmlElement element,
  _ParseContext context,
  Set<String> visiting,
) {
  final elementsById = context.elementsById;
  final id = element.getAttribute('id');
  if (id != null && !visiting.add(id)) return null; // href cycle

  final attributes = <String, String>{
    for (final a in element.attributes) a.name.local: a.value,
  };
  var stops = _parseStops(element);
  var stopNodes = _parseStopNodes(element, context);

  // Walks the full href chain (not just the immediate parent) merging each
  // ancestor's own attributes, so a geometry attribute (x1/y1/.../fy) missing
  // on both this element AND its immediate parent still resolves from a
  // grandparent (a → b → c where only `c` declares it). `chainVisited` bounds
  // the walk against a cyclic href the same way [visiting] bounds the
  // recursive stop-list resolution below.
  //
  // 遍历完整的 href 链（而非只查直接父级），合并每一级祖先自身的属性——使得
  // 某个几何属性（x1/y1/…/fy）在本元素与其直接父级上都缺失时，仍能从祖父级
  // 解析出来（a → b → c，只有 `c` 声明了该属性）。`chainVisited` 约束遍历，
  // 防止 href 成环，与下方 [visiting] 约束递归解析色标列表同理。
  final immediateHref = attributes['href']?.trim();
  final chainVisited = <String>{?id};
  var current = element;
  while (true) {
    final h = current.getAttribute('href')?.trim();
    if (h == null || !h.startsWith('#')) break;
    final parentId = h.substring(1);
    if (!chainVisited.add(parentId)) break; // href cycle
    final parent = elementsById[parentId];
    if (parent == null || !_gradientTags.contains(parent.name.local)) break;
    final parentAttributes = <String, String>{
      for (final a in parent.attributes) a.name.local: a.value,
    };
    for (final entry in parentAttributes.entries) {
      attributes.putIfAbsent(entry.key, () => entry.value);
    }
    current = parent;
  }
  if (immediateHref != null && immediateHref.startsWith('#') && stops.isEmpty) {
    final parent = elementsById[immediateHref.substring(1)];
    if (parent != null && _gradientTags.contains(parent.name.local)) {
      final parentDef = _buildGradient(parent, context, visiting);
      stops = parentDef?.stops ?? const [];
      stopNodes = parentDef?.stopNodes ?? const [];
    }
  }
  if (id != null) visiting.remove(id);
  if (stops.isEmpty) return null;

  final animatedNode = _parseGradientAttributeAnimations(element, context);

  final radial = element.name.local == 'radialGradient';
  final rawTransform = attributes['gradientTransform'];
  double number(String key, double fallback) {
    final raw = attributes[key];
    if (raw == null) return fallback;
    final trimmed = raw.trim();
    // Percentages are the only unit that shows up on gradient coordinates in
    // practice; anything else parses as a plain number.
    //
    // 实际会出现在渐变坐标上的单位只有百分比；其余一律按普通数字解析。
    if (trimmed.endsWith('%')) {
      final n = double.tryParse(trimmed.substring(0, trimmed.length - 1));
      return n == null ? fallback : n / 100;
    }
    return double.tryParse(trimmed) ?? fallback;
  }

  return SvgGradientDef(
    radial: radial,
    stops: stops,
    objectBoundingBox: attributes['gradientUnits'] != 'userSpaceOnUse',
    tileMode: switch (attributes['spreadMethod']) {
      'reflect' => TileMode.mirror,
      'repeat' => TileMode.repeated,
      _ => TileMode.clamp,
    },
    x1: number('x1', 0),
    y1: number('y1', 0),
    x2: number('x2', 1),
    y2: number('y2', 0),
    cx: number('cx', 0.5),
    cy: number('cy', 0.5),
    r: number('r', 0.5),
    fx: attributes.containsKey('fx') ? number('fx', 0.5) : null,
    fy: attributes.containsKey('fy') ? number('fy', 0.5) : null,
    gradientTransform: rawTransform == null
        ? null
        : parseTransformMatrix(rawTransform),
    stopNodes: stopNodes,
    animatedNode: animatedNode,
  );
}

/// Numeric attributes an `<animate>` may target directly on a
/// `<linearGradient>`/`<radialGradient>` element (as opposed to on one of its
/// `<stop>` children) — see [_parseGradientAttributeAnimations].
///
/// `<animate>` 可直接作用在 `<linearGradient>`/`<radialGradient>` 元素本身
/// （而非其 `<stop>` 子元素）上的数值属性——见 [_parseGradientAttributeAnimations]。
const _gradientNumericAttributes = {
  'x1',
  'y1',
  'x2',
  'y2',
  'cx',
  'cy',
  'r',
  'fx',
  'fy',
};

/// Builds the [SvgNode] carrying a gradient element's own `<animate>`
/// children targeting `x1`/`y1`/`x2`/`y2`/`cx`/`cy`/`r`/`fx`/`fy` — resampled
/// every frame by `svg_gradient.dart`'s `resampleGradientAtTime`, overriding
/// [SvgGradientDef]'s static geometry. Its attribute map mirrors the
/// element's own so a resample without any matching animation just reproduces
/// the original values (see `_stopFromAttributes`-style fallback pattern in
/// the resampler).
///
/// 构建承载渐变元素自身 `<animate>` 子元素（作用于
/// `x1`/`y1`/`x2`/`y2`/`cx`/`cy`/`r`/`fx`/`fy`）的 [SvgNode]——由
/// `svg_gradient.dart` 的 `resampleGradientAtTime` 逐帧重采样，覆盖
/// [SvgGradientDef] 的静态几何。其属性表镜像元素自身的属性，因此没有匹配动画
/// 时重采样只会原样复现原始值（重采样器中与 `_stopFromAttributes` 相同的回退
/// 模式）。
SvgNode _parseGradientAttributeAnimations(
  XmlElement element,
  _ParseContext context,
) {
  final attributes = <String, String>{
    for (final a in element.attributes) a.name.local: a.value,
  };
  final animations = <SmilAnimation>[];
  for (final child in element.childElements) {
    if (child.name.local != 'animate') continue;
    final attributeName = child.getAttribute('attributeName');
    if (attributeName == null ||
        !_gradientNumericAttributes.contains(attributeName)) {
      continue;
    }
    final anim = _parseAnimate(child);
    if (anim != null) {
      animations.add(anim);
      context.animations.add(anim);
    }
  }
  return SvgNode(
    kind: SvgNodeKind.group,
    attributes: attributes,
    animations: animations,
  );
}

/// Builds one [SvgNode] per `<stop>` child, parallel to (and in the same
/// order as) [_parseStops]' output, carrying each stop's own `<animate>`
/// children — numeric ones (`stop-opacity`/`offset`) via [SvgNode.animations],
/// `stop-color` via [SvgNode.colorAnimations] (see [_parseAnimateColor]).
/// Resampled every frame by `svg_gradient.dart`'s `resampleGradientAtTime`.
///
/// 为每个 `<stop>` 子元素构建一个 [SvgNode]，与 [_parseStops] 的输出并行对应
/// （顺序一致），携带该色标自身的 `<animate>` 子元素——数值型
/// （`stop-opacity`/`offset`）经 [SvgNode.animations]，`stop-color` 经
/// [SvgNode.colorAnimations]（见 [_parseAnimateColor]）。由 `svg_gradient.dart`
/// 的 `resampleGradientAtTime` 逐帧重采样。
List<SvgNode> _parseStopNodes(XmlElement element, _ParseContext context) {
  final nodes = <SvgNode>[];
  for (final child in element.childElements) {
    if (child.name.local != 'stop') continue;
    final attributes = <String, String>{
      for (final a in child.attributes) a.name.local: a.value,
    };
    _normalizeColorAttributes(attributes);
    final numericAnimations = <SmilAnimation>[];
    final colorAnimations = <SmilColorAnimation>[];
    for (final grandchild in child.childElements) {
      if (grandchild.name.local != 'animate') continue;
      final attributeName = grandchild.getAttribute('attributeName');
      if (attributeName == 'stop-color') {
        final anim = _parseAnimateColor(grandchild);
        if (anim != null) {
          colorAnimations.add(anim);
          context.animations.add(anim);
        }
      } else {
        final anim = _parseAnimate(grandchild);
        if (anim != null) {
          numericAnimations.add(anim);
          context.animations.add(anim);
        }
      }
    }
    nodes.add(
      SvgNode(
        kind: SvgNodeKind.group,
        attributes: attributes,
        animations: numericAnimations,
        colorAnimations: colorAnimations,
      ),
    );
  }
  return nodes;
}

/// Parses an `<animate attributeName="stop-color">` timeline: each keyframe
/// token is a colour (any form `_normalizeColorAttributes` accepts) resolved
/// to hex once, here, then packed into [SmilColorAnimation]'s `0xAARRGGBB`
/// ints.
///
/// 解析 `<animate attributeName="stop-color">` 时间线：每个关键帧词元是一个
/// 颜色（`_normalizeColorAttributes` 接受的任意形式），在此一次性解析为十六进制，
/// 再打包为 [SmilColorAnimation] 的 `0xAARRGGBB` 整数。
SmilColorAnimation? _parseAnimateColor(XmlElement element) {
  final valuesRaw = element.getAttribute('values');
  final from = element.getAttribute('from');
  final to = element.getAttribute('to');
  final raw = (valuesRaw != null && valuesRaw.trim().isNotEmpty)
      ? valuesRaw
      : (from != null && to != null ? '$from;$to' : null);
  if (raw == null) return null;

  final tokens = raw
      .split(';')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (tokens.length < 2) return null;

  final packed = <int>[];
  for (final token in tokens) {
    final hex = token.startsWith('#')
        ? token
        : (resolveColorToHex(token) ?? token);
    final color = parseSvgHexColor(hex);
    if (color == null) return null;
    packed.add(color.toARGB32());
  }

  final beginSpec = parseSmilBeginSpec(element.getAttribute('begin'));
  return SmilColorAnimation(
    values: packed,
    duration: parseSmilDuration(element.getAttribute('dur')),
    elementId: element.getAttribute('id'),
    beginSpec: beginSpec,
    begin: beginSpec.offset, // provisional, see _parseAnimate
    fillFreeze: element.getAttribute('fill') == 'freeze',
    repeatCount: parseSmilRepeatCount(element.getAttribute('repeatCount')),
    calcMode: parseSmilCalcMode(element.getAttribute('calcMode')),
    keyTimes: parseSmilKeyTimes(element.getAttribute('keyTimes')),
    keySplines: parseSmilKeySplines(element.getAttribute('keySplines')),
  );
}

/// Reads a gradient's `<stop>` children (`offset`, `stop-color`,
/// `stop-opacity`), skipping any stop whose colour can't be resolved.
///
/// 读取渐变的 `<stop>` 子元素（`offset`、`stop-color`、`stop-opacity`），
/// 颜色无法解析的色标会被跳过。
List<SvgGradientStop> _parseStops(XmlElement element) {
  final stops = <SvgGradientStop>[];
  for (final child in element.childElements) {
    if (child.name.local != 'stop') continue;
    final attributes = <String, String>{
      for (final a in child.attributes) a.name.local: a.value,
    };
    _normalizeColorAttributes(attributes);
    final stop = stopFromAttributes(attributes);
    if (stop != null) stops.add(stop);
  }
  stops.sort((a, b) => a.offset.compareTo(b.offset));
  return stops;
}

/// Whether [document] has any `<image>` node awaiting decode — lets callers
/// skip the async `resolveImageNodes` await entirely for the common
/// no-image case.
///
/// [document] 中是否存在待解码的 `<image>` 节点——让调用方在无图片的常见场景
/// 完全跳过异步 `resolveImageNodes` 的 await。
bool documentHasImages(SvgDocument document) => _hasImageNode(document.root);

bool _hasImageNode(SvgNode node) =>
    node.kind == SvgNodeKind.image || node.children.any(_hasImageNode);

/// Walks [document]'s tree decoding every `<image>` node's base64 `href` into
/// [SvgNode.resolvedImage], in place.
///
/// `href` is expected in `data:<mime>;base64,<payload>` form (the only form
/// SMIL icon assets use in practice); a node whose `href` is missing, isn't a
/// `data:` URI, or fails to decode is left with `resolvedImage == null` and
/// silently skipped by the painter — no throw, matching this engine's
/// "unsupported construct renders as invisible" convention.
///
/// 遍历 [document] 的树，把每个 `<image>` 节点的 base64 `href` 解码进
/// [SvgNode.resolvedImage]（原地修改）。
///
/// `href` 期望是 `data:<mime>;base64,<payload>` 形式（SMIL 图标资产实际唯一
/// 会用到的形式）；`href` 缺失、非 `data:` URI 或解码失败的节点会保持
/// `resolvedImage == null`，绘制时被静默跳过——不抛错，符合本引擎"不支持的
/// 结构表现为不可见"的一贯约定。
Future<void> resolveImageNodes(SvgDocument document) async {
  await _resolveNode(document.root);
}

Future<void> _resolveNode(SvgNode node) async {
  if (node.kind == SvgNodeKind.image) {
    node.resolvedImage = await _decodeDataUriImage(node.attributes['href']);
  }
  for (final child in node.children) {
    await _resolveNode(child);
  }
}

Future<ui.Image?> _decodeDataUriImage(String? href) async {
  if (href == null) return null;
  final commaIndex = href.indexOf(',');
  if (!href.startsWith('data:') || commaIndex == -1) return null;
  final meta = href.substring(5, commaIndex); // between "data:" and ","
  if (!meta.contains('base64')) return null;
  try {
    final bytes = base64Decode(href.substring(commaIndex + 1));
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    // The codec owns decoder-side native buffers that are independent of the
    // frame it hands out, and only one frame is ever pulled here (no animated
    // GIF/APNG playback). Dropping the reference without disposing leaves
    // those buffers to the GC's finalizer queue — invisible in the Dart heap,
    // visible in RSS.
    //
    // codec 持有与它交出的帧相互独立的解码器侧原生缓冲，而这里只会取一帧
    // （不做 GIF/APNG 动图播放）。只丢引用不 dispose，那些缓冲就留给 GC 的
    // finalizer 队列——在 Dart heap 里看不见，在 RSS 里看得见。
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

const _tagToKind = {
  'g': SvgNodeKind.group,
  'path': SvgNodeKind.path,
  'circle': SvgNodeKind.circle,
  'rect': SvgNodeKind.rect,
  'ellipse': SvgNodeKind.ellipse,
  'line': SvgNodeKind.line,
  'polyline': SvgNodeKind.polyline,
  'polygon': SvgNodeKind.polygon,
  'image': SvgNodeKind.image,
  'text': SvgNodeKind.text,
};

/// Maximum `<use>` reference depth before resolution gives up, guarding
/// against pathological (but non-cyclic) reference chains.
///
/// Value borrowed with attribution from `full_svg_flutter`'s
/// `lib/src/animation/svg_use_references.dart` (`maxSvgUseRecursionDepth`,
/// MIT licensed) — see `benchmark/baseline_f/full_svg_flutter_lib/src/
/// animation/svg_use_references.dart` in this repo.
///
/// `<use>` 引用解析放弃前的最大深度，防御病态（但无环）的引用链。
///
/// 取值带署名地借自 `full_svg_flutter` 的
/// `lib/src/animation/svg_use_references.dart`（`maxSvgUseRecursionDepth`，
/// MIT 许可）——见本仓库 `benchmark/baseline_f/full_svg_flutter_lib/src/
/// animation/svg_use_references.dart`。
const _maxUseDepth = 10;

/// Per-parse state threaded through [_parseElement]: every animation found so
/// far (for the one-shot syncbase `begin` resolution and the document-duration
/// tally), plus everything `<use>` resolution needs (a document-wide id →
/// element index, so forward references work regardless of document order, and
/// an in-progress target set that stops reference cycles).
///
/// 单次解析过程中传递给 [_parseElement] 的状态：迄今发现的所有动画（供一次性
/// 的同步基准 `begin` 解析与文档总时长统计使用），加上 `<use>` 解析所需的一切
/// （文档级 id → 元素索引，使前向引用不受文档顺序影响；以及记录解析中目标的
/// 集合，用于阻断引用环）。
class _ParseContext {
  _ParseContext({required this.elementsById});

  final Map<String, XmlElement> elementsById;
  final List<SmilTimed> animations = <SmilTimed>[];
  final Set<String> resolvingUseTargets = <String>{};
  int useDepth = 0;

  /// Set true as soon as any parsed element carries a `mask` reference or a
  /// blur `filter` — i.e. something `AnimatedSvgPainter` can only draw by
  /// opening a `canvas.saveLayer` offscreen render target. Collected here,
  /// during the walk the parser already does, so nothing has to re-walk the
  /// tree later to answer "is this document expensive to rasterize?".
  ///
  /// 只要有任何被解析的元素带 `mask` 引用或模糊 `filter`，就置为 true——也就是
  /// `AnimatedSvgPainter` 只能靠 `canvas.saveLayer` 开离屏渲染目标才能画出来的
  /// 情形。在解析器本来就要做的这趟遍历里顺手收集，因此后续无需再遍历一次树来
  /// 回答"这份文档光栅化贵不贵"。
  bool sawOffscreenLayer = false;
}

SvgNode _parseElement(
  XmlElement element,
  SvgNodeKind kind,
  _ParseContext context,
) {
  final attributes = <String, String>{
    for (final a in element.attributes) a.name.local: a.value,
  };
  _normalizeColorAttributes(attributes);

  // Mark this element's own id as "being parsed" for the duration of its
  // subtree, so a <use> inside it that points back at an ancestor is caught by
  // the same cycle guard as any other reference cycle.
  //
  // 在解析本元素子树期间，把它自身的 id 标记为"解析中"，使其内部指回祖先的
  // <use> 与其它引用环走同一套环检测。
  final selfId = attributes['id'];
  final markedSelfId =
      selfId != null && context.resolvingUseTargets.add(selfId);

  final animations = <SmilAnimation>[];
  final transformAnimations = <SmilTransformAnimation>[];
  final motionAnimations = <SmilMotionAnimation>[];
  final children = <SvgNode>[];
  for (final child in element.childElements) {
    final localName = child.name.local;
    if (localName == 'animate') {
      final anim = _parseAnimate(child);
      if (anim != null) {
        animations.add(anim);
        context.animations.add(anim);
      }
      continue;
    }
    if (localName == 'animateTransform') {
      final anim = _parseAnimateTransform(child);
      if (anim != null) {
        transformAnimations.add(anim);
        context.animations.add(anim);
      }
      continue;
    }
    if (localName == 'animateMotion') {
      final anim = _parseAnimateMotion(child, context);
      if (anim != null) {
        motionAnimations.add(anim);
        context.animations.add(anim);
      }
      continue;
    }
    if (localName == 'use') {
      final resolved = _resolveUse(child, context);
      if (resolved != null) children.add(resolved);
      continue;
    }
    final childKind = _tagToKind[localName];
    if (childKind == null) continue; // unsupported element: skip subtree
    children.add(_parseElement(child, childKind, context));
  }

  if (markedSelfId) context.resolvingUseTargets.remove(selfId);

  final rawTransform = attributes['transform'];
  final maskId = parseUrlId(attributes['mask']);
  final blurSigma = _parseBlurSigma(attributes['filter'], context);
  if (maskId != null || (blurSigma != null && blurSigma > 0)) {
    context.sawOffscreenLayer = true;
  }

  return SvgNode(
    kind: kind,
    attributes: attributes,
    children: children,
    animations: animations,
    transformAnimations: transformAnimations,
    motionAnimations: motionAnimations,
    transform: rawTransform == null ? null : parseTransformMatrix(rawTransform),
    clipPathId: parseUrlId(attributes['clip-path']),
    maskId: maskId,
    blurSigma: blurSigma,
    // Only <text> ever gets a non-null [XmlNode.innerText] read here — no
    // <tspan> support, so the whole subtree's text is taken flat.
    // 只有 <text> 才会读取 [XmlNode.innerText]——不支持 <tspan>，直接取整个
    // 子树的纯文本。
    textContent: kind == SvgNodeKind.text ? element.innerText.trim() : null,
  );
}

final _cssBlurPattern = RegExp(r'blur\(\s*([\d.]+)(px)?\s*\)');

/// Parses `filter="blur(Npx)"` (CSS `filter` shorthand syntax, as emitted by
/// some SVG tools) or `filter="url(#id)"` pointing at a top-level
/// `<filter id="..."><feGaussianBlur stdDeviation="N"/></filter>` into a
/// Gaussian blur sigma. Returns null for no `filter` attribute, an
/// unsupported filter (anything but a single `feGaussianBlur` primitive), or
/// a dangling/malformed reference — matching this engine's silent-degradation
/// convention rather than throwing.
///
/// 把 `filter="blur(Npx)"`（部分 SVG 工具产出的 CSS `filter` 简写语法）或指向
/// 顶层 `<filter id="..."><feGaussianBlur stdDeviation="N"/></filter>` 的
/// `filter="url(#id)"` 解析为高斯模糊 sigma。无 `filter` 属性、不支持的滤镜
/// （除单个 `feGaussianBlur` 图元外的任何内容）、或悬空/格式错误的引用均返回
/// null——与本引擎"静默降级"的一贯约定一致，不抛错。
double? _parseBlurSigma(String? raw, _ParseContext context) {
  if (raw == null) return null;
  final value = raw.trim();
  final cssMatch = _cssBlurPattern.firstMatch(value);
  if (cssMatch != null) return double.tryParse(cssMatch.group(1)!);

  final id = parseUrlId(value);
  if (id == null) return null;
  final filterElement = context.elementsById[id];
  if (filterElement == null || filterElement.name.local != 'filter') {
    return null;
  }
  for (final child in filterElement.childElements) {
    if (child.name.local != 'feGaussianBlur') continue;
    return double.tryParse(child.getAttribute('stdDeviation') ?? '');
  }
  return null;
}

/// Extracts the `#id` out of a `url(#id)` (or `url('#id')`/`url("#id")`)
/// paint/effect reference, or null when [raw] isn't one — used for
/// `clip-path`/`mask` (see [_parseElement]); mirrors the equivalent
/// per-frame helper in `svg_style.dart`'s `ResolvedStyle.inherit`, but this
/// one runs once at parse time since `clip-path`/`mask` targets aren't
/// themselves animated (only their *content* can be — see svgx CLAUDE.md
/// task notes).
///
/// How many arc-length samples an `<animateMotion>` path is reduced to at
/// parse time. Dense enough that per-frame linear interpolation between
/// neighbouring samples is visually exact for icon-sized motion, and cheap
/// enough (a few hundred doubles) to build once per animation.
///
/// 解析阶段把 `<animateMotion>` 路径规约成多少个弧长采样点。足够密，使逐帧在
/// 相邻采样点间线性插值对图标尺度的运动而言视觉上无误差；也足够便宜（几百个
/// double），可为每条动画构建一次。
const _motionSampleCount = 128;

/// Parses `<animateMotion>` — its own `path="..."`, or an `<mpath href="#id">`
/// child pointing at a `<path>` element's `d`.
///
/// The path is turned into an arc-length lookup table right here, using
/// `dart:ui`'s `Path.computeMetrics()` / `PathMetric.getTangentForOffset()`
/// (which do proper arc-length parameterization, including across multiple
/// subpaths), so nothing curve-related happens per frame. `rotate` supports
/// `auto`, `auto-reverse` and a fixed number of degrees.
///
/// Returns null (the animation simply doesn't exist) when there's no usable
/// path, matching this engine's silent-degradation convention.
///
/// 解析 `<animateMotion>`——其自身的 `path="..."`，或指向某个 `<path>` 元素 `d`
/// 的 `<mpath href="#id">` 子元素。
///
/// 路径在此处就被转成弧长查找表，用的是 `dart:ui` 的
/// `Path.computeMetrics()`/`PathMetric.getTangentForOffset()`（它们已正确实现
/// 弧长参数化，且能跨多个子路径），因此逐帧不做任何与曲线相关的计算。`rotate`
/// 支持 `auto`、`auto-reverse` 以及固定角度数值。
///
/// 没有可用路径时返回 null（该动画等同于不存在），符合本引擎静默降级的约定。
SmilMotionAnimation? _parseAnimateMotion(
  XmlElement element,
  _ParseContext context,
) {
  var pathData = element.getAttribute('path');
  if (pathData == null) {
    for (final child in element.childElements) {
      if (child.name.local != 'mpath') continue;
      final href = {
        for (final a in child.attributes) a.name.local: a.value,
      }['href']?.trim();
      if (href == null || !href.startsWith('#')) continue;
      pathData = context.elementsById[href.substring(1)]?.getAttribute('d');
      break;
    }
  }
  if (pathData == null || pathData.trim().isEmpty) return null;

  final samples = _sampleMotionPath(
    parseSvgPathData(pathData),
    element.getAttribute('rotate'),
  );
  if (samples == null) return null;

  final beginSpec = parseSmilBeginSpec(element.getAttribute('begin'));
  return SmilMotionAnimation(
    samples: samples,
    duration: parseSmilDuration(element.getAttribute('dur')),
    elementId: element.getAttribute('id'),
    beginSpec: beginSpec,
    begin: beginSpec.offset, // provisional, see _parseAnimate
    fillFreeze: element.getAttribute('fill') == 'freeze',
    repeatCount: parseSmilRepeatCount(element.getAttribute('repeatCount')),
    keyPoints: _parseKeyPoints(element.getAttribute('keyPoints')),
    keyTimes: parseSmilKeyTimes(element.getAttribute('keyTimes')),
    keySplines: parseSmilKeySplines(element.getAttribute('keySplines')),
    calcMode: parseSmilCalcMode(element.getAttribute('calcMode')),
  );
}

/// Parses `<animateMotion keyPoints="0;0.25;1">` into an arc-length-fraction
/// list, or null if absent/malformed (any entry that doesn't parse, or fewer
/// than two entries, invalidates the whole list — same tolerance as
/// [parseSmilKeyTimes]).
///
/// 解析 `<animateMotion keyPoints="0;0.25;1">` 为弧长比例列表；缺失/格式错误
/// （任一项无法解析，或少于两项）时返回 null——容错策略与 [parseSmilKeyTimes]
/// 一致。
List<double>? _parseKeyPoints(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.split(';').map((s) => double.tryParse(s.trim())).toList();
  if (parts.any((v) => v == null) || parts.length < 2) return null;
  return parts.cast<double>();
}

/// Walks [path] with `dart:ui`'s path metrics, producing
/// [_motionSampleCount] + 1 samples evenly spaced by arc length across all of
/// its subpaths, with the tangent angle baked in per [rotate].
///
/// 用 `dart:ui` 的 path metrics 遍历 [path]，在其所有子路径上按弧长等距产出
/// [_motionSampleCount] + 1 个采样点，并按 [rotate] 预先烘焙好切线角度。
List<SmilMotionSample>? _sampleMotionPath(ui.Path path, String? rotate) {
  final metrics = path.computeMetrics().toList();
  final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
  if (metrics.isEmpty || totalLength <= 0) return null;

  final autoRotate = rotate == 'auto' || rotate == 'auto-reverse';
  final reverse = rotate == 'auto-reverse';
  final fixedAngle = autoRotate ? 0.0 : (double.tryParse(rotate ?? '') ?? 0.0);

  final samples = <SmilMotionSample>[];
  for (var i = 0; i <= _motionSampleCount; i++) {
    var distance = totalLength * i / _motionSampleCount;
    var metric = metrics.first;
    for (final candidate in metrics) {
      if (distance <= candidate.length || candidate == metrics.last) {
        metric = candidate;
        break;
      }
      distance -= candidate.length;
    }
    final tangent = metric.getTangentForOffset(
      distance.clamp(0.0, metric.length),
    );
    if (tangent == null) return null;
    // ui.Tangent.angle is measured counter-clockwise-negative (it is
    // `-atan2(dy, dx)`), while Canvas.rotate takes the plain atan2 sense —
    // hence the negation.
    //
    // ui.Tangent.angle 是按逆时针取负度量的（其定义为 `-atan2(dy, dx)`），而
    // Canvas.rotate 用的是普通 atan2 方向——故此处取负。
    final angle = autoRotate
        ? -tangent.angle * 180 / math.pi + (reverse ? 180 : 0)
        : fixedAngle;
    samples.add(
      SmilMotionSample(tangent.position.dx, tangent.position.dy, angle),
    );
  }
  return samples;
}

/// Colour attributes normalized once, at parse time, from any CSS3/SVG colour
/// syntax (`red`, `cornflowerblue`, `rgb(...)`, `hsl(...)`) into `#RRGGBBAA`
/// hex — the one form the per-frame style resolver (`svg_style.dart`) parses.
///
/// 解析阶段一次性归一化的颜色属性：把任意 CSS3/SVG 颜色写法（`red`、
/// `cornflowerblue`、`rgb(...)`、`hsl(...)`）转成 `#RRGGBBAA` 十六进制——
/// 逐帧样式解析器（`svg_style.dart`）唯一需要认识的形式。
const _colorAttributes = ['fill', 'stroke', 'stop-color', 'color'];

/// Rewrites [attributes]' colour values in place: anything that isn't already
/// hex, `none`, `currentColor`, `inherit` or a `url(...)` paint reference is
/// handed to the Rust colour parser once and replaced with its hex form.
///
/// A value the Rust parser rejects (or that can't be resolved because the
/// native library isn't loaded) is left untouched, so it degrades exactly as
/// it did before this normalization existed.
///
/// 原地重写 [attributes] 中的颜色取值：凡是不属于十六进制、`none`、
/// `currentColor`、`inherit`、`url(...)` 涂料引用的值，都交给 Rust 颜色解析器
/// 解析一次，并替换为其十六进制形式。
///
/// Rust 解析器拒绝的值（或因原生库未加载而无法解析的值）保持原样，行为与本
/// 归一化不存在时完全一致。
void _normalizeColorAttributes(Map<String, String> attributes) {
  for (final key in _colorAttributes) {
    final raw = attributes[key];
    if (raw == null) continue;
    final value = raw.trim();
    if (value.isEmpty ||
        value.startsWith('#') ||
        value.startsWith('url(') ||
        value == 'none' ||
        value == 'currentColor' ||
        value == 'inherit') {
      continue;
    }
    final hex = resolveColorToHex(value);
    if (hex != null) attributes[key] = hex;
  }
}

/// Attributes that belong to the `<use>` element's own placement, not to the
/// instance it produces — they must not leak onto the wrapper group as
/// presentation attributes.
///
/// 属于 `<use>` 元素自身摆放方式、而非其产出实例的属性——不应作为表现属性
/// 泄漏到包装分组上。
const _usePlacementAttributes = {
  'href',
  'x',
  'y',
  'width',
  'height',
  'transform',
  'id',
};

/// Resolves `<use href="#id">` into a real subtree.
///
/// The referenced element is parsed **again** from the source XML (rather than
/// the already-built node tree being copied), which makes forward references
/// work for free: the id → element index is built over the whole document
/// before any node is created, so a `<use>` may precede its target's `<defs>`.
///
/// Semantics chosen (SVG2 "shadow tree" reading): the instance is a full
/// re-parse including the target's own `<animate>`/`<animateTransform>`
/// children, so an animated target animates in both places, and ids are left
/// as-is on the instance (this engine binds animations structurally, never by
/// id lookup, so duplicate ids can't mis-target anything).
///
/// Returns null — i.e. the `<use>` renders nothing, no throw — when the href
/// is missing/not a local `#id`, the target doesn't exist, the target's tag
/// isn't a renderable one, the reference forms a cycle, or nesting exceeds
/// [_maxUseDepth].
///
/// 把 `<use href="#id">` 解析成真实子树。
///
/// 被引用元素是从源 XML **重新解析**一遍（而不是拷贝已构建的节点树），这让
/// 前向引用天然可用：id → 元素索引在创建任何节点之前就已对整份文档建好，因此
/// `<use>` 可以出现在其目标 `<defs>` 之前。
///
/// 语义选择（按 SVG2 的"影子树"解读）：实例是包含目标自身
/// `<animate>`/`<animateTransform>` 子元素在内的完整重新解析，因此带动画的
/// 目标在两处都会播放动画；实例上的 id 原样保留（本引擎按结构挂载动画，从不
/// 按 id 查找，重复 id 不会导致误绑定）。
///
/// 以下情况返回 null（即该 `<use>` 不渲染任何内容，且不抛错）：href 缺失或
/// 不是本地 `#id`、目标不存在、目标标签不可渲染、引用成环，或嵌套超过
/// [_maxUseDepth]。
SvgNode? _resolveUse(XmlElement useElement, _ParseContext context) {
  final attributes = <String, String>{
    for (final a in useElement.attributes) a.name.local: a.value,
  };
  final href = attributes['href']?.trim(); // covers xlink:href (local name)
  if (href == null || !href.startsWith('#')) return null;
  final id = href.substring(1);
  if (id.isEmpty) return null;
  if (context.resolvingUseTargets.contains(id)) return null; // reference cycle
  if (context.useDepth >= _maxUseDepth) return null;

  final target = context.elementsById[id];
  if (target == null) return null; // dangling reference: render nothing
  final targetTag = target.name.local;
  // <symbol>/<svg> targets are treated as plain groups: their own
  // width/height/viewBox scaling is NOT applied (documented simplification).
  //
  // <symbol>/<svg> 目标按普通分组处理：不应用其自身的
  // width/height/viewBox 缩放（明确记录的简化）。
  final targetKind = (targetTag == 'symbol' || targetTag == 'svg')
      ? SvgNodeKind.group
      : _tagToKind[targetTag];
  if (targetKind == null) return null;

  context.resolvingUseTargets.add(id);
  context.useDepth++;
  final instance = _parseElement(target, targetKind, context);
  context.useDepth--;
  context.resolvingUseTargets.remove(id);

  _normalizeColorAttributes(attributes);
  return SvgNode(
    kind: SvgNodeKind.group,
    attributes: {
      for (final entry in attributes.entries)
        if (!_usePlacementAttributes.contains(entry.key))
          entry.key: entry.value,
    },
    children: [instance],
    transform: _usePlacementTransform(attributes),
  );
}

/// Builds the instance's placement matrix from the `<use>` element's own
/// `transform` and `x`/`y` (SVG: `transform` first, then `translate(x, y)`).
///
/// The pure `x`/`y` case is computed directly in Dart so it works even where
/// the native library isn't loaded; only a real `transform` string needs the
/// Rust grammar parser.
///
/// 由 `<use>` 元素自身的 `transform` 与 `x`/`y` 构建实例的摆放矩阵（SVG 语义：
/// 先 `transform`，再 `translate(x, y)`）。
///
/// 纯 `x`/`y` 的情况直接在 Dart 里算出，因此原生库未加载时同样有效；只有真正
/// 带 `transform` 字符串时才需要 Rust 的语法解析器。
List<double>? _usePlacementTransform(Map<String, String> attributes) {
  final x = double.tryParse(attributes['x'] ?? '') ?? 0;
  final y = double.tryParse(attributes['y'] ?? '') ?? 0;
  final raw = attributes['transform'];
  if (raw == null) {
    if (x == 0 && y == 0) return null;
    return [1, 0, 0, 1, x, y];
  }
  return parseTransformMatrix(x == 0 && y == 0 ? raw : '$raw translate($x,$y)');
}

SmilAnimation? _parseAnimate(XmlElement element) {
  final attributeName = element.getAttribute('attributeName');
  if (attributeName == null) return null;
  final values = parseSmilValues(
    values: element.getAttribute('values'),
    from: element.getAttribute('from'),
    to: element.getAttribute('to'),
  );
  if (values == null) return null;

  final beginSpec = parseSmilBeginSpec(element.getAttribute('begin'));
  return SmilAnimation(
    attributeName: attributeName,
    values: values,
    duration: parseSmilDuration(element.getAttribute('dur')),
    elementId: element.getAttribute('id'),
    beginSpec: beginSpec,
    // Provisional: overwritten by resolveSmilBeginTimes for syncbase refs.
    // 暂定值：同步基准引用会被 resolveSmilBeginTimes 覆盖。
    begin: beginSpec.offset,
    fillFreeze: element.getAttribute('fill') == 'freeze',
    repeatCount: parseSmilRepeatCount(element.getAttribute('repeatCount')),
    calcMode: parseSmilCalcMode(element.getAttribute('calcMode')),
    keyTimes: parseSmilKeyTimes(element.getAttribute('keyTimes')),
    keySplines: parseSmilKeySplines(element.getAttribute('keySplines')),
  );
}

const _transformTypes = {
  'translate': SmilTransformType.translate,
  'scale': SmilTransformType.scale,
  'rotate': SmilTransformType.rotate,
  'skewX': SmilTransformType.skewX,
  'skewY': SmilTransformType.skewY,
};

SmilTransformAnimation? _parseAnimateTransform(XmlElement element) {
  final type = _transformTypes[element.getAttribute('type')];
  if (type == null) return null; // unknown type: skip, render as no transform
  final rawFrames = parseSmilTransformKeyframes(
    values: element.getAttribute('values'),
    from: element.getAttribute('from'),
    to: element.getAttribute('to'),
  );
  if (rawFrames == null) return null;

  final beginSpec = parseSmilBeginSpec(element.getAttribute('begin'));
  return SmilTransformAnimation(
    type: type,
    values: [
      for (final frame in rawFrames) _normalizeTransformComponents(type, frame),
    ],
    duration: parseSmilDuration(element.getAttribute('dur')),
    elementId: element.getAttribute('id'),
    beginSpec: beginSpec,
    begin: beginSpec.offset, // provisional, see _parseAnimate

    fillFreeze: element.getAttribute('fill') == 'freeze',
    repeatCount: parseSmilRepeatCount(element.getAttribute('repeatCount')),
    calcMode: parseSmilCalcMode(element.getAttribute('calcMode')),
    keyTimes: parseSmilKeyTimes(element.getAttribute('keyTimes')),
    keySplines: parseSmilKeySplines(element.getAttribute('keySplines')),
  );
}

/// Pads/derives a raw `<animateTransform>` keyframe (1-3 numbers, per SVG's
/// per-type shorthand grammar) into the fixed 3-component form
/// [SmilTransformAnimation] expects: `translate` → `[tx, ty(=0)]`, `scale` →
/// `[sx, sy(=sx)]`, `rotate` → `[angle, cx(=0), cy(=0)]`.
///
/// 把原始 `<animateTransform>` 关键帧（1~3 个数字，遵循 SVG 各 type 的简写
/// 语法）填充/派生为 [SmilTransformAnimation] 期望的固定 3 分量形式：
/// `translate` → `[tx, ty(=0)]`，`scale` → `[sx, sy(=sx)]`，`rotate` →
/// `[angle, cx(=0), cy(=0)]`，`skewX`/`skewY` → `[angle]`。
List<double> _normalizeTransformComponents(
  SmilTransformType type,
  List<double> raw,
) {
  switch (type) {
    case SmilTransformType.translate:
      final tx = raw.isNotEmpty ? raw[0] : 0.0;
      final ty = raw.length > 1 ? raw[1] : 0.0;
      return [tx, ty, 0];
    case SmilTransformType.scale:
      final sx = raw.isNotEmpty ? raw[0] : 1.0;
      final sy = raw.length > 1 ? raw[1] : sx;
      return [sx, sy, 0];
    case SmilTransformType.rotate:
      final angle = raw.isNotEmpty ? raw[0] : 0.0;
      final cx = raw.length > 1 ? raw[1] : 0.0;
      final cy = raw.length > 2 ? raw[2] : 0.0;
      return [angle, cx, cy];
    case SmilTransformType.skewX:
    case SmilTransformType.skewY:
      return [raw.isNotEmpty ? raw[0] : 0.0, 0, 0];
  }
}
