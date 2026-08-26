// Timeline model for SMIL `<animate>`/`<animateTransform>` elements: parses
// timing attributes once, then samples a value for any point on the global
// timeline. Original implementation — see svgx CLAUDE.md "参考对象" table for
// the ideas (not code) borrowed from svg-rs / F.
//
// 单个 SMIL `<animate>`/`<animateTransform>` 元素的时间线模型：一次性解析
// 其时序属性，之后可对全局时间线上任意时刻采样出数值。原创实现——思路参考见
// svgx CLAUDE.md "参考对象"表（借鉴 svg-rs / F 的思路，非代码）。

import 'dart:math' as math;

/// How many times an animation repeats (SMIL `repeatCount`).
///
/// 动画重复次数（SMIL `repeatCount`）。
class SmilRepeatCount {
  /// A finite repeat count, e.g. `repeatCount="2.5"`. / 有限重复次数。
  const SmilRepeatCount.finite(this.count) : indefinite = false;

  /// `repeatCount="indefinite"` — loops forever, never freezes.
  ///
  /// `repeatCount="indefinite"`——无限循环，永不定格。
  const SmilRepeatCount.indefinite() : count = 1, indefinite = true;

  /// Runs exactly once (the SMIL/engine default). / 只运行一次（SMIL/引擎默认值）。
  static const SmilRepeatCount once = SmilRepeatCount.finite(1);

  /// Number of iterations; meaningless when [indefinite] is true.
  ///
  /// 迭代次数；[indefinite] 为 true 时此值无意义。
  final double count;

  /// Whether this loops forever. / 是否永久循环。
  final bool indefinite;
}

/// Non-linear timing mode for keyframe interpolation (SMIL `calcMode`).
///
/// 关键帧插值的非线性时序模式（SMIL `calcMode`）。
enum SmilCalcMode {
  /// Even interpolation between keyframes (default). / 关键帧间线性插值（默认）。
  linear,

  /// Step function: holds each keyframe's value, no interpolation.
  ///
  /// 阶跃函数：保持每个关键帧的值，不插值。
  discrete,

  /// Keyframes are spaced by "distance" between consecutive values so motion
  /// has constant pace, ignoring any `keyTimes`.
  ///
  /// 关键帧按相邻数值间的"距离"分布，使运动匀速，忽略 `keyTimes`。
  paced,

  /// Cubic-bezier easing per segment, driven by `keySplines` (see
  /// [CubicBezier]). Falls back to [linear] for a segment with no matching
  /// spline (see [_locateSegment] callers).
  ///
  /// 每段使用三次贝塞尔缓动，由 `keySplines` 驱动（见 [CubicBezier]）。若某段
  /// 没有对应的 spline，回退为 [linear]（见调用 [_locateSegment] 处）。
  spline,
}

/// A single `keySplines` cubic-bezier control-point quad, easing the
/// progress *within* one keyframe segment (SMIL, borrowed from CSS
/// `cubic-bezier()` timing functions).
///
/// Adapted with attribution from `full_svg_flutter`'s
/// `lib/src/animation/smil/smil_animation_curves.dart` (`CubicBezier` class,
/// MIT licensed) — see `benchmark/baseline_f/full_svg_flutter_lib/src/
/// animation/smil/smil_animation_curves.dart` in this repo. Newton's-method
/// root solve is a well-known technique for inverting a cubic bezier's X(t)
/// to get Y at a given progress; this is the same self-contained algorithm.
///
/// 单个 `keySplines` 三次贝塞尔控制点四元组，为一个关键帧区间*内部*的进度
/// 提供缓动（SMIL 语义借自 CSS `cubic-bezier()` 缓动函数）。
///
/// 带署名地改编自 `full_svg_flutter` 的
/// `lib/src/animation/smil/smil_animation_curves.dart`（`CubicBezier` 类，
/// MIT 许可）——见本仓库 `benchmark/baseline_f/full_svg_flutter_lib/src/
/// animation/smil/smil_animation_curves.dart`。用牛顿法反解三次贝塞尔的
/// X(t) 从而在给定进度处取得 Y，是广为人知的通用技术；这里是同一个自包含
/// 算法。
class CubicBezier {
  /// Creates a cubic-bezier curve from its two control points.
  ///
  /// 用两个控制点创建三次贝塞尔曲线。
  const CubicBezier(this.x1, this.y1, this.x2, this.y2);

  /// Control point 1 X. / 控制点 1 的 X。
  final double x1;

  /// Control point 1 Y. / 控制点 1 的 Y。
  final double y1;

  /// Control point 2 X. / 控制点 2 的 X。
  final double x2;

  /// Control point 2 Y. / 控制点 2 的 Y。
  final double y2;

  /// Eases progress [t] in `[0, 1]` through this curve.
  ///
  /// 用该曲线为 `[0, 1]` 范围内的进度 [t] 做缓动。
  double transform(double t) {
    if (x1 == 0 && y1 == 0 && x2 == 1 && y2 == 1) return t; // linear curve

    var x = t;
    for (var i = 0; i < 8; i++) {
      final curveX = _bezierComponent(x1, x2, x);
      final diff = curveX - t;
      if (diff.abs() < 1e-6) break;
      final derivative = _bezierDerivative(x1, x2, x);
      if (derivative.abs() < 1e-6) break;
      x -= diff / derivative;
    }
    return _bezierComponent(y1, y2, x);
  }

  static double _bezierComponent(double p1, double p2, double t) =>
      _a(p1, p2) * t * t * t + _b(p1, p2) * t * t + _c(p1) * t;

  static double _bezierDerivative(double p1, double p2, double t) =>
      3 * _a(p1, p2) * t * t + 2 * _b(p1, p2) * t + _c(p1);

  static double _a(double p1, double p2) => 1.0 - 3.0 * p2 + 3.0 * p1;
  static double _b(double p1, double p2) => 3.0 * p2 - 6.0 * p1;
  static double _c(double p1) => 3.0 * p1;
}

