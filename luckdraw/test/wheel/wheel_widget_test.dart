import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';
import '../support/test_images.dart';
import 'wheel_render_support.dart';
import 'wheel_test_support.dart';

/// 自定义后端，记录表面构建次数和当前数据。
final class _Renderer extends LuckyRenderer<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>> {
  /// 当前输入。
  LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame>? data;

  /// 构建次数。
  int builds = 0;

  /// 返回可查找的独立表面。
  @override
  Widget buildSurface(BuildContext context,
      LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) {
    builds++;
    this.data = data;
    return const ColoredBox(color: kWheelRenderAccent);
  }
}

/// 通过真实 Ticker 验证转盘 Widget 契约。
void main() {
  group('LuckyWheel', () {
    testWidgets(
        'tap inside the button radius calls onStart only in idle-like phases',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      var starts = 0;
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: wheelTestConfig(),
          controller: controller,
          onStart: () => starts++)));
      await tester.tap(find.byType(LuckyWheel));
      expect(starts, 1);
      controller.idleSpin();
      await tester.pump();
      await tester.tap(find.byType(LuckyWheel));
      expect(starts, 2);
      controller.play();
      await tester.pump();
      await tester.tap(find.byType(LuckyWheel));
      expect(starts, 2);
      controller.stop(0);
      await wheelPumpTo(tester, controller, LuckyPhase.decelerating);
      await tester.tap(find.byType(LuckyWheel));
      expect(starts, 2);
      await wheelPumpTo(tester, controller, LuckyPhase.settled);
      await tester.tap(find.byType(LuckyWheel));
      expect(starts, 3);
    });
    testWidgets(
        'onButtonTap fires in every phase with the current phase (#370)',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      final phases = <LuckyPhase>[];
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: wheelTestConfig(),
          controller: controller,
          onButtonTap: (index, phase) {
            expect(index, 0);
            phases.add(phase);
          })));
      await tester.tap(find.byType(LuckyWheel));
      controller.idleSpin();
      await tester.pump();
      await tester.tap(find.byType(LuckyWheel));
      controller.play();
      await tester.pump();
      await tester.tap(find.byType(LuckyWheel));
      await wheelPumpTo(tester, controller, LuckyPhase.cruising);
      await tester.tap(find.byType(LuckyWheel));
      controller.stop(2);
      await wheelPumpTo(tester, controller, LuckyPhase.decelerating);
      await tester.tap(find.byType(LuckyWheel));
      await wheelPumpTo(tester, controller, LuckyPhase.settled);
      await tester.tap(find.byType(LuckyWheel));
      expect(phases, [
        LuckyPhase.idle,
        LuckyPhase.idleSpinning,
        LuckyPhase.accelerating,
        LuckyPhase.cruising,
        LuckyPhase.decelerating,
        LuckyPhase.settled
      ]);
    });
    testWidgets('tap outside the buttons does nothing', (tester) async {
      var calls = 0;
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: wheelRenderFixture(),
          onStart: () => calls++,
          onButtonTap: (_, __) => calls++)));
      await tester.tapAt(
          tester.getTopLeft(find.byType(LuckyWheel)) + const Offset(10, 10));
      expect(calls, 0);
    });
    testWidgets('onEnd receives the prize at the target index', (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      final results = <LuckyResult<WheelPrize>>[];
      final phases = <LuckyPhase>[];
      final passed = <int>[];
      final config = wheelTestConfig();
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: config,
          controller: controller,
          onEnd: results.add,
          onPhaseChanged: phases.add,
          onSectorPassed: passed.add,
          semanticsValueBuilder: (phase, result) =>
              '${phase.name}:${result?.index}')));
      controller.play();
      await wheelPumpTo(tester, controller, LuckyPhase.cruising);
      controller.stop(2);
      await wheelPumpTo(tester, controller, LuckyPhase.settled);
      expect(results.single.index, 2);
      expect(results.single.prize, same(config.prizes[2]));
      expect(phases, [
        LuckyPhase.accelerating,
        LuckyPhase.cruising,
        LuckyPhase.decelerating,
        LuckyPhase.settled
      ]);
      expect(passed, isNotEmpty);
    });
    testWidgets('afterStart beforeDraw and afterDraw hooks are invoked',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      var starts = 0;
      final order = <String>[];
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: wheelTestConfig(),
          controller: controller,
          hooks: LuckyHooks(
              afterStart: () => starts++,
              beforeDraw: (_, size) {
                expect(size, kWheelRenderSize);
                order.add('before');
              },
              afterDraw: (_, __) => order.add('after')))));
      expect(order, ['before', 'after']);
      controller.play();
      await tester.pump();
      await tester.pump(kWheelRenderStep);
      expect(starts, 1);
      expect(order.length, greaterThan(2));
      expect(order.length.isEven, isTrue);
    });
    testWidgets(
        'onReady fires after images settle and onImageError reports failures (#417)',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final provider = LuckyTestImageProvider(completer);
      final errors = <LuckyImageError>[];
      var ready = 0;
      var paints = 0;
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: WheelConfig(prizes: [
            WheelPrize(
                images: [LuckyImage(provider)], painter: (_, __) => paints++)
          ]),
          onReady: () => ready++,
          onImageError: errors.add)));
      expect(paints, greaterThan(0), reason: '图片未完成时首帧已经录制');
      expect(ready, 0);
      completer.fail(StateError('image failed'));
      await tester.pump();
      expect(errors.single.slot, const LuckyImageSlot('prizes', 0, 0));
      expect(ready, 1);
      PaintingBinding.instance.imageCache.clear();
      expect(completer.listenerCount, 0);
    });
    testWidgets(
        'prize count change while cruising applies immediately keeping the angle (#382)',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      final renderer = _Renderer();
      final config = wheelTestConfig();
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: config, controller: controller, renderer: renderer)));
      controller.play();
      await wheelPumpTo(tester, controller, LuckyPhase.cruising);
      final angle = controller.rotateDeg;
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: config.copyWith(prizes: config.prizes.take(3).toList()),
          controller: controller,
          renderer: renderer)));
      expect(controller.rotateDeg, angle);
      expect(controller.phase.value, LuckyPhase.cruising);
      expect(renderer.data!.layout.sectors, hasLength(config.prizes.length),
          reason: 'F2：运动期结构变化排队，保留旧表面');
      controller.stop(5);
      await wheelPumpTo(tester, controller, LuckyPhase.settled);
      await tester.pump();
      expect(controller.lastResult!.index, 5);
      expect(renderer.data!.layout.sectors, hasLength(3));
    });
    testWidgets('repaints through the frame listenable without rebuilding',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wheelRenderRoot(
          LuckyWheel(config: wheelTestConfig(), controller: controller)));
      controller.play();
      await wheelPumpTo(tester, controller, LuckyPhase.cruising);
      final painter = wheelSurfacePainter(tester);
      final records = painter.cache.debugRecordCount;
      final element = tester.element(find.byType(CustomPaint));
      final paintWidget = tester.widget<CustomPaint>(find.byType(CustomPaint));
      final angle = controller.rotateDeg;
      await tester.pump(kWheelRenderStep);
      await tester.pump(kWheelRenderStep);
      expect(controller.rotateDeg, greaterThan(angle));
      expect(wheelSurfacePainter(tester), same(painter));
      expect(tester.element(find.byType(CustomPaint)), same(element));
      expect(tester.widget<CustomPaint>(find.byType(CustomPaint)),
          same(paintWidget));
      expect(painter.cache.debugRecordCount, records);
    });
    testWidgets(
        'unbounded constraints without width or height throw a FlutterError with guidance',
        (tester) async {
      await tester.pumpWidget(const MediaQuery(
          data: MediaQueryData(),
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                  child: LuckyWheel(config: WheelConfig())))));
      expect(
          tester.takeException(),
          isA<FlutterError>().having((error) => error.toString(), 'guidance',
              contains('width/height')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const MediaQuery(
          data: MediaQueryData(),
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: UnconstrainedBox(
                  child: LuckyWheel(
                      config: WheelConfig(), width: 200, height: 200)))));
      expect(tester.takeException(), isNull);
    });
    testWidgets('a custom renderer replaces the canvas renderer',
        (tester) async {
      final renderer = _Renderer();
      await tester.pumpWidget(wheelRenderRoot(
          LuckyWheel(config: wheelRenderFixture(), renderer: renderer)));
      expect(find.byType(ColoredBox), findsOneWidget);
      expect(find.byType(CustomPaint), findsNothing);
      expect(renderer.data!.layout.sectors, hasLength(6));
    });
    testWidgets('layers receive wheel layout and frame', (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      final seen = <LuckyLayerPosition>[];
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: wheelTestConfig(),
          controller: controller,
          layers: [
            for (final position in LuckyLayerPosition.values)
              LuckyCallbackLayer<WheelLayout, WheelFrame>((canvas, context) {
                expect(context.layout.size, kWheelRenderSize);
                expect(context.frame, same(controller.frame));
                expect(context.size, kWheelRenderSize);
                seen.add(position);
              }, position: position),
          ])));
      expect(seen, LuckyLayerPosition.values);
    });
    testWidgets(
        'reassemble invalidates wheel pictures and zero size paints nothing',
        (tester) async {
      await tester.pumpWidget(
          wheelRenderRoot(LuckyWheel(config: wheelRenderFixture())));
      final painter = wheelSurfacePainter(tester);
      final records = painter.cache.debugRecordCount;
      tester
          .element(find.byWidgetPredicate((widget) => widget is LuckyGameView))
          // ignore: invalid_use_of_protected_member
          .reassemble();
      await tester.pump();
      expect(painter.cache.debugRecordCount, greaterThan(records));
      await tester.pumpWidget(const MediaQuery(
          data: MediaQueryData(),
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                  child: SizedBox.shrink(
                      child: LuckyWheel(config: WheelConfig()))))));
      expect(find.byType(CustomPaint), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('dispose removes pending image listeners and active ticker',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final provider = LuckyTestImageProvider(completer);
      final controller = WheelController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          controller: controller,
          config: WheelConfig(prizes: [
            WheelPrize(images: [LuckyImage(provider)])
          ]))));
      PaintingBinding.instance.imageCache.clear();
      expect(completer.listenerCount, 1);
      controller.play();
      await tester.pump(kWheelRenderStep);
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(kWheelRenderStep);
      expect(completer.listenerCount, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        'structural changes wait during deceleration and appearance changes keep motion',
        (tester) async {
      final controller = WheelController();
      addTearDown(controller.dispose);
      final renderer = _Renderer();
      final config = wheelTestConfig();
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: config, controller: controller, renderer: renderer)));
      controller.play();
      await wheelPumpTo(tester, controller, LuckyPhase.cruising);
      controller.stop(5);
      await wheelPumpTo(tester, controller, LuckyPhase.decelerating);
      final angle = controller.rotateDeg;
      final changed = config.copyWith(prizes: config.prizes.take(3).toList());
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: changed, controller: controller, renderer: renderer)));
      expect(renderer.data!.layout.sectors, hasLength(6));
      expect(controller.rotateDeg, angle);
      await wheelPumpTo(tester, controller, LuckyPhase.settled);
      expect(controller.lastResult!.index, 5);
      expect(renderer.data!.layout.sectors, hasLength(3));
      final current = controller.rotateDeg;
      await tester.pumpWidget(wheelRenderRoot(LuckyWheel(
          config: changed.copyWith(
              style: const WheelStyle(
                  background: LuckyFill.color(kWheelRenderAccent))),
          controller: controller,
          renderer: renderer)));
      expect(controller.rotateDeg, current);
      expect(renderer.data!.layout.sectors.first.background,
          const LuckyFill.color(kWheelRenderAccent));
    });
    testWidgets(
        'smallest containing button wins and structural fields are classified',
        (tester) async {
      const game = WheelGame();
      const config = WheelConfig(buttons: [
        WheelButton(radius: LuckyLength.px(60)),
        WheelButton(radius: LuckyLength.px(20)),
        WheelButton(),
      ], prizes: [
        WheelPrize(),
        WheelPrize()
      ]);
      final input = LuckyLayoutInput.headless(kWheelRenderSize);
      final layout = game.computeLayout(config, input);
      input.measurer.dispose();
      expect(
          game
              .hitTestAll(config, layout, WheelFrame(), layout.center)
              .single
              .index,
          1);
      expect(
          game
              .hitTestAll(config, layout, WheelFrame(),
                  layout.center + const Offset(60, 0))
              .single
              .index,
          0);
      expect(
          game.hitTestAll(config, layout, WheelFrame(), Offset.zero), isEmpty);
      expect(game.isStructuralChange(config, config), isFalse);
      expect(
          game.isStructuralChange(
              config,
              config.copyWith(prizes: [
                const WheelPrize(sectorWeight: 2),
                const WheelPrize()
              ])),
          isTrue);
      expect(
          game.isStructuralChange(config,
              config.copyWith(options: const WheelOptions(offsetDegree: 7))),
          isTrue);
      expect(game.semanticsLabel(config), '幸运大转盘，共 2 个奖品');
    });
    testWidgets(
        'images invalidate only image segments and controller replacement reconnects frames',
        (tester) async {
      final completer = LuckyTestImageCompleter();
      final provider = LuckyTestImageProvider(completer);
      final first = WheelController();
      final second = WheelController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final config = wheelRenderFixture().copyWith(prizes: [
        WheelPrize(images: [
          LuckyImage(provider,
              width: const LuckyLength.px(30), height: const LuckyLength.px(30))
        ]),
        ...kLuckyWheelFixture.prizes.skip(1),
      ]);
      await tester.pumpWidget(
          wheelRenderRoot(LuckyWheel(config: config, controller: first)));
      final painter = wheelSurfacePainter(tester);
      final before = painter.cache.debugRecordCount;
      final image = await tester
          .runAsync(() => createLuckyTestImage(color: kWheelRenderAccent));
      completer.succeed(image!);
      image.dispose();
      await tester.pump();
      expect(painter.cache.debugRecordCount, before + 1);
      expect(completer.listenerCount, 0);
      await tester.pumpWidget(
          wheelRenderRoot(LuckyWheel(config: config, controller: second)));
      expect(wheelSurfacePainter(tester), isNot(same(painter)));
      second.play();
      await tester.pump();
      await tester.pump(kWheelRenderStep);
      expect(second.rotateDeg, greaterThan(0));
    });
  });
}
