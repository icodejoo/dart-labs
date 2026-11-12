import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/lots/render/lots_painter.dart';

import '../support/lots_fixtures.dart';
import '../support/recording_canvas.dart';

/// 验证抽签缓存与画布平衡。
void main() {
  group('LotsCanvasRenderer', () {
    test('stick pictures are recorded once per style', () {
      final n = LuckyFrameNotifier(), cache = LuckyPictureCache();
      addTearDown(n.dispose);
      addTearDown(cache.dispose);
      final data = lotsSurface(n);
      final painter = LotsPainter(data, cache);
      expect(cache.debugRecordCount, 10);
      LotsPainter(data, cache).paint(TestRecordingCanvas(), data.layout.size);
      expect(cache.debugRecordCount, 10);
      expect(painter.shouldRepaint(painter), isFalse);
    });
    test('per frame paint replays cached pictures without recording', () {
      final n = LuckyFrameNotifier(), cache = LuckyPictureCache();
      addTearDown(n.dispose);
      addTearDown(cache.dispose);
      final data = lotsSurface(n);
      final painter = LotsPainter(data, cache);
      for (var i = 0; i < 100; i++) {
        data.frame.shakeDeg = i % 12.0;
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, data.layout.size);
        expect(canvas.countCalls(#drawPicture), 15);
      }
      expect(cache.debugRecordCount, 10);
    });
    test('painting never calls saveLayer and keeps save count balanced', () {
      final n = LuckyFrameNotifier(), cache = LuckyPictureCache();
      addTearDown(n.dispose);
      addTearDown(cache.dispose);
      final data = lotsSurface(n);
      final canvas = TestRecordingCanvas();
      LotsPainter(data, cache).paint(canvas, data.layout.size);
      canvas.expectBalancedWithoutSaveLayer();
    });
  });
}
