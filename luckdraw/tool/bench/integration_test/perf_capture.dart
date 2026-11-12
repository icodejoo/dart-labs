import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/src/wheel/render/wheel_painter.dart';
import 'package:luckdraw/wheel.dart';

import '../lib/main.dart';

/// 同一真机、同一 37° 运动姿态的截图，独立于帧时采样。
Future<void> capturePerfWheel(
    IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester) async {
  final images = await prepareBenchImages();
  final captures = <String, String>{};
  final metadata = <String, Object?>{};
  final modes = [LuckyCacheMode.picture, LuckyCacheMode.auto];
  for (final mode in modes) {
    final scene =
        createBenchScene('wheel_steady', images, wheelCacheMode: mode);
    const boundaryKey = ValueKey('perf-wheel-capture');
    try {
      await tester.pumpWidget(
          benchShell(RepaintBoundary(key: boundaryKey, child: scene.widget)));
      await scene.ready.timeout(const Duration(seconds: 15));
      expect(scene.play(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final controller = (scene.widget as LuckyWheel).controller!;
      controller.pauseForLifecycle();
      controller.frame.rotateDeg = 37;
      expect(controller.frame.phase.isMoving, isTrue);
      final paint = find.descendant(
          of: find.byType(LuckyWheel), matching: find.byType(CustomPaint));
      tester.renderObject(paint).markNeedsPaint();
      await tester.pump();
      final painter =
          tester.widget<CustomPaint>(paint).painter! as WheelPainter;
      metadata[mode.name] = {
        'rotate_deg': controller.frame.rotateDeg,
        'phase': controller.frame.phase.name,
        'dpr': tester.view.devicePixelRatio,
        'raster_rgba_bytes': painter.cache.debugRasterBytes,
      };
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      final image =
          await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        captures['wheel_37_${mode.name}'] =
            base64Encode(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } finally {
      await tester.pumpWidget(benchShell(const SizedBox.shrink()));
      scene.dispose();
    }
  }
  binding.reportData = {
    'bench_samples': <String, Object?>{},
    'perf_images': captures,
    'perf_capture_metadata': metadata,
  };
}
