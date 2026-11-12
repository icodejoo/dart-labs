import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve, Curves;

import 'types.dart' show StaggerDirection;

/// 数位滚动引擎：纯 Dart 计算，不依赖 widget，包内使用（不导出）。
///
/// 持有一次过渡里每个数位列的起止端点和当前位置。AnimatedCounter 的状态机只负责
/// 时间轴与生命周期，进度 t 到各列位置的换算全部在这里。
///
/// 两种模式：
/// - 普通（累计）模式：个位列携带整个数值，每个更高位是 `值 / 10^位`，低位比高位滚得快。
///   [currentDigits] 存放连续的里程表位置。
/// - fast 单步模式：每列只从旧位走到新位一个身位，[currentDigits] 存放 0–1 进度，
///   起止位在 [fastFromDigits] / [fastToDigits]。
///
/// 示例：
/// ```dart
/// final engine = DigitRollEngine()
///   ..begin(from: [0, 0], to: [1, 2], fast: false, unchanged: false);
/// engine.compute(t: 0.5, curve: Curves.linear, baseDurationUs: 1e6,
///     totalDurationUs: 1e6, staggerUs: 0, direction: StaggerDirection.rightToLeft,
///     valueRange: 12, autoEaseThreshold: 100000, fast: false);
/// print(engine.currentDigits); // [0.5, 1.0]
/// ```
class DigitRollEngine {
  /// 过渡起点各列数位（已左侧补零到 [maxDigits] 位）；普通模式下为累计位值。
  List<double> oldDigits = <double>[];

  /// 过渡终点各列数位（已左侧补零到 [maxDigits] 位）；普通模式下为累计位值。
  List<double> targetDigits = <double>[];

  /// 当前帧各列位置：普通模式为里程表位置，fast 模式为 0–1 进度。
  List<double> currentDigits = <double>[];

  /// fast 模式每列的起始数位（0–9）。
  List<int> fastFromDigits = <int>[];

  /// fast 模式每列的终止数位（0–9）。
  List<int> fastToDigits = <int>[];

  /// 列数；只增不减，保证宽度和对齐在值变小时保持稳定。
  int maxDigits = 0;

  /// 当前 [currentDigits] 使用的表示是否为 fast 进度，避免配置更新后误读旧数组。
  bool digitsAreFast = false;

  /// 把端点与当前位置都落在静止的 [digits] 上（初始化或格式变化后重建）。
  ///
  /// [digits] 为该值拆出的各列数位；[fast] 为 true 时 [currentDigits] 全部置为
  /// 进度 1.0（已到终点）。
  void settle(List<double> digits, {required bool fast}) {
    digitsAreFast = fast;
    maxDigits = digits.length;
    oldDigits = List<double>.from(digits);
    targetDigits = List<double>.from(digits);
    fastFromDigits = <int>[for (final d in digits) d.toInt().abs() % 10];
    fastToDigits = List<int>.from(fastFromDigits);
    currentDigits = fast
        ? List<double>.filled(maxDigits, 1.0)
        : List<double>.from(digits);
  }

  /// 准备一次新过渡的端点；列数取历史最大值，并把较短的一侧左侧补零。
  ///
  /// [from] / [to] 为起止数位；[fast] 决定 [currentDigits] 的表示；[unchanged] 为
  /// true 表示起止值相同（fast 模式下进度直接置 1.0，否则从 0 起）。
  void begin({
    required List<double> from,
    required List<double> to,
    required bool fast,
    required bool unchanged,
  }) {
    digitsAreFast = fast;
    maxDigits = math.max(maxDigits, math.max(from.length, to.length));
    oldDigits = <double>[
      ...List<double>.filled(maxDigits - from.length, 0.0),
      ...from,
    ];
    targetDigits = <double>[
      ...List<double>.filled(maxDigits - to.length, 0.0),
      ...to,
    ];
    currentDigits = fast
        ? List<double>.filled(maxDigits, unchanged ? 1.0 : 0.0)
        : List<double>.from(oldDigits);
    // 保留真实的旧、新端点供 fast、reverse 和 repeat 共用；完成后只改变可见性。
    fastFromDigits = <int>[for (final v in oldDigits) v.toInt().abs() % 10];
    fastToDigits = <int>[for (final v in targetDigits) v.toInt().abs() % 10];
  }

