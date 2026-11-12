import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 几何测量允许的像素误差。
const double _epsilon = 0.0001;

/// 验证扇形外弧与顶点。
void main() {
  group('buildFanPath', () {
    test('fan contour is explicitly closed for stroking', () {
      final path = buildFanPath(
          outerRadius: 100, start: 0, end: math.pi / 2, gutter: 10);
      expect(path.computeMetrics().single.isClosed, isTrue);
    });
    test('zero gutter fan apex is the center', () {
      final path =
          buildFanPath(outerRadius: 100, start: 0, end: math.pi / 2, gutter: 0);
      expect(path.getBounds(), const Rect.fromLTWH(0, 0, 100, 100));
      expect(path.contains(const Offset(1, 1)), isTrue);
      expect(path.contains(const Offset(-1, 1)), isFalse);
    });
    test(
        'gutter shrinks the outer arc by gutter / (2 * radius) radians on each side',
        () {
      final path = buildFanPath(
          outerRadius: 100, start: 0, end: math.pi / 2, gutter: 10);
      final metric = path.computeMetrics().single;
      final first = metric.getTangentForOffset(0)!.position;
      expect(first.dx, closeTo(math.cos(10 / (2 * 100)) * 100, _epsilon));
      expect(first.dy, closeTo(math.sin(10 / (2 * 100)) * 100, _epsilon));
      final bounds = path.getBounds();
      expect(bounds.right, closeTo(math.cos(0.05) * 100, _epsilon));
      expect(bounds.bottom, closeTo(math.cos(0.05) * 100, _epsilon));
    });
    test('apex lies on the bisector at gutter / 2 / abs(sin(half sweep))', () {
      final path = buildFanPath(
          outerRadius: 100, start: -math.pi / 4, end: math.pi / 4, gutter: 10);
      final expected = 10 / 2 / math.sin(-math.pi / 4).abs();
      expect(path.getBounds().left, closeTo(expected, _epsilon));
      expect(path.contains(Offset(expected + 0.1, 0)), isTrue);
      expect(path.contains(Offset(expected - 0.1, 0)), isFalse);
    });
    test('non-positive outer radius yields an empty path', () {
      expect(
          buildFanPath(outerRadius: 0, start: 0, end: 1, gutter: 2)
              .computeMetrics(),
          isEmpty);
      expect(
          buildFanPath(outerRadius: -1, start: 0, end: 1, gutter: 2)
              .computeMetrics(),
          isEmpty);
    });
  });
}
