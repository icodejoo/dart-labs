import 'dart:math' as math;

import 'package:flutter/widgets.dart' show StrokeCap;
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Deterministic tests for RingPainter.arcGeometry — the pure geometry that
// gives a countdown ring rounded ends AND a gap visible from the first tick.
//
// RingPainter.arcGeometry 的确定性测试——让倒计时环既有圆头、缺口又从第 1 tick
// 起就可见的纯几何。
void main() {
  const full = 2 * math.pi;
  const top = -math.pi / 2;

  test('round cap on a full ring is clamped so the two caps only touch', () {
    final g = RingPainter.arcGeometry(
      startAngle: top,
      sweepAngle: full,
      progress: 1.0,
      strokeWidth: 12,
      radius: 54,
      strokeCap: StrokeCap.round,
      clockwise: true,
      anchorAtEnd: true,
    );
    // Below a full turn by ~one cap diameter → hairline gap, no overlap.
    expect(g.sweep.abs(), lessThan(full));
    expect(g.sweep.abs(), greaterThan(0));
    expect(g.sweep.abs(), closeTo(full - 12 / 54, 1e-9));
  });

  test('butt cap on a full ring closes seamlessly (no clamp)', () {
    final g = RingPainter.arcGeometry(
      startAngle: top,
      sweepAngle: full,
      progress: 1.0,
      strokeWidth: 12,
      radius: 54,
      strokeCap: StrokeCap.butt,
      clockwise: true,
      anchorAtEnd: true,
    );
    expect(g.sweep.abs(), closeTo(full, 1e-9));
  });

  test('mid progress is exact — below the clamp threshold', () {
    final g = RingPainter.arcGeometry(
      startAngle: top,
      sweepAngle: full,
      progress: 0.5,
      strokeWidth: 12,
      radius: 54,
      strokeCap: StrokeCap.round,
      clockwise: true,
      anchorAtEnd: true,
    );
    expect(g.sweep.abs(), closeTo(full * 0.5, 1e-9));
  });

  test('anchorAtEnd opens the gap at startAngle, sweeping clockwise', () {
    final g = RingPainter.arcGeometry(
      startAngle: top,
      sweepAngle: full,
      progress: 0.75,
      strokeWidth: 8,
      radius: 50,
      strokeCap: StrokeCap.butt,
      clockwise: true,
      anchorAtEnd: true,
    );
    // emptied = 25% of the turn, pushed clockwise (dir +1) off the top.
    expect(g.start, closeTo(top + 0.25 * full, 1e-9));
    expect(g.sweep, closeTo(0.75 * full, 1e-9));
  });

  test('counter (anchor at start) grows from startAngle', () {
    final g = RingPainter.arcGeometry(
      startAngle: top,
      sweepAngle: full,
      progress: 0.3,
      strokeWidth: 8,
      radius: 50,
      strokeCap: StrokeCap.round,
      clockwise: true,
      anchorAtEnd: false,
    );
    expect(g.start, closeTo(top, 1e-9));
    expect(g.sweep, closeTo(0.3 * full, 1e-9));
  });

  test('partial-arc gauge is never clamped even with round caps', () {
    const gauge = 1.5 * math.pi;
    final g = RingPainter.arcGeometry(
      startAngle: 0,
      sweepAngle: gauge,
      progress: 1.0,
      strokeWidth: 20,
      radius: 40,
      strokeCap: StrokeCap.round,
      clockwise: true,
      anchorAtEnd: false,
    );
    expect(g.sweep.abs(), closeTo(gauge, 1e-9));
  });
}
