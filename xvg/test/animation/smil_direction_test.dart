import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';

import 'discrete_reference.dart';

/// 独立贝塞尔参考求值所允许的数值误差。
const _referenceTolerance = 1e-5;

/// 语义测试的标准迭代时长，便于按毫秒避开跳变。
const _duration = Duration(seconds: 1);

/// 用多项式与二分反解贝塞尔，独立于引擎的牛顿求解器。
double _refBezier(CubicBezier curve, double x) {
  if (x <= 0 || x >= 1) return x;

  /// 直接按 Bernstein 基函数求坐标。
  double coordinate(double t, double a, double b) =>
      3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 60; i++) {
    final mid = (low + high) / 2;
    if (coordinate(mid, curve.x1, curve.x2) < x) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return coordinate((low + high) / 2, curve.y1, curve.y2);
}

/// 按 CSS 活动区间、有向迭代进度和关键帧区间独立求值。
/// 测试内点避开关键帧边界，端点仍应用所属区间的缓动。
double? refSample(SmilAnimation animation, Duration time) {
  final elapsed = time.inMicroseconds - animation.begin.inMicroseconds;
  if (elapsed < 0) return null;
  final period = animation.duration.inMicroseconds;
  var iteration = 0;
  var progress = 1.0;
  if (period != 0) {
    final count = animation.repeatCount.count;
    final ended =
        !animation.repeatCount.indefinite &&
        elapsed >= (period * count).round();
    if (ended) {
      if (!animation.fillFreeze) return null;
      // ceil(count)-1 是末次有内容的迭代，包括小数次数。
      iteration = count.ceil() - 1;
      progress = count - iteration;
    } else {
      iteration = elapsed ~/ period;
      progress = (elapsed - iteration * period) / period;
    }
  }
  final reverse = switch (animation.direction) {
    SmilDirection.normal => false,
    SmilDirection.reverse => true,
    SmilDirection.alternate => iteration % 2 == 1,
    SmilDirection.alternateReverse => iteration % 2 == 0,
  };
  if (reverse) progress = 1 - progress;
  final values = animation.values;
  final times =
      animation.keyTimes ??
      [for (var i = 0; i < values.length; i++) i / (values.length - 1)];
  var index = 0;
  while (index + 1 < times.length - 1 && progress >= times[index + 1]) {
    index++;
  }
  var fraction = (progress - times[index]) / (times[index + 1] - times[index]);
  final splines = animation.keySplines;
  if (animation.calcMode == SmilCalcMode.spline &&
      splines != null &&
      index < splines.length) {
    final easing = splines[index];
    if (easing is CubicBezier) {
      fraction = _refBezier(easing, fraction);
    } else if (easing is SmilStepsEasing) {
      final n = easing.count;
      final extra =
          easing.position == SmilStepPosition.start ||
              easing.position == SmilStepPosition.jumpBoth
          ? 1
          : 0;
      final divisor =
          n +
          switch (easing.position) {
            SmilStepPosition.jumpNone => -1,
            SmilStepPosition.jumpBoth => 1,
            _ => 0,
          };
      // 内点不需要引擎为边界舍入设置的容差。
      fraction = ((fraction * n).floor() + extra).clamp(0, divisor) / divisor;
    }
  }
  return values[index] + (values[index + 1] - values[index]) * fraction;
}

/// 比较所有位，包括负零；NaN 必须双方同为 NaN。
void _expectBits(double? actual, double? expected, String reason) {
  if (actual == null || expected == null) {
    expect(actual, expected, reason: reason);
  } else if (expected.isNaN) {
    expect(actual.isNaN, isTrue, reason: reason);
  } else {
    final data = ByteData(16)
      ..setFloat64(0, actual)
      ..setFloat64(8, expected);
    expect(data.getUint64(0), data.getUint64(8), reason: reason);
  }
}

/// 构造与数值动画同源的三分量变换，逐分量核查采样结果。
SmilTransformAnimation _transform(SmilAnimation a) => SmilTransformAnimation(
  type: SmilTransformType.translate,
  values: [
    for (final v in a.values) [v, -v, 0],
  ],
  duration: a.duration,
  begin: a.begin,
  fillFreeze: a.fillFreeze,
  repeatCount: a.repeatCount,
  direction: a.direction,
  calcMode: a.calcMode,
  keyTimes: a.keyTimes,
  keySplines: a.keySplines,
);

