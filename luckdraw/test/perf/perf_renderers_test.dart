import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/src/capsule/render/capsule_painter.dart';
import 'package:luckdraw/src/grid/render/grid_painter.dart';
import 'package:luckdraw/src/lotto/render/lotto_painter.dart';
import 'package:luckdraw/src/number_wheel/render/number_wheel_painter.dart';

import '../support/capsule_fixtures.dart';
import '../support/recording_canvas.dart';

/// 固定逻辑尺寸与物理像素比。
const Size _size = Size(320, 320);

/// 格子背景与模糊阴影，避免未定义的默认填充影响缓存断言。
const LuckyCellStyle _shadowStyle = LuckyCellStyle(
    background: LuckyFill.color(Color(0xFFFFAA00)),
    shadow: LuckyShadow(blur: 6, color: Color(0x66000000)));

/// 使用真实宿主和默认自动缓存，允许变更设备像素比。
Widget _root(Widget child,
        {double dpr = 2, TextScaler textScale = TextScaler.noScaling}) =>
    MediaQuery(
        data: MediaQueryData(devicePixelRatio: dpr, textScaler: textScale),
        child: Directionality(
            textDirection: TextDirection.ltr,
            child:
                Center(child: SizedBox.fromSize(size: _size, child: child))));

/// 从真实 surface 中取得指定生产画笔。
T _painter<T extends CustomPainter>(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<T>()
    .single;

/// 回放一次并断言帧路径不使用离屏图层。
TestRecordingCanvas _paint(CustomPainter painter) {
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, _size);
  canvas.expectBalancedWithoutSaveLayer();
  return canvas;
}