/// A `begin` attribute as written, before syncbase references are resolved
/// into absolute times.
///
/// Three shapes: a plain offset (`begin="0.6s"` → [syncbaseId] null), a
/// syncbase reference (`begin="ring.end+0.2s"` → [syncbaseId] `ring`,
/// [onSyncbaseEnd] true, [offset] 0.2s), and everything else (event values
/// like `begin="click"`), which parses as a zero offset — see
/// [parseSmilBeginSpec].
///
/// 尚未把同步基准引用解析为绝对时间的、原样的 `begin` 属性。
///
/// 三种形态：纯偏移（`begin="0.6s"`，[syncbaseId] 为 null）、同步基准引用
/// （`begin="ring.end+0.2s"`，[syncbaseId] 为 `ring`、[onSyncbaseEnd] 为 true、
/// [offset] 为 0.2s），以及其余情况（如 `begin="click"` 这类事件值），按零偏移
/// 解析——见 [parseSmilBeginSpec]。
class SmilBeginSpec {
  /// Creates a begin specification. / 创建一个 begin 规格。
  const SmilBeginSpec({
    required this.offset,
    this.syncbaseId,
    this.onSyncbaseEnd = false,
  });

  /// A plain `begin` offset with no reference. / 无引用的纯 `begin` 偏移。
  const SmilBeginSpec.offset(this.offset)
    : syncbaseId = null,
      onSyncbaseEnd = false;

  /// Offset added to the resolved base time (may be negative).
  ///
  /// 加在解析出的基准时间上的偏移（可为负）。
  final Duration offset;

  /// Id of the animation element this one syncs to, or null for a plain offset.
  ///
  /// 本动画所同步到的动画元素 id；纯偏移时为 null。
  final String? syncbaseId;

  /// Whether the reference is to the target's *end* (`id.end`) rather than its
  /// begin (`id.begin`).
  ///
  /// 引用的是目标的*结束*时刻（`id.end`）还是开始时刻（`id.begin`）。
  final bool onSyncbaseEnd;
}

/// A `begin` far enough in the future that the animation never fires — how a
/// timeline whose `begin` can't be resolved (reference cycle, or a syncbase on
/// an animation that never ends) is disabled without special-casing every
/// sampling site.
///
/// 一个远到永不会到达的 `begin`——`begin` 无法解析（引用成环，或同步到一个
/// 永不结束的动画）时用它使该时间线失效，避免在每个采样点写特判。
const Duration kSmilNeverBegins = Duration(days: 3650000);

/// The timing surface `resolveSmilBeginTimes` works against, implemented by
/// both [SmilAnimation] and [SmilTransformAnimation] so one resolution pass
/// covers `<animate>` and `<animateTransform>` alike.
///
/// `resolveSmilBeginTimes` 所依赖的时序接口，由 [SmilAnimation] 与
/// [SmilTransformAnimation] 共同实现，使一次解析同时覆盖 `<animate>` 与
/// `<animateTransform>`。
abstract interface class SmilTimed {
  /// The animation element's own `id`, if any (what syncbases reference).
  ///
  /// 动画元素自身的 `id`（同步基准所引用的对象），可能为 null。
  String? get elementId;

  /// The unresolved `begin` attribute. / 尚未解析的 `begin` 属性。
  SmilBeginSpec get beginSpec;

  /// The resolved begin time on the global timeline.
  ///
  /// 全局时间线上已解析的开始时刻。
  Duration get begin;
  set begin(Duration value);

  /// One iteration's duration. / 单次迭代时长。
  Duration get duration;

  /// Repeat count. / 重复次数。
  SmilRepeatCount get repeatCount;
}

/// Resolves every syncbase `begin` in [animations] into an absolute time, in
/// place.
///
/// Walks the reference graph with a three-colour DFS (unvisited / in-progress /
/// done). An animation on a reference cycle — or one syncing to the `end` of an
/// animation that never ends (`repeatCount="indefinite"`), or to an animation
/// that is itself disabled — gets [kSmilNeverBegins], i.e. it is disabled
/// rather than guessed at. A reference to an id that doesn't exist falls back
/// to the plain offset (as if no reference had been written).
///
/// 原地把 [animations] 中所有同步基准 `begin` 解析为绝对时间。
///
/// 用三色 DFS（未访问/进行中/已完成）遍历引用图。位于引用环上的动画——以及同步
/// 到一个永不结束（`repeatCount="indefinite"`）的动画的 `end`、或同步到一个
/// 本身已失效的动画的动画——都会被赋予 [kSmilNeverBegins]，即直接失效而不是
/// 猜一个值。引用了不存在的 id 时，回退为纯偏移（等同于没写引用）。
///
/// Example:
/// ```dart
/// resolveSmilBeginTimes(allAnimationsInDocument);
/// ```
void resolveSmilBeginTimes(List<SmilTimed> animations) {
  final byId = <String, SmilTimed>{};
  for (final animation in animations) {
    final id = animation.elementId;
    if (id != null) byId.putIfAbsent(id, () => animation);
  }

  const white = 0, grey = 1, black = 2;
  final colors = <SmilTimed, int>{for (final a in animations) a: white};

  Duration resolve(SmilTimed animation) {
    switch (colors[animation]) {
      case black:
        return animation.begin;
      case grey:
        // Cycle: disable this animation and let the caller inherit that.
        // 成环：使该动画失效，调用方继承这一结果。
        animation.begin = kSmilNeverBegins;
        return kSmilNeverBegins;
    }
    colors[animation] = grey;

    final spec = animation.beginSpec;
    final targetId = spec.syncbaseId;
    final target = targetId == null ? null : byId[targetId];
    if (target == null) {
      animation.begin = spec.offset; // plain offset, or a dangling reference
    } else {
      final base = resolve(target);
      if (base == kSmilNeverBegins) {
        animation.begin = kSmilNeverBegins;
      } else if (!spec.onSyncbaseEnd) {
        animation.begin = base + spec.offset;
      } else if (target.repeatCount.indefinite) {
        animation.begin = kSmilNeverBegins; // an end that never arrives
      } else {
        final activeMicros =
            (target.duration.inMicroseconds * target.repeatCount.count).round();
        animation.begin =
            base + Duration(microseconds: activeMicros) + spec.offset;
      }
    }

    colors[animation] = black;
    return animation.begin;
  }

  for (final animation in animations) {
    resolve(animation);
  }
}

