import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/number_wheel/model/number_wheel_config.dart';
import 'package:luckdraw/src/number_wheel/render/number_wheel_painter.dart';

import '../support/number_wheel_fixtures.dart';
import '../support/recording_canvas.dart';

/// 验证显示列表录制次数与画布变换平衡。
void main() {
  group('NumberWheelCanvasRenderer', () {
    test('a 200 pocket disc records its static segments once', () {
      final notifier = LuckyFrameNotifier();
      final cache = LuckyPictureCache();
      addTearDown(notifier.dispose);
      addTearDown(cache.dispose);
      final data =
          numberWheelSurface(notifier, config: NumberWheelConfig.range(0, 199));
      final painter = NumberWheelPainter(data, cache);
      expect(cache.debugRecordCount, 3);
      NumberWheelPainter(data, cache)
          .paint(TestRecordingCanvas(), data.layout.size);
      expect(cache.debugRecordCount, 3);
      expect(painter.shouldRepaint(painter), isFalse);
    });
    test('per frame paint replays the disc and ball pictures without recording',
        () {
      final notifier = LuckyFrameNotifier();
      final cache = LuckyPictureCache();
      addTearDown(notifier.dispose);
      addTearDown(cache.dispose);
      final data = numberWheelSurface(notifier);
      final painter = NumberWheelPainter(data, cache);
      for (var i = 0; i < 100; i++) {
        data.frame.discDeg += 1;
        data.frame.ballDeg -= 2;
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, data.layout.size);
        expect(canvas.countCalls(#drawPicture), 3);
      }
      expect(cache.debugRecordCount, 3);
    });
    test('painting never calls saveLayer and keeps save count balanced', () {
      final notifier = LuckyFrameNotifier();
      final cache = LuckyPictureCache();
      addTearDown(notifier.dispose);
      addTearDown(cache.dispose);
      final data = numberWheelSurface(notifier);
      final canvas = TestRecordingCanvas();
      NumberWheelPainter(data, cache).paint(canvas, data.layout.size);
      canvas.expectBalancedWithoutSaveLayer();
    });
  });
}