/// 返回帧中使用的首张缓存位图。
ui.Image _image(TestRecordingCanvas canvas) => canvas.invocations
    .firstWhere((entry) => entry.invocation.memberName == #drawImageRect)
    .invocation
    .positionalArguments
    .first! as ui.Image;

/// 运动位图必须响应低频输入并在结算时恢复矢量。
void main() {
  group('PERF renderers', () {
    testWidgets(
        'number disc switches phases and invalidates DPR options and size',
        (tester) async {
      final controller = NumberWheelController();
      addTearDown(controller.dispose);

      /// 按指定缓存策略构建同一页面。
      Widget view(
              {LuckyPerformanceOptions performance =
                  const LuckyPerformanceOptions(),
              double dpr = 2,
              double width = 320}) =>
          _root(
              Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                      width: width,
                      height: _size.height,
                      child: LuckyNumberWheel(
                          config: NumberWheelConfig.range(0, 36),
                          controller: controller,
                          performance: performance))),
              dpr: dpr);
      await tester.pumpWidget(view());
      controller.frame.phase = LuckyPhase.cruising;
      var painter = _painter<NumberWheelPainter>(tester);
      final image = _image(_paint(painter));
      expect(image.width, 640);
      final records = painter.cache.debugRecordCount;
      controller.frame.phase = LuckyPhase.settled;
      expect(_paint(painter).countCalls(#drawImageRect), 0);
      expect(painter.cache.debugRecordCount, records);
      await tester.pumpWidget(view(dpr: 3, width: 300));
      expect(image.debugDisposed, isTrue);
      painter = _painter<NumberWheelPainter>(tester);
      controller.frame.phase = LuckyPhase.cruising;
      final updated = _image(_paint(painter));
      expect(updated.width, 900);
      await tester.pumpWidget(view(
          dpr: 3,
          width: 300,
          performance: const LuckyPerformanceOptions(
              cacheMode: LuckyCacheMode.raster, maxRasterSide: 10)));
      expect(updated.debugDisposed, isTrue);
      expect(
          _paint(_painter<NumberWheelPainter>(tester))
              .countCalls(#drawImageRect),
          0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'grid caches only shadow backgrounds and preserves vector content order',
        (tester) async {
      final controller = GridController();
      addTearDown(controller.dispose);
      var callbacks = 0;
      final config = GridConfig(prizes: [
        GridPrize(
            x: 0,
            y: 0,
            texts: const [LuckyText('outside', left: LuckyLength.px(-100))],
            painter: (canvas, rect, active) {
              callbacks++;
            }),
        const GridPrize(x: 1, y: 0),
      ], style: const GridStyle(cell: _shadowStyle));
      await tester
          .pumpWidget(_root(LuckyGrid(config: config, controller: controller)));
      final painter = _painter<GridPainter>(tester);
      expect(_paint(painter).countCalls(#drawImageRect), 0);
      controller.frame.phase = LuckyPhase.cruising;
      final calls = callbacks;
      final moving = _paint(painter);
      expect(moving.countCalls(#drawImageRect), 2);
      expect(moving.countCalls(#drawPicture), greaterThanOrEqualTo(3));
      final names = moving.invocations
          .map((entry) => entry.invocation.memberName)
          .toList();
      final firstImage = names.indexOf(#drawImageRect);
      expect(names[firstImage + 1], #drawPicture);
      expect(callbacks, calls);
      expect(painter.cache.debugRasterBytes, greaterThan(0));
      final image = _image(moving);
      await tester.pumpWidget(const SizedBox());
      expect(image.debugDisposed, isTrue);
    });

    testWidgets('capsule color sprites honor phase limit and sampling changes',
        (tester) async {
      final controller = CapsuleController();
      addTearDown(controller.dispose);

      /// 按指定缓存策略构建同一页面。
      Widget view(LuckyPerformanceOptions performance) =>
          _root(LuckyCapsuleMachine(
              config: capsuleConfig,
              controller: controller,
              performance: performance));
      await tester.pumpWidget(view(const LuckyPerformanceOptions()));
      var painter = _painter<CapsulePainter>(tester);
      expect(_paint(painter).countCalls(#drawImageRect), 0);
      controller.frame.phase = LuckyPhase.cruising;
      final moving = _paint(painter);
      expect(
          moving.countCalls(#drawImageRect), capsuleLayout().capsules.length);
      final image = _image(moving);
      final records = painter.pictures.cache.debugRecordCount;
      _paint(painter);
      expect(painter.pictures.cache.debugRecordCount, records);
      await tester.pumpWidget(view(const LuckyPerformanceOptions(
          maxRasterSide: 1, filterQuality: FilterQuality.high)));
      expect(image.debugDisposed, isTrue);
      painter = _painter<CapsulePainter>(tester);
      expect(_paint(painter).countCalls(#drawImageRect), 0);
      expect(painter.pictures.cache.debugRasterBytes, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'lotto balls restore vectors and dispose raster after option changes',
        (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);

      /// 按指定缓存策略构建同一页面。
      Widget view(LuckyPerformanceOptions performance) => _root(LuckyLotto(
          config: LottoConfig.superLotto(),
          controller: controller,
          performance: performance));
      await tester.pumpWidget(view(const LuckyPerformanceOptions()));
      final painter = _painter<LottoPainter>(tester);
      expect(_paint(painter).countCalls(#drawImageRect), 0);
      controller.frame.phase = LuckyPhase.cruising;
      final moving = _paint(painter);
      expect(moving.countCalls(#drawImageRect), 47);
      final image = _image(moving);
      controller.frame.phase = LuckyPhase.settled;
      expect(_paint(painter).countCalls(#drawImageRect), 0);
      await tester.pumpWidget(view(
          const LuckyPerformanceOptions(cacheMode: LuckyCacheMode.picture)));
      expect(image.debugDisposed, isTrue);
      expect(_painter<LottoPainter>(tester).cache.debugRasterBytes, 0);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'lotto sprite bounds include long labels and system scaled text',
        (tester) async {
      final cases = [
        (
          const LottoPool(
              min: -10000,
              max: -9999,
              count: 1,
              ballFill: LuckyFill.color(Color(0xFF00AA00))),
          TextScaler.noScaling
        ),
        (
          const LottoPool(
              min: 1,
              max: 2,
              count: 1,
              ballFill: LuckyFill.color(Color(0xFF00AA00))),
          const TextScaler.linear(4)
        ),
      ];
      for (final entry in cases) {
        final controller = LottoController();
        await tester.pumpWidget(_root(
            LuckyLotto(
                config: LottoConfig(pools: [entry.$1]),
                controller: controller,
                textScaling: LuckyTextScaling.system),
            textScale: entry.$2));
        controller.frame.phase = LuckyPhase.cruising;
        final painter = _painter<LottoPainter>(tester);
        final canvas = _paint(painter);
        final destination = canvas.invocations
            .firstWhere((call) => call.invocation.memberName == #drawImageRect)
            .invocation
            .positionalArguments[2]! as Rect;
        expect(destination.width,
            greaterThan(painter.data.layout.drums.single.ballRadius * 2 + 1));
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    });
  });
}
