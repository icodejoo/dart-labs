import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/benchmark_frame_driver.dart';

class _StaticPainter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_StaticPainter oldDelegate) => false;
}

void main() {
  testWidgets('逐帧平移并绕回，仅重绘驱动边界，卸载释放 ticker', (tester) async {
    final staticPainter = _StaticPainter();
    Widget page({Key? driverKey, Color color = Colors.black}) => Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: color,
        child: Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: const Size(10, 10),
                painter: staticPainter,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: BenchmarkFrameDriver(key: driverKey),
            ),
          ],
        ),
      ),
    );
    final driverPaint = find.descendant(
      of: find.byType(BenchmarkFrameDriver),
      matching: find.byType(CustomPaint),
    );
    final driverBoundary = find.descendant(
      of: find.byType(BenchmarkFrameDriver),
      matching: find.byType(RepaintBoundary),
    );
    Future<int> pixelX() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        driverBoundary,
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final width = image.width;
      image.dispose();
      return List.generate(
        width,
        (x) => x,
      ).firstWhere((x) => bytes.getUint8((width + x) * 4 + 3) > 0);
    }

    await tester.pumpWidget(page());
    final first = tester.widget<CustomPaint>(driverPaint).painter!;
    final firstX = await tester.runAsync(pixelX);
    final paints = staticPainter.paints;
    await tester.pump(const Duration(milliseconds: 16));
    expect(await tester.runAsync(pixelX), (firstX! + 1) % 32);
    for (var i = 0; i < 31; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(await tester.runAsync(pixelX), firstX);
    expect(staticPainter.paints, paints);

    await tester.pumpWidget(page(color: Colors.white));
    final same = tester.widget<CustomPaint>(driverPaint).painter!;
    expect(same.shouldRepaint(first), isFalse);
    await tester.pumpWidget(page(driverKey: const ValueKey('new')));
    final different = tester.widget<CustomPaint>(driverPaint).painter!;
    expect(different.shouldRepaint(first), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
