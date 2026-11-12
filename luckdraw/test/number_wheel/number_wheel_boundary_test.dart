import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/src/number_wheel/motion/number_wheel_motion.dart';
import 'package:luckdraw/src/number_wheel/render/number_wheel_painter.dart';

import '../support/number_wheel_fixtures.dart';
import '../support/recording_canvas.dart';

/// 用于检查 SPI 默认时间轴上限的最小实现。
final class _DefaultMotionProbe extends LuckyMotion<NumberWheelConfig,
    NumberWheelLayout, NumberWheelFrame, LuckyResult<NumberWheelPocket>> {
  /// 保留基类已实现的默认行为，其余未调用成员明确抛错。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 验证防御分支、玩法 SPI、层回放和缓存失效。
void main() {
  test(
      'number wheel boundaries > missing layouts frame timebase and structural changes are safe',
      () {
    final empty = NumberWheelMotion();
    expect(empty.start(), isFalse);
    expect(empty.idleSpin(), isFalse);
    expect(
        _DefaultMotionProbe().maxFrameDelta, const Duration(milliseconds: 100));
    final config = numberWheelFixture.copyWith(
        options: numberWheelFixture.options.copyWith(
            motion:
                numberWheelTestMotion.copyWith(timebase: LuckyTimebase.frame)));
    final m = numberWheelMotion(config);
    cruiseNumberWheel(m);
    m.stop(1);
    settleNumberWheel(m);
    expect(m.takeResult()?.index, 1);
    expect(m.idleSpin(), isTrue);
    expect(m.idleSpin(), isFalse);
    m.tick(10, double.nan);
    expect(m.frame.discDeg.isFinite, isTrue);
    m.configure(const NumberWheelConfig(pockets: []),
        numberWheelLayout(const NumberWheelConfig(pockets: [])));
    expect(m.phase, LuckyPhase.idle);
    const game = NumberWheelGame();
    final controller = game.createController();
    controller.dispose();
    expect(
        game.isStructuralChange(
            numberWheelFixture, const NumberWheelConfig(pockets: [])),
        isTrue);
    expect(game.isStructuralChange(numberWheelFixture, numberWheelFixture),
        isFalse);
    expect(
        game.hitTestAll(numberWheelFixture, numberWheelLayout(),
            NumberWheelFrame(), Offset.zero),
        isEmpty);
  });
  testWidgets(
      'number wheel rendering > static dynamic layers and image generations invalidate cached pictures',
      (tester) async {
    final notifier = LuckyFrameNotifier(), images = NumberWheelTestImages();
    addTearDown(notifier.dispose);
    var staticPaints = 0, dynamicPaints = 0, before = 0, after = 0;
    final hooks = LuckyHooks(
        beforeDraw: (_, __) => before++, afterDraw: (_, __) => after++);
    final staticLayer = LuckyCallbackLayer<NumberWheelLayout, NumberWheelFrame>(
        (canvas, context) {
      staticPaints++;
      expect(context.layout.count, 3);
    }, isStatic: true, position: LuckyLayerPosition.background);
    final moving = LuckyCallbackLayer<NumberWheelLayout, NumberWheelFrame>(
        (canvas, context) {
      dynamicPaints++;
      expect(context.frame.discDeg.isFinite, isTrue);
    }, rotatesWithWheel: true, position: LuckyLayerPosition.foreground);
    final data = numberWheelSurface(notifier,
        images: images, hooks: hooks, layers: [staticLayer, moving]);
    final cache = LuckyPictureCache();
    addTearDown(cache.dispose);
    final painter = NumberWheelPainter(data, cache),
        canvas = TestRecordingCanvas();
    painter.paint(canvas, data.layout.size);
    painter.paint(canvas, data.layout.size);
    expect(staticPaints, 1);
    expect(dynamicPaints, 2);
    expect(before, 2);
    expect(after, 2);
    canvas.expectBalancedWithoutSaveLayer();

    /// 挂接同一个渲染表面，观察低频版本变更。
    Future<NumberWheelPainter> pump(
        LuckySurfaceData<NumberWheelConfig, NumberWheelLayout, NumberWheelFrame>
            input) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
              builder: (context) => const NumberWheelCanvasRenderer()
                  .buildSurface(context, input))));
      return tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
          as NumberWheelPainter;
    }

    final first = await pump(data);
    final count = first.cache.debugRecordCount;
    await pump(data);
    expect(first.cache.debugRecordCount, count);
    final changedLayer =
        LuckyCallbackLayer<NumberWheelLayout, NumberWheelFrame>((_, __) {},
            isStatic: true, position: LuckyLayerPosition.aboveItems);
    final second = await pump(numberWheelSurface(notifier,
        images: images, layers: [changedLayer, moving]));
    expect(second.cache.debugRecordCount, greaterThan(count));
    expect(second.shouldRepaint(first), isTrue);
    final previous = second.cache.debugRecordCount;
    images.generation++;
    final third = await pump(numberWheelSurface(notifier,
        images: images, layers: [changedLayer, moving]));
    expect(third.cache.debugRecordCount, greaterThan(previous));
    await tester.pumpWidget(const SizedBox());
  });
}