/// Parses a SMIL `begin` attribute into a [SmilBeginSpec].
///
/// Supported: a plain clock value (`"0.6s"`, `"600ms"`, `"2"`), and syncbase
/// references `"id.begin"` / `"id.end"` with an optional `+`/`-` clock offset
/// (`"ring.end+0.2s"`).
///
/// **Not supported** (documented, not silently mis-parsed): event values
/// (`"click"`, `"id.click"`), `wallclock()`, `accessKey()`, and
/// semicolon-separated begin lists — all parse to a zero offset, i.e. the
/// animation starts immediately, which is this engine's existing behaviour for
/// anything it can't read.
///
/// 把 SMIL `begin` 属性解析为 [SmilBeginSpec]。
///
/// 支持：纯时钟值（`"0.6s"`、`"600ms"`、`"2"`），以及带可选 `+`/`-` 时钟偏移的
/// 同步基准引用 `"id.begin"`/`"id.end"`（如 `"ring.end+0.2s"`）。
///
/// **不支持**（明确记录，而非静默错解）：事件值（`"click"`、`"id.click"`）、
/// `wallclock()`、`accessKey()`，以及分号分隔的 begin 列表——一律解析为零偏移，
/// 即动画立即开始，与本引擎对读不懂的取值的一贯行为一致。
///
/// Example:
/// ```dart
/// parseSmilBeginSpec('ring.end+0.2s'); // syncbaseId: 'ring', onEnd, +200ms
/// ```
SmilBeginSpec parseSmilBeginSpec(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return const SmilBeginSpec.offset(Duration.zero);

  final match = RegExp(r'^([^\s.+-]+)\.(begin|end)\s*(?:([+-])\s*(.+))?$')
      .firstMatch(value);
  if (match == null) return SmilBeginSpec.offset(parseSmilDuration(value));

  final magnitude = parseSmilDuration(match.group(4));
  final offset = match.group(3) == '-' ? -magnitude : magnitude;
  return SmilBeginSpec(
    offset: offset,
    syncbaseId: match.group(1),
    onSyncbaseEnd: match.group(2) == 'end',
  );
}

/// A parsed, self-contained `<animate>` timeline for one numeric attribute.
///
/// Supports: a `values` keyframe list (or `from`/`to` shorthand), `dur`, a
/// plain numeric `begin` offset or a syncbase `begin` (`"other.end+0.2s"`,
/// resolved by [resolveSmilBeginTimes]), `fill="freeze"` vs the SMIL default
/// ("remove"), `repeatCount` (finite or `indefinite`), `calcMode`
/// (`linear`/`discrete`/`paced`/`spline`), `keyTimes`, and `keySplines`.
///
/// **Not supported** (documented, not silently ignored): event-based `begin`
/// values (e.g. `begin="click"`) — these parse as a zero offset.
///
/// 单个数值属性的、自包含的已解析 `<animate>` 时间线。
///
/// 支持：`values` 关键帧列表（或 `from`/`to` 简写）、`dur`、纯数值 `begin`
/// 偏移或同步基准 `begin`（`"other.end+0.2s"`，由 [resolveSmilBeginTimes]
/// 解析）、`fill="freeze"` 与 SMIL 默认行为（"remove"）、`repeatCount`
/// （有限次数或 `indefinite`）、`calcMode`（`linear`/`discrete`/`paced`/
/// `spline`）、`keyTimes`、`keySplines`。
///
/// **不支持**（明确声明而非静默忽略）：事件型 `begin`（如 `begin="click"`）
/// ——按零偏移解析。
class SmilAnimation implements SmilTimed {
  /// Creates a fully-parsed animation timeline.
  ///
  /// 创建一个已完整解析的动画时间线。
  SmilAnimation({
    required this.attributeName,
    required this.values,
    required this.duration,
    required this.begin,
    required this.fillFreeze,
    this.repeatCount = SmilRepeatCount.once,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    this.elementId,
    this.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  }) : assert(
         values.length >= 2,
         'an <animate> needs at least two keyframe values',
       );

  @override
  final String? elementId;

  @override
  final SmilBeginSpec beginSpec;

  /// The presentation attribute being animated, e.g. `stroke-dashoffset`.
  ///
  /// 被动画驱动的表现属性，例如 `stroke-dashoffset`。
  final String attributeName;

  /// Keyframe values, distributed across [duration] per [calcMode]/[keyTimes].
  ///
  /// 关键帧数值，按 [calcMode]/[keyTimes] 分布在 [duration] 内。
  final List<double> values;

  /// Total duration of one iteration (SMIL `dur`). / 单次迭代总时长（SMIL `dur`）。
  @override
  final Duration duration;

  /// Delay before the animation starts on the global timeline (SMIL `begin`).
  ///
  /// 动画在全局时间线上开始前的延迟（SMIL `begin`）。
  ///
  /// Mutable only so `resolveSmilBeginTimes` can fill in a syncbase reference
  /// once, right after parsing, before any frame is sampled.
  ///
  /// 可写仅仅是为了让 `resolveSmilBeginTimes` 在解析完成后、任何一帧被采样之前
  /// 一次性填入同步基准解析结果。
  @override
  Duration begin;

  /// Whether the end value is held after completion (`fill="freeze"`). With a
  /// finite [repeatCount] this freezes at the value reached after the last
  /// repeat; with [SmilRepeatCount.indefinite] this is never consulted since
  /// the animation never ends.
  ///
  /// 完成后是否定格末值（`fill="freeze"`）。有限 [repeatCount] 时定格在最后
  /// 一次重复结束时的值；[SmilRepeatCount.indefinite] 时永不参考此值，因为
  /// 动画永不结束。
  final bool fillFreeze;

  /// Number of times the animation repeats (SMIL `repeatCount`).
  ///
  /// 动画重复次数（SMIL `repeatCount`）。
  @override
  final SmilRepeatCount repeatCount;

  /// Keyframe interpolation mode (SMIL `calcMode`). / 关键帧插值模式（SMIL `calcMode`）。
  final SmilCalcMode calcMode;

  /// Custom per-keyframe timing fractions in `[0, 1]`, one per [values] entry
  /// (SMIL `keyTimes`); null means keyframes are spaced evenly.
  ///
  /// 每个关键帧的自定义时间比例，取值 `[0, 1]`，与 [values] 一一对应（SMIL
  /// `keyTimes`）；为 null 表示关键帧均匀分布。
  final List<double>? keyTimes;

  /// Per-segment cubic-bezier easing curves (SMIL `keySplines`), one per
  /// segment (`values.length - 1`); only consulted when [calcMode] is
  /// [SmilCalcMode.spline]. Null/mismatched-length falls back to linear
  /// easing within the segment.
  ///
  /// 每段的三次贝塞尔缓动曲线（SMIL `keySplines`），共 `values.length - 1`
  /// 段；仅在 [calcMode] 为 [SmilCalcMode.spline] 时生效。为 null 或长度不
  /// 匹配时该段回退为线性缓动。
  final List<CubicBezier>? keySplines;

