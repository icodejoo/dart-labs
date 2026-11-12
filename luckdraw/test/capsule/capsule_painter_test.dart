import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';
import 'package:luckdraw/src/capsule/render/capsule_painter.dart';

import '../support/capsule_fixtures.dart';
import '../support/recording_canvas.dart';

/// 可在原地更新版本与图片的只读视图测试替身。
final class _Images implements LuckyImageSet {
  /// 创建首帧视图。
  _Images(this.resolved);

  /// 当前已解码图片。
  final LuckyResolvedImage resolved;

  /// 变更版本。
  @override
  int generation = 0;

  /// 已加载完成。
  @override
  bool get isSettled => true;

  /// 第一个奖品的第一张图片，其余槽返回空。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) =>
      slot.itemIndex == 0 && slot.imageIndex == 0 ? resolved : null;
}

/// 验证 Picture 录制次数与帧绘制调用。
void main() {
  group('CapsuleCanvasRenderer', () {
    test('capsule pictures are recorded once per color pair', () {
      final config = capsuleConfig.copyWith(prizes: [
        capsuleConfig.prizes.first,
        capsuleConfig.prizes.first.copyWith(weight: 2)
      ]);
      final motion = CapsuleMotion()..configure(config, capsuleLayout(config)),
          notifier = LuckyFrameNotifier();
      final pictures = CapsulePictures()
        ..prepare(capsuleSurface(motion.frame, notifier, config: config));
      expect(identical(pictures.capsules[0], pictures.capsules[1]), isTrue);
      expect(pictures.cache.debugRecordCount, 6);
      pictures.dispose();
      notifier.dispose();
    });
    test('per frame paint replays cached pictures without recording', () {
      final motion = CapsuleMotion()..configure(capsuleConfig, capsuleLayout()),
          notifier = LuckyFrameNotifier();
      final data = capsuleSurface(motion.frame, notifier);
      final pictures = CapsulePictures()..prepare(data),
          canvas = TestRecordingCanvas();
      final count = pictures.cache.debugRecordCount;
      final painter = CapsulePainter(data, pictures);
      motion.start();
      for (var i = 0; i < 30; i++) {
        motion.tick(0, 16);
        painter.paint(canvas, capsuleSize);
      }
      expect(pictures.cache.debugRecordCount, count);
      expect(
          canvas.countCalls(#drawPicture) + canvas.countCalls(#drawImageRect),
          30 * (3 + capsuleLayout().capsules.length));
      expect(canvas.countCalls(#drawImageRect),
          30 * capsuleLayout().capsules.length);
      expect(canvas.countCalls(#drawPath), 0);
      expect(painter.shouldRepaint(CapsulePainter(data, pictures)), isFalse);
      pictures.dispose();
      notifier.dispose();
    });
    test('painting never calls saveLayer and keeps save count balanced', () {
      final motion = CapsuleMotion()..configure(capsuleConfig, capsuleLayout()),
          notifier = LuckyFrameNotifier();
      final data = capsuleSurface(motion.frame, notifier);
      final pictures = CapsulePictures()..prepare(data),
          canvas = TestRecordingCanvas();
      final painter = CapsulePainter(data, pictures);
      motion.start();
      motion.requestStop(1);
      for (var i = 0; i < 400; i++) {
        motion.tick(0, 20);
        painter.paint(canvas, capsuleSize);
      }
      expect(motion.phase, LuckyPhase.settled);
      expect(canvas.countCalls(#scale), greaterThan(0));
      canvas.expectBalancedWithoutSaveLayer();
      pictures.dispose();
      notifier.dispose();
    });
  });
  testWidgets(
      'CapsuleCanvasRenderer edges > surface reuses resources across phase rebuilds and disposes',
      (tester) async {
    final motion = CapsuleMotion()..configure(capsuleConfig, capsuleLayout()),
        notifier = LuckyFrameNotifier();
    Widget surface(
            LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame>
                data) =>
        capsuleHost(Builder(
            builder: (context) =>
                const CapsuleCanvasRenderer().buildSurface(context, data)));
    await tester.pumpWidget(surface(capsuleSurface(motion.frame, notifier)));
    final before = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
        as CapsulePainter;
    final records = before.pictures.cache.debugRecordCount;
    motion.start();
    notifier.notify();
    await tester.pump();
    expect(before.pictures.cache.debugRecordCount, records);
    await tester.pumpWidget(surface(capsuleSurface(motion.frame, notifier)));
    final after = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!
        as CapsulePainter;
    expect(identical(before.pictures, after.pictures), isTrue);
    expect(after.pictures.cache.debugRecordCount, records);
    expect(after.shouldRepaint(before), isTrue);
    final next = LuckyFrameNotifier();
    await tester.pumpWidget(surface(capsuleSurface(motion.frame, next,
        generation: 1, imagesListenable: next)));
    expect(after.pictures.cache.debugRecordCount, greaterThan(records));
    next.notify();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    notifier.dispose();
    next.dispose();
  });
  test(
      'CapsuleCanvasRenderer edges > layers hooks and card painter are ordered',
      () {
    final calls = <String>[];
    final notifier = LuckyFrameNotifier(),
        motion = CapsuleMotion()..configure(capsuleConfig, capsuleLayout());
    final layers = <LuckyLayer<CapsuleLayout, CapsuleFrame>>[
      for (final pos in LuckyLayerPosition.values)
        LuckyCallbackLayer((canvas, context) => calls.add(pos.name),
            position: pos),
      LuckyCallbackLayer((canvas, context) => calls.add('static'),
          isStatic: true)
    ];
    final config = capsuleConfig.copyWith(prizes: [
      capsuleConfig.prizes.first.copyWith(painter: (canvas, bounds) {
        calls.add('card');
        expect(bounds, capsuleLayout().card);
      })
    ]);
    final data = capsuleSurface(motion.frame, notifier,
        config: config,
        layers: layers,
        hooks: LuckyHooks(
            beforeDraw: (canvas, size) => calls.add('before'),
            afterDraw: (canvas, size) => calls.add('after')));
    final pictures = CapsulePictures()..prepare(data);
    expect(calls, ['card', 'static']);
    calls.clear();
    CapsulePainter(data, pictures).paint(TestRecordingCanvas(), capsuleSize);
    expect(calls, [
      'before',
      'background',
      'belowItems',
      'aboveItems',
      'foreground',
      'after'
    ]);
    pictures.dispose();
    notifier.dispose();
  });
  testWidgets(
      'CapsuleCanvasRenderer edges > image arrivals invalidate only image card pictures',
      (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF8855EE), BlendMode.src);
    final source = recorder.endRecording(), image = source.toImageSync(2, 2);
    source.dispose();
    final images = _Images(LuckyResolvedImage(image, const Size(2, 2))),
        notifier = LuckyFrameNotifier();
    const picture = LuckyImage(AssetImage('prize.png'),
        width: LuckyLength.percent(40),
        height: LuckyLength.percent(20),
        opacity: 0.8,
        borderRadius: 2);
    final config = capsuleConfig.copyWith(
        prizes: [
          capsuleConfig.prizes.first.copyWith(images: [picture, picture])
        ],
        style: capsuleConfig.style.copyWith(
            globeFill: const LuckyFill.color(Color(0x2266CCFF)),
            bodyFill: const LuckyFill.color(Color(0xFFEE7788)),
            knobFill: const LuckyFill.color(Color(0xFFFFFFFF)),
            card: const LuckyCellStyle(
                border: LuckyBorder(width: 2, color: Color(0xFF000000)),
                foreground: LuckyFill.color(Color(0x11000000)))));
    final requests =
        const CapsuleGame().collectImages(config, capsuleLayout(config));
    expect(requests.length, 2);
    expect(requests.first.decodeLogicalWidth, 96);
    expect(requests.first.decodeLogicalHeight, 36);
    final motion = CapsuleMotion()..configure(config, capsuleLayout(config));
    final data = capsuleSurface(motion.frame, notifier,
        config: config, images: images, imagesListenable: notifier);
    await tester.pumpWidget(capsuleHost(Builder(
        builder: (context) =>
            const CapsuleCanvasRenderer().buildSurface(context, data))));
    final painter = tester
        .widget<CustomPaint>(find.byType(CustomPaint))
        .painter! as CapsulePainter;
    final back = painter.pictures.back,
        capsule = painter.pictures.capsules.first,
        card = painter.pictures.cards.first,
        count = painter.pictures.cache.debugRecordCount;
    images.generation++;
    notifier.notify();
    await tester.pump();
    expect(painter.pictures.cache.debugRecordCount, count + 1);
    expect(identical(painter.pictures.back, back), isTrue);
    expect(identical(painter.pictures.capsules.first, capsule), isTrue);
    expect(identical(painter.pictures.cards.first, card), isFalse);
    await tester.pumpWidget(const SizedBox());
    notifier.dispose();
    image.dispose();
  });
}
