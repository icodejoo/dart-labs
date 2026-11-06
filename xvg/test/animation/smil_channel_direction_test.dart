import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';

import 'discrete_reference.dart';

/// 独立贝塞尔参考求值所允许的数值误差。
const _tolerance = 1e-5;

/// 标准迭代时长，便于按毫秒避开跳变。
const _duration = Duration(seconds: 1);

/// 采样刻度数（每刻度 10ms）。
const _ticks = 410;

/// 运动路径采样表的点数，x、y 都与弧长比例成正比。
const _motionTableSize = 11;

/// 运动表 x 方向的总长。
const _motionLength = 100.0;

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

/// 一组与通道无关的关键帧缓动配置。
class _Combo {
  const _Combo(this.count, this.mode, this.times, this.splines);

  /// 关键帧个数。
  final int count;

  /// 插值模式。
  final SmilCalcMode mode;

  /// 可选的 keyTimes。
  final List<double>? times;

  /// 可选的段缓动。
  final List<SmilSegmentEasing>? splines;
}

const _combos = <_Combo>[
  _Combo(2, SmilCalcMode.linear, null, null),
  _Combo(
    4,
    SmilCalcMode.spline,
    [0, 0.2, 0.6, 1],
    [
      CubicBezier(0.25, 0.1, 0.25, 1),
      SmilStepsEasing(3),
      SmilStepsEasing(4, SmilStepPosition.jumpNone),
    ],
  ),
  _Combo(
    3,
    SmilCalcMode.spline,
    [0, 0.4, 1],
    [
      SmilStepsEasing(3, SmilStepPosition.jumpBoth),
      SmilStepsEasing(2, SmilStepPosition.start),
    ],
  ),
  _Combo(3, SmilCalcMode.spline, null, [
    CubicBezier(0.68, -0.55, 0.265, 1.55),
    CubicBezier(0.42, 0, 0.58, 1),
  ]),
  _Combo(4, SmilCalcMode.discrete, [0, 0.2, 0.6, 1], null),
];

/// 参考的有向迭代进度：按 CSS 活动区间与方向规则求值，未生效返回 null。
double? _refProgress({
  required Duration time,
  required Duration begin,
  required SmilRepeatCount repeat,
  required bool freeze,
  required SmilDirection direction,
}) {
  final elapsed = time.inMicroseconds - begin.inMicroseconds;
  if (elapsed < 0) return null;
  final period = _duration.inMicroseconds;
  var iteration = 0;
  var progress = 1.0;
  final ended =
      !repeat.indefinite && elapsed >= (period * repeat.count).round();
  if (ended) {
    if (!freeze) return null;
    iteration = repeat.count.ceil() - 1;
    progress = repeat.count - iteration;
  } else {
    iteration = elapsed ~/ period;
    progress = (elapsed - iteration * period) / period;
  }
  final reverse = switch (direction) {
    SmilDirection.normal => false,
    SmilDirection.reverse => true,
    SmilDirection.alternate => iteration.isOdd,
    SmilDirection.alternateReverse => iteration.isEven,
  };
  return reverse ? 1 - progress : progress;
}

/// 参考的段定位：返回起始关键帧下标与未缓动的段内比例。
(int, double) _refLocate(_Combo combo, double progress) {
  final times =
      combo.times ??
      [for (var i = 0; i < combo.count; i++) i / (combo.count - 1)];
  var index = 0;
  while (index + 1 < times.length - 1 && progress >= times[index + 1]) {
    index++;
  }
  return (index, (progress - times[index]) / (times[index + 1] - times[index]));
}

