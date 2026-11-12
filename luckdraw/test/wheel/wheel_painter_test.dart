import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';
import '../support/recording_canvas.dart';
import 'wheel_render_support.dart';

/// 可重复使用的内存图片配置，不进行真实资源加载。
const AssetImage _provider = AssetImage('wheel-test.png');

/// 可按内容版本主动失效的静态用户层。
final class _RefreshLayer extends LuckyLayer<WheelLayout, WheelFrame> {
  /// 创建固定在奖品下方的静态层。
  _RefreshLayer()
      : super(position: LuckyLayerPosition.belowItems, isStatic: true);

  /// 本轮是否需要重录。
  bool dirty = false;

  /// 实际录制次数。
  int records = 0;

  /// 绘制并验证复用上下文。
  @override
  void paint(
      Canvas canvas, LuckyLayerContext<WheelLayout, WheelFrame> context) {
    records++;
    canvas.drawCircle(context.layout.center, 5, Paint());
  }

  /// 允许同一层实例按内容变化请求失效。
  @override
  bool shouldRepaint(covariant _RefreshLayer oldLayer) => dirty;
}

/// 保留布局与帧，只替换图片通知通道，模拟自定义宿主。
LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> _replaceImageSignal(
        LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data,
        Listenable signal) =>
    LuckySurfaceData(
        config: data.config,
        layout: data.layout,
        layoutGeneration: data.layoutGeneration,
        frame: data.frame,
        frameListenable: data.frameListenable,
        images: data.images,
        imagesListenable: signal,
        layers: data.layers,
        hooks: data.hooks,
        devicePixelRatio: data.devicePixelRatio,
        textScale: data.textScale,
        textDirection: data.textDirection,
        performance: data.performance,
        isAnimating: data.isAnimating);

/// 保留生产 surface 状态，替换其宿主输入。
Widget _surface(LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) =>
    wheelRenderRoot(Builder(
        builder: (context) =>
            const WheelCanvasRenderer().buildSurface(context, data)));

/// 使用三组图片的配置，包含分段和图片样式分支。
WheelConfig _imageConfig({double opacity = 1, double? borderRadius}) =>
    wheelRenderFixture().copyWith(blocks: [
      const WheelBlock(
          background: LuckyFill.color(kWheelRenderAccent),
          images: [
            WheelBlockImage(_provider),
            WheelBlockImage(_provider, rotate: true),
            WheelBlockImage(_provider),
          ]),
      const WheelBlock(
          padding: 12, background: LuckyFill.color(Color(0xff244466))),
    ], prizes: [
      WheelPrize(images: [
        LuckyImage(_provider,
            width: const LuckyLength.px(30),
            opacity: opacity,
            borderRadius: borderRadius)
      ]),
      const WheelPrize(),
    ], buttons: [
      const WheelButton(
          radius: LuckyLength.px(30), images: [LuckyImage(_provider)]),
    ]);

/// 将所有配置槽位映射到同一张真实小图片。
Future<WheelRenderImages> _images(
    WidgetTester tester, WheelConfig config) async {
  final image = await tester.runAsync(() =>
      createLuckyTestImage(color: kWheelRenderAccent, width: 8, height: 6));
  addTearDown(image!.dispose);
  final input = LuckyLayoutInput.headless(kWheelRenderSize);
  final layout = const WheelGame().computeLayout(config, input);
  input.measurer.dispose();
  final images = WheelRenderImages();
  for (final request in const WheelGame().collectImages(config, layout)) {
    images.values[request.slot] = LuckyResolvedImage(image, const Size(8, 6));
  }
  return images;
}

/// 获取指定画布调用的参数列表。
List<List<Object?>> _arguments(TestRecordingCanvas canvas, Symbol method) =>
    canvas.invocations
        .where((record) => record.invocation.memberName == method)
        .map((record) => record.invocation.positionalArguments)
        .toList();

