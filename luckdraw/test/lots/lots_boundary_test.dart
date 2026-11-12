import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/src/lots/motion/lots_motion.dart';
import 'package:luckdraw/src/lots/render/lots_painter.dart';

import '../support/fixtures.dart';
import '../support/lots_fixtures.dart';
import '../support/recording_canvas.dart';

/// 验证布局缺失、槽位命中、图片请求和缓存失效。
void main() {
  test(
      'lots boundaries > missing layouts optional reveal and transformed stick hits are safe',
      () {
    final empty = LotsMotion();
    expect(empty.start(), isFalse);
    expect(empty.idleSpin(), isFalse);
    expect(empty.passedReel, 0);
    expect(empty.passedIndex, -1);
    final config = lotsFixture.copyWith(
        options: lotsFixture.options.copyWith(
            revealOnSettle: false,
            motion: lotsFixture.options.motion
                .copyWith(timebase: LuckyTimebase.frame)));
    final m = lotsMotion(config);
    cruiseLots(m);
    m.stop(4);
    settleLots(m);
    expect(m.frame.revealProgress, 0);
    expect(m.frame.riseProgress, 1);
    expect(m.takeResult()?.index, 1);
    const game = LotsGame();
    final l = lotsLayout(config);
    final mouth = l.cylinder.topCenter,
        delta = l.raisedStick(1).bottomCenter -
            const Offset(0, 1) -
            l.cylinder.topCenter;
    final angle = l.angles[1];
    final point = mouth +
        Offset(delta.dx * math.cos(angle) - delta.dy * math.sin(angle),
            delta.dx * math.sin(angle) + delta.dy * math.cos(angle));
    expect(game.hitTestAll(config, l, m.frame, point).single.index, 1);
    expect(
        game.hitTestAll(config, lotsLayout(config, Size.zero), m.frame, point),
        isEmpty);
    expect(game.hitTestAll(config, l, m.frame, Offset.zero), isEmpty);
    expect(game.isStructuralChange(config, config), isFalse);
    expect(game.isStructuralChange(config, const LotsConfig()), isTrue);
    expect(
        game.isStructuralChange(
            config,
            config.copyWith(
                options: config.options.copyWith(visibleSticks: 1))),
        isTrue);
    final controller = game.createController();
    controller.dispose();
    expect(m.idleSpin(), isTrue);
    expect(m.idleSpin(), isFalse);
    m.tick(1, double.nan);
    expect(m.frame.shakeDeg.isFinite, isTrue);
    m.configure(const LotsConfig(), lotsLayout(const LotsConfig()));
    expect(m.phase, LuckyPhase.idle);
  });
  testWidgets(
      'lots rendering > cards images layers and version changes preserve cached replay',
      (tester) async {
    final notifier = LuckyFrameNotifier(), images = LotsTestImages();
    addTearDown(notifier.dispose);
    final image = await createLuckyTestImage(
        color: const Color(0xFF009988), width: 8, height: 8);
    addTearDown(image.dispose);
    const item = LuckyImage(AssetImage('unused.png'),
        width: LuckyLength.px(20), height: LuckyLength.px(12));
    var custom = 0, staticPaints = 0, dynamicPaints = 0, before = 0, after = 0;
    final config = lotsFixture.copyWith(sticks: [
      LotsStick(
          label: 'A',
          images: const [item, item],
          texts: const [LuckyText('Card')],
          painter: (_, bounds) {
            custom++;
            expect(bounds.width, greaterThan(0));
          })
    ]);
    images.values[const LuckyImageSlot('sticks', 0, 0)] =
        LuckyResolvedImage(image, const Size(8, 8));
    final requests = const LotsGame().collectImages(config, lotsLayout(config));
    expect(requests, hasLength(2));
    expect(requests.first.decodeLogicalWidth, 20);
    expect(requests.first.decodeLogicalHeight, 12);
    final frame = LotsFrame()
      ..phase = LuckyPhase.settled
      ..targetIndex = 0
      ..targetSlot = 0
      ..riseProgress = 1
      ..revealProgress = 1;
    final staticLayer = LuckyCallbackLayer<LotsLayout, LotsFrame>((_, context) {
      staticPaints++;
      expect(context.layout.sticks, isNotEmpty);
    }, isStatic: true, position: LuckyLayerPosition.background);
    final dynamicLayer =
        LuckyCallbackLayer<LotsLayout, LotsFrame>((_, context) {
      dynamicPaints++;
      expect(context.frame, same(frame));
    }, position: LuckyLayerPosition.foreground);
    final data = lotsSurface(notifier,
        config: config,
        frame: frame,
        images: images,
        layers: [staticLayer, dynamicLayer],
        hooks: LuckyHooks(
            beforeDraw: (_, __) => before++, afterDraw: (_, __) => after++));
    final cache = LuckyPictureCache();
    addTearDown(cache.dispose);
    final painter = LotsPainter(data, cache), canvas = TestRecordingCanvas();
    painter.paint(canvas, data.layout.size);
    painter.paint(canvas, data.layout.size);
    canvas.expectBalancedWithoutSaveLayer();
    expect(custom, 1);
    expect(staticPaints, 1);
    expect(dynamicPaints, 2);
    expect(before, 2);
    expect(after, 2);

    /// 重建同一个表面以检查持有缓存与版本失效。
    Future<LotsPainter> pump(
        LuckySurfaceData<LotsConfig, LotsLayout, LotsFrame> input) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
              builder: (context) =>
                  const LotsCanvasRenderer().buildSurface(context, input))));
      return tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
          as LotsPainter;
    }

    final first = await pump(data);
    final count = first.cache.debugRecordCount;
    await pump(data);
    expect(first.cache.debugRecordCount, count);
    final changedLayer = LuckyCallbackLayer<LotsLayout, LotsFrame>((_, __) {},
        isStatic: true, position: LuckyLayerPosition.aboveItems);
    final nextData = lotsSurface(notifier,
        config: config,
        frame: frame,
        images: images,
        layers: [changedLayer, dynamicLayer]);
    final second = await pump(nextData);
    expect(second.cache.debugRecordCount, greaterThan(count));
    expect(second.shouldRepaint(first), isTrue);
    final previous = second.cache.debugRecordCount;
    images.generation++;
    final third = await pump(nextData);
    expect(third.cache.debugRecordCount, greaterThan(previous));
    await tester.pumpWidget(const SizedBox());
  });
}
