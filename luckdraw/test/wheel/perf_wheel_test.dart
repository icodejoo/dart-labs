import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/wheel.dart';

import '../support/recording_canvas.dart';
import 'wheel_render_support.dart';

/// 验证转盘自动缓存、严格兼容和原生资源生命周期。
void main() {
  group('PERF wheel', () {
    testWidgets('auto switches between moving raster and settled picture',
        (tester) async {
      final harness = WheelPainterHarness();
      final original = TestRecordingCanvas();
      harness.painter.paint(original, kWheelRenderSize);
      expect(original.countCalls(#drawImageRect), 0);
      final bytes = harness.cache.debugRasterBytes;
      expect(bytes, 800 * 800 * 4);
      harness.frame.phase = LuckyPhase.cruising;
      harness.frame.rotateDeg = 37;
      final moving = TestRecordingCanvas();
      harness.painter.paint(moving, kWheelRenderSize);
      expect(moving.countCalls(#drawImageRect), 1);
      final records = harness.cache.debugRecordCount;
      harness.frame.phase = LuckyPhase.settled;
      final settled = TestRecordingCanvas();
      harness.painter.paint(settled, kWheelRenderSize);
      expect(settled.countCalls(#drawImageRect), 0);
      expect(
          settled.countCalls(#drawPicture), original.countCalls(#drawPicture));
      expect(harness.cache.debugRecordCount, records);
      expect(harness.cache.debugRasterBytes, bytes);
      moving.expectBalancedWithoutSaveLayer();
    });

    testWidgets('strict upstream frame configuration keeps picture playback',
        (tester) async {
      final config = wheelFromLuckyCanvasConfig({
        'prizes': [<String, Object?>{}, <String, Object?>{}],
      }, options: LuckyCanvasCompatOptions.strictUpstream())
          .config;
      expect(config.options.motion.timebase, LuckyTimebase.frame);
      final harness = WheelPainterHarness(config: config);
      harness.frame.phase = LuckyPhase.cruising;
      final canvas = TestRecordingCanvas();
      harness.painter.paint(canvas, kWheelRenderSize);
      expect(canvas.countCalls(#drawImageRect), 0);
      expect(canvas.countCalls(#drawPicture), greaterThan(0));
      expect(harness.cache.debugRasterBytes, 0);
    });

    testWidgets('repeated mount dispose balances pictures images and tickers',
        (tester) async {
      final createdPictures = <ui.Picture>{};
      final disposedPictures = <ui.Picture>{};
      final createdImages = <ui.Image>{};
      final disposedImages = <ui.Image>{};
      final pictureCreate = ui.Picture.onCreate;
      final pictureDispose = ui.Picture.onDispose;
      final imageCreate = ui.Image.onCreate;
      final imageDispose = ui.Image.onDispose;
      ui.Picture.onCreate = (value) {
        pictureCreate?.call(value);
        createdPictures.add(value);
      };
      ui.Picture.onDispose = (value) {
        pictureDispose?.call(value);
        disposedPictures.add(value);
      };
      ui.Image.onCreate = (value) {
        imageCreate?.call(value);
        createdImages.add(value);
      };
      ui.Image.onDispose = (value) {
        imageDispose?.call(value);
        disposedImages.add(value);
      };
      try {
        for (var cycle = 0; cycle < 10; cycle++) {
          final controller = WheelController();
          await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
              config: wheelRenderFixture(), controller: controller)));
          expect(controller.play(), isTrue);
          await tester.pump(kWheelRenderStep);
          expect(tester.binding.transientCallbackCount, greaterThan(0));
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
          expect(createdPictures.difference(disposedPictures), isEmpty);
          expect(createdImages.difference(disposedImages), isEmpty);
        }
        expect(createdPictures.length, greaterThanOrEqualTo(10));
        expect(createdImages.length, greaterThanOrEqualTo(10));
        expect(disposedPictures.intersection(createdPictures), createdPictures);
        expect(disposedImages.intersection(createdImages), createdImages);
      } finally {
        ui.Picture.onCreate = pictureCreate;
        ui.Picture.onDispose = pictureDispose;
        ui.Image.onCreate = imageCreate;
        ui.Image.onDispose = imageDispose;
      }
    });
  });
}
