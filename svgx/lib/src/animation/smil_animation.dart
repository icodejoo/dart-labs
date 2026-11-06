// Timeline model for SMIL `<animate>`/`<animateTransform>` elements: parses
// timing attributes once, then samples a value for any point on the global
// timeline. Original implementation — see svgx CLAUDE.md "参考对象" table for
// the ideas (not code) borrowed from svg-rs / F.
//
// 单个 SMIL `<animate>`/`<animateTransform>` 元素的时间线模型：一次性解析
// 其时序属性，之后可对全局时间线上任意时刻采样出数值。原创实现——思路参考见
// svgx CLAUDE.md "参考对象"表（借鉴 svg-rs / F 的思路，非代码）。

import 'dart:math' as math;
import 'dart:typed_data';

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

/// 阶跃位置，与 CSS 阶跃位置同构，避免引入 CSS 解析依赖。
enum SmilStepPosition {
  /// 在每段开始时跳变。
  start,

  /// 在每段结束时跳变。
  end,

  /// 两端都不跳变。
  jumpNone,

  /// 两端都跳变。
  jumpBoth,
}

/// 每段缓动的统一接口。
///
/// 例如：`SmilSegmentEasing easing = const CubicBezier(0, 0, 1, 1);`。
abstract interface class SmilSegmentEasing {
  /// 把段内进度映射为缓动后的进度。
  double transform(double t);
}

/// 按阶跃次数与位置求值的段缓动，输出钳制到 `[0, 1]`。
///
/// 例如：`const SmilStepsEasing(3).transform(0.5)` 返回 `1 / 3`。
class SmilStepsEasing implements SmilSegmentEasing {
  /// 创建阶跃缓动；调用方保证次数至少为 1，jumpNone 时至少为 2。
  const SmilStepsEasing(this.count, [this.position = SmilStepPosition.end]);

  /// 阶跃次数。
  final int count;

  /// 阶跃发生的位置。
  final SmilStepPosition position;

  /// 吸收分数边界附近的浮点误差。
  static const double _boundaryTolerance = 1e-9;

  /// 求阶跃进度并钳制输出；NaN 按进度 0 求值。
  @override
  double transform(double t) {
    if (t.isNaN) t = 0;
    if (t >= 1) return 1;
    if (t <= -1) return 0;
    var step = (t * count + _boundaryTolerance).floor();
    if (position == SmilStepPosition.start ||
        position == SmilStepPosition.jumpBoth) {
      step += 1;
    }
    final jumps = switch (position) {
      SmilStepPosition.start || SmilStepPosition.end => count,
      SmilStepPosition.jumpNone => count - 1,
      SmilStepPosition.jumpBoth => count + 1,
    };
    return step.clamp(0, jumps) / jumps;
  }
}

/// 动画的迭代播放方向，例如 `SmilDirection.alternate` 交替正反播放。
enum SmilDirection {
  /// 每次正向播放。
  normal,

  /// 每次反向播放。
  reverse,

  /// 偶数次迭代反向播放。
  alternate,

  /// 奇数次迭代反向播放。
  alternateReverse,
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
class CubicBezier implements SmilSegmentEasing {
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
  ///
  /// 先牛顿迭代反解 x(s)=t；s 越出 `[0, 1]`、导数过小或步数用尽仍未收敛时，改用
  /// 二分兜底。x1/x2 在 `[0, 1]` 内时与精确解的误差不超过 1e-5。`t <= 0` 返回 0，
  /// `t >= 1` 返回 1；输出的 y 不做钳制，回弹曲线可以越出 `[0, 1]`。
  @override
  double transform(double t) {
    if (x1 == 0 && y1 == 0 && x2 == 1 && y2 == 1) return t; // linear curve
    if (!(t > 0)) return 0; // 含 NaN，一并归零
    if (t >= 1) return 1;

    // x(s) 按 Horner 形式求值，系数只算一次；求解逻辑写在本方法内而不是拆成
    // 子方法，是为了避免热路径上返回 double 的装箱开销。
    final a = _a(x1, x2);
    final b = _b(x1, x2);
    final c = _c(x1);
    final a3 = 3 * a;
    final b2 = 2 * b;
    var s = t;
    var converged = false;
    for (var i = 0; i < _newtonMaxIterations; i++) {
      final derivative = (a3 * s + b2) * s + c;
      final slope = derivative.abs();
      if (slope < _minDerivative) break;
      final step = (((a * s + b) * s + c) * s - t) / derivative;
      s -= step;
      if (s < 0 || s > 1) break;
      final tolerance = slope >= _healthyDerivative
          ? _newtonLooseTolerance
          : _newtonTightTolerance;
      if (step.abs() < tolerance) {
        converged = true;
        break;
      }
    }
    if (!converged) {
      // 牛顿失效：在 [0, 1] 上二分，只看符号，与导数无关。
      var lo = 0.0;
      var hi = 1.0;
      for (var i = 0; i < _bisectIterations; i++) {
        final mid = (lo + hi) / 2;
        if (((a * mid + b) * mid + c) * mid < t) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      s = (lo + hi) / 2;
    }
    return _bezierComponent(y1, y2, s);
  }

  /// 牛顿迭代的最大步数。
  static const int _newtonMaxIterations = 8;

  /// 导数健康（≥ [_healthyDerivative]）时的收敛阈值：牛顿二次收敛，迈出一步后
  /// 的残余误差远小于单步修正量，所以单步修正量小于它就够了。
  static const double _newtonLooseTolerance = 3e-4;

  /// 导数偏小（近重根，仅线性收敛）时的收敛阈值，要收得更紧。
  static const double _newtonTightTolerance = 1e-7;

  /// 区分"导数健康"与"导数偏小"的分界。
  static const double _healthyDerivative = 0.3;

  /// 牛顿迭代允许的最小导数绝对值，更小则放弃牛顿改走二分。
  static const double _minDerivative = 1e-6;

  /// 二分兜底的步数，区间宽度收敛到约 1e-12。
  static const int _bisectIterations = 40;

  static double _bezierComponent(double p1, double p2, double t) =>
      _a(p1, p2) * t * t * t + _b(p1, p2) * t * t + _c(p1) * t;

  static double _a(double p1, double p2) => 1.0 - 3.0 * p2 + 3.0 * p1;
  static double _b(double p1, double p2) => 3.0 * p2 - 6.0 * p1;
  static double _c(double p1) => 3.0 * p1;
}

/// restart 规则 `always`：每次 begin 都重新开始（SMIL 默认值）。
/// The `always` restart rule: every begin restarts the interval (SMIL default).
const _kRestartAlways = 'always';

/// restart 规则 `never`：首次开始后忽略之后所有 begin。
/// The `never` restart rule: ignore every begin after the first.
const _kRestartNever = 'never';

/// restart 规则 `whenNotActive`：仅在当前区间未活动时接受 begin。
/// The `whenNotActive` restart rule: accept a begin only while inactive.
const _kRestartWhenNotActive = 'whenNotActive';

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
    this.entries,
    this.restart = _kRestartAlways,
    this.endSpecs,
    this.minimum,
    this.maximum,
  });

  /// A plain `begin` offset with no reference. / 无引用的纯 `begin` 偏移。
  const SmilBeginSpec.offset(this.offset)
    : syncbaseId = null,
      onSyncbaseEnd = false,
      entries = null,
      restart = _kRestartAlways,
      endSpecs = null,
      minimum = null,
      maximum = null;

  /// Offset added to the resolved base time (may be negative).
  ///
  /// 加在解析出的基准时间上的偏移（可为负）。
  final Duration offset;

  /// Non-null only for begin-value-list syntax; single values keep the old path.
  /// 仅分号列表非空；普通单值保留旧路径。
  final List<SmilBeginSpec>? entries;

  /// Restart rule used by the bounded interval resolver.
  /// 列表区间求解使用的重启规则。
  final String restart;

  /// Optional end instance specifications on the document timeline.
  /// 文档时间线上的可选 end 实例规格。
  final List<SmilBeginSpec>? endSpecs;

  /// Minimum active duration, including any frozen repeat tail.
  /// 最短活动期，包含重复结束后的冻结尾段。
  final Duration? minimum;

  /// Maximum active duration. / 最长活动期。
  final Duration? maximum;

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

/// 六类 SMIL 动画共用的时序字段与采样入口，保留同步基准解析所需的可写开始时刻。
///
/// 例如：`SmilTimeline timeline = SmilAnimation(attributeName: 'opacity',
/// values: [0, 1], duration: const Duration(seconds: 1), begin: Duration.zero,
/// fillFreeze: true);`，之后可用 `timeline.begin = Duration.zero` 回写开始时刻。
abstract class SmilTimeline implements SmilTimed {
  /// 创建共享时间线；子类通过 super 参数转发时序配置。
  ///
  /// 例如：`MyTimeline({required super.duration, required super.begin,
  /// required super.fillFreeze});`。
  SmilTimeline({
    required this.duration,
    required this.begin,
    required this.fillFreeze,
    this.repeatCount = SmilRepeatCount.once,
    this.direction = SmilDirection.normal,
    this.elementId,
    this.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  });

