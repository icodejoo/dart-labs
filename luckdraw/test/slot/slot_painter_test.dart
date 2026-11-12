import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/slot/render/slot_atlas.dart';
import 'package:luckdraw/src/slot/render/slot_painter.dart';

import '../support/recording_canvas.dart';
import '../support/slot_fixtures.dart';

/// 创建测试拥有的单像素图片。
ui.Image _image() {
  final r = ui.PictureRecorder();
  final c = Canvas(r);
  c.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final p = r.endRecording();
  final image = p.toImageSync(1, 1);
  p.dispose();
  return image;
}

/// 验证可见窗口调用、缓存与资源更新。
void main() {
  group('SlotCanvasRenderer', () {
    testWidgets('draws only visible cells per reel clipped to the reel rect',
        (tester) async {
      final data = slotSurfaceData(
          config: slotTestConfig.copyWith(
              prizes: List.filled(50, slotTestPrizes.first)));
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      final painter = SlotPainter(data, cache);
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, data.layout.size);
      expect(canvas.countCalls(#clipRect), 3);
      expect(canvas.countCalls(#drawPicture),
          lessThanOrEqualTo(1 + 3 * data.layout.reels.first.maxVisibleCells));
      final clips = canvas.invocations
          .where((r) => r.invocation.memberName == #clipRect)
          .map((r) => r.invocation.positionalArguments.first);
      expect(clips, data.layout.reels.map((r) => r.clipRect));
    });
    testWidgets(
        'per frame paint replays cached cell pictures without recording',
        (tester) async {
      var records = 0;
      final config = slotTestConfig.copyWith(
          prizes: slotTestPrizes
              .map((p) => p.copyWith(painter: (_, __, ___) {
                    records++;
                  }))
              .toList());
      final images = SlotTestImages();
      final data = slotSurfaceData(config: config, images: images);
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      final painter = SlotPainter(data, cache);
      expect(records, 3);
      final count = cache.debugRecordCount;
      for (var i = 0; i < 100; i++) {
        data.frame.scroll[0] = i.toDouble();
        painter.paint(TestRecordingCanvas(), data.layout.size);
      }
      expect(records, 3);
      expect(cache.debugRecordCount, count);
      final same = SlotPainter(data, cache);
      expect(same.shouldRepaint(painter), isFalse);
      final changed =
          SlotPainter(slotSurfaceData(config: config, generation: 2), cache);
      expect(changed.shouldRepaint(painter), isTrue);
      images.generation++;
      final newImages = SlotPainter(data, cache);
      expect(newImages.shouldRepaint(painter), isTrue);
    });
    testWidgets('wrap-around draws the first prizes after the last',
        (tester) async {
      final data = slotSurfaceData(
          config: slotTestConfig.copyWith(reels: [
        const SlotReel(),
        const SlotReel(order: []),
        const SlotReel(order: [0, 99, 2])
      ]));
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      final painter = SlotPainter(data, cache);
      final canvas = TestRecordingCanvas();
      data.frame.scroll[0] =
          data.layout.reels.first.period + data.layout.cellAndSpacing * 2;
      painter.paint(canvas, data.layout.size);
      final pictures = canvas.invocations
          .where((r) => r.invocation.memberName == #drawPicture)
          .map((r) => r.invocation.positionalArguments.first)
          .toList();
      expect(
          pictures,
          containsAllInOrder([
            cache.picture(2002, (_) => fail('已缓存')),
            cache.picture(2000, (_) => fail('已缓存'))
          ]));
      expect(canvas.countCalls(#clipRect), 2);
      data.frame.scroll[0] = -data.layout.reels.first.period * 2;
      painter.paint(TestRecordingCanvas(), data.layout.size);
      expect(cache.debugRecordCount, 4);
    });
    testWidgets(
        'raster mode draws visible cells with one drawAtlas call per frame',
        (tester) async {
      final atlas = SlotAtlas();
      final cache = LuckyPictureCache();
      addTearDown(atlas.dispose);
      addTearDown(cache.dispose);
      final data = slotSurfaceData(
          performance:
              const LuckyPerformanceOptions(cacheMode: LuckyCacheMode.raster));
      final painter = SlotPainter(data, cache, atlas: atlas);
      expect(atlas.pageSizes, hasLength(1));
      for (var i = 0; i < 10; i++) {
        data.frame.scroll[0] = i * 31.0;
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, data.layout.size);
        expect(canvas.countCalls(#drawRawAtlas), 1);
        expect(canvas.countCalls(#drawPicture), 0);
        expect(canvas.countCalls(#clipRect), 0);
      }
      final same = SlotPainter(data, cache, atlas: atlas);
      expect(same.shouldRepaint(painter), isFalse);
    });
    testWidgets('painting never calls saveLayer and keeps save count balanced',
        (tester) async {
      for (final mode in SlotMode.values) {
        final data = slotSurfaceData(
            config: slotTestConfig.copyWith(
                options: slotTestConfig.options.copyWith(mode: mode)));
        final cache = LuckyPictureCache();
        addTearDown(cache.dispose);
        final painter = SlotPainter(data, cache);
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, data.layout.size);
        canvas.expectBalancedWithoutSaveLayer();
      }
      final empty = slotSurfaceData(config: const SlotConfig());
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      final canvas = TestRecordingCanvas();
      SlotPainter(empty, cache).paint(canvas, empty.layout.size);
      canvas.expectBalancedWithoutSaveLayer();
    });
    testWidgets(
        'recording respects cell blocks images text borders and layer positions',
        (tester) async {
      final image = _image();
      addTearDown(image.dispose);
      const img = LuckyImage(AssetImage('unused.png'),
          width: LuckyLength.px(10), height: LuckyLength.px(10));
      const fill = LuckyFill.color(Color(0xFF112233));
      final config = slotTestConfig.copyWith(
          blocks: [
            const LuckyBoxBlock(
                background: fill,
                border: LuckyBorder(width: 2, color: Color(0xFF112233)),
                images: [img])
          ],
          style: const SlotStyle(
              cell: LuckyCellStyle(
                  border: LuckyBorder(width: 1, color: Color(0xFF112233)),
                  foreground: fill)),
          prizes: [
            const SlotPrize(
                background: fill,
                texts: [LuckyText('A\n\nB', wordWrap: false)],
                images: [img, img])
          ]);
      final images = SlotTestImages();
      images.values[const LuckyImageSlot('prizes', 0, 0)] =
          LuckyResolvedImage(image, const Size(1, 1));
      images.values[const LuckyImageSlot('blocks', 0, 0)] =
          LuckyResolvedImage(image, const Size(1, 1));
      final order = <String>[];
      final data = slotSurfaceData(
          config: config,
          images: images,
          layers: [
            for (final pos in LuckyLayerPosition.values)
              LuckyCallbackLayer((c, ctx) {
                order.add(pos.name);
                expect(ctx.layout, isA<SlotLayout>());
              }, position: pos),
            LuckyCallbackLayer((c, ctx) {
              order.add('static');
            }, isStatic: true),
          ],
          hooks: LuckyHooks(
              beforeDraw: (_, __) => order.add('before'),
              afterDraw: (_, __) => order.add('after')));
      final cache = LuckyPictureCache();
      addTearDown(cache.dispose);
      final painter = SlotPainter(data, cache);
      expect(order, ['static']);
      order.clear();
      painter.paint(TestRecordingCanvas(), data.layout.size);
      expect(order, [
        'before',
        'background',
        'belowItems',
        'aboveItems',
        'foreground',
        'after'
      ]);
      final requests = const SlotGame().collectImages(config, data.layout);
      expect(requests, hasLength(3));
      expect(requests.first.decodeLogicalWidth, 10);
      expect(requests.last.decodeLogicalHeight, 10);
      final noFill = config.copyWith(
          blocks: [const LuckyBoxBlock()],
          style: const SlotStyle(cell: LuckyCellStyle()),
          prizes: [const SlotPrize()]);
      cache.invalidateAll();
      SlotPainter(slotSurfaceData(config: noFill), cache)
          .paint(TestRecordingCanvas(), data.layout.size);
      expect(cache.debugRecordCount, greaterThan(4));
    });
    testWidgets(
        'surface updates invalidate pictures and image listeners without frame rebuilds',
        (tester) async {
      final images = SlotTestImages();
      final changes = ChangeNotifier();
      final other = ChangeNotifier();
      final frames = ChangeNotifier();
      addTearDown(changes.dispose);
      addTearDown(other.dispose);
      addTearDown(frames.dispose);
      var records = 0;
      final config = slotTestConfig.copyWith(prizes: [
        SlotPrize(painter: (_, __, ___) {
          records++;
        })
      ]);
      final layers = <LuckyLayer<SlotLayout, SlotFrame>>[
        LuckyCallbackLayer((_, __) {}, isStatic: true)
      ];
      Future<void> pump(
          {int generation = 1,
          Listenable? listen,
          List<LuckyLayer<SlotLayout, SlotFrame>>? customLayers}) async {
        final data = slotSurfaceData(
            config: config,
            generation: generation,
            images: images,
            imagesListenable: listen ?? changes,
            frames: frames,
            layers: customLayers ?? layers);
        await tester.pumpWidget(Directionality(
            textDirection: TextDirection.ltr,
            child: const SlotCanvasRenderer().buildSurface(
                tester.element(find.byType(Directionality).first), data)));
      }

      await tester.pumpWidget(const Directionality(
          textDirection: TextDirection.ltr, child: SizedBox()));
      await pump();
      expect(records, 1);
      frames.notifyListeners();
      await tester.pump();
      expect(records, 1);
      await pump();
      expect(records, 1);
      changes.notifyListeners();
      await tester.pump();
      expect(records, 2);
      images.generation++;
      await pump();
      expect(records, 3);
      await pump(generation: 2, listen: other);
      expect(records, 4);
      await pump(generation: 2, listen: other, customLayers: []);
      expect(records, 5);
      await pump(
          generation: 2,
          listen: other,
          customLayers: [LuckyCallbackLayer((_, __) {}, isStatic: true)]);
      expect(records, 6);
      await pump(
          generation: 2,
          listen: other,
          customLayers: [LuckyCallbackLayer((_, __) {}, isStatic: true)]);
      expect(records, 7);
      await tester.pumpWidget(const SizedBox());
      changes.notifyListeners();
      other.notifyListeners();
      expect(tester.takeException(), isNull);
    });
  });
}