  /// Samples the animated value at global timeline time [t].
  ///
  /// Returns null when the animation hasn't started yet, or has ended without
  /// `fill="freeze"` — in both cases the caller should use the element's own
  /// static attribute value instead of an override.
  ///
  /// 在全局时间线时刻 [t] 采样动画值。
  ///
  /// 若动画尚未开始，或已结束且未设置 `fill="freeze"`，返回 null——两种
  /// 情况下调用方都应使用元素自身的静态属性值，而非覆盖值。
  double? sample(Duration t) {
    final timing = _resolveTiming(
      t: t,
      begin: begin,
      duration: duration,
      repeatCount: repeatCount,
      fillFreeze: fillFreeze,
    );
    if (timing == null) return null;

    final segments = values.length - 1;
    final effectiveKeyTimes = calcMode == SmilCalcMode.paced
        ? _pacedKeyTimes<double>(values, (a, b) => (b - a).abs())
        : keyTimes;
    final segment = _locateSegment(
      timing.progress,
      segments,
      effectiveKeyTimes,
    );
    if (calcMode == SmilCalcMode.discrete) return values[segment.index];

    final a = values[segment.index];
    final b = values[segment.index + 1];
    final segT = _easedSegmentT(calcMode, keySplines, segment);
    return a + (b - a) * segT;
  }
}

/// The kind of transform an `<animateTransform>` drives.
///
/// Covers SVG's full `type` set: `translate`/`scale`/`rotate`/`skewX`/`skewY`.
///
/// `<animateTransform>` 驱动的变换种类。
///
/// 覆盖 SVG `type` 的全部取值：`translate`/`scale`/`rotate`/`skewX`/`skewY`。
enum SmilTransformType {
  /// `type="translate"`, components `[tx, ty]`. / `type="translate"`，分量 `[tx, ty]`。
  translate,

  /// `type="scale"`, components `[sx, sy]`. / `type="scale"`，分量 `[sx, sy]`。
  scale,

  /// `type="rotate"`, components `[angleDegrees, cx, cy]`.
  ///
  /// `type="rotate"`，分量 `[angleDegrees, cx, cy]`。
  rotate,

  /// `type="skewX"`, components `[angleDegrees]` — shears X along Y.
  ///
  /// `type="skewX"`，分量 `[angleDegrees]`——沿 Y 方向错切 X。
  skewX,

  /// `type="skewY"`, components `[angleDegrees]` — shears Y along X.
  ///
  /// `type="skewY"`，分量 `[angleDegrees]`——沿 X 方向错切 Y。
  skewY,
}

/// A parsed, self-contained `<animateTransform>` timeline.
///
/// Each keyframe in [values] is a 3-component `List<double>` whose meaning
/// depends on [type] (see [SmilTransformType]); values are normalized to 3
/// components at parse time (`svg_document_parser.dart`) so this class never
/// needs to know about SVG's per-type shorthand grammar (e.g. `scale`'s
/// single-number form meaning `sy == sx`).
///
/// Timing semantics (`begin`/`duration`/`fillFreeze`/`repeatCount`/
/// `calcMode`/`keyTimes`) mirror [SmilAnimation] exactly.
///
/// 一个已完整解析的、自包含的 `<animateTransform>` 时间线。
///
/// [values] 中每个关键帧是一个 3 分量的 `List<double>`，具体含义取决于
/// [type]（见 [SmilTransformType]）；分量已在解析阶段
/// （`svg_document_parser.dart`）归一化为 3 个，因此本类无需了解 SVG 各
/// type 的简写语法（例如 `scale` 单数值形式意味着 `sy == sx`）。
///
/// 时序语义（`begin`/`duration`/`fillFreeze`/`repeatCount`/`calcMode`/
/// `keyTimes`）与 [SmilAnimation] 完全一致。
class SmilTransformAnimation implements SmilTimed {
  /// Creates a fully-parsed transform animation timeline.
  ///
  /// 创建一个已完整解析的变换动画时间线。
  SmilTransformAnimation({
    required this.type,
    required this.values,
    required this.duration,
    required this.begin,
    required this.fillFreeze,
    this.repeatCount = SmilRepeatCount.once,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    this.elementId,
    this.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  }) : assert(
         values.length >= 2,
         'an <animateTransform> needs at least two keyframe values',
       );

  @override
  final String? elementId;

  @override
  final SmilBeginSpec beginSpec;

  /// Which transform this drives. / 驱动的变换种类。
  final SmilTransformType type;

  /// Keyframe values, each a normalized 3-component list (see class doc).
  ///
  /// 关键帧数值，每个是归一化后的 3 分量列表（见类注释）。
  final List<List<double>> values;

  /// Total duration of one iteration (SMIL `dur`). / 单次迭代总时长（SMIL `dur`）。
  @override
  final Duration duration;

  /// Delay before the animation starts on the global timeline (SMIL `begin`).
  ///
  /// 动画在全局时间线上开始前的延迟（SMIL `begin`）。
  ///
  /// Mutable for the same reason as [SmilAnimation.begin] — filled in once by
  /// `resolveSmilBeginTimes` right after parsing.
  ///
  /// 可写的原因同 [SmilAnimation.begin]——由 `resolveSmilBeginTimes` 在解析后
  /// 一次性填入。
  @override
  Duration begin;

  /// Whether the end value is held after completion (`fill="freeze"`).
  ///
  /// 完成后是否定格末值（`fill="freeze"`）。
  final bool fillFreeze;

  /// Number of times the animation repeats (SMIL `repeatCount`).
  ///
  /// 动画重复次数（SMIL `repeatCount`）。
  @override
  final SmilRepeatCount repeatCount;

  /// Keyframe interpolation mode (SMIL `calcMode`). / 关键帧插值模式（SMIL `calcMode`）。
  final SmilCalcMode calcMode;

  /// Custom per-keyframe timing fractions, one per [values] entry.
  ///
  /// 每个关键帧的自定义时间比例，与 [values] 一一对应。
  final List<double>? keyTimes;

  /// Per-segment cubic-bezier easing curves (SMIL `keySplines`); see
  /// [SmilAnimation.keySplines].
  ///
  /// 每段的三次贝塞尔缓动曲线（SMIL `keySplines`）；见
  /// [SmilAnimation.keySplines]。
  final List<CubicBezier>? keySplines;