  /// 动画元素自身的 `id`（同步基准所引用的对象），可能为 null。
  @override
  final String? elementId;

  /// 尚未解析同步基准引用的原始 `begin` 属性。
  @override
  final SmilBeginSpec beginSpec;

  /// 单次迭代总时长（SMIL `dur`）。
  @override
  final Duration duration;

  /// 动画在全局时间线上开始前的延迟（SMIL `begin`）。
  ///
  /// 可写是为了让 [resolveSmilBeginTimes] 在解析完成后、任何一帧被采样之前
  /// 一次性填入同步基准解析结果。
  @override
  Duration begin;

  /// 完成后是否定格末值（`fill="freeze"`）。有限 [repeatCount] 时定格在最后
  /// 一次重复结束时的值；无限重复时不使用此值，因为动画永不结束。
  final bool fillFreeze;

  /// 动画重复次数（SMIL `repeatCount`）。
  @override
  final SmilRepeatCount repeatCount;

  /// 迭代的播放方向，默认正向。
  final SmilDirection direction;

  /// Resolved list intervals, allocated only for a list dependency component.
  /// 列表连通分量的已求解区间；普通单值路径不分配。
  List<SmilInterval>? intervals;

  /// True when interval expansion reached a safety bound.
  /// 整个连通分量已触及展开安全预算。
  bool instancesTruncated = false;

  /// Whether this component can keep producing instances. / 分量是否持续产生实例。
  bool get hasPendingInstances =>
      _listResolver?.hasCycle == true && _listResolver!._queue.isNotEmpty;

  /// 所属列表连通分量的前向求解器；普通单值路径为 null。
  /// Forward resolver of this list component; null on the legacy single-value path.
  _ForwardBeginResolver? _listResolver;

  /// Last interval end, used by document playback duration accounting.
  /// 最后一个区间的结束时刻，用于文档播放时长统计。
  Duration? get intervalEnd =>
      intervals?.isNotEmpty == true ? intervals!.last.end : null;

  /// 解析全局时刻的迭代进度；未开始或已结束且不定格时返回 null。
  _Timing? _timingAt(Duration t) {
    _listResolver?.extend(t);
    final resolved = intervals;
    if (resolved != null) {
      // 二分定位区间，长时间采样仍为 O(log n)。 / Binary interval lookup.
      var lo = 0, hi = resolved.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (resolved[mid].begin <= t) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo == 0) return null;
      final interval = resolved[lo - 1];
      if (t >= interval.end && !fillFreeze) return null;
      final sampleTime = t < interval.end ? t : interval.end;
      final local = sampleTime - interval.begin;
      final natural = smilActiveDuration(duration, repeatCount);
      if (!repeatCount.indefinite && local >= natural) {
        return _resolveTiming(
          t: natural,
          begin: Duration.zero,
          duration: duration,
          repeatCount: repeatCount,
          fillFreeze: true,
          direction: direction,
        );
      }
      if (sampleTime == interval.end &&
          duration > Duration.zero &&
          local.inMicroseconds > 0 &&
          local.inMicroseconds % duration.inMicroseconds == 0) {
        final iteration = local.inMicroseconds ~/ duration.inMicroseconds - 1;
        return _Timing(_directed(direction, iteration, 1));
      }
      return _resolveTiming(
        t: local,
        begin: Duration.zero,
        duration: duration,
        repeatCount: repeatCount,
        fillFreeze: true,
        direction: direction,
      );
    }
    return _resolveTiming(
      t: t,
      begin: begin,
      duration: duration,
      repeatCount: repeatCount,
      fillFreeze: fillFreeze,
      direction: direction,
    );
  }
}

/// Resolves every syncbase `begin` in [animations] into an absolute time, in
/// place.
///
/// List components use bounded instance expansion, extended on demand for
/// forward dependencies. Components without lists retain the legacy DFS.
/// 列表所在分量按预算展开实例；正向依赖按需延长，无列表分量保持旧 DFS。
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
  // No list: preserve legacy DFS behaviour and avoid extra per-animation data.
  if (animations.any((a) => a.beginSpec.entries != null)) {
    _resolveBeginLists(animations);
    return;
  }
  _resolveLegacyBeginTimes(animations);
}

void _resolveLegacyBeginTimes(List<SmilTimed> animations) {
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
    if (spec.offset == kSmilNeverBegins) {
      animation.begin = kSmilNeverBegins;
    } else if (target == null) {
      animation.begin = spec.offset; // plain offset, or a dangling reference
    } else {
      final base = resolve(target);
      if (base == kSmilNeverBegins) {
        animation.begin = kSmilNeverBegins;
      } else if (!spec.onSyncbaseEnd) {
        animation.begin = addSmilTime(base, spec.offset);
      } else if (target.repeatCount.indefinite) {
        animation.begin = kSmilNeverBegins; // an end that never arrives
      } else {
        animation.begin = addSmilTime(
          addSmilTime(
            base,
            smilActiveDuration(target.duration, target.repeatCount),
          ),
          spec.offset,
        );
      }
    }

    colors[animation] = black;
    return animation.begin;
  }

  for (final animation in animations) {
    resolve(animation);
  }
}

/// One accepted active interval in document time, with an exclusive end.
/// 文档时间中的有效活动区间，结束时刻不包含在内。
class SmilInterval {
  /// Creates an accepted interval. / 创建有效区间。
  const SmilInterval(this.begin, this.end);

  /// Inclusive start. / 包含起点。
  final Duration begin;

  /// Exclusive end (possibly the never sentinel). / 不包含终点，可为永不结束。
  final Duration end;
}

// The CSS compiler and legacy single-value parser need no new timing objects.
// List items deliberately use a stricter grammar: events/empty items never fire.
/// 解析分号分隔的 begin 列表，只保留合法的实例规格（事件与空项被丢弃）。
/// Parses a `;`-separated begin list, keeping only valid instance specs.
List<SmilBeginSpec> _parseInstanceSpecs(String raw) => [
  for (final item in raw.split(';'))
    if (_isInstanceSpec(item.trim())) parseSmilBeginSpec(item.trim()),
];

/// 纯时钟值的正则：允许符号、小数、指数、单位，以及 `hh:mm:ss` 形式。
/// Pattern for a plain clock value (sign, fraction, exponent, unit, or h:m:s).
final _clockInstancePattern = RegExp(
  r'^[+-]?(?:(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?(?:h|min|ms|s)?|(?:\d+:)?[0-5]\d:[0-5]\d(?:\.\d+)?)$',
);

/// 同步基准引用的正则：捕获基准 id、`begin`/`end` 与可选的 ±偏移。
/// Pattern for a syncbase reference: captures id, begin/end, and optional offset.
final _syncInstancePattern = RegExp(
  r'^[^\s;]+?\.(begin|end)(?:\s*([+-])\s*(.+))?$',
);

/// 判断 [value] 是否为纯时钟值。 / Whether [value] is a plain clock value.
bool _isClockInstance(String value) => _clockInstancePattern.hasMatch(value);

/// 判断 [value] 能否作为列表实例：时钟值，或偏移合法的同步基准引用。
/// Whether [value] is usable as a list instance: a clock value or a well-formed syncbase reference.
bool _isInstanceSpec(String value) {
  if (_isClockInstance(value)) return true;
  final match = _syncInstancePattern.firstMatch(value);
  return match != null &&
      (match.group(3) == null ||
          _isClockInstance('${match.group(2)}${match.group(3)}'));
}

/// Attach XML-only restart/end/min/max data without changing CSS constructors.
/// Default single begin values return the same object with no extra allocation.
/// 附加 XML 的 restart/end/min/max 配置；默认单值 begin 不额外分配对象。
SmilBeginSpec configureSmilBegin(
  SmilBeginSpec spec, {
  String? restart,
  String? end,
  String? min,
  String? max,
}) {
  if (restart == null && end == null && min == null && max == null) return spec;
  return SmilBeginSpec(
    offset: spec.offset,
    syncbaseId: spec.syncbaseId,
    onSyncbaseEnd: spec.onSyncbaseEnd,
    entries: spec.entries,
    restart: restart ?? _kRestartAlways,
    endSpecs: end == null ? null : _parseInstanceSpecs(end),
    minimum: min == null ? null : parseSmilDuration(min),
    maximum: max == null || max.trim() == 'indefinite'
        ? null
        : parseSmilDuration(max),
  );
}

