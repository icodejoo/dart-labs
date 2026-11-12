import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/lotto/render/lotto_painter.dart';

import '../support/lotto_fixtures.dart';
import '../support/recording_canvas.dart';
import 'lotto_render_support.dart';
import 'lotto_widget_test.dart' show lottoHost, settleLotto;

/// 从渲染表面提取当前画笔。
LottoPainter currentLottoPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.descendant(
        of: find.byType(LuckyLotto), matching: find.byType(CustomPaint)))
    .painter! as LottoPainter;

/// 验证静态段缓存和帧回放。
void main() {
  group('LottoCanvasRenderer', () {
    testWidgets(
        'layers cache invalidate and empty surfaces keep their contracts',
        (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      final callbacks = <String>[];
      final layers = [
        LuckyCallbackLayer<LottoLayout, LottoFrame>((canvas, context) {
          callbacks.add('static');
          expect(context.layout.size, isNot(Size.zero));
        }, position: LuckyLayerPosition.background, isStatic: true),
        LuckyCallbackLayer<LottoLayout, LottoFrame>((canvas, context) {
          callbacks.add('dynamic');
          expect(context.frame, same(controller.frame));
        }, position: LuckyLayerPosition.belowItems),
      ];
      Widget view(LottoConfig config, {double width = 400}) => lottoHost(
          LuckyLotto(
              config: config,
              controller: controller,
              width: width,
              height: lottoSize.height,
              hooks: LuckyHooks(
                  beforeDraw: (_, size) => callbacks.add('before'),
                  afterDraw: (_, size) => callbacks.add('after')),
              layers: layers));
      await tester.pumpWidget(view(lottoConfig));
      var painter = currentLottoPainter(tester);
      final count = painter.cache.debugRecordCount;
      final recorded = callbacks.where((c) => c == 'static').length;
      callbacks.clear();
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, lottoSize);
      expect(callbacks, ['before', 'dynamic', 'after']);
      canvas.expectBalancedWithoutSaveLayer();
      expect(painter.cache.debugRecordCount, count);
      expect(recorded, 1);
      final config =
          lottoConfig.copyWith(style: const LottoStyle(buttonText: '开奖'));
      await tester.pumpWidget(view(config, width: 420));
      painter = currentLottoPainter(tester);
      expect(painter.cache.debugRecordCount, greaterThan(count));
      expect(callbacks.where((c) => c == 'static'), hasLength(1));
      final notifier = ChangeNotifier();
      addTearDown(notifier.dispose);
      final empty = lottoLayout(lottoConfig, Size.zero);
      final emptyPainter = LottoPainter(
          data: lottoSurfaceData(
              config: lottoConfig,
              layout: empty,
              frame: controller.frame,
              listenable: notifier),
          cache: LuckyPictureCache());
      final untouched = TestRecordingCanvas();
      emptyPainter.paint(untouched, Size.zero);
      expect(untouched.invocations, isEmpty);
      expect(emptyPainter.shouldRepaint(emptyPainter), isFalse);
      expect(painter.shouldRepaint(emptyPainter), isTrue);
      emptyPainter.cache.dispose();
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('default ownership and structural geometry use only lotto APIs',
        (tester) async {
      const game = LottoGame();
      expect(game.isStructuralChange(lottoConfig, lottoConfig), isFalse);
      final p = lottoConfig.pools.first;
      for (final replacement in <LottoConfig>[
        lottoConfig.copyWith(pools: [p]),
        lottoConfig
            .copyWith(pools: [p.copyWith(min: 0), lottoConfig.pools.last]),
        lottoConfig
            .copyWith(pools: [p.copyWith(max: 8), lottoConfig.pools.last]),
        lottoConfig
            .copyWith(pools: [p.copyWith(count: 2), lottoConfig.pools.last]),
      ]) {
        expect(game.isStructuralChange(lottoConfig, replacement), isTrue);
      }
      final widget =
          LuckyLotto(config: lottoConfig, onBallDrawn: (_, number) {});
      expect(widget.onBallDrawn, isNotNull);
      await tester.pumpWidget(
          lottoHost(SizedBox.fromSize(size: lottoSize, child: widget)));
      expect(find.byType(CustomPaint), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('ball pictures are recorded once per number', (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(lottoHost(LuckyLotto(
          config: LottoConfig.superLotto(),
          controller: controller,
          width: lottoSize.width,
          height: lottoSize.height)));
      final cache = currentLottoPainter(tester).cache;
      expect(cache.debugRecordCount, 50);
      controller.play();
      for (var i = 0; i < 10; i++) {
        await tester.pump(lottoStep);
      }
      expect(currentLottoPainter(tester).cache, same(cache));
      expect(cache.debugRecordCount, 50);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('per frame paint replays cached pictures without recording',
        (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(lottoHost(LuckyLotto(
          config: lottoConfig,
          controller: controller,
          width: lottoSize.width,
          height: lottoSize.height)));
      controller.play();
      await tester.pump(lottoStep);
      final painter = currentLottoPainter(tester);
      final count = painter.cache.debugRecordCount;
      for (var i = 0; i < 30; i++) {
        await tester.pump(lottoStep);
        final canvas = TestRecordingCanvas();
        currentLottoPainter(tester).paint(canvas, lottoSize);
        expect(
            canvas.countCalls(#drawPicture) + canvas.countCalls(#drawImageRect),
            14);
        expect(canvas.countCalls(#translate), 11);
        expect(currentLottoPainter(tester).cache.debugRecordCount, count);
      }
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('painting never calls saveLayer and keeps save count balanced',
        (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(lottoHost(LuckyLotto(
          config: lottoConfig,
          controller: controller,
          width: lottoSize.width,
          height: lottoSize.height)));
      controller.play();
      controller.stopWith(lottoDraw);
      for (var i = 0; i < 100; i++) {
        await tester.pump(lottoStep);
        final canvas = TestRecordingCanvas();
        currentLottoPainter(tester).paint(canvas, lottoSize);
        canvas.expectBalancedWithoutSaveLayer();
        expect(
            canvas.countCalls(#drawPicture) + canvas.countCalls(#drawImageRect),
            14);
      }
      await settleLotto(tester, controller);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