/// 验证静态录制、每帧回放及上游绘制顺序。
void main() {
  group('WheelCanvasRenderer', () {
    testWidgets(
        'surface reconnects image signals and honors static layer invalidation',
        (tester) async {
      final layer = _RefreshLayer();
      final images = WheelRenderImages();
      final harness = WheelPainterHarness(
          config: _imageConfig(), images: images, layers: [layer]);
      await tester.pumpWidget(_surface(harness.data));
      final painter = wheelSurfacePainter(tester);
      final signal = LuckyFrameNotifier();
      addTearDown(signal.dispose);
      final data = _replaceImageSignal(harness.data, signal);
      final count = painter.cache.debugRecordCount;
      await tester.pumpWidget(_surface(data));
      expect(painter.cache.debugRecordCount, count);
      images.generation++;
      await tester.pumpWidget(_surface(data));
      expect(painter.cache.debugRecordCount, greaterThan(count));
      final refreshed = painter.cache.debugRecordCount;
      signal.notify();
      await tester.pump();
      expect(painter.cache.debugRecordCount, refreshed, reason: '重复通知不重新录制');
      final layerRecords = layer.records;
      layer.dirty = true;
      await tester.pumpWidget(_surface(data));
      expect(layer.records, layerRecords + 1);
      expect(painter.cache.debugRecordCount, greaterThan(refreshed));
    });
    testWidgets('static segments are recorded once while spinning',
        (tester) async {
      final harness = WheelPainterHarness();
      final count = harness.cache.debugRecordCount;
      expect(count, 2);
      for (var i = 0; i < 20; i++) {
        harness.frame.rotateDeg = i.toDouble();
        harness.painter.paint(TestRecordingCanvas(), kWheelRenderSize);
      }
      expect(harness.cache.debugRecordCount, count);
      expect(harness.painter.shouldRepaint(harness.painter), isFalse);
      final second = WheelPainterHarness();
      second.painter.rebuildSegments(second.data);
      expect(second.painter.shouldRepaint(harness.painter), isTrue);
    });
    testWidgets('rotating segments are replayed with one rotation per frame',
        (tester) async {
      final harness = WheelPainterHarness();
      harness.frame.rotateDeg = 37;
      final canvas = TestRecordingCanvas();
      harness.painter.paint(canvas, kWheelRenderSize);
      expect(canvas.countCalls(#rotate), 1);
      expect(_arguments(canvas, #rotate).single.single,
          closeTo(luckyDegToRad(37), 1e-12));
      expect(canvas.countCalls(#drawPicture), 2);
      canvas.expectBalancedWithoutSaveLayer();
    });
    testWidgets(
        'block images with rotate true rotate with the wheel and keep z-order',
        (tester) async {
      final config = _imageConfig();
      final harness = WheelPainterHarness(
          config: config, images: await _images(tester, config));
      final canvas = TestRecordingCanvas();
      harness.painter.paint(canvas, kWheelRenderSize);
      expect(canvas.countCalls(#drawPicture), 5);
      expect(canvas.countCalls(#rotate), 2);
      expect(
          canvas.invocations
              .map((r) => r.invocation.memberName)
              .where((name) => name == #drawPicture || name == #rotate),
          [
            #drawPicture,
            #rotate,
            #drawPicture,
            #drawPicture,
            #rotate,
            #drawPicture,
            #drawPicture
          ]);
      final records = TestRecordingCanvas();
      harness.painter.debugRecordSegments(records);
      expect(records.countCalls(#drawImageRect), 5);
    });
    testWidgets('raster cache mode keeps every texture within maxRasterSide',
        (tester) async {
      final harness = WheelPainterHarness(
          performance: const LuckyPerformanceOptions(
              cacheMode: LuckyCacheMode.raster, maxRasterSide: 800));
      final canvas = TestRecordingCanvas();
      harness.painter.paint(canvas, kWheelRenderSize);
      final args = _arguments(canvas, #drawImageRect).single;
      final image = args.first! as ui.Image;
      expect(image.width, 800);
      expect(image.height, 800);
      expect((args.last! as Paint).filterQuality, FilterQuality.low);
      final limited = WheelPainterHarness(
          performance: const LuckyPerformanceOptions(
              cacheMode: LuckyCacheMode.raster, maxRasterSide: 32));
      final fallback = TestRecordingCanvas();
      limited.painter.paint(fallback, kWheelRenderSize);
      expect(fallback.countCalls(#drawImageRect), 0);
      expect(fallback.countCalls(#drawPicture), 2);
    });
    testWidgets('image borderRadius clips the image (#254)', (tester) async {
      final config = _imageConfig(borderRadius: 4);
      final harness = WheelPainterHarness(
          config: config, images: await _images(tester, config));
      final canvas = TestRecordingCanvas();
      harness.painter.debugRecordSegments(canvas);
      expect(canvas.countCalls(#clipRRect), 1);
      expect(
          (_arguments(canvas, #clipRRect).single.first! as RRect).tlRadiusX, 4);
      canvas.expectBalancedWithoutSaveLayer();
    });
    testWidgets('image opacity is applied without saveLayer', (tester) async {
      final config = _imageConfig(opacity: 0.5);
      final harness = WheelPainterHarness(
          config: config, images: await _images(tester, config));
      final canvas = TestRecordingCanvas();
      harness.painter.debugRecordSegments(canvas);
      final paints =
          _arguments(canvas, #drawImageRect).map((args) => args.last! as Paint);
      expect(paints.map((paint) => colorAlpha8(paint.color)), contains(128));
      canvas.expectBalancedWithoutSaveLayer();
    });
    testWidgets(
        'pointer triangle is drawn only when the button has a background',
        (tester) async {
      final harness = WheelPainterHarness(
          config: const WheelConfig(buttons: [
        WheelButton(radius: LuckyLength.px(20), pointer: true),
        WheelButton(
            radius: LuckyLength.px(40),
            pointer: true,
            background: LuckyFill.color(kWheelRenderAccent)),
        WheelButton(
            radius: LuckyLength.px(50),
            background: LuckyFill.color(kWheelRenderAccent)),
      ]));
      final canvas = TestRecordingCanvas();
      harness.painter.debugRecordSegments(canvas);
      final paths = _arguments(canvas, #drawPath);
      expect(paths, hasLength(3));
      expect((paths[1].first! as Path).getBounds(),
          const Rect.fromLTRB(-40, -80, 40, 0));
    });
    testWidgets(
        'painting never calls saveLayer and keeps save count balanced (#176)',
        (tester) async {
      final harness = WheelPainterHarness(config: _imageConfig(), layers: [
        LuckyCallbackLayer<WheelLayout, WheelFrame>((canvas, context) {
          canvas.drawCircle(Offset.zero, 3, Paint());
        }, rotatesWithWheel: true, position: LuckyLayerPosition.aboveItems)
      ]);
      final frame = TestRecordingCanvas();
      harness.painter.paint(frame, kWheelRenderSize);
      frame.expectBalancedWithoutSaveLayer();
      final records = TestRecordingCanvas();
      harness.painter.debugRecordSegments(records);
      records.expectBalancedWithoutSaveLayer();
    });
    testWidgets(
        'gradient backgrounds are supported on prizes and blocks (#402)',
        (tester) async {
      const gradient =
          LuckyFill.gradient(LinearGradient(colors: kWheelRenderColors));
      final harness = WheelPainterHarness(
          config: const WheelConfig(
              blocks: [WheelBlock(background: gradient)],
              prizes: [WheelPrize(background: gradient)]));
      final canvas = TestRecordingCanvas();
      harness.painter.debugRecordSegments(canvas);
      final args = _arguments(canvas, #drawPath);
      expect(args, hasLength(2));
      expect(
          args.map((a) => (a.last! as Paint).shader), everyElement(isNotNull));
    });
    testWidgets('images are drawn with FilterQuality.low like canvas smoothing',
        (tester) async {
      final config = _imageConfig();
      final harness = WheelPainterHarness(
          config: config, images: await _images(tester, config));
      final canvas = TestRecordingCanvas();
      harness.painter.debugRecordSegments(canvas);
      expect(_arguments(canvas, #drawImageRect), hasLength(5));
      expect(
          _arguments(canvas, #drawImageRect)
              .map((a) => (a.last! as Paint).filterQuality),
          everyElement(FilterQuality.low));
    });
    testWidgets(
        'prize painter paints in sector-local coordinates (#354 workaround)',
        (tester) async {
      WheelPrizePaintContext? seen;
      final harness = WheelPainterHarness(
          config: WheelConfig(prizes: [
        WheelPrize(painter: (canvas, context) {
          seen = context;
          canvas.drawCircle(Offset.zero, 7, Paint());
        }),
      ]));
      final canvas = TestRecordingCanvas();
      harness.painter.debugRecordSegments(canvas);
      expect(seen!.index, 0);
      expect(seen!.prizeRadius, 200);
      final rotation = canvas.invocations
          .indexWhere((r) => r.invocation.memberName == #rotate);
      final callback = canvas.invocations
          .indexWhere((r) => r.invocation.memberName == #drawCircle);
      expect(rotation, lessThan(callback));
      expect(canvas.invocations[rotation - 1].invocation.positionalArguments, [
        harness.data.layout.sectors.single.anchor.dx,
        harness.data.layout.sectors.single.anchor.dy
      ]);
    });
  });
}
