import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/render/capsule_painter.dart';
import 'package:luckdraw/src/grid/render/grid_painter.dart';
import 'package:luckdraw/src/lotto/render/lotto_painter.dart';
import 'package:luckdraw/src/number_wheel/render/number_wheel_painter.dart';
import 'package:luckdraw/src/wheel/render/wheel_painter.dart';

// 复用独立基准工程的真实配置；主包不增加对该应用的依赖或复制场景配置。
// ignore: avoid_relative_lib_imports
import '../../tool/bench/lib/main.dart';

/// 以真机相同逻辑尺寸及 DPR 检查各场景纹理占用，不把它等同于 RSS。
void main() {
  testWidgets(
      'PERF memory > native byte totals match bench bounds at device DPR',
      (tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final images = await tester.runAsync(prepareBenchImages);
    final sizes = <String, int>{};
    final scenes = [
      'wheel_steady',
      'number_wheel_spin',
      'capsule_mixing',
      'lotto_draw',
      'grid_steady'
    ];
    for (final key in scenes) {
      final scene = createBenchScene(key, images!);
      await tester.pumpWidget(benchShell(scene.widget));
      var ready = false;
      final readiness = scene.ready.then((_) {
        ready = true;
      });
      for (var turn = 0; turn < 100 && !ready; turn++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ready, isTrue);
      await readiness;
      await tester.pump();
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter);
      final LuckyPictureCache cache;
      switch (key) {
        case 'wheel_steady':
          cache = painters.whereType<WheelPainter>().single.cache;
        case 'number_wheel_spin':
          cache = painters.whereType<NumberWheelPainter>().single.cache;
        case 'capsule_mixing':
          cache = painters.whereType<CapsulePainter>().single.pictures.cache;
        case 'lotto_draw':
          cache = painters.whereType<LottoPainter>().single.cache;
        case 'grid_steady':
          cache = painters.whereType<GridPainter>().single.cache;
        default:
          throw StateError('未覆盖的基准场景');
      }
      sizes[key] = cache.debugRasterBytes;
      expect(sizes[key], greaterThan(0));
      if (key == 'wheel_steady' || key == 'number_wheel_spin') {
        expect(sizes[key], 880 * 880 * 4);
      }
      await tester.pumpWidget(const SizedBox());
      scene.dispose();
      expect(cache.debugRasterBytes, 0);
    }
    expect(sizes.length, scenes.length);
    debugPrint('PERF_NATIVE_RGBA_BYTES ${jsonEncode(sizes)}');
  });
}
