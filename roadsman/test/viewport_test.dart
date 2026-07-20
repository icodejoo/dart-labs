import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

void main() {
  group('viewport', () {
    test('createViewport 返回原点、scale=1、idle', () {
      final s = createViewport();
      expect(s.offsetX, 0);
      expect(s.offsetY, 0);
      expect(s.scale, 1);
      expect(s.phase, ViewportPhase.idle);
    });

    test('computeBounds：内容比面板宽时 minX 为负', () {
      final bounds = computeBounds(400, 216, 800, 216, 1);
      expect(bounds.minX, -400);
      expect(bounds.maxX, 0);
    });

    test('dragBy 在边界内正常累加偏移', () {
      final bounds = computeBounds(400, 216, 800, 216, 1);
      var s = createViewport();
      s = dragBy(s, -50, 0, bounds, defaultViewportConfig);
      expect(s.offsetX, -50);
      expect(s.phase, ViewportPhase.dragging);
    });

    test('dragBy 越界时按橡皮筋阻尼压缩', () {
      final bounds = computeBounds(400, 216, 800, 216, 1);
      var s = createViewport();
      // 越过 minX=-400 边界，拖到 -450：阻尼后应比 -450 更靠近边界。
      s = dragBy(s, -450, 0, bounds, defaultViewportConfig);
      expect(s.offsetX, greaterThan(-450));
      expect(s.offsetX, lessThan(-400));
    });

    test('Y 轴在内容高度不超过面板时锁死为 0', () {
      final bounds = computeBounds(400, 216, 800, 216, 1); // minY = 0（内容不超高）
      var s = createViewport();
      s = dragBy(s, 0, 50, bounds, defaultViewportConfig);
      expect(s.offsetY, 0);
    });

    test('zoomAt 保持焦点处内容屏幕位置不变（缩放不变量）', () {
      final bounds0 = computeBounds(400, 216, 800, 216, 1);
      final s0 = dragBy(createViewport(), -100, 0, bounds0, defaultViewportConfig);
      final nextScale = 1.5;
      final bounds1 = computeBounds(400, 216, 800, 216, nextScale);
      final s1 = zoomAt(s0, 200, 100, nextScale, bounds1);

      // 缩放前焦点处的内容坐标。
      final contentXBefore = (200 - s0.offsetX) / s0.scale;
      final contentXAfter = (200 - s1.offsetX) / s1.scale;
      expect(contentXAfter, closeTo(contentXBefore, 0.001));
      expect(s1.scale, nextScale);
    });

    test('zoomAt 超出 [0.5, 3] 会被 clamp', () {
      final bounds = computeBounds(400, 216, 800, 216, 5);
      final s = zoomAt(createViewport(), 0, 0, 10, bounds);
      expect(s.scale, 3);
    });

    test('endDrag 低速回到 idle 或 rebound，高速进入 inertia', () {
      final bounds = computeBounds(400, 216, 800, 216, 1);
      final slow = endDrag(createViewport(), 0.001, 0, bounds, defaultViewportConfig);
      expect(slow.phase, ViewportPhase.idle);

      final fast = endDrag(createViewport(), 1.0, 0, bounds, defaultViewportConfig);
      expect(fast.phase, ViewportPhase.inertia);
    });
  });
}
