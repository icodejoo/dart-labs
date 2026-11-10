import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/slot/motion/slot_motion.dart';
import 'package:luckdraw/src/slot/render/slot_atlas.dart';
import 'package:luckdraw/src/slot/render/slot_painter.dart';
import '../support/slot_fixtures.dart';

/// 将回放结果转为逻辑像素。
Future<ByteData> _pixels(SlotPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), slotTestSize);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(300, 180);
  try {
    return (await image.toByteData())!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 多列、回调与图集缺陷回归。
void main() {
  test('F2 slot reel count changes cancel instead of settling invalid targets',
      () {
    final m = SlotMotion()
      ..configure(slotTestConfig, slotLayout())
      ..start()
      ..requestStop([1, 1, 1]);
    final next =
        slotTestConfig.copyWith(reels: [const SlotReel(), const SlotReel()]);
    m.configure(next, slotLayout(next));
    for (var i = 0; i < 20; i++) {
      m.tick(i * 16, 16);
    }
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
    expect(m.frame.targets, [-1, -1]);
  });
  test('F2 slot strict first deceleration frame equals stopScroll', () {
    final config = slotTestConfig.copyWith(
        options: slotTestConfig.options.copyWith(
            motion: slotTestMotion.copyWith(
                stopSolver: const UpstreamStopSolver())));
    final m = SlotMotion()
      ..configure(config, slotLayout(config))
      ..start()
      ..tick(0, 0)
      ..tick(32, 32)
      ..requestStop([1, 1, 1])
      ..tick(48, 16);
    final before = m.frame.scroll.toList();
    m.tick(64, 16);
    expect(before.first, isNot(0));
    expect(m.frame.scroll, before);
    expect(m.frame.scroll, m.stopScroll);
  });
  test('F2 slot huge positive targets normalize before Int32 storage', () {
    final h = SlotHarness();
    addTearDown(h.dispose);
    h.cruise();
    expect(h.controller.stop(4294967297), isTrue);
    h.settle();
    expect(h.results.single.indices, [2, 2, 2]);
    expect(h.results.single.index, 2);
  });
  testWidgets('F2 lever onPull can synchronously submit targets after autoplay',
      (tester) async {
    final controller = SlotController();
    addTearDown(controller.dispose);
    bool? accepted;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
            data: const MediaQueryData(),
            child: Center(
                child: LuckyLeverSlotMachine(
                    config: slotTestConfig,
                    controller: controller,
                    width: 300,
                    height: 180,
                    onPull: () {
                      accepted = controller.stopEach([1, 1, 1]);
                    })))));
    await tester.tap(find.bySemanticsLabel('拉杆'));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(accepted, isTrue);
    expect(controller.lastResult!.indices, [1, 1, 1]);
    await tester.pumpWidget(const SizedBox());
  });
  test('F2 slot emits every crossed cell including full modulo loops', () {
    final config = slotTestConfig.copyWith(
        reels: [const SlotReel()],
        options: slotTestConfig.options
            .copyWith(motion: slotTestMotion.copyWith(speed: 250)));
    final m = SlotMotion()
      ..configure(config, slotLayout(config, const Size(100, 300)))
      ..start()
      ..tick(0, 0);
    final passed = <(int, int)>[];
    m.tick(32, 32);
    m.dispatchPassed((r, i) => passed.add((r, i)));
    expect(passed, [(0, 1), (0, 2)]);
    passed.clear();
    m.tick(48, 16);
    m.dispatchPassed((r, i) => passed.add((r, i)));
    expect(passed, [(0, 0), (0, 1), (0, 2)]);
  });
  testWidgets('F2 slot raster preserves shadows outside individual cell bounds',
      (tester) async {
    final config = slotTestConfig.copyWith(
        prizes: [
          const SlotPrize(background: LuckyFill.color(Color(0xFFFFFFFF)))
        ],
        options: slotTestConfig.options.copyWith(rowSpacing: 20, colSpacing: 0),
        style: const SlotStyle(
            cell: LuckyCellStyle(
                shadow: LuckyShadow(offsetY: -10, color: Color(0xFF000000)))));
    final vectorCache = LuckyPictureCache(), rasterCache = LuckyPictureCache();
    final atlas = SlotAtlas();
    addTearDown(vectorCache.dispose);
    addTearDown(rasterCache.dispose);
    addTearDown(atlas.dispose);
    final vector = SlotPainter(slotSurfaceData(config: config), vectorCache);
    final raster = SlotPainter(
        slotSurfaceData(
            config: config,
            performance: const LuckyPerformanceOptions(
                cacheMode: LuckyCacheMode.raster)),
        rasterCache,
        atlas: atlas);
    await tester.runAsync(() async {
      final expected = await _pixels(vector), actual = await _pixels(raster);
      const offset = (35 * 300 + 50) * 4;
      expect(expected.getUint32(offset), 0x000000FF);
      expect(actual.getUint32(offset), expected.getUint32(offset));
      expect(actual.buffer.asUint8List(), expected.buffer.asUint8List());
    });
  });
  test(
      'F2 slot direct prize shrink replans and clearing prizes cancels movement',
      () {
    final m = SlotMotion()
      ..configure(slotTestConfig, slotLayout())
      ..start()
      ..requestStop([2, 2, 2]);
    for (var i = 0; i < 5; i++) {
      m.tick(i * 16, 16);
    }
    final next = slotTestConfig.copyWith(prizes: [slotTestPrizes.first]);
    m.configure(next, slotLayout(next));
    for (var i = 5; i < 30; i++) {
      m.tick(i * 16, 16);
    }
    expect(m.takeResult()!.indices, [0, 0, 0]);
    m.start();
    final empty = slotTestConfig.copyWith(prizes: []);
    m.configure(empty, slotLayout(empty));
    expect(m.phase, LuckyPhase.idle);
    expect(m.takeResult()!.cancelled, isTrue);
  });
}