  /// Samples the animated transform components at global timeline time [t].
  ///
  /// Returns null under the same conditions as [SmilAnimation.sample] — the
  /// caller should treat this transform as identity (i.e. skip it) in that
  /// case.
  ///
  /// 在全局时间线时刻 [t] 采样变换分量。
  ///
  /// 返回 null 的条件与 [SmilAnimation.sample] 相同——此时调用方应将该变换
  /// 视为单位变换（即跳过）。
  List<double>? sample(Duration t) {
    final timing = _resolveTiming(
      t: t,
      begin: begin,
      duration: duration,
      repeatCount: repeatCount,
      fillFreeze: fillFreeze,
    );
    if (timing == null) return null;

    final segments = values.length - 1;
    final effectiveKeyTimes = calcMode == SmilCalcMode.paced
        ? _pacedKeyTimes<List<double>>(values, _vectorDistance)
        : keyTimes;
    final segment = _locateSegment(
      timing.progress,
      segments,
      effectiveKeyTimes,
    );
    if (calcMode == SmilCalcMode.discrete) return values[segment.index];

    final a = values[segment.index];
    final b = values[segment.index + 1];
    final segT = _easedSegmentT(calcMode, keySplines, segment);
    return [for (var i = 0; i < a.length; i++) a[i] + (b[i] - a[i]) * segT];
  }
}

/// One sampled point on an `<animateMotion>` path: where the element sits and,
/// for `rotate="auto"`, which way it faces.
///
/// `<animateMotion>` 路径上的一个采样点：元素所处位置，以及在
/// `rotate="auto"` 下的朝向。
class SmilMotionSample {
  /// Creates a motion sample. / 创建一个运动采样点。
  const SmilMotionSample(this.x, this.y, this.angleDegrees);

  /// X offset to translate the element by. / 元素平移的 X 偏移。
  final double x;

  /// Y offset to translate the element by. / 元素平移的 Y 偏移。
  final double y;

  /// Rotation in degrees to apply after translating (0 unless the animation
  /// asks for one).
  ///
  /// 平移后应施加的旋转角度（除非动画要求，否则为 0）。
  final double angleDegrees;
}

/// A parsed `<animateMotion>` timeline: an arc-length-parameterized lookup
/// table built once at parse time, sampled with plain interpolation per frame.
///
/// The table comes from `dart:ui`'s own `Path.computeMetrics()` /
/// `PathMetric.getTangentForOffset()` (see `svg_document_parser.dart`), which
/// already does arc-length parameterization properly — this class only stores
/// the result, so no curve flattening happens on the per-frame path.
///
/// Timing semantics (`begin`/`duration`/`fillFreeze`/`repeatCount`, including
/// syncbase `begin`) mirror [SmilAnimation] exactly.
///
/// `keyPoints` (a `values`-shaped list of `[0, 1]` arc-length fractions, one
/// per `keyTimes` entry) plus `calcMode`/`keyTimes`/`keySplines` are
/// supported — see [keyPoints]. **Not supported** (documented): `<mpath>`
/// pointing at anything other than a `<path>`'s `d`.
///
/// 已解析的 `<animateMotion>` 时间线：解析阶段一次性建好的、按弧长参数化的
/// 查找表，逐帧只做普通插值采样。
///
/// 该表由 `dart:ui` 自身的 `Path.computeMetrics()` /
/// `PathMetric.getTangentForOffset()` 生成（见 `svg_document_parser.dart`），
/// 弧长参数化由官方 API 完成——因此逐帧路径上不会发生任何曲线展平计算。
///
/// 时序语义（`begin`/`duration`/`fillFreeze`/`repeatCount`，含同步基准
/// `begin`）与 [SmilAnimation] 完全一致。
///
/// **不支持**（明确记录）：`<animateMotion>` 上的
/// `keyPoints`/`keyTimes`/`calcMode`（运动始终按弧长匀速），以及指向 `<path>`
/// 的 `d` 之外任何东西的 `<mpath>`。
class SmilMotionAnimation implements SmilTimed {
  /// Creates a motion timeline from a precomputed sample table.
  ///
  /// 用预计算好的采样表创建一条运动时间线。
  SmilMotionAnimation({
    required this.samples,
    required this.duration,
    required this.begin,
    required this.fillFreeze,
    this.repeatCount = SmilRepeatCount.once,
    this.elementId,
    this.beginSpec = const SmilBeginSpec.offset(Duration.zero),
    this.keyPoints,
    this.keyTimes,
    this.keySplines,
    this.calcMode = SmilCalcMode.linear,
  }) : assert(samples.length >= 2, 'a motion path needs at least two samples'),
       assert(
         keyPoints == null || keyPoints.length >= 2,
         'keyPoints needs at least two values',
       );

  /// Evenly-spaced-by-arc-length samples from the motion path, first to last.
  ///
  /// 沿弧长等距分布的运动路径采样点，从头到尾。
  final List<SmilMotionSample> samples;

  /// `keyPoints="0;0.25;1"` — arc-length fractions (`[0, 1]`) the element
  /// should be at for each `keyTimes` entry, overriding the default of
  /// "arc-length fraction == time fraction". Null preserves the exact
  /// pre-existing behaviour (direct progress → sample-table lookup).
  ///
  /// `keyPoints="0;0.25;1"`——每个 `keyTimes` 时刻元素应处于的弧长比例
  /// （`[0, 1]`），覆盖默认的"弧长比例 == 时间比例"。为 null 时保持既有行为
  /// 原样不变（进度直接映射到采样表）。
  final List<double>? keyPoints;

  /// `keyPoints`' own timing fractions; only consulted when [keyPoints] is
  /// set. See [SmilAnimation.keyTimes].
  ///
  /// [keyPoints] 自身的时间比例；仅在设置了 [keyPoints] 时生效。见
  /// [SmilAnimation.keyTimes]。
  final List<double>? keyTimes;

  /// Per-segment easing curves for [keyPoints]; see [SmilAnimation.keySplines].
  ///
  /// [keyPoints] 各段的缓动曲线；见 [SmilAnimation.keySplines]。
  final List<CubicBezier>? keySplines;

  /// Interpolation mode for [keyPoints]; only consulted when [keyPoints] is
  /// set.
  ///
  /// [keyPoints] 的插值模式；仅在设置了 [keyPoints] 时生效。
  final SmilCalcMode calcMode;

  @override
  final Duration duration;

  @override
  Duration begin;

  /// Whether the final position is held after completion (`fill="freeze"`).
  ///
  /// 完成后是否定格在末位置（`fill="freeze"`）。
  final bool fillFreeze;

  @override
  final SmilRepeatCount repeatCount;

  @override
  final String? elementId;

  @override
  final SmilBeginSpec beginSpec;