/// 验证方向矩阵、真实样本形态和旧实现逐位回归。
void main() {
  const repeats = [1.0, 2.0, 3.0, 1.5, 0.5, double.infinity];
  const combinations =
      <(List<double>, List<double>?, List<SmilSegmentEasing>?)>[
        ([0, 1], null, null),
        (
          [0, 1, -0.5, 2],
          [0, 0.2, 0.6, 1],
          [
            CubicBezier(0.25, 0.1, 0.25, 1),
            SmilStepsEasing(3),
            SmilStepsEasing(4, SmilStepPosition.jumpNone),
          ],
        ),
        (
          [1, -1, 0.5],
          [0, 0.4, 1],
          [
            SmilStepsEasing(3, SmilStepPosition.jumpBoth),
            SmilStepsEasing(2, SmilStepPosition.start),
          ],
        ),
        (
          [0, 1, -1],
          null,
          [
            CubicBezier(0.68, -0.55, 0.265, 1.55),
            CubicBezier(0.42, 0, 0.58, 1),
          ],
        ),
      ];
  for (final direction in SmilDirection.values) {
    test('$direction 与独立 CSS 参考矩阵一致', () {
      for (final count in repeats) {
        for (final freeze in [false, true]) {
          for (final beginMs in [-350, 0, 250]) {
            for (final (values, times, splines) in combinations) {
              final a = SmilAnimation(
                attributeName: 'x',
                values: values,
                duration: _duration,
                begin: Duration(milliseconds: beginMs),
                fillFreeze: freeze,
                direction: direction,
                repeatCount: count.isInfinite
                    ? const SmilRepeatCount.indefinite()
                    : SmilRepeatCount.finite(count),
                calcMode: splines == null
                    ? SmilCalcMode.linear
                    : SmilCalcMode.spline,
                keyTimes: times,
                keySplines: splines,
              );
              final transform = _transform(a);
              // 每个潜在边界前后各 1ms，同时覆盖迭代与冻结终态。
              for (var tick = -10; tick <= 410; tick++) {
                for (final offset in [-1, 1]) {
                  final t = Duration(
                    milliseconds: beginMs + tick * 10 + offset,
                  );
                  final expected = refSample(a, t);
                  final scalar = a.sample(t);
                  final vector = transform.sample(t);
                  final reason = '$count/$freeze/$beginMs/$tick/$offset';
                  if (expected == null) {
                    expect(scalar, isNull, reason: reason);
                    expect(vector, isNull, reason: reason);
                  } else {
                    expect(
                      scalar,
                      closeTo(expected, _referenceTolerance),
                      reason: reason,
                    );
                    expect(
                      vector![0],
                      closeTo(expected, _referenceTolerance),
                      reason: reason,
                    );
                    expect(
                      vector[1],
                      closeTo(-expected, _referenceTolerance),
                      reason: reason,
                    );
                    expect(vector[2], 0, reason: reason);
                  }
                }
              }
            }
          }
        }
      }
    });
  }
  test('零时长取迭代零的有向末态', () {
    for (final d in SmilDirection.values) {
      for (final freeze in [false, true]) {
        final a = SmilAnimation(
          attributeName: 'x',
          values: const [0, 1],
          duration: Duration.zero,
          begin: const Duration(milliseconds: 10),
          fillFreeze: freeze,
          direction: d,
        );
        for (final ms in [9, 10, 11, 100]) {
          final t = Duration(milliseconds: ms);
          expect(a.sample(t), refSample(a, t));
          expect(_transform(a).sample(t)?.first, refSample(a, t));
        }
      }
    }
  });
  test('107/119 形态跨六个周期', () {
    for (final (direction, duration, values, times, splines) in [
      (
        SmilDirection.alternate,
        const Duration(milliseconds: 4000),
        <double>[299.62, 299.62, 79.2],
        <double>[0, 0.6, 1],
        <SmilSegmentEasing>[
          const CubicBezier(0, 0, 1, 1),
          const CubicBezier(0, 0, 1, 1),
        ],
      ),
      (
        SmilDirection.alternateReverse,
        const Duration(milliseconds: 3500),
        <double>[0, 1, 0.2],
        <double>[0, 0.4, 1],
        <SmilSegmentEasing>[
          const CubicBezier(0.42, 0, 0.58, 1),
          const CubicBezier(0.42, 0, 0.58, 1),
        ],
      ),
    ]) {
      final a = SmilAnimation(
        attributeName: 'x',
        values: values,
        duration: duration,
        begin: Duration.zero,
        fillFreeze: true,
        repeatCount: const SmilRepeatCount.indefinite(),
        direction: direction,
        keyTimes: times,
        keySplines: splines,
        calcMode: SmilCalcMode.spline,
      );
      final transform = _transform(a);
      for (var ms = 1; ms < duration.inMilliseconds * 6; ms += 17) {
        final t = Duration(milliseconds: ms);
        expect(a.sample(t), closeTo(refSample(a, t)!, _referenceTolerance));
        expect(
          transform.sample(t)!.first,
          closeTo(refSample(a, t)!, _referenceTolerance),
        );
      }
    }
  });
  test('normal 固定种子 24000 组：discrete 按规范，其余逐位保持旧行为', () {
    final random = math.Random(0x534d494c);
    for (var trial = 0; trial < 24000; trial++) {
      final size = 2 + random.nextInt(5);
      final values = [
        for (var i = 0; i < size; i++)
          trial % 11 == 0 ? 0.0 : (random.nextInt(2001) - 1000).toDouble(),
      ];
      if (trial % 17 == 0) values[0] = -0.0;
      final duration = Duration(
        microseconds: trial % 13 == 0 ? 0 : 1 + random.nextInt(3000000),
      );
      final begin = Duration(
        microseconds: trial % 3 == 0 ? 0 : random.nextInt(4000001) - 2000000,
      );
      final repeat = trial % 5 == 0
          ? const SmilRepeatCount.indefinite()
          : SmilRepeatCount.finite(
              trial % 2 == 0
                  ? 1.0 + random.nextInt(4)
                  : 0.1 + random.nextInt(40) / 10,
            );
      final times = trial % 3 == 0
          ? null
          : (<double>[
              0,
              for (var i = 1; i < size - 1; i++) random.nextDouble(),
              1,
            ]..sort());
      if (times != null && trial % 19 == 0) times.removeLast();
      if (times != null && times.length > 2 && trial % 23 == 0) {
        times[1] = times[0];
      }
      final splines = trial % 3 == 0
          ? null
          : <CubicBezier>[
              for (var i = 0; i < (trial % 4 == 0 ? size - 2 : size - 1); i++)
                CubicBezier(
                  random.nextDouble(),
                  random.nextDouble() * 2 - 0.5,
                  random.nextDouble(),
                  random.nextDouble() * 2 - 0.5,
                ),
            ];
      final a = SmilAnimation(
        attributeName: 'x',
        values: values,
        duration: duration,
        begin: begin,
        fillFreeze: random.nextBool(),
        repeatCount: repeat,
        calcMode:
            SmilCalcMode.values[random.nextInt(SmilCalcMode.values.length)],
        keyTimes: times,
        keySplines: splines,
      );
      final transform = _transform(a);
      final total = (duration.inMicroseconds * repeat.count).round();
      for (final local in [
        -1,
        0,
        duration.inMicroseconds,
        total - 1,
        total,
        total + 1,
        random.nextInt(16000001) - 4000000,
      ]) {
        final t = begin + Duration(microseconds: local);
        final reason = 'trial=$trial local=$local';
        _expectBits(a.sample(t), _oldScalar(a, t), reason);
        final expected = _oldVector(transform, t);
        final actual = transform.sample(t);
        if (expected == null) {
          expect(actual, isNull, reason: reason);
        } else {
          for (var component = 0; component < expected.length; component++) {
            _expectBits(actual![component], expected[component], reason);
          }
        }
      }
    }
  });
  test('逐位比较明确区分负零并处理 NaN', () {
    _expectBits(-0.0, -0.0, '负零');
    _expectBits(double.nan, double.nan, 'NaN');
  });
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
double _oldVectorDistance(List<double> a, List<double> b) {
  var sumSquares = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = b[i] - a[i];
    sumSquares += d * d;
  }
  return math.sqrt(sumSquares);
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
class _OldTiming {
  /// 保存旧时序进度。
  const _OldTiming(this.progress);

  /// 旧采样器的中间值。
  final double progress;
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
_OldTiming? _oldResolveTiming({
  required Duration t,
  required Duration begin,
  required Duration duration,
  required SmilRepeatCount repeatCount,
  required bool fillFreeze,
}) {
  final local = t - begin;
  if (local.isNegative) return null;
  if (duration.inMicroseconds == 0) return const _OldTiming(1);

  final localMicros = local.inMicroseconds;
  final durationMicros = duration.inMicroseconds;

  if (repeatCount.indefinite) {
    return _OldTiming((localMicros % durationMicros) / durationMicros);
  }

  final totalMicros = (durationMicros * repeatCount.count).round();
  if (localMicros >= totalMicros) {
    if (!fillFreeze) return null;
    final wholeIterations = repeatCount.count.floor();
    final fractional = repeatCount.count - wholeIterations;
    return _OldTiming(fractional == 0 ? 1 : fractional);
  }
  return _OldTiming((localMicros % durationMicros) / durationMicros);
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
class _OldSegment {
  /// 保存旧段位置。
  const _OldSegment(this.index, this.t);

  /// 旧采样器的中间值。
  final int index;

  /// 旧采样器的中间值。
  final double t;
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
_OldSegment _oldLocateSegment(
  double progress,
  int segments,
  List<double>? keyTimes,
) {
  if (keyTimes != null && keyTimes.length == segments + 1) {
    for (var i = 0; i < segments; i++) {
      final t0 = keyTimes[i];
      final t1 = keyTimes[i + 1];
      if (progress <= t1 || i == segments - 1) {
        final span = t1 - t0;
        final segT = span <= 0 ? 0.0 : ((progress - t0) / span).clamp(0.0, 1.0);
        return _OldSegment(i, segT);
      }
    }
  }
  final scaled = (progress * segments).clamp(0.0, segments.toDouble());
  final index = scaled.floor().clamp(0, segments - 1);
  return _OldSegment(index, (scaled - index).clamp(0.0, 1.0));
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
double _oldEasedSegmentT(
  SmilCalcMode calcMode,
  List<CubicBezier>? keySplines,
  _OldSegment segment,
) {
  if (calcMode != SmilCalcMode.spline ||
      keySplines == null ||
      segment.index >= keySplines.length) {
    return segment.t;
  }
  return keySplines[segment.index].transform(segment.t);
}

/// 从 HEAD 保留的旧引擎求值逻辑，作为逐位回归基准。
List<double> _oldPacedKeyTimes<T>(
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

/// 离散分支使用独立规范参考；其余保留旧时序、定位、缓动和插值顺序。
double? _oldScalar(SmilAnimation animation, Duration t) {
  final begin = animation.begin;
  final duration = animation.duration;
  final repeatCount = animation.repeatCount;
  final fillFreeze = animation.fillFreeze;
  final values = animation.values;
  final calcMode = animation.calcMode;
  final keyTimes = animation.keyTimes;
  final keySplines = animation.keySplines?.cast<CubicBezier>();
  final timing = _oldResolveTiming(
    t: t,
    begin: begin,
    duration: duration,
    repeatCount: repeatCount,
    fillFreeze: fillFreeze,
  );
  if (timing == null) return null;

  if (calcMode == SmilCalcMode.discrete) {
    return values[referenceDiscreteIndex(
      timing.progress,
      values.length,
      keyTimes,
    )];
  }
  final segments = values.length - 1;
  final effectiveKeyTimes = calcMode == SmilCalcMode.paced
      ? (_oldPacedKeyTimes<double>(values, (a, b) => (b - a).abs()))
      : keyTimes;
  final segment = _oldLocateSegment(
    timing.progress,
    segments,
    effectiveKeyTimes,
  );

  final a = values[segment.index];
  final b = values[segment.index + 1];
  final segT = _oldEasedSegmentT(calcMode, keySplines, segment);
  return a + (b - a) * segT;
}

/// 离散分支使用独立规范参考；其余保留旧时序、定位、缓动和插值顺序。
List<double>? _oldVector(SmilTransformAnimation animation, Duration t) {
  final begin = animation.begin;
  final duration = animation.duration;
  final repeatCount = animation.repeatCount;
  final fillFreeze = animation.fillFreeze;
  final values = animation.values;
  final calcMode = animation.calcMode;
  final keyTimes = animation.keyTimes;
  final keySplines = animation.keySplines?.cast<CubicBezier>();
  final timing = _oldResolveTiming(
    t: t,
    begin: begin,
    duration: duration,
    repeatCount: repeatCount,
    fillFreeze: fillFreeze,
  );
  if (timing == null) return null;

  if (calcMode == SmilCalcMode.discrete) {
    return values[referenceDiscreteIndex(
      timing.progress,
      values.length,
      keyTimes,
    )];
  }
  final segments = values.length - 1;
  final effectiveKeyTimes = calcMode == SmilCalcMode.paced
      ? (_oldPacedKeyTimes<List<double>>(values, _oldVectorDistance))
      : keyTimes;
  final segment = _oldLocateSegment(
    timing.progress,
    segments,
    effectiveKeyTimes,
  );

  final a = values[segment.index];
  final b = values[segment.index + 1];
  final segT = _oldEasedSegmentT(calcMode, keySplines, segment);
  return [for (var i = 0; i < a.length; i++) a[i] + (b[i] - a[i]) * segT];
}