  /// 交换起止端点（普通与 fast 两套数位一并交换），供 reverse 与往返 repeat 使用。
  void swapEndpoints() {
    final tmp = List<double>.from(oldDigits);
    oldDigits = List<double>.from(targetDigits);
    targetDigits = tmp;
    final fastTmp = fastFromDigits;
    fastFromDigits = fastToDigits;
    fastToDigits = fastTmp;
  }

  /// 个位列走过的比例（0–1），用来从起止数值还原屏幕当前值。
  ///
  /// 列尚未建立时返回 null；[fallbackT] 用于起止位相同（跨度为零）时兜底。
  double? displayProgress(double fallbackT) {
    if (currentDigits.isEmpty) return null;
    if (digitsAreFast) return currentDigits.last.clamp(0.0, 1.0);
    final span = targetDigits.last - oldDigits.last;
    return span == 0 ? fallbackT : (currentDigits.last - oldDigits.last) / span;
  }

  /// 第 [i] 列的错峰延迟（自启动的微秒数）。
  ///
  /// [staggerUs] 为相邻两列的启动间隔；[direction] 决定从哪一端先启动；
  /// [digitCount] 为列数。滚动与回弹共用，保证相位对齐。
  static double staggerDelayUs(
    int i, {
    required double staggerUs,
    required StaggerDirection direction,
    required int digitCount,
  }) =>
      switch (direction) {
        StaggerDirection.leftToRight => staggerUs * i,
        StaggerDirection.rightToLeft => staggerUs * (digitCount - 1 - i),
      };

  /// 按过渡进度 [t]（0–1，线性时间）就地写入 [currentDigits]，热路径零分配。
  ///
  /// - [curve]：整体曲线；线性且 [valueRange] 超过 [autoEaseThreshold] 时自动换成 easeInOut。
  /// - [baseDurationUs]：单列滚动时长（已按倍速缩放，不含错峰）。
  /// - [totalDurationUs]：含错峰的总时长（已按倍速缩放）。
  /// - [staggerUs]：相邻列启动间隔（已按倍速缩放；0 表示不错峰）。
  /// - [direction]：错峰方向。
  /// - [valueRange]：本次过渡数值总跨度 |新 − 旧|，只用于 autoEase 判断。
  /// - [fast]：true 时每列只写 0–1 进度，单步由渲染层完成。
  /// - [curveForDigit]：按从左到右的列序返回逐位曲线，返回 null 时用整体曲线。
  /// - [interpolation]：自定义插值 `(from, to, progress)`，空则线性。
  void compute({
    required double t,
    required Curve curve,
    required double baseDurationUs,
    required double totalDurationUs,
    required double staggerUs,
    required StaggerDirection direction,
    required double valueRange,
    required double autoEaseThreshold,
    required bool fast,
    Curve? Function(int digitIndex)? curveForDigit,
    double Function(double from, double to, double t)? interpolation,
  }) {
    // autoEase 依据数值总跨度，而非逐位环绕增量（后者 ≤ 10，永远够不到阈值）。
    final bool autoEase = curve == Curves.linear && valueRange > autoEaseThreshold;
    final Curve computeCurve = autoEase ? Curves.easeInOut : curve;

    // 帧间复用缓冲；仅当位数变化时重分配（每次过渡一次）。
    if (currentDigits.length != maxDigits) {
      currentDigits = List<double>.filled(maxDigits, 0.0);
    }

    final double elapsedUs = t * totalDurationUs;
    for (int i = 0; i < maxDigits; i++) {
      double tDigit = t;
      // t 到终点（含减少动画直接落位）时各位一律到位，不再按错峰延迟折算。
      if (staggerUs > 0.0 && t < 1.0) {
        final double delayUs = staggerDelayUs(i,
            staggerUs: staggerUs, direction: direction, digitCount: maxDigits);
        tDigit = ((elapsedUs - delayUs) / baseDurationUs).clamp(0.0, 1.0);
      }
      final Curve digitCurve = curveForDigit?.call(i) ?? computeCurve;
      final double progress = digitCurve.transform(tDigit);

      // 快速模式：列只携带 0–1 进度；from→新位 的单步由渲染层完成（此处不做级联）。
      if (fast) {
        currentDigits[i] = progress;
        continue;
      }

      final double from = oldDigits[i];
      final double to = targetDigits[i];
      // 回弹由 DigitBounce 作为逐列位置轻推单独施加，不写入数值。
      currentDigits[i] = interpolation != null
          ? interpolation(from, to, progress)
          : from + (to - from) * progress;
    }
  }
}