  /// Samples the element's position (and `rotate="auto"` angle) at global
  /// timeline time [t], or null when the animation isn't active — same
  /// convention as [SmilAnimation.sample].
  ///
  /// 在全局时间线时刻 [t] 采样元素位置（以及 `rotate="auto"` 的角度）；动画未
  /// 激活时返回 null——约定与 [SmilAnimation.sample] 相同。
  SmilMotionSample? sample(Duration t) {
    final timing = _resolveTiming(
      t: t,
      begin: begin,
      duration: duration,
      repeatCount: repeatCount,
      fillFreeze: fillFreeze,
    );
    if (timing == null) return null;

    // With no keyPoints, arc-length fraction == time fraction — the exact
    // pre-existing (SVG "paced") behaviour. keyPoints reroutes progress
    // through the same segment-location/easing machinery calcMode drives on
    // SmilAnimation, but its output is an arc-length fraction, not a value.
    //
    // 没有 keyPoints 时，弧长比例等于时间比例——即既有的（SVG "paced"）行为。
    // keyPoints 把进度改道，走与 SmilAnimation 上 calcMode 相同的区间定位/
    // 缓动机制，只是产出的是弧长比例而非数值。
    var arcFraction = timing.progress;
    final points = keyPoints;
    if (points != null) {
      final segments = points.length - 1;
      final effectiveKeyTimes = calcMode == SmilCalcMode.paced
          ? _pacedKeyTimes<double>(points, (a, b) => (b - a).abs())
          : keyTimes;
      final segment = _locateSegment(
        timing.progress,
        segments,
        effectiveKeyTimes,
      );
      if (calcMode == SmilCalcMode.discrete) {
        arcFraction = points[segment.index];
      } else {
        final a = points[segment.index];
        final b = points[segment.index + 1];
        final segT = _easedSegmentT(calcMode, keySplines, segment);
        arcFraction = a + (b - a) * segT;
      }
    }

    final scaled = (arcFraction * (samples.length - 1)).clamp(
      0.0,
      (samples.length - 1).toDouble(),
    );
    final index = scaled.floor().clamp(0, samples.length - 2);
    final localT = scaled - index;
    final a = samples[index];
    final b = samples[index + 1];
    return SmilMotionSample(
      a.x + (b.x - a.x) * localT,
      a.y + (b.y - a.y) * localT,
      // The table is dense, so the segment's own angle is used rather than
      // interpolated — interpolating would need ±180° wrap handling for no
      // visible gain.
      //
      // 采样表足够密，直接取该段自身的角度而不插值——插值需要处理 ±180° 绕回，
      // 视觉上却没有收益。
      a.angleDegrees,
    );
  }
}

/// A parsed, self-contained colour `<animate>` timeline (e.g.
/// `attributeName="stop-color"` on a gradient `<stop>` — see
/// `svg_document_parser.dart`'s `_parseAnimateColor`).
///
/// Kept separate from [SmilAnimation] because colours interpolate per
/// ARGB-byte, not as a single scalar; [values] are packed `0xAARRGGBB` ints
/// so this file (deliberately framework-independent — see file doc) never
/// needs to import a colour type. Timing semantics (`begin`/`duration`/
/// `fillFreeze`/`repeatCount`/`calcMode`/`keyTimes`/`keySplines`) mirror
/// [SmilAnimation] exactly, reusing the same segment-location/easing helpers.
///
/// 一个已完整解析的、自包含的颜色 `<animate>` 时间线（例如渐变 `<stop>` 上的
/// `attributeName="stop-color"`——见 `svg_document_parser.dart` 的
/// `_parseAnimateColor`）。
///
/// 与 [SmilAnimation] 分开存放，因为颜色是按 ARGB 字节插值，而非单一标量；
/// [values] 打包为 `0xAARRGGBB` 整数，使本文件（刻意保持与框架无关——见文件
/// 头注释）无需引入颜色类型。时序语义（`begin`/`duration`/`fillFreeze`/
/// `repeatCount`/`calcMode`/`keyTimes`/`keySplines`）与 [SmilAnimation] 完全
/// 一致，复用同一套区间定位/缓动辅助函数。
class SmilColorAnimation implements SmilTimed {
  /// Creates a fully-parsed colour timeline. / 创建一个已完整解析的颜色时间线。
  SmilColorAnimation({
    required this.values,
    required this.duration,
    required this.begin,
    required this.fillFreeze,
    this.repeatCount = SmilRepeatCount.once,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    this.elementId,
    this.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  }) : assert(
         values.length >= 2,
         'a colour <animate> needs at least two keyframe values',
       );

  @override
  final String? elementId;

  @override
  final SmilBeginSpec beginSpec;

  /// Keyframe colours packed as `0xAARRGGBB`. / 关键帧颜色，打包为 `0xAARRGGBB`。
  final List<int> values;

  @override
  final Duration duration;

  @override
  Duration begin;

  /// Whether the end value is held after completion. / 完成后是否定格末值。
  final bool fillFreeze;

  @override
  final SmilRepeatCount repeatCount;

  /// Keyframe interpolation mode. / 关键帧插值模式。
  final SmilCalcMode calcMode;

  /// Custom per-keyframe timing fractions; see [SmilAnimation.keyTimes].
  ///
  /// 每个关键帧的自定义时间比例；见 [SmilAnimation.keyTimes]。
  final List<double>? keyTimes;

  /// Per-segment easing curves; see [SmilAnimation.keySplines].
  ///
  /// 每段的缓动曲线；见 [SmilAnimation.keySplines]。
  final List<CubicBezier>? keySplines;

  /// Samples the animated colour (as `0xAARRGGBB`) at global timeline time
  /// [t]; same null convention as [SmilAnimation.sample].
  ///
  /// 在全局时间线时刻 [t] 采样动画颜色（`0xAARRGGBB`）；空值约定同
  /// [SmilAnimation.sample]。
  int? sample(Duration t) {
    final timing = _resolveTiming(
      t: t,
      begin: begin,
      duration: duration,
      repeatCount: repeatCount,
      fillFreeze: fillFreeze,
    );
    if (timing == null) return null;

    final segments = values.length - 1;
    final effectiveKeyTimes = calcMode == SmilCalcMode.paced
        ? _pacedKeyTimes<int>(values, _argbDistance)
        : keyTimes;
    final segment = _locateSegment(
      timing.progress,
      segments,
      effectiveKeyTimes,
    );
    if (calcMode == SmilCalcMode.discrete) return values[segment.index];

    final a = values[segment.index];
    final b = values[segment.index + 1];
    final segT = _easedSegmentT(calcMode, keySplines, segment);
    int lerpChannel(int shift) {
      final ca = (a >> shift) & 0xFF;
      final cb = (b >> shift) & 0xFF;
      return (ca + (cb - ca) * segT).round().clamp(0, 255);
    }

    return (lerpChannel(24) << 24) |
        (lerpChannel(16) << 16) |
        (lerpChannel(8) << 8) |
        lerpChannel(0);
  }
}

