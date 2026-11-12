import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/slot/render/slot_atlas.dart';
import 'package:luckdraw/src/slot/render/slot_painter.dart';

import '../support/recording_canvas.dart';
import '../support/slot_fixtures.dart';

/// 将真实画布回放为像素，以检查图集源格和目标位置。
Future<ByteData> _pixels(SlotPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), slotTestSize);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(
      slotTestSize.width.toInt(), slotTestSize.height.toInt());
  try {
    return (await image.toByteData())!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 分页、源裁剪、回退与表面资源生命周期。
void main() {
  group('SlotAtlas', () {
    testWidgets(
        'raster pixels match vector replay across modes and wrapped orders',
        (tester) async {
      for (final mode in SlotMode.values) {
        final config = slotTestConfig.copyWith(
            prizes:
                slotTestPrizes.map((p) => p.copyWith(texts: const [])).toList(),
            reels: [
              const SlotReel(order: [2, 0, 1]),
              const SlotReel(order: [1, 99, 0]),
              const SlotReel()
            ],
            options: slotTestConfig.options.copyWith(
                mode: mode,
                cellAspectRatio: 1.4,
                rowSpacing: 5,
                colSpacing: 8));
        final vector = slotSurfaceData(config: config);
        vector.frame.scroll.setAll(0, [-375.0, 92.0, 1000.0]);
        final raster = slotSurfaceData(
            config: config,
            frame: vector.frame,
            devicePixelRatio: 1.25,
            performance: const LuckyPerformanceOptions(
                cacheMode: LuckyCacheMode.raster, maxRasterSide: 250));
        final cache = LuckyPictureCache();
        final atlas = SlotAtlas();
        addTearDown(cache.dispose);
        addTearDown(atlas.dispose);
        final a = SlotPainter(vector, cache);
        final b = SlotPainter(raster, cache, atlas: atlas);
        await tester.runAsync(() async {
          final expected = await _pixels(a);
          final actual = await _pixels(b);
          var checked = 0;
          const width = 300;
          const channels = 4;
          // 位图双线性采样会改变边缘抗锯齿；只比较离颜色边界至少两像素的内部。
          for (var y = 2; y < 178; y += 3) {
            for (var x = 2; x < 298; x += 3) {
              final p = (y * width + x) * channels;
              final pixel = expected.getUint32(p);
              var interior = true;
              for (var dy = -2; dy <= 2; dy++) {
                for (var dx = -2; dx <= 2; dx++) {
                  if (expected.getUint32(p + (dy * width + dx) * channels) !=
                      pixel) {
                    interior = false;
                  }
                }
              }
              if (!interior) continue;
              checked++;
              for (var c = 0; c < channels; c++) {
                expect(actual.getUint8(p + c),
                    closeTo(expected.getUint8(p + c), 2),
                    reason: '${mode.name} ($x,$y)');
              }
            }
          }
          expect(checked, greaterThan(2000));
        });
      }
    });
    testWidgets(
        'pages respect the pixel limit and clip every sprite to its reel',
        (tester) async {
      for (final mode in SlotMode.values) {
        final config = slotTestConfig.copyWith(
            prizes: List.filled(50, slotTestPrizes.first),
            reels: [
              const SlotReel(),
              const SlotReel(order: []),
              const SlotReel(order: [0, 99, 2])
            ],
            options: slotTestConfig.options
                .copyWith(mode: mode, rowSpacing: 7, colSpacing: 8));
        final data = slotSurfaceData(
            config: config,
            devicePixelRatio: 1.25,
            performance: const LuckyPerformanceOptions(
                cacheMode: LuckyCacheMode.raster, maxRasterSide: 250));
        final cache = LuckyPictureCache();
        final atlas = SlotAtlas();
        addTearDown(cache.dispose);
        addTearDown(atlas.dispose);
        final painter = SlotPainter(data, cache, atlas: atlas);
        expect(atlas.pageSizes.length, greaterThan(1));
        expect(atlas.pageSizes.every((s) => s.width <= 250 && s.height <= 250),
            isTrue);
        const scrolls = [-999.0, 0.0, 301.0, 50000.0];
        for (final scroll in scrolls) {
          data.frame.scroll.fillRange(0, 3, scroll);
          final canvas = TestRecordingCanvas();
          painter.paint(canvas, data.layout.size);
          expect(canvas.countCalls(#drawRawAtlas), atlas.pageSizes.length);
          expect(canvas.countCalls(#drawPicture), 0);
          expect(canvas.countCalls(#clipRect), 0);
          var visible = 0;
          for (final call in canvas.invocations
              .where((c) => c.invocation.memberName == #drawRawAtlas)) {
            final args = call.invocation.positionalArguments;
            final image = args[0] as ui.Image;
            final transforms = args[1] as Float32List;
            final rects = args[2] as Float32List;
            for (var p = 0; p < rects.length; p += 4) {
              if (rects[p + 2] == rects[p]) continue;
              visible++;
              expect(rects[p], greaterThanOrEqualTo(0));
              expect(rects[p + 1], greaterThanOrEqualTo(0));
              expect(rects[p + 2], lessThanOrEqualTo(image.width + 0.001));
              expect(rects[p + 3], lessThanOrEqualTo(image.height + 0.001));
              final x = transforms[p + 2];
              final y = transforms[p + 3];
              final right = x + (rects[p + 2] - rects[p]) * transforms[p];
              final bottom = y + (rects[p + 3] - rects[p + 1]) * transforms[p];
              expect(
                  data.layout.reels.any((r) =>
                      x >= r.clipRect.left - 0.001 &&
                      y >= r.clipRect.top - 0.001 &&
                      right <= r.clipRect.right + 0.001 &&
                      bottom <= r.clipRect.bottom + 0.001),
                  isTrue);
            }
          }
          expect(visible, greaterThan(0));
        }
      }
    });
    testWidgets(
        'oversized cells fall back and reconfiguration releases old pages',
        (tester) async {
      final cache = LuckyPictureCache();
      final atlas = SlotAtlas();
      addTearDown(cache.dispose);
      addTearDown(atlas.dispose);
      final data = slotSurfaceData(
          performance:
              const LuckyPerformanceOptions(cacheMode: LuckyCacheMode.raster));
      SlotPainter(data, cache, atlas: atlas);
      expect(atlas.pageSizes, isNotEmpty);
      final small = slotSurfaceData(
          performance: const LuckyPerformanceOptions(
              cacheMode: LuckyCacheMode.raster, maxRasterSide: 10));
      final painter = SlotPainter(small, cache, atlas: atlas);
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, small.layout.size);
      expect(atlas.pageSizes, isEmpty);
      expect(canvas.countCalls(#drawRawAtlas), 0);
      expect(canvas.countCalls(#drawPicture), greaterThan(0));
      final empty = slotSurfaceData(
          config: const SlotConfig(), performance: data.performance);
      SlotPainter(empty, cache, atlas: atlas)
          .paint(TestRecordingCanvas(), empty.layout.size);
      expect(atlas.pageSizes, isEmpty);
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
              builder: (context) =>
                  const SlotCanvasRenderer().buildSurface(context, data))));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });
}
