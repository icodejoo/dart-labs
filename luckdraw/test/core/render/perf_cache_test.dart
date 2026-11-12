import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/core/render/cached_picture.dart';

import '../../support/recording_canvas.dart';

/// 验证自动缓存的阶段选择、物理尺寸、采样、失效和原生资源所有权。
void main() {
  group('PERF cache', () {
    test('auto replays raster only while moving and honors filter quality', () {
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      const bounds = ui.Rect.fromLTWH(-4, -3, 8, 6);
      final playback = LuckyCachedPicture(
          cache,
          0,
          bounds,
          2,
          (canvas) => canvas.drawRect(bounds, ui.Paint()),
          const LuckyPerformanceOptions(filterQuality: FilterQuality.medium));
      expect(playback.mode, LuckyCacheMode.auto);
      expect(playback.bounds, bounds);
      expect(playback.picture, same(cache.picture(0, (_) => fail('重复录制'))));
      expect(cache.debugRasterBytes, 16 * 12 * 4);
      final moving = TestRecordingCanvas();
      playback.paint(moving, isMoving: true);
      final call = moving.invocations.single.invocation;
      expect(call.memberName, #drawImageRect);
      expect(call.positionalArguments[1], const ui.Rect.fromLTWH(0, 0, 16, 12));
      expect(call.positionalArguments[2], bounds);
      expect((call.positionalArguments[3]! as ui.Paint).filterQuality,
          FilterQuality.medium);
      final idle = TestRecordingCanvas();
      playback.paint(idle, isMoving: false);
      expect(idle.invocations.single.invocation.memberName, #drawPicture);
      expect(cache.debugRecordCount, 1);
      moving.expectBalancedWithoutSaveLayer();
      idle.expectBalancedWithoutSaveLayer();
    });

    test('explicit modes and oversized segments preserve vector fallback', () {
      final modes = [LuckyCacheMode.picture, LuckyCacheMode.raster];
      for (final mode in modes) {
        final cache = LuckyPictureCache();
        final playback = LuckyCachedPicture(
            cache,
            0,
            const ui.Rect.fromLTWH(0, 0, 8, 8),
            1,
            (_) {},
            LuckyPerformanceOptions(cacheMode: mode));
        final canvas = TestRecordingCanvas();
        playback.paint(canvas, isMoving: false);
        expect(canvas.invocations.single.invocation.memberName,
            mode == LuckyCacheMode.picture ? #drawPicture : #drawImageRect);
        cache.dispose();
        expect(playback.picture.debugDisposed, isTrue);
        expect(cache.debugRasterBytes, 0);
      }
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      final oversized = LuckyCachedPicture(
          cache,
          0,
          const ui.Rect.fromLTWH(0, 0, 8, 8),
          2,
          (_) {},
          const LuckyPerformanceOptions(maxRasterSide: 8));
      final canvas = TestRecordingCanvas();
      oversized.paint(canvas, isMoving: true);
      expect(canvas.invocations.single.invocation.memberName, #drawPicture);
      expect(cache.debugRasterBytes, 0);
    });

    test('origin and DPR changes rebuild even at identical rounded pixel size',
        () {
      final cache = LuckyPictureCache(mode: LuckyCacheMode.auto);
      addTearDown(cache.dispose);
      const size = ui.Size(2, 2);
      final first = cache.raster(0, size, 1.1, (_) {})!;
      final samePixels = cache.raster(0, size, 1.2, (_) => fail('重复录制'))!;
      expect(first.debugDisposed, isTrue);
      expect(samePixels.width, first.width);
      final moved = cache.raster(0, size, 1.2, (_) => fail('重复录制'),
          origin: const ui.Offset(-1, -1))!;
      expect(samePixels.debugDisposed, isTrue);
      expect(
          cache.raster(0, size, 1.2, (_) => fail('重复录制'),
              origin: const ui.Offset(-1, -1)),
          same(moved));
      expect(cache.debugRasterBytes, 3 * 3 * 4);
      cache.invalidate(0);
      expect(moved.debugDisposed, isTrue);
      expect(cache.debugRasterBytes, 0);
      expect(cache.debugRecordCount, 1);
    });

    testWidgets('negative origins retain the complete centered sprite',
        (tester) async {
      final cache = LuckyPictureCache(mode: LuckyCacheMode.auto);
      addTearDown(cache.dispose);
      final image = cache.raster(0, const ui.Size(4, 4), 2, (canvas) {
        canvas.drawRect(const ui.Rect.fromLTWH(-2, -2, 4, 4),
            ui.Paint()..color = const ui.Color(0xFFFF0000));
      }, origin: const ui.Offset(-2, -2))!;
      final bytes = await tester.runAsync(image.toByteData);
      expect(bytes, isNotNull);
      final pixels = bytes!.buffer.asUint8List();
      expect(pixels.length, 8 * 8 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        expect(pixels.sublist(i, i + 4), [255, 0, 0, 255]);
      }
    });
  });
}