double _argbDistance(int a, int b) {
  var sumSquares = 0.0;
  for (var shift = 0; shift < 32; shift += 8) {
    final d = ((a >> shift) & 0xFF) - ((b >> shift) & 0xFF);
    sumSquares += d * d;
  }
  return math.sqrt(sumSquares);
}

double _vectorDistance(List<double> a, List<double> b) {
  var sumSquares = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = b[i] - a[i];
    sumSquares += d * d;
  }
  return math.sqrt(sumSquares);
}

/// Resolved timing state shared by [SmilAnimation.sample] and
/// [SmilTransformAnimation.sample]: how far into the current (or, once
/// frozen, final) iteration the animation is.
///
/// [SmilAnimation.sample]/[SmilTransformAnimation.sample] 共用的已解析时序
/// 状态：动画处于当前（若已定格则为最终）一轮的哪个进度上。
class _Timing {
  const _Timing(this.progress);

  /// Progress within the current iteration, in `[0, 1]`.
  ///
  /// 当前迭代内的进度，取值 `[0, 1]`。
  final double progress;
}

/// Computes [_Timing] for global time [t] given an animation's `begin`/
/// `duration`/`repeatCount`/`fill` — shared by both animation classes so
/// looping and freeze semantics stay identical between scalar and transform
/// animations.
///
/// 根据动画的 `begin`/`duration`/`repeatCount`/`fill`，为全局时刻 [t] 计算
/// [_Timing]——两个动画类共用，确保循环与定格语义在数值动画与变换动画间保持
/// 一致。
_Timing? _resolveTiming({
  required Duration t,
  required Duration begin,
  required Duration duration,
  required SmilRepeatCount repeatCount,
  required bool fillFreeze,
}) {
  final local = t - begin;
  if (local.isNegative) return null;
  if (duration.inMicroseconds == 0) return const _Timing(1);

  final localMicros = local.inMicroseconds;
  final durationMicros = duration.inMicroseconds;

  if (repeatCount.indefinite) {
    return _Timing((localMicros % durationMicros) / durationMicros);
  }

  final totalMicros = (durationMicros * repeatCount.count).round();
  if (localMicros >= totalMicros) {
    if (!fillFreeze) return null;
    final wholeIterations = repeatCount.count.floor();
    final fractional = repeatCount.count - wholeIterations;
    return _Timing(fractional == 0 ? 1 : fractional);
  }
  return _Timing((localMicros % durationMicros) / durationMicros);
}

/// A located keyframe segment: interpolate between `values[index]` and
/// `values[index + 1]` at local fraction `t`.
///
/// 定位到的关键帧区间：在 `values[index]` 与 `values[index + 1]` 之间按局部
/// 比例 `t` 插值。
class _Segment {
  const _Segment(this.index, this.t);

  /// Index of the segment's starting keyframe. / 区间起始关键帧的下标。
  final int index;

  /// Fraction within the segment, in `[0, 1]`. / 区间内的比例，取值 `[0, 1]`。
  final double t;
}

/// Maps overall [progress] (`[0, 1]`) to a keyframe [_Segment], honoring
/// custom [keyTimes] when provided and valid (length `segments + 1`),
/// otherwise assuming even spacing.
///
/// 把总体 [progress]（`[0, 1]`）映射到关键帧 [_Segment]：若提供了合法的自定义
/// [keyTimes]（长度为 `segments + 1`）则按其分布，否则按均匀分布处理。
_Segment _locateSegment(double progress, int segments, List<double>? keyTimes) {
  if (keyTimes != null && keyTimes.length == segments + 1) {
    for (var i = 0; i < segments; i++) {
      final t0 = keyTimes[i];
      final t1 = keyTimes[i + 1];
      if (progress <= t1 || i == segments - 1) {
        final span = t1 - t0;
        final segT = span <= 0 ? 0.0 : ((progress - t0) / span).clamp(0.0, 1.0);
        return _Segment(i, segT);
      }
    }
  }
  final scaled = (progress * segments).clamp(0.0, segments.toDouble());
  final index = scaled.floor().clamp(0, segments - 1);
  return _Segment(index, (scaled - index).clamp(0.0, 1.0));
}

/// Applies `keySplines` easing (when [calcMode] is [SmilCalcMode.spline] and
/// a matching spline exists for [segment]'s index) to its local fraction;
/// otherwise returns the fraction unchanged (linear within the segment).
///
/// 当 [calcMode] 为 [SmilCalcMode.spline] 且 [segment] 下标存在对应 spline 时，
/// 对其局部比例应用 `keySplines` 缓动；否则原样返回（区间内线性）。
double _easedSegmentT(
  SmilCalcMode calcMode,
  List<CubicBezier>? keySplines,
  _Segment segment,
) {
  if (calcMode != SmilCalcMode.spline ||
      keySplines == null ||
      segment.index >= keySplines.length) {
    return segment.t;
  }
  return keySplines[segment.index].transform(segment.t);
}

/// Computes `calcMode="paced"` keyframe timing: each keyframe's time fraction
/// is proportional to the cumulative [distance] traveled so far, so the
/// animated value changes at a constant rate regardless of uneven keyframe
/// values. Falls back to even spacing if every keyframe is equidistant (zero
/// total distance).
///
/// 计算 `calcMode="paced"` 的关键帧时序：每个关键帧的时间比例正比于累计
/// [distance]，使动画值以恒定速率变化，不受关键帧数值疏密不均影响。若总
/// 距离为零（所有关键帧重合）则退化为均匀分布。
List<double> _pacedKeyTimes<T>(
  List<T> values,
  double Function(T a, T b) distance,
) {
  final n = values.length;
  final cumulative = List<double>.filled(n, 0);
  var total = 0.0;
  for (var i = 1; i < n; i++) {
    total += distance(values[i - 1], values[i]);
    cumulative[i] = total;
  }
  if (total <= 0) {
    return [for (var i = 0; i < n; i++) i / (n - 1)];
  }
  return [for (final c in cumulative) c / total];
}

