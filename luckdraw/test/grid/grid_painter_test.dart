import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/src/grid/render/grid_painter.dart';

import '../support/grid_fixtures.dart';
import '../support/recording_canvas.dart';
import 'grid_controller_test.dart' show gridHost;
import 'grid_render_fixtures.dart';

/// 渐变和描边测试色。
const Color _red = Color(0xFFFF0000);

/// 渐变结束色。
const Color _blue = Color(0xFF0000FF);

/// 九宫格合并层与缓存测试。
void main() {
  group('GridCanvasRenderer', () {
    test('each cell has cached normal and active pictures', () {
      final cache = LuckyPictureCache();
      final painter = GridPainter(data: gridSurfaceData(), cache: cache);
      expect(cache.debugRecordCount, 1 + 9 * 2);
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, const Size(300, 300));
      expect(canvas.countCalls(#drawPicture), 10);
      expect(cache.debugRecordCount, 19);
      cache.dispose();
    });
    test(
        'per frame paint replays one cached picture per cell without recording',
        () {
      final frame = GridFrame();
      final cache = LuckyPictureCache();
      final painter =
          GridPainter(data: gridSurfaceData(frame: frame), cache: cache);
      for (var i = 0; i < 30; i++) {
        frame.activeIndex = i.remainder(8);
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, const Size(300, 300));
        expect(canvas.countCalls(#drawPicture), 10);
      }
      expect(cache.debugRecordCount, 19);
      expect(painter.shouldRepaint(painter), isTrue);
      cache.dispose();
    });
    test('gradient background uses legacy endpoints on the shrunk rect', () {
      const fill = LuckyFill.legacyLinear(
          LuckyLegacyGradientDirection.angle(90),
          [LuckyColorStop(_red), LuckyColorStop(_blue)]);
      final config = gridFixture.copyWith(
          prizes: const [GridPrize(x: 0, y: 0)],
          style: const GridStyle(
              cell: LuckyCellStyle(
                  background: fill,
                  shadow: LuckyShadow(offsetX: 12, offsetY: -8, color: _red))));
      final data = gridSurfaceData(config: config);
      final cache = LuckyPictureCache();
      final painter = GridPainter(data: data, cache: cache);
      final canvas = TestRecordingCanvas();
      painter.recordCell(canvas, 0, false);
      final visual = data.layout.cells.first.normal;
      expect(visual.rect.width, data.layout.hitRect(0).width - 12);
      expect(visual.rect.top, data.layout.hitRect(0).top + 8);
      final draws = canvas.invocations
          .where((call) => call.invocation.memberName == #drawPath)
          .toList();
      expect(draws, hasLength(2));
      expect((draws.last.invocation.positionalArguments[1] as Paint).shader,
          isNotNull);
      expect((draws.last.invocation.positionalArguments[0] as Path).getBounds(),
          visual.rect);
      final expected =
          (fill as LuckyLegacyLinearFill).direction.endpoints(visual.rect);
      expect(expected.$1.dx,
          (visual.rect.left + visual.rect.width).truncateToDouble());
      expect(expected.$2.dx, expected.$1.dx);
      expect(expected.$1.dy,
          (visual.rect.top + visual.rect.height).truncateToDouble());
      expect(expected.$2.dy, visual.rect.top.truncateToDouble());
      cache.dispose();
    });
    test('painting never calls saveLayer and keeps save count balanced', () {
      final cache = LuckyPictureCache();
      final painter = GridPainter(data: gridSurfaceData(), cache: cache);
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, const Size(300, 300));
      painter.recordCell(canvas, 0, true);
      canvas.expectBalancedWithoutSaveLayer();
      expect(canvas.countCalls(#drawPicture), 10);
      cache.dispose();
    });
  });
  test(
      'GridPainter images > base loading gates active images and falls back until active loads',
      () async {
    final base = await createGridTestImage(color: _red);
    final active = await createGridTestImage(color: _blue);
    const image = GridImage(AssetImage('base'),
        activeImage: AssetImage('active'),
        width: LuckyLength.percent(50),
        height: LuckyLength.px(20),
        opacity: 0.5,
        borderRadius: 4);
    final config = gridFixture.copyWith(prizes: const [
      GridPrize(x: 0, y: 0, images: [image])
    ]);
    final images = GridTestImages();
    const normalSlot = LuckyImageSlot('prizes', 0, 0);
    const activeSlot = LuckyImageSlot('prizes', 0, 0, active: true);
    images.values[activeSlot] = LuckyResolvedImage(active, const Size(8, 8));
    final cache = LuckyPictureCache();
    final data = gridSurfaceData(config: config, images: images);
    final painter = GridPainter(data: data, cache: cache);
    final notLoaded = TestRecordingCanvas();
    painter.recordCell(notLoaded, 0, true);
    expect(notLoaded.countCalls(#drawImageRect), 0);
    images.values[normalSlot] = LuckyResolvedImage(base, const Size(8, 8));
    final loaded = TestRecordingCanvas();
    painter.recordCell(loaded, 0, true);
    final draw = loaded.invocations
        .singleWhere((call) => call.invocation.memberName == #drawImageRect);
    expect(draw.invocation.positionalArguments.first, active);
    expect((draw.invocation.positionalArguments.last as Paint).filterQuality,
        FilterQuality.low);
    images.values.remove(activeSlot);
    final fallback = TestRecordingCanvas();
    painter.recordCell(fallback, 0, true);
    expect(
        fallback.invocations
            .singleWhere((call) => call.invocation.memberName == #drawImageRect)
            .invocation
            .positionalArguments
            .first,
        base);
    loaded.expectBalancedWithoutSaveLayer();
    cache.dispose();
    base.dispose();
    active.dispose();
  });
  testWidgets(
      'GridPainter layers > static layers cache while dynamic layers and hooks run each frame',
      (tester) async {
    final calls = <String>[];
    var customPaints = 0;
    final config = gridFixture.copyWith(blocks: const [
      LuckyBoxBlock(border: LuckyBorder(width: 2, color: _red))
    ], prizes: [
      GridPrize(
          x: 0,
          y: 0,
          style: const LuckyCellStyle(
              border: LuckyBorder(width: 2, color: _red),
              foreground: gridNormalFill),
          painter: (_, __, ___) => customPaints++)
    ], buttons: [
      GridButton(
          x: 1,
          y: 1,
          painter: (_, __, active) {
            expect(active, isFalse);
            customPaints++;
          })
    ]);
    final cache = LuckyPictureCache();
    final data = gridSurfaceData(
        config: config,
        hooks: LuckyHooks(
            beforeDraw: (_, __) => calls.add('before'),
            afterDraw: (_, __) => calls.add('after')),
        layers: [
          LuckyCallbackLayer<GridLayout, GridFrame>(
              (_, __) => calls.add('static'),
              position: LuckyLayerPosition.background,
              isStatic: true),
          LuckyCallbackLayer<GridLayout, GridFrame>(
              (_, __) => calls.add('below'),
              position: LuckyLayerPosition.belowItems),
          LuckyCallbackLayer<GridLayout, GridFrame>(
              (_, __) => calls.add('above'),
              position: LuckyLayerPosition.aboveItems),
          LuckyCallbackLayer<GridLayout, GridFrame>(
              (_, __) => calls.add('front')),
        ]);
    final painter = GridPainter(data: data, cache: cache);
    expect(customPaints, 4);
    expect(calls, ['static']);
    calls.clear();
    final canvas = TestRecordingCanvas();
    painter.paint(canvas, data.layout.size);
    expect(calls, ['before', 'below', 'above', 'front', 'after']);
    expect(customPaints, 4);
    canvas.expectBalancedWithoutSaveLayer();
    cache.dispose();
  });
  testWidgets(
      'GridCanvasRenderer updates > layout images listeners and controller replacement invalidate caches',
      (tester) async {
    final frames = ChangeNotifier();
    final nextFrames = ChangeNotifier();
    final imageChanges = ChangeNotifier();
    final nextChanges = ChangeNotifier();
    final images = GridTestImages();
    var data = gridSurfaceData(
        frames: frames, imageChanges: imageChanges, images: images);
    late StateSetter rebuild;
    await tester
        .pumpWidget(gridHost(StatefulBuilder(builder: (context, setter) {
      rebuild = setter;
      return const GridCanvasRenderer().buildSurface(context, data);
    })));
    final initial = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter
        as GridPainter;
    final before = initial.cache.debugRecordCount;
    images.generation++;
    imageChanges.notifyListeners();
    await tester.pump();
    expect(initial.cache.debugRecordCount, before * 2);
    rebuild(() => data = gridSurfaceData(
        frames: frames,
        imageChanges: imageChanges,
        images: images,
        generation: 2));
    await tester.pump();
    expect(initial.cache.debugRecordCount, before * 3);
    rebuild(() => data = gridSurfaceData(
        frames: frames,
        imageChanges: imageChanges,
        images: images,
        generation: 2));
    await tester.pump();
    expect(initial.cache.debugRecordCount, before * 3);
    rebuild(() => data = gridSurfaceData(
        frames: nextFrames, imageChanges: nextChanges, images: images));
    await tester.pump();
    expect(tester.widget<CustomPaint>(find.byType(CustomPaint)).painter,
        isNot(same(initial)));
    await tester.pumpWidget(const SizedBox());
    frames.dispose();
    nextFrames.dispose();
    imageChanges.dispose();
    nextChanges.dispose();
  });
}
