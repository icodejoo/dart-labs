import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

import 'package:luckdraw/src/core/render/paint_helpers.dart';
import 'package:luckdraw/src/core/render/perf_trace.dart';
import '../../support/fixtures.dart';
import '../../support/recording_canvas.dart';

/// 测试布局。
final class _Layout extends LuckyLayout {
  /// 创建固定尺寸布局。
  const _Layout() : super(size: const Size(100, 100));

  /// 测试布局非空。
  @override
  bool get isEmpty => false;
}

/// 测试帧。
final class _Frame extends LuckyFrame {}

/// 在 TextPainter 释放段落前记录真实文字宽度和位置。
final class _TextCanvas extends TestRecordingCanvas {
  /// 最近一次段落宽度。
  double width = 0;

  /// 最近一次段落位置。
  Offset position = Offset.zero;

  /// 同步读取段落度量并记录画布调用。
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    width = paragraph.longestLine;
    position = offset;
    super.drawParagraph(paragraph, offset);
  }
}

/// 验证插件层协议和内部录制助手。
void main() {
  group('LuckyLayer', () {
    testWidgets('recording text uses the same textScale as measurement',
        (tester) async {
      const scale = TextScaler.linear(2);
      const style = TextStyle(fontSize: 12);
      const line = LuckyTextLine('奖品', 0, 30, style);
      final measurer = TextPainterMeasurer(textScaler: scale);
      final canvas = _TextCanvas();
      paintLuckyTextLines(canvas, [line], measurer, textScale: scale);
      final painter = TextPainter(
          text: const TextSpan(text: '奖品', style: style),
          textDirection: TextDirection.ltr,
          textScaler: scale)
        ..layout();
      // 录制出的段落宽度与相同倍率的布局测量一致。
      expect(canvas.width, measurer.measure('奖品', style));
      expect(canvas.position, Offset(0, 30 - measurer.baseline(style)));
      expect(measurer.measure('奖品', style), painter.width);
      painter.dispose();
      measurer.dispose();
    });
    testWidgets(
        'static layers are recorded into the cache and not repainted per frame',
        (tester) async {
      var paints = 0;
      final layer = LuckyCallbackLayer<_Layout, _Frame>((canvas, context) {
        paints++;
        expect(context.size, context.layout.size);
      }, isStatic: true);
      final context = LuckyLayerContext<_Layout, _Frame>()
        ..layout = const _Layout()
        ..frame = _Frame()
        ..size = const Size(100, 100);
      final cache = LuckyPictureCache();
      for (var tick = 0; tick < 10; tick++) {
        final picture =
            cache.picture(0, (canvas) => layer.paint(canvas, context));
        final canvas = TestRecordingCanvas()..drawPicture(picture);
        expect(canvas.countCalls(#drawPicture), 1);
      }
      expect(layer.shouldRepaint(layer), isFalse);
      expect(layer.isStatic, isTrue);
      expect(layer.rotatesWithWheel, isFalse);
      expect(paints, 1);
      expect(cache.debugRecordCount, 1);
      cache.dispose();
    });
    testWidgets('dynamic layers paint every frame in position order',
        (tester) async {
      final order = <LuckyLayerPosition>[];
      final context = LuckyLayerContext<_Layout, _Frame>()
        ..layout = const _Layout()
        ..frame = _Frame()
        ..size = const Size(100, 100);
      final layers = [
        for (final position in LuckyLayerPosition.values)
          LuckyCallbackLayer<_Layout, _Frame>(
              (canvas, context) => order.add(position),
              position: position)
      ];
      for (var frame = 0; frame < 2; frame++) {
        for (final layer in layers) {
          layer.paint(TestRecordingCanvas(), context);
        }
      }
      expect(
          order, [...LuckyLayerPosition.values, ...LuckyLayerPosition.values]);
      expect(context.devicePixelRatio, 1);
      expect(layers.every((layer) => !layer.isStatic), isTrue);
    });
    testWidgets('hooks beforeDraw and afterDraw wrap all layers',
        (tester) async {
      final calls = <String>[];
      final hooks = LuckyHooks(
          beforeDraw: (_, __) => calls.add('before'),
          afterDraw: (_, __) => calls.add('after'));
      final context = LuckyLayerContext<_Layout, _Frame>()
        ..layout = const _Layout()
        ..frame = _Frame()
        ..size = const Size(100, 100);
      final canvas = TestRecordingCanvas();
      hooks.beforeDraw!(canvas, context.size);
      LuckyCallbackLayer<_Layout, _Frame>((_, __) => calls.add('layer'))
          .paint(canvas, context);
      hooks.afterDraw!(canvas, context.size);
      expect(calls, ['before', 'layer', 'after']);
    });
    testWidgets('foreground layer draws above items for indicators (#227)',
        (tester) async {
      final canvas = TestRecordingCanvas();
      final context = LuckyLayerContext<_Layout, _Frame>()
        ..layout = const _Layout()
        ..frame = _Frame()
        ..size = const Size(100, 100);
      final layer = LuckyCallbackLayer<_Layout, _Frame>((canvas, context) =>
          canvas.drawColor(const Color(0xffff0000), BlendMode.src));
      canvas.drawColor(const Color(0xff0000ff), BlendMode.src);
      layer.paint(canvas, context);
      expect(layer.position, LuckyLayerPosition.foreground);
      expect(canvas.invocations.last.invocation.positionalArguments.first,
          const Color(0xffff0000));
    });
    testWidgets(
        'recording helpers preserve shadows opacity clipping baselines and avoid saveLayer',
        (tester) async {
      luckyTraceStart('test');
      luckyTraceEnd();
      final canvas = TestRecordingCanvas();
      const rect = Rect.fromLTWH(0, 0, 20, 20);
      final path = Path()..addRect(rect);
      const fill = LuckyColorFill(Color(0xff0000ff));
      paintLuckyFill(canvas, path, fill, rect);
      paintLuckyFill(canvas, path, fill, rect,
          shadow: const LuckyShadow(color: Color(0xff000000), blur: 4), dpr: 2);
      paintLuckyFill(canvas, path, fill, rect,
          shadow: const LuckyShadow(color: Color(0xff000000)));
      strokeLuckyBorder(canvas, rect, 2,
          const LuckyBorder(width: 1, color: Color(0xff000000)));
      strokeLuckyBorder(canvas, rect, 2,
          const LuckyBorder(width: 0, color: Color(0xff000000)));
      final image = await createLuckyTestImage(color: const Color(0xff000000));
      drawLuckyImage(canvas, image, rect, borderRadius: 2, opacity: 0.5);
      drawLuckyImage(canvas, image, rect);
      const lines = [LuckyTextLine('奖品', 1, 18, TextStyle(fontSize: 12))];
      paintLuckyTextLines(canvas, lines, null);
      final measurer = TextPainterMeasurer();
      paintLuckyTextLines(canvas, lines, measurer);
      measurer.dispose();
      image.dispose();
      expect(canvas.countCalls(#drawPath), 5);
      expect(canvas.countCalls(#drawImageRect), 2);
      expect(canvas.countCalls(#drawParagraph), 2);
      canvas.expectBalancedWithoutSaveLayer();
      final input = LuckyLayoutInput.headless(const Size(100, 100));
      expect(input.textDirection, TextDirection.ltr);
      expect(input.alignment, Alignment.topLeft);
      input.measurer.dispose();
    });
  });
}