/// 落位回弹的逐列时间轴：每列在自己滚动结束的瞬间回弹，整体与滚动并发。
///
/// 回弹是对已定位数位的纯位置轻推：数值钉在目标，不会露出相邻数位。幅度用 tanh
/// 限制在一个数位高度内，渲染层把 [fill] 写出的值当作数位高度的比例消费。
class DigitBounce {
  /// 创建回弹时间轴。
  ///
  /// [overshoot] 为回弹幅度（须大于 0）；[staggerUs] 为相邻列启动间隔；
  /// [baseDurationUs] 为单列滚动时长；[direction] 为错峰方向；[digitCount] 为列数。
  DigitBounce({
    required double overshoot,
    required this.staggerUs,
    required this.baseDurationUs,
    required this.direction,
    required this.digitCount,
  }) : maxFraction = _maxFractionOf(overshoot) {
    double lastRollEndUs = 0.0;
    for (int i = 0; i < digitCount; i++) {
      final e = rollEndUs(i);
      if (e > lastRollEndUs) lastRollEndUs = e;
    }
    totalUs = lastRollEndUs + bounceUs;
  }

  /// 单次回弹的时长（微秒）。
  static const double bounceUs = 350000.0;

  /// 相邻列启动间隔（微秒，已按倍速缩放）。
  final double staggerUs;

  /// 单列滚动时长（微秒，已按倍速缩放）。
  final double baseDurationUs;

  /// 错峰方向。
  final StaggerDirection direction;

  /// 列数。
  final int digitCount;

  /// 轻推的最大比例（数位高度的分数），由 tanh(overshoot) 得到。
  final double maxFraction;

  /// 时间轴总长：最后一列滚动结束再加一次回弹（微秒）。
  late final double totalUs;

  static double _maxFractionOf(double overshoot) {
    final double ex2 = math.exp(2.0 * overshoot);
    return (ex2 - 1) / (ex2 + 1);
  }

  /// 第 [i] 列滚动结束的时刻（自启动的微秒数）。
  double rollEndUs(int i) =>
      DigitRollEngine.staggerDelayUs(i,
          staggerUs: staggerUs, direction: direction, digitCount: digitCount) +
      baseDurationUs;

  /// 把时间轴进度 [t]（0–1）对应的逐列轻推比例写入 [out]；[out] 长度至少为 [digitCount]。
  void fill(List<double> out, double t) {
    final double elapsedUs = t * totalUs;
    for (int i = 0; i < digitCount; i++) {
      final double localUs = elapsedUs - rollEndUs(i);
      out[i] = (localUs > 0.0 && localUs < bounceUs)
          ? maxFraction * math.sin(math.pi * localUs / bounceUs)
          : 0.0;
    }
  }
}
