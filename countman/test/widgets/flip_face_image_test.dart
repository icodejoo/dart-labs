import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bitmap.dart';

/// 统计位图与段落提交次数，其余调用忽略。
class _Probe implements Canvas {
  int images = 0;
  int paragraphs = 0;
  final bitmaps = <ui.Image>[];
  final sources = <Rect>[];
  final destinations = <Rect>[];

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    images++;
    bitmaps.add(image);
    sources.add(src);
    destinations.add(dst);
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => paragraphs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 带一个位数从 4 翻到 5 的单卡画笔。
FlipCardPainter _painter(
  AnimationController c,
  CountdownType type, {
  TextStyle style = const TextStyle(fontSize: 22, color: Colors.white),
  Color color = const Color(0xFF212121),
}) {
  final cache = CardGlyphCache();
  addTearDown(cache.clear);
  return FlipCardPainter(
    repaint: c,
    controller: c,
    model: CardModel([4])
      ..target = [5]
      ..changedMask = [true],
    geom: const CardGeometry(
      size: Size(30, 40),
      cells: [Cell(0, 30, 0, BorderRadius.all(Radius.circular(4)))],
      separatorCenters: [],
      unitLabelCenters: [],
      unitLabelText: [],
    ),
    transitionType: type,
    scaleEffect: SlideEffect.none,
    scaleFactor: 1.5,
    opacityEffect: SlideEffect.none,
    perspective: 0.006,
    cardHeight: 40,
    cardColor: color,
    textStyle: style,
    labelStyle: const TextStyle(fontSize: 11),
    separatorStyle: const TextStyle(fontSize: 15),
    separator: ':',
    digitCache: cache,
    sepCache: cache,
    labelCache: cache,
  );
}

/// 测试用子类：重写外观钩子，验证不会被位图路径绕过。
class _CustomPainter extends FlipCardPainter {
  _CustomPainter(FlipCardPainter p)
    : super(
        repaint: p.controller,
        controller: p.controller,
        model: p.model,
        geom: p.geom,
        transitionType: p.transitionType,
        scaleEffect: p.scaleEffect,
        scaleFactor: p.scaleFactor,
        opacityEffect: p.opacityEffect,
        perspective: p.perspective,
        cardHeight: p.cardHeight,
        cardColor: p.cardColor,
        textStyle: p.textStyle,
        labelStyle: p.labelStyle,
        separatorStyle: p.separatorStyle,
        separator: p.separator,
        digitCache: p.digitCache,
        sepCache: p.sepCache,
        labelCache: p.labelCache,
      );
}

void main() {
  tearDown(FlipCardPainter.clearFaceImageCache);

  testWidgets('calendar 翻转中的四个半卡走位图，不再逐帧提交文字段落', (tester) async {
    final c = AnimationController(vsync: tester, value: 0.4);
    final probe = _Probe();
    _painter(c, CountdownType.calendar).paint(probe, const Size(30, 40));
    expect(probe.images, 4);
    expect(probe.paragraphs, 0);
    c.dispose();
  });

  testWidgets('flip 旋转的整卡走位图', (tester) async {
    final c = AnimationController(vsync: tester, value: 0.3);
    final probe = _Probe();
    _painter(c, CountdownType.flip).paint(probe, const Size(30, 40));
    expect(probe.images, 1);
    expect(probe.paragraphs, 0);
    c.dispose();
  });

  testWidgets('子类画笔保持矢量路径，外观钩子不被绕过', (tester) async {
    final c = AnimationController(vsync: tester, value: 0.4);
    final probe = _Probe();
    _CustomPainter(
      _painter(c, CountdownType.calendar),
    ).paint(probe, const Size(30, 40));
    expect(probe.images, 0);
    expect(probe.paragraphs, greaterThan(0));
    c.dispose();
  });

  testWidgets('卡面命中跨画笔共享，公开清理释放并重建位图', (tester) async {
    final c = AnimationController(vsync: tester);
    addTearDown(c.dispose);
    const rect = Rect.fromLTWH(20, 20, 30, 40);
    ui.Image image(FlipCardPainter p) {
      final probe = _Probe();
      p.drawRotatedFace(probe, rect, 4, BorderRadius.zero, 0, 1, 1);
      expect(probe.destinations.single.contains(rect.topLeft), isTrue);
      return probe.bitmaps.single;
    }

    final p = _painter(c, CountdownType.flip);
    final first = image(p);
    expect(image(_painter(c, CountdownType.flip)), same(first));
    FlipCardPainter.clearFaceImageCache();
    FlipCardPainter.clearFaceImageCache();
    expect(first.debugDisposed, isTrue);
    expect(p.digitCache, isNotEmpty);
    expect(image(p), isNot(same(first)));
  });

  testWidgets('卡面 8 MiB 预算包含边距，命中保留较新项', (tester) async {
    final c = AnimationController(vsync: tester);
    addTearDown(c.dispose);
    final p = _painter(c, CountdownType.flip);
    const rect = Rect.fromLTWH(0, 0, 180, 180);
    ui.Image image(int value) {
      final probe = _Probe();
      p.drawRotatedFace(probe, rect, value, BorderRadius.zero, 0, 1, 1);
      return probe.bitmaps.single;
    }

    final first = image(0);
    final second = image(1);
    final cost = first.width * first.height * 4;
    final capacity = (8 * 1024 * 1024) ~/ cost;
    for (var i = 2; i < capacity; i++) {
      image(i);
    }
    expect(image(0), same(first));
    image(capacity);
    expect(second.debugDisposed, isTrue);
    expect(first.debugDisposed, isFalse);
  });

  testWidgets('卡面超预算、空尺寸和生成失败回退矢量', (tester) async {
    final c = AnimationController(vsync: tester);
    addTearDown(c.dispose);
    final p = _painter(c, CountdownType.flip);
    for (final rect in [
      const Rect.fromLTWH(0, 0, 2000, 2000),
      Rect.zero,
      const Rect.fromLTWH(0, 0, double.infinity, 40),
    ]) {
      final probe = _Probe();
      p.drawRotatedFace(probe, rect, 4, BorderRadius.zero, 0, 1, 1);
      expect(probe.images, 0);
      expect(probe.paragraphs, 1);
    }
  });

  testWidgets('alpha 小于 1 保持矢量逐层合成，真实像素与原路径一致', (tester) async {
    final c = AnimationController(vsync: tester);
    addTearDown(c.dispose);
    final p = _painter(c, CountdownType.flip);
    const rect = Rect.fromLTWH(40, 40, 30, 40);
    for (final scale in [1.0, 1.2]) {
      final probe = _Probe();
      p.drawRotatedFace(probe, rect, 4, BorderRadius.zero, 0, 0.5, scale);
      expect(probe.images, 0);
      expect(probe.paragraphs, 1);
    }
    final actual = await raster(
      tester,
      (canvas) =>
          p.drawRotatedFace(canvas, rect, 4, BorderRadius.zero, 0, 0.5, 1),
    );
    final expected = await raster(
      tester,
      (canvas) => p.drawFaceWithAlpha(canvas, rect, 4, BorderRadius.zero, 0.5),
    );
    expect(actual, expected);
    final alpha = [for (var i = 3; i < actual.length; i += 4) actual[i]];
    expect(alpha.reduce((a, b) => a > b ? a : b), 196);
  });

  testWidgets('大字及阴影在整卡旋转时保留卡面外像素，半卡保持裁切', (tester) async {
    final c = AnimationController(vsync: tester);
    addTearDown(c.dispose);
    const rect = Rect.fromLTWH(65, 55, 30, 40);
    for (final shadows in [
      <Shadow>[],
      const [Shadow(color: Colors.red, offset: Offset(12, -9), blurRadius: 4)],
    ]) {
      final p = _painter(
        c,
        CountdownType.flip,
        style: TextStyle(fontSize: 70, color: Colors.white, shadows: shadows),
      );
      final vector = _CustomPainter(p);
      final actual = await raster(
        tester,
        (canvas) =>
            p.drawRotatedFace(canvas, rect, 4, BorderRadius.zero, 0.2, 1, 1.1),
      );
      final expected = await raster(
        tester,
        (canvas) => vector.drawRotatedFace(
          canvas,
          rect,
          4,
          BorderRadius.zero,
          0.2,
          1,
          1.1,
        ),
      );
      var outside = 0;
      for (var y = 0; y < 160; y++) {
        for (var x = 0; x < 160; x++) {
          if (!rect.contains(Offset(x.toDouble(), y.toDouble())) &&
              actual[(y * 160 + x) * 4 + 3] > 0) {
            outside++;
          }
        }
      }
      expect(outside, greaterThan(100));
      expectPixelsClose(actual, expected, meanTolerance: 2);
      var actualAlpha = 0;
      var expectedAlpha = 0;
      for (var i = 3; i < actual.length; i += 4) {
        actualAlpha += actual[i];
        expectedAlpha += expected[i];
      }
      expect(actualAlpha / expectedAlpha, closeTo(1, 0.03));
      for (final upper in [true, false]) {
        final half = await raster(
          tester,
          (canvas) => p.rotatedCalendarHalf(
            canvas,
            rect,
            4,
            BorderRadius.zero,
            FlipCardPainter.calendarZeroAngle,
            upper: upper,
          ),
        );
        final reference = await raster(
          tester,
          (canvas) => vector.rotatedCalendarHalf(
            canvas,
            rect,
            4,
            BorderRadius.zero,
            FlipCardPainter.calendarZeroAngle,
            upper: upper,
          ),
        );
        expectPixelsClose(half, reference);
        expect(half[(50 * 160 + 70) * 4 + 3], 0);
        expect(half[(60 * 160 + 60) * 4 + 3], 0);
      }
    }
  });
}