/// 解析全部 begin/end 依赖：按连通分量分组，逐分量交给前向或有界求解器。
/// Resolves all begin/end dependencies, component by component.
void _resolveBeginLists(List<SmilTimed> animations) {
  final byId = <String, SmilTimed>{};
  for (final a in animations) {
    if (a.elementId != null) byId.putIfAbsent(a.elementId!, () => a);
  }
  final affected = <SmilTimed>{
    for (final a in animations)
      if (a.beginSpec.entries != null) a,
  };
  // Include both sources and dependents, so a single a.end inherits every
  // interval when a is a list. Unconnected single/CSS tracks retain legacy DFS.
  var changed = true;
  while (changed) {
    changed = false;
    for (final a in animations) {
      for (final spec in [
        ...?a.beginSpec.entries,
        if (a.beginSpec.entries == null) a.beginSpec,
        ...?a.beginSpec.endSpecs,
      ]) {
        final target = byId[spec.syncbaseId];
        if (target != null &&
            (affected.contains(a) || affected.contains(target))) {
          if (affected.add(a)) changed = true;
          if (affected.add(target)) changed = true;
        }
      }
    }
  }
  _resolveLegacyBeginTimes(
    animations.where((a) => !affected.contains(a)).toList(),
  );
  final timelines = affected.whereType<SmilTimeline>().toList();
  for (final a in timelines) {
    a.intervals = [];
  }

  final budget = _SmilWorkBudget();
  final remaining = timelines.toSet();
  final neighbors = <SmilTimeline, Set<SmilTimeline>>{
    for (final a in timelines) a: {},
  };
  for (final a in timelines) {
    for (final spec in [
      ...?a.beginSpec.entries,
      if (a.beginSpec.entries == null) a.beginSpec,
      ...?a.beginSpec.endSpecs,
    ]) {
      final target = byId[spec.syncbaseId];
      if (target is SmilTimeline && neighbors.containsKey(target)) {
        neighbors[a]!.add(target);
        neighbors[target]!.add(a);
      }
    }
  }
  while (remaining.isNotEmpty) {
    final component = <SmilTimeline>[];
    final pending = [remaining.first];
    remaining.remove(pending.first);
    while (pending.isNotEmpty) {
      final a = pending.removeLast();
      component.add(a);
      for (final neighbor in neighbors[a]!) {
        if (remaining.remove(neighbor)) pending.add(neighbor);
      }
    }
    if (_ForwardBeginResolver.supports(component, byId)) {
      _ForwardBeginResolver(component, byId, budget).extend(Duration.zero);
    } else {
      _resolveBoundedBeginComponent(component, byId, budget);
    }
  }
}

// 文档级累计预算也覆盖后续惰性展开，避免各分量分别耗满预算。
// The document shares one lifetime budget, including lazy extensions.
const _maxSmilIntervals = 20000;

/// 单个前向求解器队列中待处理通知的上限，超出即截断（防负偏移/环导致的膨胀）。
/// Cap on pending notices in one forward resolver queue; excess truncates.
const _maxSmilQueuedNotices = 100000;

/// 文档级区间总预算，由所有分量与惰性展开共享；耗尽即截断。
/// Document-wide interval budget shared by all components and lazy extensions.
const _maxSmilBudgetIntervals = 100000;

/// 前向求解器每次惰性展开预取的时间窗口（64 秒）。
/// Lookahead window the forward resolver prefetches on each lazy extension.
const _kSmilPrefetchWindow = Duration(seconds: 64);

/// 文档级工作预算：限制求解的总计算量，耗尽后展开即截断。
/// Document-wide work budget; expansion truncates once it runs out.
class _SmilWorkBudget {
  /// 剩余计算单位。 / Remaining work units.
  int remaining = 600000;

  /// 已接受的区间总数。 / Total accepted intervals so far.
  int intervals = 0;

  /// 预算是否已耗尽。 / Whether the budget is exhausted.
  bool get exhausted => remaining <= 0;

  /// 消耗 [count] 个单位，返回预算是否仍为正。
  /// Spends [count] units; returns whether budget remains.
  bool spend([int count = 1]) => (remaining -= count) > 0;
}

// 按时间排序的实例通知；结束通知携带原区间以撤销被 restart 截短的结束。
// End notices retain their interval identity so restart cancels stale ends.
/// 实例通知：[track] 在 [time] 开始（[interval] 为 null），或结束（携带原区间）。
/// Instance notice: a start at [time], or an end carrying its original interval.
class _SmilNotice {
  /// 创建通知。 / Creates a notice.
  const _SmilNotice(this.time, this.track, [this.interval]);

  /// 通知触发时刻。 / Time the notice fires.
  final Duration time;

  /// 所属时间线。 / Owning timeline.
  final SmilTimeline track;

  /// 结束通知携带的原区间；开始通知为 null。
  /// Original interval for end notices; null for start notices.
  final SmilInterval? interval;
}

// 正向同步图使用最小堆推进，仅处理新通知；每块预取 64 秒。
// A chronological heap expands forward graphs without rescanning old intervals.
/// 前向同步图求解器：以最小堆按时间推进，惰性展开区间。
/// Forward syncbase-graph resolver: a time-ordered heap that expands intervals lazily.
class _ForwardBeginResolver {
  /// 为 [tracks] 构建求解器：登记依赖边、计算入度，并检测依赖环（[hasCycle]）。
  /// Builds the resolver for [tracks]: registers dependency edges and detects cycles.
  _ForwardBeginResolver(this.tracks, this.byId, this.budget) {
    final predictEnds = tracks.any(
      (a) => (a.beginSpec.entries ?? [a.beginSpec]).any(
        (s) => s.syncbaseId != null && s.offset < Duration.zero,
      ),
    );
    final indegree = <SmilTimeline, int>{for (final a in tracks) a: 0};
    final successors = <SmilTimeline, List<SmilTimeline>>{};
    for (final a in tracks) {
      a._listResolver = this;
      _seen[a] = {};
      for (final spec in a.beginSpec.entries ?? [a.beginSpec]) {
        final target = byId[spec.syncbaseId];
        if (target is SmilTimeline) {
          final arc = predictEnds && spec.onSyncbaseEnd
              ? SmilBeginSpec(
                  offset:
                      smilActiveDuration(target.duration, target.repeatCount) +
                      spec.offset,
                  syncbaseId: spec.syncbaseId,
                )
              : spec;
          _arcs.putIfAbsent(target, () => []).add((a, arc));
          successors.putIfAbsent(target, () => []).add(a);
          indegree[a] = indegree[a]! + 1;
        } else if (spec.syncbaseId == null) {
          _enqueue(a, spec.offset);
        }
      }
    }
    final roots = [
      for (final a in tracks)
        if (indegree[a] == 0) a,
    ];
    var removed = 0;
    while (roots.isNotEmpty) {
      final a = roots.removeLast();
      removed++;
      for (final b in successors[a] ?? <SmilTimeline>[]) {
        indegree[b] = indegree[b]! - 1;
        if (indegree[b] == 0) roots.add(b);
      }
    }
    hasCycle = removed != tracks.length;
  }

  /// 本分量内参与求解的全部时间线。 / Timelines in this component.
  final List<SmilTimeline> tracks;

  /// 全文档 id 到时间线的索引，用于解析同步基准。 / Document id index for syncbase lookup.
  final Map<String, SmilTimed> byId;

  /// 文档级共享的工作预算。 / Document-wide shared work budget.
  final _SmilWorkBudget budget;

  /// 按时间排序的待处理通知（最小堆）。 / Pending notices, ordered as a min-heap by time.
  final _queue = <_SmilNotice>[];

  /// 已被 restart 截短、其原定结束通知需忽略的区间。
  /// Intervals cut short by restart; their scheduled end notices must be ignored.
  final _cancelled = <SmilInterval>{};

  /// 每条时间线已入队的开始时刻（微秒），用于去重。
  /// Start times (microseconds) already queued per timeline, for de-duplication.
  final _seen = <SmilTimeline, Set<int>>{};

  /// 每个基准时间线对应的依赖方及其 begin 规格。
  /// Dependents of each syncbase timeline, paired with their begin specs.
  final _arcs = <SmilTimeline, List<(SmilTimeline, SmilBeginSpec)>>{};

  /// 依赖图是否含环（拓扑排序无法消去全部节点）；含环时只能按窗口推进。
  /// Whether the dependency graph has a cycle; if so, expansion proceeds by window.
  late final bool hasCycle;

  /// 预算耗尽后是否已停止。 / Whether expansion has stopped after exhausting the budget.
  bool _stopped = false;

  /// 已展开到的文档时刻上界，用于让重复的 [extend] 调用幂等。
  /// Document-time horizon already expanded through; makes repeated [extend] calls idempotent.
  Duration _through = const Duration(seconds: -1);

