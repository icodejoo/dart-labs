import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 测试矩形。
const Rect _rect = Rect.fromLTWH(10, 20, 100, 40);

/// 验证圆角限制与空矩形行为。
void main() {
  group('buildRoundRectPath', () {
    test('zero height away from the origin returns a truly empty path', () {
      final path = buildRoundRectPath(const Rect.fromLTWH(10, 20, 40, 0), 5);
      expect(path.getBounds(), Rect.zero);
      expect(path.computeMetrics(), isEmpty);
    });
    test('radius is clamped to half of the shorter side', () {
      final actual = buildRoundRectPath(_rect, 200);
      final expected = buildRoundRectPath(_rect, 20);
      expect(actual.getBounds(), _rect);
      expect(Path.combine(PathOperation.xor, actual, expected).getBounds(),
          Rect.zero);
      expect(actual.contains(const Offset(11, 21)), isFalse);
    });
    test('zero radius produces a plain rectangle', () {
      final path = buildRoundRectPath(_rect, 0);
      expect(path.getBounds(), _rect);
      expect(path.contains(const Offset(10.1, 20.1)), isTrue);
    });
    test('non-positive width or height yields an empty path', () {
      expect(
          buildRoundRectPath(const Rect.fromLTWH(0, 0, 0, 40), 5)
              .computeMetrics(),
          isEmpty);
      expect(
          buildRoundRectPath(const Rect.fromLTWH(0, 0, 40, -1), 5)
              .computeMetrics(),
          isEmpty);
    });
    test('negative radius is treated as zero', () {
      final path = buildRoundRectPath(_rect, -2);
      expect(path.getBounds(), _rect);
      expect(path.contains(const Offset(10.1, 20.1)), isTrue);
    });
  });
}
