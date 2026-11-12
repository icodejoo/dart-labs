import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bitmap.dart';

class _Probe implements Canvas {
  final images = <ui.Image>[];
  final destinations = <Rect>[];
  var lines = 0;

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    images.add(image);
    destinations.add(dst);
  }

  @override
  void drawLine(Offset a, Offset b, Paint paint) => lines++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _style = DialCountdownStyle(
  showArcA: false,
  showArcB: false,
  showInner: false,
);

Future<CustomPainter> _mount(
  WidgetTester tester, {
  DialCountdownStyle style = _style,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: DialCountdown(to: const Duration(seconds: 60), style: style),
      ),
    ),
  );
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere((w) => w.painter != null)
      .painter!;
}

void main() {
  tearDown(Countman.destroy);
  tearDown(DialCountdown.clearTickImageCache);

  testWidgets('刻度环按值命中且公开清理释放位图，下次绘制重建', (tester) async {
    final painter = await _mount(tester);
    ui.Image image() {
      final probe = _Probe();
      painter.paint(probe, const Size.square(200));
      expect(probe.lines, 0);
      expect(probe.destinations.single, const Rect.fromLTWH(0, 0, 200, 200));
      return probe.images.single;
    }

    final first = image();
    // 新配置实例的值相同，也应命中。
    (painter as dynamic).update(
      TimeParts.of(const Duration(seconds: 60)),
      const DialCountdownStyle(
        ticks: DialTicksConfig(),
        showArcA: false,
        showArcB: false,
        showInner: false,
      ),
    );
    expect(image(), same(first));
    DialCountdown.clearTickImageCache();
    DialCountdown.clearTickImageCache();
    expect(first.debugDisposed, isTrue);
    expect(image(), isNot(same(first)));
  });

  testWidgets('刻度环 32 MiB 字节预算按 LRU 淘汰并 dispose', (tester) async {
    final painter = await _mount(tester);
    DialCountdown.clearTickImageCache();
    ui.Image image(int seconds) {
      (painter as dynamic).update(
        TimeParts.of(Duration(seconds: seconds)),
        _style,
      );
      final probe = _Probe();
      painter.paint(probe, const Size.square(400));
      return probe.images.single;
    }

    final first = image(1);
    final second = image(2);
    final cost = first.width * first.height * 4;
    final capacity = (32 * 1024 * 1024) ~/ cost;
    for (var i = 3; i <= capacity; i++) {
      image(i);
    }
    expect(image(1), same(first));
    image(capacity + 1);
    expect(second.debugDisposed, isTrue);
    expect(first.debugDisposed, isFalse);
  });

  testWidgets('刻度环单张超预算、空尺寸和生成失败均回退矢量', (tester) async {
    final painter = await _mount(tester);
    for (final size in [
      const Size.square(4000),
      Size.zero,
      const Size(double.infinity, 200),
    ]) {
      final probe = _Probe();
      painter.paint(probe, size);
      expect(probe.images, isEmpty);
      expect(probe.lines, 60);
    }
  });

  testWidgets('glow 位图边距保留矩形外像素，位置与矢量一致', (tester) async {
    final painter = await _mount(
      tester,
      style: const DialCountdownStyle(
        glow: true,
        ticks: DialTicksConfig(count: 4, radius: 49, width: 2),
        showArcA: false,
        showArcB: false,
        showInner: false,
      ),
    );
    const size = Size.square(100);
    final probe = _Probe();
    painter.paint(probe, size);
    expect(probe.destinations.single, const Rect.fromLTWH(-6, -6, 112, 112));
    expect(probe.images.single.width, greaterThan(100));
    final actual = await raster(tester, (canvas) {
      canvas.translate(30, 30);
      painter.paint(canvas, size);
    });
    (painter as dynamic).debugUseTickImages = false;
    final expected = await raster(tester, (canvas) {
      canvas.translate(30, 30);
      painter.paint(canvas, size);
    });
    expect(actual[(28 * 160 + 80) * 4 + 3], greaterThan(0));
    expect(expected[(28 * 160 + 80) * 4 + 3], greaterThan(0));
    expectPixelsClose(actual, expected, meanTolerance: 0.1);
  });
}
