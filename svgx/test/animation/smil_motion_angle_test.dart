import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';

/// 角度比较的数值容差。
const _tolerance = 1e-9;

/// 单次迭代时长，便于用毫秒表示进度。
const _duration = Duration(seconds: 1);

/// 用手工角度表构造一条线性运动，采样点按等间距排布。
SmilMotionAnimation _motion(List<double> angles, {bool interpolate = false}) =>
    SmilMotionAnimation(
      samples: [
        for (var i = 0; i < angles.length; i++)
          SmilMotionSample(i.toDouble(), 0, angles[i]),
      ],
      duration: _duration,
      begin: Duration.zero,
      fillFreeze: true,
      interpolateAngle: interpolate,
    );

/// 取 [fraction]（`[0, 1]`）处的角度。
double _angleAt(SmilMotionAnimation a, double fraction) => a
    .sample(Duration(microseconds: (fraction * 1000000).round()))!
    .angleDegrees;

/// 把角度归一到 `[0, 360)`，用于比较等价角。
double _norm(double d) => (d % 360 + 360) % 360;

/// 逐位比较 double，包括 -0.0。
void _expectBits(double actual, double expected, String reason) {
  final data = ByteData(16)
    ..setFloat64(0, actual)
    ..setFloat64(8, expected);
  expect(data.getUint64(0), data.getUint64(8), reason: reason);
}

/// 验证 `interpolateAngle` 的线性插值、绕回与默认行为。
void main() {
  group('interpolateAngle = true', () {
    test('普通区间线性插值', () {
      final a = _motion([0, 90], interpolate: true);
      expect(_angleAt(a, 0.25), closeTo(22.5, _tolerance));
      expect(_angleAt(a, 0.5), closeTo(45, _tolerance));
      expect(_angleAt(a, 0.75), closeTo(67.5, _tolerance));
    });

    test('359 到 1 走短弧：中点是 0 的等价角，而非 180', () {
      final a = _motion([359, 1], interpolate: true);
      expect(_norm(_angleAt(a, 0.5)), closeTo(0, _tolerance));
      // 起点处保持 359，四分之一处为 359.5，而不是长路上的 269。
      expect(_angleAt(a, 0), closeTo(359, _tolerance));
      expect(_angleAt(a, 0.25), closeTo(359.5, _tolerance));
    });

    test('1 到 359 反向走短弧', () {
      final a = _motion([1, 359], interpolate: true);
      expect(_norm(_angleAt(a, 0.5)), closeTo(0, _tolerance));
      expect(_angleAt(a, 0.25), closeTo(0.5, _tolerance));
    });

    test('_wrap180 语义：359 到 1 的差值折为 2 而不是 -358', () {
      // 差值 1 - 359 = -358；折回后应为 2，由中点 359 + 2 * 0.5 = 360 反推。
      final a = _motion([359, 1], interpolate: true);
      expect(_angleAt(a, 0.5), closeTo(360, _tolerance));
    });

    test('恰好 180 度差取 -180 一侧，行为确定', () {
      final a = _motion([0, 180], interpolate: true);
      // (180 + 180) % 360 - 180 = -180，因此 0 到 180 向负方向走。
      expect(_angleAt(a, 0.5), closeTo(-90, _tolerance));
    });

    test('跨多段表：每段独立折回', () {
      final a = _motion([170, -170, -90], interpolate: true);
      // 第一段 170 到 -170 走短弧经过 180，第二段普通插值。
      expect(_norm(_angleAt(a, 0.25)), closeTo(180, _tolerance));
      expect(_angleAt(a, 0.75), closeTo(-130, _tolerance));
    });

    test('末端定格取最后一段的终点', () {
      final a = _motion([359, 1], interpolate: true);
      expect(_norm(_angleAt(a, 1)), closeTo(1, _tolerance));
    });
  });

  group('interpolateAngle = false', () {
    test('取段起点角度，与旧行为逐位相同', () {
      const angles = <double>[10, 80, -170, 170, 359.5, 0];
      final a = _motion(angles);
      final b = _motion(angles, interpolate: false);
      for (var i = 0; i <= 1000; i++) {
        final t = Duration(milliseconds: i);
        final scaled = (i / 1000 * (angles.length - 1)).clamp(
          0.0,
          (angles.length - 1).toDouble(),
        );
        final index = scaled.floor().clamp(0, angles.length - 2);
        _expectBits(a.sample(t)!.angleDegrees, angles[index], 'default $i');
        _expectBits(b.sample(t)!.angleDegrees, angles[index], 'false $i');
      }
    });

    test('默认值是 false', () {
      expect(_motion([0, 90]).interpolateAngle, isFalse);
      expect(_motion([0, 90]).direction, SmilDirection.normal);
    });
  });
}