/// 参考的缓动：阶跃按公式独立计算，内点不需要边界容差。
double _refEase(_Combo combo, int index, double fraction) {
  final splines = combo.splines;
  if (combo.mode != SmilCalcMode.spline ||
      splines == null ||
      index >= splines.length) {
    return fraction;
  }
  final easing = splines[index];
  if (easing is CubicBezier) return _refBezier(easing, fraction);
  final steps = easing as SmilStepsEasing;
  final n = steps.count;
  final extra =
      steps.position == SmilStepPosition.start ||
          steps.position == SmilStepPosition.jumpBoth
      ? 1
      : 0;
  final divisor =
      n +
      switch (steps.position) {
        SmilStepPosition.jumpNone => -1,
        SmilStepPosition.jumpBoth => 1,
        _ => 0,
      };
  return ((fraction * n).floor() + extra).clamp(0, divisor) / divisor;
}

/// 标量参考值：离散按每帧切换时间取值，其余模式按段插值。
double _refScalar(_Combo combo, List<double> values, double progress) {
  if (combo.mode == SmilCalcMode.discrete) {
    return values[referenceDiscreteIndex(progress, values.length, combo.times)];
  }
  final (index, fraction) = _refLocate(combo, progress);
  final eased = _refEase(combo, index, fraction);
  return values[index] + (values[index + 1] - values[index]) * eased;
}

/// 各通道共用的帧值：每帧一个标量。
List<double> _scalars(int n) => [for (var i = 0; i < n; i++) i * 17.0 - 20];

/// 各通道共用的颜色帧：灰阶，便于逐通道比较。
List<int> _grays(int n) => [
  for (var i = 0; i < n; i++)
    0xFF000000 | ((i * 60 + 10) << 16) | ((i * 60 + 10) << 8) | (i * 60 + 10),
];

/// 遍历次数、定格、起始偏移与采样时刻，对每个有效时刻调用 [check]。
void _forEachSample(
  SmilDirection direction,
  void Function(
    _Combo combo,
    SmilRepeatCount repeat,
    bool freeze,
    Duration begin,
    Duration time,
    double? progress,
  )
  check,
) {
  const repeats = [1.0, 2.0, 3.0, 1.5, 0.5, double.infinity];
  for (final count in repeats) {
    final repeat = count.isInfinite
        ? const SmilRepeatCount.indefinite()
        : SmilRepeatCount.finite(count);
    for (final freeze in [false, true]) {
      for (final beginMs in [-350, 0, 250]) {
        final begin = Duration(milliseconds: beginMs);
        for (final combo in _combos) {
          for (var tick = -10; tick <= _ticks; tick++) {
            for (final offset in [-1, 1]) {
              final time = Duration(milliseconds: beginMs + tick * 10 + offset);
              check(
                combo,
                repeat,
                freeze,
                begin,
                time,
                _refProgress(
                  time: time,
                  begin: begin,
                  repeat: repeat,
                  freeze: freeze,
                  direction: direction,
                ),
              );
            }
          }
        }
      }
    }
  }
}

/// 比较两个可空 double；null 必须同时为 null。
void _expectClose(double? actual, double? expected, String reason) {
  if (expected == null) {
    expect(actual, isNull, reason: reason);
  } else {
    expect(actual, closeTo(expected, _tolerance), reason: reason);
  }
}