/// Parses a SMIL `dur`/`begin` time string (e.g. `"0.5s"`, `"600ms"`, `"2"`)
/// into a [Duration]. Unitless numbers are treated as seconds, matching the
/// SMIL default. Unparsable input maps to [Duration.zero].
///
/// 解析 SMIL `dur`/`begin` 时间字符串（如 `"0.5s"`、`"600ms"`、`"2"`）为
/// [Duration]。无单位数字按秒处理（SMIL 默认单位）。无法解析时返回
/// [Duration.zero]。
Duration parseSmilDuration(String? raw) {
  if (raw == null) return Duration.zero;
  final value = raw.trim();
  if (value.isEmpty || value == 'indefinite') return Duration.zero;
  double? seconds;
  if (value.endsWith('ms')) {
    final n = double.tryParse(value.substring(0, value.length - 2));
    if (n != null) seconds = n / 1000;
  } else if (value.endsWith('s')) {
    seconds = double.tryParse(value.substring(0, value.length - 1));
  } else {
    seconds = double.tryParse(value);
  }
  seconds ??= 0;
  return Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}

/// Parses a SMIL `repeatCount` attribute: `"indefinite"`, a positive number,
/// or absent/unparsable (defaults to [SmilRepeatCount.once]).
///
/// 解析 SMIL `repeatCount` 属性：`"indefinite"`、正数，或缺失/无法解析（默认
/// [SmilRepeatCount.once]）。
SmilRepeatCount parseSmilRepeatCount(String? raw) {
  if (raw == null) return SmilRepeatCount.once;
  final value = raw.trim();
  if (value == 'indefinite') return const SmilRepeatCount.indefinite();
  final n = double.tryParse(value);
  if (n == null || n <= 0) return SmilRepeatCount.once;
  return SmilRepeatCount.finite(n);
}

/// Parses a SMIL `calcMode` attribute; unrecognized/absent values default to
/// [SmilCalcMode.linear].
///
/// 解析 SMIL `calcMode` 属性；无法识别/缺失的值默认按 [SmilCalcMode.linear]
/// 处理。
SmilCalcMode parseSmilCalcMode(String? raw) {
  return switch (raw) {
    'discrete' => SmilCalcMode.discrete,
    'paced' => SmilCalcMode.paced,
    'spline' => SmilCalcMode.spline,
    _ => SmilCalcMode.linear,
  };
}

/// Parses a SMIL `keySplines="0.1 0.7 1.0 0.1;..."` attribute into one
/// [CubicBezier] per segment, or null if absent/malformed (any segment not
/// parsing to exactly 4 numbers invalidates the whole list, since a partial
/// spline list can't be safely matched to segments).
///
/// 解析 SMIL `keySplines="0.1 0.7 1.0 0.1;..."` 属性为每段一个 [CubicBezier]；
/// 缺失/格式错误时返回 null（任一段无法解析出恰好 4 个数字都会使整个列表
/// 作废，因为局部的 spline 列表无法安全地与分段对应）。
List<CubicBezier>? parseSmilKeySplines(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final splines = <CubicBezier>[];
  for (final segment in raw.split(';')) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (parts.length != 4 || parts.any((v) => v == null)) return null;
    splines.add(CubicBezier(parts[0]!, parts[1]!, parts[2]!, parts[3]!));
  }
  return splines.isEmpty ? null : splines;
}

/// Parses a SMIL `keyTimes="0;0.3;1"` attribute into a fraction list, or null
/// if absent/malformed (caller then falls back to even spacing).
///
/// 解析 SMIL `keyTimes="0;0.3;1"` 属性为比例列表；缺失/格式错误时返回 null
/// （调用方回退到均匀分布）。
List<double>? parseSmilKeyTimes(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.split(';').map((s) => double.tryParse(s.trim())).toList();
  if (parts.any((v) => v == null)) return null;
  return parts.cast<double>();
}

/// Parses a SMIL `values="v1;v2;..."` keyframe list, or falls back to a
/// `from`/`to` pair, into a numeric keyframe list.
///
/// Returns null if neither `values` nor a usable `from`/`to` pair is present,
/// or if any keyframe fails to parse as a number — this animates only
/// single-numeric presentation attributes (see [SmilAnimation] doc).
///
/// 解析 SMIL `values="v1;v2;..."` 关键帧列表，若不存在则回退到 `from`/`to`
/// 组合，得到数值关键帧列表。
///
/// 若既无 `values` 也无可用的 `from`/`to`，或任一关键帧无法解析为数字，
/// 返回 null——只对单一数值型表现属性做动画（见 [SmilAnimation] 类注释）。
List<double>? parseSmilValues({String? values, String? from, String? to}) {
  if (values != null && values.trim().isNotEmpty) {
    final parts = values
        .split(';')
        .map((s) => double.tryParse(s.trim()))
        .toList();
    if (parts.any((v) => v == null) || parts.length < 2) return null;
    return parts.cast<double>();
  }
  if (from != null && to != null) {
    final f = double.tryParse(from.trim());
    final t = double.tryParse(to.trim());
    if (f == null || t == null) return null;
    return [f, t];
  }
  return null;
}

/// Parses a SMIL `<animateTransform>` `values="a b c;d e f;..."` keyframe
/// list (or `from`/`to` shorthand) into per-keyframe number lists, without
/// interpreting how many components each type expects — see
/// `svg_document_parser.dart`'s per-type normalization, which pads/derives
/// the SVG-grammar shorthand (e.g. `scale`'s single-number form) into the
/// fixed 3-component form [SmilTransformAnimation] expects.
///
/// Returns null if neither `values` nor a usable `from`/`to` pair parses.
///
/// 解析 SMIL `<animateTransform>` 的 `values="a b c;d e f;..."` 关键帧列表
/// （或 `from`/`to` 简写）为逐关键帧的数值列表，不解读每种 type 应有多少个
/// 分量——具体的按 type 归一化（如 `scale` 单数值简写的派生）见
/// `svg_document_parser.dart`，统一填充为 [SmilTransformAnimation] 期望的
/// 固定 3 分量形式。
///
/// 若 `values` 与可用的 `from`/`to` 均无法解析，返回 null。
List<List<double>>? parseSmilTransformKeyframes({
  String? values,
  String? from,
  String? to,
}) {
  List<double>? parseComponents(String raw) {
    final parts = raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map(double.tryParse)
        .toList();
    if (parts.isEmpty || parts.any((v) => v == null)) return null;
    return parts.cast<double>();
  }

  if (values != null && values.trim().isNotEmpty) {
    final frames = values.split(';').map((s) => parseComponents(s)).toList();
    if (frames.any((f) => f == null) || frames.length < 2) return null;
    return frames.cast<List<double>>();
  }
  if (from != null && to != null) {
    final f = parseComponents(from);
    final t = parseComponents(to);
    if (f == null || t == null) return null;
    return [f, t];
  }
  return null;
}
