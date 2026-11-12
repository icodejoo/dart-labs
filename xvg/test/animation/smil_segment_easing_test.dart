import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';

/// 获取非负数附近相邻的双精度数，覆盖阶梯分数边界的舍入误差。
double _neighbor(double value, int offset) {
  if (value == 0) {
    final data = ByteData(8)..setUint64(0, 1);
    return offset < 0 ? -data.getFloat64(0) : data.getFloat64(0);
  }
  final data = ByteData(8)..setFloat64(0, value);
  data.setUint64(0, data.getUint64(0) + offset);
  return data.getFloat64(0);
}

/// 混合缓动采样的数值比较容差。
const _sampleTolerance = 1e-10;

/// 测试使用的完整迭代时长。
const _duration = Duration(seconds: 1);

/// 同时检查数值与变换通道的混合段缓动。
void _checkSegments(List<SmilSegmentEasing> easing) {
  const values = [0.0, 10.0, 30.0, 60.0];
  const times = [0.0, 0.2, 0.6, 1.0];
  final numeric = SmilAnimation(
    attributeName: 'x',
    values: values,
    duration: _duration,
    begin: Duration.zero,
    fillFreeze: true,
    calcMode: SmilCalcMode.spline,
    keyTimes: times,
    keySplines: easing,
  );
  final transform = SmilTransformAnimation(
    type: SmilTransformType.translate,
    values: [
      for (final value in values) [value, -value, 0],
    ],
    duration: _duration,
    begin: Duration.zero,
    fillFreeze: true,
    calcMode: SmilCalcMode.spline,
    keyTimes: times,
    keySplines: easing,
  );
  for (final (micros, segment, fraction) in [
    (100000, 0, 0.5),
    (300000, 1, 0.25),
    (700000, 2, 0.25),
    (1000000, 2, 1.0),
  ]) {
    final eased = segment < easing.length
        ? easing[segment].transform(fraction)
        : fraction;
    final expected =
        values[segment] + (values[segment + 1] - values[segment]) * eased;
    final t = Duration(microseconds: micros);
    expect(numeric.sample(t), closeTo(expected, _sampleTolerance));
    expect(transform.sample(t)![0], closeTo(expected, _sampleTolerance));
    expect(transform.sample(t)![1], closeTo(-expected, _sampleTolerance));
  }
}

/// 验证阶跃表、边界稳定性以及两个通道的段缓动接线。
void main() {
  for (final (count, position, expected) in [
    (1, SmilStepPosition.end, [0.0, 0, 0, 0, 1]),
    (3, SmilStepPosition.end, [0.0, 0, 1 / 3, 2 / 3, 1]),
    (2, SmilStepPosition.start, [0.5, 0.5, 1, 1, 1]),
    (4, SmilStepPosition.jumpNone, [0.0, 1 / 3, 2 / 3, 1, 1]),
    (3, SmilStepPosition.jumpBoth, [0.25, 0.25, 0.5, 0.75, 1]),
  ]) {
    test('steps($count, $position) 表驱动', () {
      final easing = SmilStepsEasing(count, position);
      const points = [0.0, 0.25, 0.5, 0.75, 1.0];
      for (var i = 0; i < points.length; i++) {
        expect(easing.transform(points[i]), expected[i]);
      }
      for (var k = 0; k <= count; k++) {
        final boundary = k / count;
        final expected = easing.transform(boundary);
        expect(easing.transform(_neighbor(boundary, -1)), expected);
        expect(easing.transform(_neighbor(boundary, 1)), expected);
      }
      for (final t in [
        -double.maxFinite,
        -2.0,
        -0.1,
        0.0,
        0.999999,
        1.0,
        1.1,
        double.maxFinite,
        double.negativeInfinity,
        double.infinity,
        double.nan,
        for (var i = 0; i <= 1000; i++) i / 1000,
      ]) {
        expect(easing.transform(t), inInclusiveRange(0, 1));
      }
      expect(easing.transform(1), 1);
    });
  }
  test('step-end 在结束前保持零', () {
    const easing = SmilStepsEasing(1);
    // 规定的 1e-9 容差会吸收最后一个 ulp，内点取容差之外。
    for (final t in [0.0, 0.1, 0.5, 0.999999]) {
      expect(easing.transform(t), 0);
    }
    expect(easing.transform(_neighbor(1, -1)), 1);
    expect(easing.transform(1), 1);
  });
  test('所有阶跃位置的边界及端点相邻 double 不抖动', () {
    for (final position in SmilStepPosition.values) {
      for (var count = 2; count <= 32; count++) {
        final easing = SmilStepsEasing(count, position);
        for (var k = 0; k <= count; k++) {
          final t = k / count;
          expect(easing.transform(_neighbor(t, -1)), easing.transform(t));
          expect(easing.transform(_neighbor(t, 1)), easing.transform(t));
        }
      }
    }
  });
  test('混合线性、贝塞尔、阶跃缓动', () {
    _checkSegments(const <SmilSegmentEasing>[
      CubicBezier(0, 0, 1, 1),
      CubicBezier(0.42, 0, 0.58, 1),
      SmilStepsEasing(4),
    ]);
  });
  test('缺失段线性回退，旧 List<CubicBezier> 无需转换', () {
    _checkSegments(const <CubicBezier>[CubicBezier(0.42, 0, 0.58, 1)]);
    _checkSegments(const <SmilSegmentEasing>[]);
  });
}