  /// 判断分量能否交给前向求解器：负偏移重启须能预告结束，否则需有界求解器。
  /// Whether this component can use the forward resolver; otherwise the bounded one is needed.
  static bool supports(List<SmilTimeline> tracks, Map<String, SmilTimed> byId) {
    for (final a in tracks) {
      if (a.beginSpec.endSpecs?.any((s) => s.syncbaseId != null) == true) {
        return false;
      }
      for (final spec in a.beginSpec.entries ?? [a.beginSpec]) {
        // 多种子负时间重启可能撤回已派生的未来 begin；交给可回撤的求解器。
        // Pre-zero restarts require retracting their dependent begin instances.
        if (spec.syncbaseId == null &&
            spec.offset < Duration.zero &&
            !_canPredictEnds(tracks, byId)) {
          return false;
        }
        if (byId[spec.syncbaseId] != null && spec.offset < Duration.zero) {
          if (!spec.onSyncbaseEnd || !_canPredictEnds(tracks, byId)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  // 单种子、每轨最多一条入边，且环周期不短于任一活动期：不会重叠重启，
  // 因而 end 可在 begin 时安全预告，支持常见的负 end 偏移图标。
  // Predict ends only when a single-seed graph provably cannot restart early.
  /// 判断能否安全预告 end（单种子、无重叠重启），见上方说明。
  /// Whether ends can be predicted safely (single seed, no overlapping restarts).
  static bool _canPredictEnds(
    List<SmilTimeline> tracks,
    Map<String, SmilTimed> byId,
  ) {
    var seeds = 0;
    var longest = Duration.zero;
    final parents = <SmilTimeline, (SmilTimeline, Duration)>{};
    for (final a in tracks) {
      if (a.repeatCount.indefinite ||
          a.duration <= Duration.zero ||
          a.beginSpec.minimum != null ||
          a.beginSpec.maximum != null ||
          a.beginSpec.endSpecs != null) {
        return false;
      }
      final active = smilActiveDuration(a.duration, a.repeatCount);
      if (active > longest) longest = active;
      for (final spec in a.beginSpec.entries ?? [a.beginSpec]) {
        final target = byId[spec.syncbaseId];
        if (target is SmilTimeline) {
          if (parents.containsKey(a)) return false;
          final delay =
              spec.offset +
              (spec.onSyncbaseEnd
                  ? smilActiveDuration(target.duration, target.repeatCount)
                  : Duration.zero);
          if (delay < Duration.zero) return false;
          parents[a] = (target, delay);
        } else if (spec.syncbaseId == null && spec.offset != kSmilNeverBegins) {
          if (++seeds > 1) return false;
        }
      }
    }
    final done = <SmilTimeline>{};
    for (final a in tracks) {
      final path = <SmilTimeline, Duration>{};
      var current = a;
      var distance = Duration.zero;
      while (!done.contains(current)) {
        final before = path[current];
        if (before != null) {
          if (distance - before < longest) return false;
          break;
        }
        path[current] = distance;
        final parent = parents[current];
        if (parent == null) break;
        distance += parent.$2;
        current = parent.$1;
      }
      done.addAll(path.keys);
    }
    return true;
  }

  /// 预算耗尽或队列超限时停止求解：清空队列，并把分量内所有时间线标记为已截断。
  /// Stops resolving on budget exhaustion or queue overflow; marks all tracks truncated.
  void _truncate() {
    _stopped = true;
    _queue.clear();
    for (final a in tracks) {
      a.instancesTruncated = true;
    }
  }

  /// 以最小堆方式插入通知（按时间升序）。 / Inserts [notice] into the min-heap by time.
  void _push(_SmilNotice notice) {
    _queue.add(notice);
    var i = _queue.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_queue[parent].time <= notice.time) break;
      _queue[i] = _queue[parent];
      i = parent;
    }
    _queue[i] = notice;
  }

  /// 弹出时间最早的通知（堆顶）。 / Removes and returns the earliest notice (heap top).
  _SmilNotice _pop() {
    final first = _queue.first;
    final last = _queue.removeLast();
    if (_queue.isEmpty) return first;
    var i = 0;
    while (i * 2 + 1 < _queue.length) {
      var child = i * 2 + 1;
      if (child + 1 < _queue.length &&
          _queue[child + 1].time < _queue[child].time) {
        child++;
      }
      if (last.time <= _queue[child].time) break;
      _queue[i] = _queue[child];
      i = child;
    }
    _queue[i] = last;
    return first;
  }

  /// 把 [a] 在 [time] 的开始通知入队；超出时长上限、永不开始或重复的会被丢弃，超预算则截断。
  /// Queues a start of [a] at [time]; drops out-of-range, never-begin, or duplicate starts.
  void _enqueue(SmilTimeline a, Duration time) {
    if (_stopped ||
        time == kSmilNeverBegins ||
        time.inMicroseconds.abs() > _maxSmilMicros) {
      return;
    }
    if (!budget.spend() || _queue.length >= _maxSmilQueuedNotices) {
      _truncate();
      return;
    }
    if (_seen[a]!.add(time.inMicroseconds)) _push(_SmilNotice(time, a));
  }

  /// 在 [time] 通知 [a] 的依赖方：[end] 为 true 时只触发基于 end 的依赖，否则只触发基于 begin 的依赖。
  /// Notifies dependents of [a] at [time]: [end] selects end-based or begin-based arcs.
  void _notify(SmilTimeline a, Duration time, {required bool end}) {
    for (final (dependent, spec)
        in _arcs[a] ?? <(SmilTimeline, SmilBeginSpec)>[]) {
      if (_stopped) break;
      if (!budget.spend()) {
        _truncate();
        break;
      }
      if (spec.onSyncbaseEnd == end) {
        _enqueue(dependent, time + spec.offset);
      }
    }
  }

  // 摊销每个实例只出入堆一次；历史查询仅做二分，不重放事件。
  // Each notice is processed once; historical samples only binary-search.
  /// 惰性推进到文档时刻 [time]：逐条出堆并展开区间，上界为 [time] 加预取窗口。
  /// Lazily expands intervals up to [time] plus the prefetch window.
  void extend(Duration time) {
    if (_stopped || time <= _through) return;
    var horizon = time + _kSmilPrefetchWindow;
    if (_through < Duration.zero &&
        _queue.isNotEmpty &&
        _queue.first.time > horizon) {
      horizon = _queue.first.time + _kSmilPrefetchWindow;
    }
    while (_queue.isNotEmpty && (!hasCycle || _queue.first.time <= horizon)) {
      if (!budget.spend()) {
        _truncate();
        break;
      }
      final notice = _pop();
      final a = notice.track;
      final intervals = a.intervals!;
      final previous = intervals.isEmpty ? null : intervals.last;
      if (notice.interval != null) {
        if (!_cancelled.remove(notice.interval)) {
          _notify(a, notice.time, end: true);
        }
        continue;
      }
      final start = notice.time;
      var active = a.repeatCount.indefinite || a.duration == Duration.zero
          ? kSmilNeverBegins
          : smilActiveDuration(a.duration, a.repeatCount);
      final minimum = a.beginSpec.minimum;
      final maximum = a.beginSpec.maximum;
      if (minimum != null && active < minimum) active = minimum;
      if (maximum != null && active > maximum) active = maximum;
      var end = active == kSmilNeverBegins ? kSmilNeverBegins : start + active;
      final ends = a.beginSpec.endSpecs;
      if (ends != null && ends.isNotEmpty) {
        Duration? explicit;
        for (final spec in ends) {
          if (!budget.spend()) {
            _truncate();
            break;
          }
          if (spec.offset >= start &&
              (explicit == null || spec.offset < explicit)) {
            explicit = spec.offset;
          }
        }
        if (explicit == null) continue;
        var length = explicit - start;
        if (minimum != null && length < minimum) length = minimum;
        if (maximum != null && length > maximum) length = maximum;
        if (start + length < end) end = start + length;
      }
      if (end <= Duration.zero) continue;
      if (previous != null) {
        if (a.beginSpec.restart == _kRestartNever) continue;
        if (start < previous.end) {
          if (a.beginSpec.restart == _kRestartWhenNotActive) continue;
          _cancelled.add(previous);
          intervals[intervals.length - 1] = SmilInterval(previous.begin, start);
          _notify(a, start, end: true);
        }
      }
      if (_stopped) break;
      if (intervals.length >= _maxSmilIntervals ||
          budget.intervals >= _maxSmilBudgetIntervals) {
        _truncate();
        break;
      }
      final interval = SmilInterval(start, end);
      intervals.add(interval);
      budget.intervals++;
      a.begin = intervals.first.begin;
      _notify(a, start, end: false);
      if (end != kSmilNeverBegins && !_stopped) {
        _push(_SmilNotice(end, a, interval));
      }
    }
    _through = horizon;
    for (final a in tracks) {
      a.begin = a.intervals!.isEmpty
          ? kSmilNeverBegins
          : a.intervals!.first.begin;
    }
  }
}

/// 有界求解器：反复扫描分量直至收敛；受文档预算与扫描上限约束，超限即截断。用于负偏移与不收敛依赖。
/// Bounded resolver: sweeps the component until it converges or hits the budget and sweep caps.
void _resolveBoundedBeginComponent(
  List<SmilTimeline> timelines,
  Map<String, SmilTimed> byId,
  _SmilWorkBudget budget,
) {
  List<Duration> instances(List<SmilBeginSpec> specs) {
    final values = <int>{};
    for (final spec in specs) {
      if (!budget.spend()) break;
      final target = byId[spec.syncbaseId];
      if (spec.syncbaseId == null) {
        if (spec.offset != kSmilNeverBegins) {
          values.add(spec.offset.inMicroseconds);
        }
      } else if (target is SmilTimeline) {
        for (final interval in target.intervals ?? const <SmilInterval>[]) {
          if (!budget.spend()) break;
          final base = spec.onSyncbaseEnd ? interval.end : interval.begin;
          if (base == kSmilNeverBegins || spec.offset == kSmilNeverBegins) {
            continue;
          }
          // Do not saturate: a time beyond the horizon must never create a
          // fabricated begin at exactly the horizon (especially in cycles).
          final value = base.inMicroseconds + spec.offset.inMicroseconds;
          if (value.abs() <= _maxSmilMicros) values.add(value);
        }
      }
    }
    // 为排序比较预留保守的 n log n 预算；不足时由外层保留上次完整结果。
    // Reserve sorting work before allocating another candidate list.
    if (!budget.spend(values.length * (values.length.bitLength + 1))) return [];
    return (values.toList()..sort())
        .map((v) => Duration(microseconds: v))
        .toList();
  }

  // Rebuild from current accepted intervals, not an append-only candidate set:
  // restart can shorten an end and must retract dependent stale end instances.
  // 文档级比较/实例预算约束负偏移及不收敛依赖；不提交预算耗尽时的半成品。
  // Global work limits bound negative/oscillating dependencies.
  final maxSweeps = 20000;
  sweeps:
  for (var sweep = 0; sweep < maxSweeps; sweep++) {
    if (budget.exhausted) break;
    var anyChange = false;
    for (final a in timelines) {
      final starts = instances(a.beginSpec.entries ?? [a.beginSpec]);
      final ends = instances(a.beginSpec.endSpecs ?? const []);
      final next = <SmilInterval>[];
      for (final start in starts) {
        if (!budget.spend()) break;
        if (start.inMicroseconds.abs() > _maxSmilMicros) continue;
        // Only <set> reaches this parser with a zero duration; its legacy
        // no-dur semantics hold until an explicit end or another instance.
        var active = a.repeatCount.indefinite || a.duration == Duration.zero
            ? kSmilNeverBegins
            : smilActiveDuration(a.duration, a.repeatCount);
        final minimum = a.beginSpec.minimum;
        final maximum = a.beginSpec.maximum;
        if (minimum != null && active < minimum) active = minimum;
        if (maximum != null && active > maximum) active = maximum;
        var end = active == kSmilNeverBegins
            ? kSmilNeverBegins
            : start + active;
        if (ends.isNotEmpty && ends.last < start) continue;
        for (final candidate in ends) {
          if (!budget.spend()) break;
          if (candidate >= start) {
            // Explicit end is constrained by min/max just like repeat duration.
            var length = candidate - start;
            if (minimum != null && length < minimum) length = minimum;
            if (maximum != null && length > maximum) length = maximum;
            if (start + length < end) end = start + length;
            break;
          }
        }
        if (end <= Duration.zero) continue;
        if (next.isNotEmpty) {
          if (a.beginSpec.restart == _kRestartNever) break;
          final previous = next.last;
          if (start < previous.end) {
            if (a.beginSpec.restart == _kRestartWhenNotActive) continue;
            next[next.length - 1] = SmilInterval(previous.begin, start);
          }
        }
        if (next.length == _maxSmilIntervals) {
          a.instancesTruncated = true;
          break;
        }
        next.add(SmilInterval(start, end));
      }
      next.removeWhere((interval) => interval.end <= Duration.zero);
      final old = a.intervals!;
      if (!budget.spend(old.length + next.length) ||
          budget.intervals + next.length - old.length >
              _maxSmilBudgetIntervals) {
        break sweeps;
      }
      budget.intervals += next.length - old.length;
      if (old.length != next.length ||
          List.generate(
            next.length,
            (i) => old[i].begin != next[i].begin || old[i].end != next[i].end,
          ).any((v) => v)) {
        a.intervals = next;
        anyChange = true;
      }
      a.begin = next.isEmpty ? kSmilNeverBegins : next.first.begin;
    }
    if (!anyChange &&
        !budget.exhausted &&
        !timelines.any((a) => a.instancesTruncated)) {
      return;
    }
    if (timelines.any((a) => a.instancesTruncated)) break;
  }
  for (final a in timelines) {
    a.instancesTruncated = true;
  }
}

/// Parses a SMIL `begin` attribute into a [SmilBeginSpec].
///
/// Supported: a plain clock value (`"0.6s"`, `"600ms"`, `"2"`), and syncbase
/// references `"id.begin"` / `"id.end"` with an optional `+`/`-` clock offset
/// (`"ring.end+0.2s"`).
///
/// **Not supported**: event values. Single event values (`"click"`, `"id.click"`), `wallclock()` and
/// `accessKey()` retain the legacy zero fallback. In a semicolon list they
/// never fire; offsets and syncbases form a bounded instance-time set.
///
/// 把 SMIL `begin` 属性解析为 [SmilBeginSpec]；`indefinite` 表示永不开始。
///
/// 支持：纯时钟值（`"0.6s"`、`"600ms"`、`"2"`），以及带可选 `+`/`-` 时钟偏移的
/// 同步基准引用 `"id.begin"`/`"id.end"`（如 `"ring.end+0.2s"`）。
///
/// **不支持**（明确记录，而非静默错解）：事件值（`"click"`、`"id.click"`）、
/// `wallclock()`、`accessKey()` 的单值保留旧零偏移回退；在分号列表中这些项
/// 永不触发。列表中的偏移和同步基准由有界区间求解器处理。
///
/// Example:
/// ```dart
/// parseSmilBeginSpec('ring.end+0.2s'); // syncbaseId: 'ring', onEnd, +200ms
/// ```
SmilBeginSpec parseSmilBeginSpec(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return const SmilBeginSpec.offset(Duration.zero);
  if (value == 'indefinite') {
    return const SmilBeginSpec.offset(kSmilNeverBegins);
  }
  if (value.contains(';')) {
    return SmilBeginSpec(
      offset: kSmilNeverBegins,
      entries: _parseInstanceSpecs(value),
    );
  }

  final match = RegExp(r'^([^\s;]+?)\.(begin|end)\s*(?:([+-])\s*(.+))?$')
      .firstMatch(value);
  if (match == null) {
    return SmilBeginSpec.offset(parseSmilDuration(value, forBegin: true));
  }

  final rawOffset = match.group(4);
  final offset = parseSmilDuration(
    rawOffset == null ? null : '${match.group(3) ?? ''}$rawOffset',
    forBegin: true,
  );
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
class SmilAnimation extends SmilTimeline {
  /// Creates a fully-parsed animation timeline.
  ///
  /// 创建一个已完整解析的动画时间线。
  SmilAnimation({
    required this.attributeName,
    required this.values,
    required super.duration,
    required super.begin,
    required super.fillFreeze,
    super.repeatCount = SmilRepeatCount.once,
    super.direction = SmilDirection.normal,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    super.elementId,
    super.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  }) : assert(
         values.length >= 2,
         'an <animate> needs at least two keyframe values',
       );

  /// The presentation attribute being animated, e.g. `stroke-dashoffset`.
  ///
  /// 被动画驱动的表现属性，例如 `stroke-dashoffset`。
  final String attributeName;

  /// Keyframe values, distributed across [duration] per [calcMode]/[keyTimes].
  ///
  /// 关键帧数值，按 [calcMode]/[keyTimes] 分布在 [duration] 内。
  final List<double> values;

  /// Keyframe interpolation mode (SMIL `calcMode`). / 关键帧插值模式（SMIL `calcMode`）。
  final SmilCalcMode calcMode;

  /// Custom per-keyframe timing fractions in `[0, 1]`, one per [values] entry
  /// (SMIL `keyTimes`); null means keyframes are spaced evenly.
  ///
  /// 每个关键帧的自定义时间比例，取值 `[0, 1]`，与 [values] 一一对应（SMIL
  /// `keyTimes`）；为 null 表示关键帧均匀分布。
  final List<double>? keyTimes;

  /// 每段的缓动，共 `values.length - 1` 段；仅在 [calcMode] 为
  /// [SmilCalcMode.spline] 时生效。支持贝塞尔与阶跃，缺失的段线性回退。
  final List<SmilSegmentEasing>? keySplines;

  /// Cached [_pacedKeyTimes] result for [SmilCalcMode.paced], computed once on
  /// first [sample] rather than every frame — it is a pure function of
  /// [values], which never changes after parsing.
  ///
  /// [SmilCalcMode.paced] 的 [_pacedKeyTimes] 缓存结果，只在首次 [sample] 时
  /// 计算一次，而非每帧都算——它是 [values] 的纯函数，解析完成后再不会变。
  List<double>? _cachedPacedKeyTimes;

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
    final timing = _timingAt(t);
    if (timing == null) return null;

    if (calcMode == SmilCalcMode.discrete) {
      return values[_discreteIndex(timing.progress, values.length, keyTimes)];
    }
    final segments = values.length - 1;
    final effectiveKeyTimes = calcMode == SmilCalcMode.paced
        ? (_cachedPacedKeyTimes ??= _pacedKeyTimes<double>(
            values,
            (a, b) => (b - a).abs(),
          ))
        : keyTimes;
    final segment = _locateSegment(
      timing.progress,
      segments,
      effectiveKeyTimes,
    );

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
class SmilTransformAnimation extends SmilTimeline {
  /// Creates a fully-parsed transform animation timeline.
  ///
  /// 创建一个已完整解析的变换动画时间线。
  SmilTransformAnimation({
    required this.type,
    required this.values,
    required super.duration,
    required super.begin,
    required super.fillFreeze,
    super.repeatCount = SmilRepeatCount.once,
    super.direction = SmilDirection.normal,
    this.replacesStaticTransform = false,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    super.elementId,
    super.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  }) : assert(
         values.length >= 2,
         'an <animateTransform> needs at least two keyframe values',
       );

  /// Which transform this drives. / 驱动的变换种类。
  final SmilTransformType type;

  /// Keyframe values, each a normalized 3-component list (see class doc).
  ///
  /// 关键帧数值，每个是归一化后的 3 分量列表（见类注释）。
  final List<List<double>> values;

  /// Keyframe interpolation mode (SMIL `calcMode`). / 关键帧插值模式（SMIL `calcMode`）。
  final SmilCalcMode calcMode;

  /// Custom per-keyframe timing fractions, one per [values] entry.
  ///
  /// 每个关键帧的自定义时间比例，与 [values] 一一对应。
  final List<double>? keyTimes;

  /// 每段的缓动，支持贝塞尔与阶跃；见 [SmilAnimation.keySplines]。
  final List<SmilSegmentEasing>? keySplines;

  /// 生效期间是否替换元素的静态 transform，供绘制层判定。
  final bool replacesStaticTransform;

  /// 此刻是否产出变换值；只解析时序，不分配采样列表或执行插值。
  ///
  /// 例如：`animation.isActiveAt(const Duration(seconds: 1))`。
  bool isActiveAt(Duration t) => _timingAt(t) != null;

  /// Cached [_pacedKeyTimes] result; see [SmilAnimation._cachedPacedKeyTimes].
  /// 缓存的 [_pacedKeyTimes] 结果；见 [SmilAnimation._cachedPacedKeyTimes]。
  List<double>? _cachedPacedKeyTimes;

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
    final timing = _timingAt(t);
    if (timing == null) return null;

    if (calcMode == SmilCalcMode.discrete) {
      return values[_discreteIndex(timing.progress, values.length, keyTimes)];
    }
    final segments = values.length - 1;
    final effectiveKeyTimes = calcMode == SmilCalcMode.paced
        ? (_cachedPacedKeyTimes ??= _pacedKeyTimes<List<double>>(
            values,
            _vectorDistance,
          ))
        : keyTimes;
    final segment = _locateSegment(
      timing.progress,
      segments,
      effectiveKeyTimes,
    );

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
class SmilMotionAnimation extends SmilTimeline {
  /// Creates a motion timeline from a precomputed sample table.
  ///
  /// 用预计算好的采样表创建一条运动时间线。
  SmilMotionAnimation({
    required this.samples,
    required super.duration,
    required super.begin,
    required super.fillFreeze,
    super.repeatCount = SmilRepeatCount.once,
    super.elementId,
    super.beginSpec = const SmilBeginSpec.offset(Duration.zero),
    this.keyPoints,
    this.keyTimes,
    this.keySplines,
    this.calcMode = SmilCalcMode.linear,
    super.direction = SmilDirection.normal,
    this.interpolateAngle = false,
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
  final List<SmilSegmentEasing>? keySplines;

  /// Interpolation mode for [keyPoints]; only consulted when [keyPoints] is
  /// set.
  ///
  /// [keyPoints] 的插值模式；仅在设置了 [keyPoints] 时生效。
  final SmilCalcMode calcMode;

  /// 是否在相邻采样点之间线性插值角度（含 ±180° 绕回）；默认取段起点角度。
  final bool interpolateAngle;

  /// Cached [_pacedKeyTimes] result; see [SmilAnimation._cachedPacedKeyTimes].
  /// 缓存的 [_pacedKeyTimes] 结果；见 [SmilAnimation._cachedPacedKeyTimes]。
  List<double>? _cachedPacedKeyTimes;

  /// Samples the element's position (and `rotate="auto"` angle) at global
  /// timeline time [t], or null when the animation isn't active — same
  /// convention as [SmilAnimation.sample].
  ///
  /// 在全局时间线时刻 [t] 采样元素位置（以及 `rotate="auto"` 的角度）；动画未
  /// 激活时返回 null——约定与 [SmilAnimation.sample] 相同。
  SmilMotionSample? sample(Duration t) {
    final timing = _timingAt(t);
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
    if (points != null && calcMode == SmilCalcMode.discrete) {
      arcFraction =
          points[_discreteIndex(timing.progress, points.length, keyTimes)];
    } else if (points != null) {
      final segments = points.length - 1;
      final effectiveKeyTimes = calcMode == SmilCalcMode.paced
          ? (_cachedPacedKeyTimes ??= _pacedKeyTimes<double>(
              points,
              (a, b) => (b - a).abs(),
            ))
          : keyTimes;
      final segment = _locateSegment(
        timing.progress,
        segments,
        effectiveKeyTimes,
      );
      final a = points[segment.index];
      final b = points[segment.index + 1];
      final segT = _easedSegmentT(calcMode, keySplines, segment);
      arcFraction = a + (b - a) * segT;
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
      // By default the table is dense, so the segment's own angle is used
      // rather than interpolated; [interpolateAngle] opts into wrap-aware
      // interpolation for sparse tables.
      //
      // 默认采样表足够密，直接取该段自身的角度而不插值；稀疏表可通过
      // [interpolateAngle] 开启带绕回处理的插值。
      interpolateAngle
          ? a.angleDegrees + _wrap180(b.angleDegrees - a.angleDegrees) * localT
          : a.angleDegrees,
    );
  }
}

/// 颜色值表示 `none` 的哨兵，位于 `0xAARRGGBB` 值域之外。
///
/// 例如：`SmilColorAnimation(values: [0xFFFF0000, kSmilColorNone], ...)`。
const int kSmilColorNone = -1;

/// 颜色与 `none` 之间离散翻转的缓动后进度阈值。
const double _colorNoneFlipAt = 0.5;

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
class SmilColorAnimation extends SmilTimeline {
  /// Creates a fully-parsed colour timeline. / 创建一个已完整解析的颜色时间线。
  SmilColorAnimation({
    required this.values,
    required super.duration,
    required super.begin,
    required super.fillFreeze,
    super.repeatCount = SmilRepeatCount.once,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    super.elementId,
    super.beginSpec = const SmilBeginSpec.offset(Duration.zero),
    this.attributeName = 'stop-color',
    super.direction = SmilDirection.normal,
  }) : assert(
         values.length >= 2,
         'a colour <animate> needs at least two keyframe values',
       );

  /// Keyframe colours packed as `0xAARRGGBB`; may hold [kSmilColorNone].
  ///
  /// 关键帧颜色，打包为 `0xAARRGGBB`；可含 [kSmilColorNone]。
  final List<int> values;

  /// 被驱动的颜色属性名，例如 `stop-color` 或 `fill`。
  final String attributeName;

  /// Keyframe interpolation mode. / 关键帧插值模式。
  final SmilCalcMode calcMode;

  /// Custom per-keyframe timing fractions; see [SmilAnimation.keyTimes].
  ///
  /// 每个关键帧的自定义时间比例；见 [SmilAnimation.keyTimes]。
  final List<double>? keyTimes;

  /// Per-segment easing curves; see [SmilAnimation.keySplines].
  ///
  /// 每段的缓动曲线；见 [SmilAnimation.keySplines]。
  final List<SmilSegmentEasing>? keySplines;

  /// Cached [_pacedKeyTimes] result; see [SmilAnimation._cachedPacedKeyTimes].
  /// 缓存的 [_pacedKeyTimes] 结果；见 [SmilAnimation._cachedPacedKeyTimes]。
  List<double>? _cachedPacedKeyTimes;

  /// Samples the animated colour (as `0xAARRGGBB`) at global timeline time
  /// [t]; same null convention as [SmilAnimation.sample].
  ///
  /// 在全局时间线时刻 [t] 采样动画颜色（`0xAARRGGBB`）；空值约定同
  /// [SmilAnimation.sample]。
  int? sample(Duration t) {
    final timing = _timingAt(t);
    if (timing == null) return null;

    if (calcMode == SmilCalcMode.discrete) {
      return values[_discreteIndex(timing.progress, values.length, keyTimes)];
    }
    final segments = values.length - 1;
    final effectiveKeyTimes = calcMode == SmilCalcMode.paced
        ? (_cachedPacedKeyTimes ??= _pacedKeyTimes<int>(values, _argbDistance))
        : keyTimes;
    final segment = _locateSegment(
      timing.progress,
      segments,
      effectiveKeyTimes,
    );

    final a = values[segment.index];
    final b = values[segment.index + 1];
    final segT = _easedSegmentT(calcMode, keySplines, segment);
    if (a == kSmilColorNone || b == kSmilColorNone) {
      if (a == b) return a;
      // CSS 中颜色与 none 不可插值，缓动后进度 >= 0.5 处离散翻转。
      return segT >= _colorNoneFlipAt ? b : a;
    }
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

/// `stroke-dasharray` 这类数值列表属性的时间线：每个关键帧一个等长列表，
/// 逐项插值。
///
/// 调用方保证所有关键帧长度相同（短列表需事先按公共长度补齐）。时序、
/// `keyTimes`、`keySplines`、`direction` 与 [SmilAnimation] 语义一致；
/// `calcMode` 支持 `linear`/`spline`/`discrete`，`paced` 对列表没有定义，
/// 按 `linear` 处理。
///
/// 例如：
/// ```dart
/// final a = SmilListAnimation(
///   attributeName: 'stroke-dasharray',
///   values: [[10, 20], [20, 40]],
///   duration: const Duration(seconds: 1),
///   begin: Duration.zero,
///   fillFreeze: true,
/// );
/// a.sample(const Duration(milliseconds: 500)); // [15, 30]
/// ```
class SmilListAnimation extends SmilTimeline {
  /// 创建列表时间线；[values] 至少两帧且各帧等长。
  SmilListAnimation({
    required this.attributeName,
    required this.values,
    required super.duration,
    required super.begin,
    required super.fillFreeze,
    super.repeatCount = SmilRepeatCount.once,
    super.direction = SmilDirection.normal,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    super.elementId,
    super.beginSpec = const SmilBeginSpec.offset(Duration.zero),
  }) : assert(
         values.length >= 2,
         'a list <animate> needs at least two keyframe values',
       ),
       assert(
         values.every((v) => v.length == values.first.length),
         'all keyframe lists must have the same length',
       );

  /// 被驱动的属性名，例如 `stroke-dasharray`。
  final String attributeName;

  /// 各关键帧的列表值，长度相同。
  final List<List<double>> values;

  /// 插值模式；`paced` 按 `linear` 处理。
  final SmilCalcMode calcMode;

  /// 每个关键帧的时间比例；见 [SmilAnimation.keyTimes]。
  final List<double>? keyTimes;

  /// 每段的缓动，支持贝塞尔与阶跃；见 [SmilAnimation.keySplines]。
  final List<SmilSegmentEasing>? keySplines;

  /// 每个关键帧列表的长度。
  int get width => values.first.length;

  /// 在全局时刻 [t] 采样；未开始或已结束且不定格时返回 null。
  ///
  /// 返回的列表每次都是新实例，调用方可自由持有。
  List<double>? sample(Duration t) {
    final timing = _timingAt(t);
    if (timing == null) return null;

    if (calcMode == SmilCalcMode.discrete) {
      return List<double>.of(
        values[_discreteIndex(timing.progress, values.length, keyTimes)],
      );
    }
    final segment = _locateSegment(
      timing.progress,
      values.length - 1,
      keyTimes,
    );

    final a = values[segment.index];
    final b = values[segment.index + 1];
    final segT = _easedSegmentT(calcMode, keySplines, segment);
    return [for (var i = 0; i < a.length; i++) a[i] + (b[i] - a[i]) * segT];
  }
}

/// 路径变形的指令码：绝对 `M`。
const int kMorphMove = 0;

/// 路径变形的指令码：绝对 `L`（`H`/`V` 也规范化为它）。
const int kMorphLine = 1;

/// 路径变形的指令码：绝对 `C`（`S` 也规范化为它）。
const int kMorphCubic = 2;

/// 路径变形的指令码：绝对 `Q`（`T` 也规范化为它）。
const int kMorphQuad = 3;

/// 路径变形的指令码：绝对 `A`，参数为 `rx ry rot large sweep x y`。
const int kMorphArc = 4;

/// 路径变形的指令码：`Z`。
const int kMorphClose = 5;

/// 各指令码对应的参数个数，下标即指令码。
const List<int> kMorphArity = <int>[2, 2, 6, 4, 7, 0];

/// 路径变形的数值数据：所有关键帧规范化为绝对坐标后，指令序列与参数个数
/// 完全一致，才能逐参数插值。解析期一次构建，逐帧只读。
///
/// 由 `svg_path_morph.dart` 的 `buildPathMorphData` 构建。
class PathMorphData {
  /// 创建变形数据。
  const PathMorphData({required this.ops, required this.frames});

  /// 各关键帧共享的指令码序列（`kMorph*`）。
  final List<int> ops;

  /// 每个关键帧的扁平参数表，按 [ops] 顺序排布，长度彼此相等。逐帧热路径只读，
  /// 用 [Float64List] 避免装箱；构建后不得修改。
  final List<Float64List> frames;
}

/// 单个 `<animate attributeName="d">` 或作用于 `d` 的 `<set>` 的时间线。
///
/// 路径字符串在解析期保留为 [frames]；各帧规范化后形状兼容时另附数值数据
/// [morph]，此时线性/spline 可插值，否则退化为离散（按 SMIL 规范，不可插值的
/// 值在 `values` 个区间内等分切换）。时序复用 [_resolveTiming] 等既有设施。
///
/// [sample] 返回单个 double「位置」：整数部分是起始关键帧下标，小数部分是段内
/// 进度（已按 `keySplines` 缓动并钳制到 `[0, 1]`）。离散时恒为整数。这样既能
/// 用一个数字做变化检测，也不必每帧分配采样对象。
///
/// `calcMode="paced"` 对路径没有定义，按 `linear` 处理。
class SmilPathAnimation extends SmilTimeline {
  /// 创建路径时间线；[frames] 至少一项（`<set>` 只有一个）。
  SmilPathAnimation({
    required this.frames,
    required super.duration,
    required super.begin,
    required super.fillFreeze,
    this.morph,
    super.repeatCount = SmilRepeatCount.once,
    this.calcMode = SmilCalcMode.linear,
    this.keyTimes,
    this.keySplines,
    super.elementId,
    super.beginSpec = const SmilBeginSpec.offset(Duration.zero),
    super.direction = SmilDirection.normal,
  }) : assert(frames.isNotEmpty, 'a path animation needs at least one frame'),
       assert(
         morph == null || morph.frames.length == frames.length,
         'morph frames must match path frames',
       );

  /// 各关键帧的原始 `d` 字符串；离散显示时直接用它（同一实例，几何缓存可命中）。
  final List<String> frames;

  /// 形状兼容时的数值数据；为 null 表示只能离散切换。
  final PathMorphData? morph;

  /// 插值模式；`paced` 按 `linear` 处理。
  final SmilCalcMode calcMode;

  /// 每个关键帧的时间比例；见 [SmilAnimation.keyTimes]。
  final List<double>? keyTimes;

  /// 每段缓动曲线；见 [SmilAnimation.keySplines]。
  final List<SmilSegmentEasing>? keySplines;

  /// 当前是否会插值（有数值数据且不是 discrete）。
  bool get interpolates => morph != null && calcMode != SmilCalcMode.discrete;

  /// 在全局时刻 [t] 采样「位置」；未开始或已结束且不定格时返回 null，
  /// 此时调用方应显示元素自身静态的 `d`。
  double? sample(Duration t) {
    final timing = _timingAt(t);
    if (timing == null) return null;

    final count = frames.length;
    if (count == 1) return 0;
    if (!interpolates) {
      return _discreteIndex(timing.progress, count, keyTimes).toDouble();
    }
    final segment = _locateSegment(timing.progress, count - 1, keyTimes);
    final eased = _easedSegmentT(calcMode, keySplines, segment);
    return segment.index + eased.clamp(0.0, 1.0);
  }
}

/// 离散模式下 [progress] 对应的关键帧下标：有合法 [keyTimes]（长度等于 [count]）
/// 时按其切换，否则把时长等分为 [count] 个区间（SMIL 规范）。
///
/// 所有离散通道（含运动 keyPoints）共用此规则；插值通道仍按 `count - 1` 段定位。
int _discreteIndex(double progress, int count, List<double>? keyTimes) {
  if (keyTimes != null && keyTimes.length == count) {
    var index = 0;
    for (var i = 1; i < count; i++) {
      if (progress >= keyTimes[i]) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }
  final index = (progress * count).floor();
  return index.clamp(0, count - 1);
}

/// 把角度差折回 `[-180, 180)`，使插值走短弧；例如 `_wrap180(358)` 得 `-2`。
double _wrap180(double d) => (d + 180) % 360 - 180;

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
@pragma('vm:prefer-inline')
_Timing? _resolveTiming({
  required Duration t,
  required Duration begin,
  required Duration duration,
  required SmilRepeatCount repeatCount,
  required bool fillFreeze,
  SmilDirection direction = SmilDirection.normal,
}) {
  if (direction == SmilDirection.normal) {
    return _resolveNormalTiming(
      t: t,
      begin: begin,
      duration: duration,
      repeatCount: repeatCount,
      fillFreeze: fillFreeze,
    );
  }
  final local = t - begin;
  if (local.isNegative) return null;
  return _resolveDirectedTiming(
    local: local,
    duration: duration,
    repeatCount: repeatCount,
    fillFreeze: fillFreeze,
    direction: direction,
  );
}

/// 正向播放沿用原始时序运算，避免方向逻辑扩大默认采样路径。
@pragma('vm:prefer-inline')
_Timing? _resolveNormalTiming({
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

  final totalMicros = smilActiveDuration(duration, repeatCount).inMicroseconds;
  if (localMicros >= totalMicros) {
    if (!fillFreeze) return null;
    final fractional = repeatCount.count % 1;
    return _Timing(fractional == 0 ? 1 : fractional);
  }
  return _Timing((localMicros % durationMicros) / durationMicros);
}

/// 非默认方向的时序求值，独立保留以缩小正向采样的热路径。
@pragma('vm:never-inline')
_Timing? _resolveDirectedTiming({
  required Duration local,
  required Duration duration,
  required SmilRepeatCount repeatCount,
  required bool fillFreeze,
  required SmilDirection direction,
}) {
  final durationMicros = duration.inMicroseconds;
  if (durationMicros == 0) return _Timing(_directed(direction, 0, 1));
  final localMicros = local.inMicroseconds;
  if (!repeatCount.indefinite &&
      localMicros >= smilActiveDuration(duration, repeatCount).inMicroseconds) {
    if (!fillFreeze) return null;
    final wholeIterations = repeatCount.count.floor();
    final fractional = repeatCount.count % 1;
    return _Timing(
      fractional == 0
          ? _directed(direction, wholeIterations - 1, 1)
          : _directed(direction, wholeIterations, fractional),
    );
  }
  return _Timing(
    _directed(
      direction,
      localMicros ~/ durationMicros,
      (localMicros % durationMicros) / durationMicros,
    ),
  );
}

/// 按零基迭代序号反转整体进度，段缓动保持原样。
double _directed(SmilDirection direction, int iteration, double progress) =>
    switch (direction) {
      SmilDirection.normal => progress,
      SmilDirection.reverse => 1 - progress,
      SmilDirection.alternate => iteration.isOdd ? 1 - progress : progress,
      SmilDirection.alternateReverse =>
        iteration.isEven ? 1 - progress : progress,
    };

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
  List<SmilSegmentEasing>? keySplines,
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

// 统一限制到约 115 天；先钳制浮点乘积再 round，时间线相加也使用同一边界。
const _maxSmilMicros = 10000000 * Duration.microsecondsPerSecond;

/// 有限重复的活动时长；超大乘积饱和到约 115 天，避免 Infinity.round()。
Duration smilActiveDuration(Duration duration, SmilRepeatCount repeatCount) =>
    Duration(
      microseconds: (duration.inMicroseconds * repeatCount.count)
          .clamp(0, _maxSmilMicros)
          .round(),
    );

/// 时间线饱和加法。先限制两个操作数，确保相加本身也不会发生整数回绕。
Duration addSmilTime(Duration a, Duration b) => Duration(
  microseconds:
      (a.inMicroseconds.clamp(-_maxSmilMicros, _maxSmilMicros) +
              b.inMicroseconds.clamp(-_maxSmilMicros, _maxSmilMicros))
          .clamp(-_maxSmilMicros, _maxSmilMicros),
);

/// Parses a SMIL `dur`/`begin` time string (e.g. `"0.5s"`, `"600ms"`, `"2"`)
/// into a [Duration]. Unitless numbers are treated as seconds, matching the
/// SMIL default. Unparsable input maps to [Duration.zero].
///
/// 解析 SMIL `dur`/`begin` 时间字符串（如 `"0.5s"`、`"600ms"`、`"2"`）为
/// [Duration]。无单位数字按秒处理（SMIL 默认单位）。无法解析时返回
/// [Duration.zero]；非有限字面值仍回退为零；有限超长时长饱和到 1e7 秒。
/// [forBegin] 用于开始偏移，正向超限返回 [kSmilNeverBegins]。
/// 支持完整/部分时钟、h/min/s/ms 与默认秒单位。
Duration parseSmilDuration(String? raw, {bool forBegin = false}) {
  if (raw == null) return Duration.zero;
  final value = raw.trim();
  if (value.isEmpty || value == 'indefinite') return Duration.zero;
  double? seconds;
  if (value.contains(':')) {
    final match = RegExp(r'^([+-])?(?:(\d+):)?(\d{2}):(\d{2}(?:\.\d+)?)$')
        .firstMatch(value);
    if (match == null) return Duration.zero;
    final hours = double.tryParse(match.group(2) ?? '0');
    final minutes = double.parse(match.group(3)!);
    final tail = double.parse(match.group(4)!);
    if (hours == null || minutes >= 60 || tail >= 60) return Duration.zero;
    seconds =
        (hours * 3600 + minutes * 60 + tail) * (match.group(1) == '-' ? -1 : 1);
  } else {
    final match = RegExp(
      r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)(h|min|ms|s)?$',
    ).firstMatch(value);
    if (match == null) return Duration.zero;
    final number = double.tryParse(match.group(1)!);
    if (number == null || !number.isFinite) return Duration.zero;
    seconds =
        number *
        switch (match.group(2)) {
          'h' => 3600.0,
          'min' => 60.0,
          'ms' => 0.001,
          _ => 1.0,
        };
  }
  if (seconds.isNaN) return Duration.zero;
  final maximum = _maxSmilMicros / Duration.microsecondsPerSecond;
  if (forBegin && seconds > maximum) return kSmilNeverBegins;
  return Duration(
    microseconds:
        (seconds.clamp(-maximum, maximum) * Duration.microsecondsPerSecond)
            .round(),
  );
}

/// Parses a SMIL `repeatCount` attribute: `"indefinite"`, a positive number,
/// or absent/unparsable (defaults to [SmilRepeatCount.once]).
///
/// 解析 SMIL `repeatCount` 属性：`"indefinite"`、正数，或缺失/无法解析（默认
/// [SmilRepeatCount.once]）；非有限数也回退为一次。
SmilRepeatCount parseSmilRepeatCount(String? raw) {
  if (raw == null) return SmilRepeatCount.once;
  final value = raw.trim();
  if (value == 'indefinite') return const SmilRepeatCount.indefinite();
  final n = double.tryParse(value);
  if (n == null || !n.isFinite || n <= 0) return SmilRepeatCount.once;
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
    if (parts.length != 4 || parts.any((v) => v == null || !v.isFinite)) {
      return null;
    }
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
  final parts = raw
      .split(';')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.isEmpty || parts.any((v) => v == null || !v.isFinite)) return null;
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
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(double.tryParse)
        .toList();
    if (parts.any((v) => v == null || !v.isFinite) || parts.length < 2) {
      return null;
    }
    return parts.cast<double>();
  }
  if (from != null && to != null) {
    final f = double.tryParse(from.trim());
    final t = double.tryParse(to.trim());
    if (f == null || t == null || !f.isFinite || !t.isFinite) return null;
    return [f, t];
  }
  return null;
}

/// 解析作用于 `d` 的 `values="path1;path2;..."`（或 `from`/`to` 简写）为路径
/// 字符串列表；空项（如末尾多余的分号）丢弃。不足两项时返回 null。
List<String>? parseSmilPathValues({String? values, String? from, String? to}) {
  if (values != null && values.trim().isNotEmpty) {
    final frames = [for (final part in values.split(';')) part.trim()]
      ..removeWhere((part) => part.isEmpty);
    return frames.length < 2 ? null : frames;
  }
  if (from != null && to != null) return [from.trim(), to.trim()];
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
  // 变换分量只接受有限数，避免采样运算传播 NaN/Infinity。
  List<double>? parseComponents(String raw) {
    final parts = raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map(double.tryParse)
        .toList();
    if (parts.isEmpty || parts.any((v) => v == null || !v.isFinite)) {
      return null;
    }
    return parts.cast<double>();
  }

  if (values != null && values.trim().isNotEmpty) {
    final frames = values
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(parseComponents)
        .toList();
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
