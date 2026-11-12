import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 验证 Canvas 顺时针扫角边界。
void main() {
  group('canvasArcSweep', () {
    test('positive clockwise sweep is end minus start', () {
      expect(canvasArcSweep(0.3, 1.7), 1.7 - 0.3);
      expect(canvasArcSweep(1, 1), 0);
    });
    test('negative clockwise sweep wraps modulo 2pi like the canvas spec', () {
      expect(canvasArcSweep(0, -math.pi / 2), 3 * math.pi / 2);
      expect(canvasArcSweep(0, -4 * math.pi), 0);
    });
    test('sweep of 2pi or more becomes a full circle', () {
      expect(canvasArcSweep(0, 2 * math.pi), 2 * math.pi);
      expect(canvasArcSweep(0, 9 * math.pi), 2 * math.pi);
    });
  });
}