/// 在四个通道上，对比引擎与独立的 CSS 方向参考。
void main() {
  test('discrete 标量参考忽略长度不匹配的 keyTimes', () {
    for (final times in [
      [0.0, 1.0],
      [0.0, 0.1, 0.2, 1.0],
    ]) {
      final combo = _Combo(3, SmilCalcMode.discrete, times, null);
      expect(_refScalar(combo, [0, 10, 20], 0.5), 10);
      expect(_refScalar(combo, [0, 10, 20], 0.9), 20);
    }
  });
  for (final direction in SmilDirection.values) {
    group('$direction', () {
      test('motion（keyPoints 路径）', () {
        // 表内 x 与 y 都与弧长比例成正比，因此能直接反推弧长比例。
        final table = [
          for (var i = 0; i < _motionTableSize; i++)
            SmilMotionSample(
              _motionLength * i / (_motionTableSize - 1),
              2 * _motionLength * i / (_motionTableSize - 1),
              0,
            ),
        ];
        _forEachSample(direction, (combo, repeat, freeze, begin, time, p) {
          final keyPoints = [
            for (var i = 0; i < combo.count; i++)
              i.isEven ? 0.8 - 0.2 * i : 0.1 + 0.25 * i,
          ];
          final a = SmilMotionAnimation(
            samples: table,
            duration: _duration,
            begin: begin,
            fillFreeze: freeze,
            repeatCount: repeat,
            direction: direction,
            keyPoints: keyPoints,
            keyTimes: combo.times,
            keySplines: combo.splines,
            calcMode: combo.mode,
          );
          final got = a.sample(time);
          final reason = '${combo.mode}/$repeat/$freeze/$begin/$time';
          if (p == null) {
            expect(got, isNull, reason: reason);
            return;
          }
          final arc = _refScalar(combo, keyPoints, p).clamp(0.0, 1.0);
          expect(got!.x, closeTo(arc * _motionLength, _tolerance * 100));
          expect(got.y, closeTo(arc * 2 * _motionLength, _tolerance * 200));
        });
      });

      test('motion（无 keyPoints，弧长即有向进度）', () {
        final table = [
          for (var i = 0; i < _motionTableSize; i++)
            SmilMotionSample(_motionLength * i / (_motionTableSize - 1), 0, 0),
        ];
        _forEachSample(direction, (combo, repeat, freeze, begin, time, p) {
          if (combo != _combos.first) return;
          final a = SmilMotionAnimation(
            samples: table,
            duration: _duration,
            begin: begin,
            fillFreeze: freeze,
            repeatCount: repeat,
            direction: direction,
          );
          final got = a.sample(time);
          if (p == null) {
            expect(got, isNull);
          } else {
            expect(got!.x, closeTo(p * _motionLength, 1e-9));
          }
        });
      });

      test('color', () {
        _forEachSample(direction, (combo, repeat, freeze, begin, time, p) {
          final grays = _grays(combo.count);
          final a = SmilColorAnimation(
            values: grays,
            duration: _duration,
            begin: begin,
            fillFreeze: freeze,
            repeatCount: repeat,
            direction: direction,
            calcMode: combo.mode,
            keyTimes: combo.times,
            keySplines: combo.splines,
          );
          final got = a.sample(time);
          final reason = '${combo.mode}/$repeat/$freeze/$begin/$time';
          if (p == null) {
            expect(got, isNull, reason: reason);
            return;
          }
          // 灰阶的蓝通道取值与标量通道同构；允许取整与钳制的 1 级误差。
          final blues = [for (final g in grays) (g & 0xFF).toDouble()];
          final expected = _refScalar(combo, blues, p).clamp(0.0, 255.0);
          expect(got! >> 24, 0xFF, reason: reason);
          expect(
            (got & 0xFF).toDouble(),
            closeTo(expected, 0.5 + 1e-3),
            reason: reason,
          );
        });
      });

      test('path（位置 = 下标 + 钳制后的缓动比例；离散按等分区间）', () {
        _forEachSample(direction, (combo, repeat, freeze, begin, time, p) {
          final a = SmilPathAnimation(
            frames: [for (var i = 0; i < combo.count; i++) 'M0 0L$i 0'],
            morph: PathMorphData(
              ops: const [kMorphMove, kMorphLine],
              frames: [
                for (var i = 0; i < combo.count; i++)
                  Float64List.fromList([0, 0, i * 10.0, 0]),
              ],
            ),
            duration: _duration,
            begin: begin,
            fillFreeze: freeze,
            repeatCount: repeat,
            direction: direction,
            calcMode: combo.mode,
            keyTimes: combo.times,
            keySplines: combo.splines,
          );
          final got = a.sample(time);
          final reason = '${combo.mode}/$repeat/$freeze/$begin/$time';
          if (p == null) {
            expect(got, isNull, reason: reason);
            return;
          }
          if (combo.mode == SmilCalcMode.discrete) {
            // 路径通道离散按规范：有合法 keyTimes（长度等于帧数）时按其切换。
            final times = combo.times!;
            var index = 0;
            for (var i = 1; i < combo.count; i++) {
              if (p >= times[i]) index = i;
            }
            expect(got, index.toDouble(), reason: reason);
            return;
          }
          final (index, fraction) = _refLocate(combo, p);
          final eased = _refEase(combo, index, fraction).clamp(0.0, 1.0);
          expect(got, closeTo(index + eased, _tolerance), reason: reason);
        });
      });

      test('list', () {
        _forEachSample(direction, (combo, repeat, freeze, begin, time, p) {
          final scalars = _scalars(combo.count);
          final a = SmilListAnimation(
            attributeName: 'stroke-dasharray',
            values: [
              for (final v in scalars) [v, -2 * v, 5],
            ],
            duration: _duration,
            begin: begin,
            fillFreeze: freeze,
            repeatCount: repeat,
            direction: direction,
            calcMode: combo.mode,
            keyTimes: combo.times,
            keySplines: combo.splines,
          );
          final got = a.sample(time);
          final reason = '${combo.mode}/$repeat/$freeze/$begin/$time';
          if (p == null) {
            expect(got, isNull, reason: reason);
            return;
          }
          final expected = _refScalar(combo, scalars, p);
          _expectClose(got![0], expected, reason);
          _expectClose(got[1], -2 * expected, reason);
          expect(got[2], 5, reason: reason);
        });
      });
    });
  }

  test('零时长：四个通道都取迭代零的有向末态', () {
    for (final direction in SmilDirection.values) {
      for (final freeze in [false, true]) {
        const zero = Duration.zero;
        final begin = const Duration(milliseconds: 10);
        // 有向进度：normal/alternate 为 1，reverse/alternateReverse 为 0。
        final expectedP =
            direction == SmilDirection.normal ||
                direction == SmilDirection.alternate
            ? 1.0
            : 0.0;
        final list = SmilListAnimation(
          attributeName: 'x',
          values: const [
            [0],
            [10],
          ],
          duration: zero,
          begin: begin,
          fillFreeze: freeze,
          direction: direction,
        );
        final color = SmilColorAnimation(
          values: const [0xFF000000, 0xFF0A0A0A],
          duration: zero,
          begin: begin,
          fillFreeze: freeze,
          direction: direction,
        );
        final path = SmilPathAnimation(
          frames: const ['a', 'b'],
          morph: PathMorphData(
            ops: const [kMorphMove],
            frames: [
              Float64List.fromList([0, 0]),
              Float64List.fromList([1, 1]),
            ],
          ),
          duration: zero,
          begin: begin,
          fillFreeze: freeze,
          direction: direction,
        );
        final motion = SmilMotionAnimation(
          samples: const [
            SmilMotionSample(0, 0, 0),
            SmilMotionSample(10, 0, 0),
          ],
          duration: zero,
          begin: begin,
          fillFreeze: freeze,
          direction: direction,
        );
        for (final ms in [9, 10, 11, 100]) {
          final t = Duration(milliseconds: ms);
          if (ms < 10) {
            expect(list.sample(t), isNull);
            expect(color.sample(t), isNull);
            expect(path.sample(t), isNull);
            expect(motion.sample(t), isNull);
          } else {
            // 零时长：只要已经开始，就停在迭代零的有向末态。
            expect(list.sample(t)![0], closeTo(10 * expectedP, 1e-9));
            expect(color.sample(t)! & 0xFF, (10 * expectedP).round());
            expect(path.sample(t), expectedP);
            expect(motion.sample(t)!.x, closeTo(10 * expectedP, 1e-9));
          }
        }
      }
    }
  });
}
