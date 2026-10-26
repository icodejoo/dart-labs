@Tags(['benchmark'])
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inner_reference.dart';
import 'paint_probe.dart';

/// 将真实画布输出转换成像素，覆盖圆头重叠和透明混合的差异。
Future<Uint8List> _pixels(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size.square(200));
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return Uint8List.fromList(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 统计至少一个通道发生变化的像素数量。
int _differentPixels(Uint8List a, Uint8List b) {
  var different = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      different++;
    }
  }
  return different;
}

/// 按颜色归并相接区间，比较合并前后的覆盖范围与颜色。
Map<Color, List<(double, double)>> _coverage(PaintProbe probe) {
  final result = <Color, List<(double, double)>>{};
  for (final arc in probe.arcs) {
    final start = math.min(arc.start, arc.start + arc.sweep);
    final end = math.max(arc.start, arc.start + arc.sweep);
    result.putIfAbsent(arc.color, () => []).add((start, end));
  }
  for (final entry in result.entries) {
    final sorted = entry.value..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(double, double)>[];
    for (final interval in sorted) {
      if (merged.isNotEmpty && interval.$1 <= merged.last.$2 + 1e-12) {
        merged[merged.length - 1] =
            (merged.last.$1, math.max(merged.last.$2, interval.$2));
      } else {
        merged.add(interval);
      }
    }
    result[entry.key] = merged;
  }
  return result;
}

/// 对照生产实现、冻结参考与候选的几何和真实像素。
void main() {
  tearDown(Countman.destroy);

  test('分钟段合并的覆盖区间与颜色一致', () {
    for (final clockwise in [true, false]) {
      for (final total in [
        0,
        999,
        10000,
        59999,
        60000,
        60001,
        3599123,
        3600000
      ]) {
        for (final remaining in [
          0,
          1,
          2999,
          3000,
          9999,
          10000,
          59999,
          60000,
          60001,
          1234567,
          total,
          total + 1000
        ]) {
          final before = PaintProbe();
          final after = PaintProbe();
          InnerReference(
                  totalMs: total, remainingMs: remaining, clockwise: clockwise)
              .paint(before, const Size.square(200));
          InnerReference(
                  totalMs: total,
                  remainingMs: remaining,
                  clockwise: clockwise,
                  merged: true)
              .paint(after, const Size.square(200));
          final expected = _coverage(before);
          final actual = _coverage(after);
          expect(actual.keys, unorderedEquals(expected.keys));
          for (final color in expected.keys) {
            expect(actual[color]!.length, expected[color]!.length);
            for (var i = 0; i < expected[color]!.length; i++) {
              expect(
                  actual[color]![i].$1, closeTo(expected[color]![i].$1, 1e-12));
              expect(
                  actual[color]![i].$2, closeTo(expected[color]![i].$2, 1e-12));
            }
          }
        }
      }
    }
  });

  testWidgets('冻结参考逐笔匹配生产内圈', (tester) async {
    late TimeParts parts;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: DialCountdown(
        to: const Duration(hours: 1),
        style: const DialCountdownStyle(
            showTicks: false, showArcA: false, showArcB: false),
        builder: (context, value) {
          parts = value;
          return const SizedBox.shrink();
        },
      ),
    ));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere((widget) => widget.painter != null)
        .painter!;
    for (final remaining in [
      0,
      1,
      3000,
      10000,
      60000,
      60001,
      1234567,
      3600000
    ]) {
      parts.set(Duration(milliseconds: remaining), const Duration(hours: 1));
      final actual = PaintProbe();
      final expected = PaintProbe();
      painter.paint(actual, const Size.square(200));
      InnerReference(remainingMs: remaining)
          .paint(expected, const Size.square(200));
      expect(actual.arcs, expected.arcs);
      expect(actual.paints.length, expected.paints.length);
    }
    parts.set(const Duration(hours: 1), const Duration(hours: 1));
    await tester.runAsync(() async {
      expect(await _pixels(painter), await _pixels(const InnerReference()));
    });
  });

  for (final glow in [false, true]) {
    testWidgets('圆头分钟段合并会改变像素 glow=$glow', (tester) async {
      for (final colors in [
        const DialColors(),
        const DialColors(normal: Color(0x80FF6A5A))
      ]) {
        await tester.runAsync(() async {
          final before =
              await _pixels(InnerReference(glow: glow, colors: colors));
          final after = await _pixels(
              InnerReference(glow: glow, colors: colors, merged: true));
          final difference = _differentPixels(before, after);
          // 几何相等不足以保证视觉相等；记录否决直接合并的可复现证据。
          expect(difference, greaterThan(0));
          // ignore: avoid_print
          print('merge pixel differences: glow=$glow alpha=${colors.normal.a} '
              'pixels=$difference/40000');
        });
      }
    });
  }
}
