import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/luckdraw.dart';

import '../lib/main.dart' show benchVariant;
import 'bench_support.dart';
import 'perf_capture.dart';

/// 用启动路由选择场景，同一 profile APK 可复用全部 PERF 实验。
void main() {
  final binding = benchBinding();
  testWidgets('perf > selected device scenario', (tester) async {
    final variant =
        ui.PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '');
    if (variant == 'wheel_capture') {
      await capturePerfWheel(binding, tester);
      return;
    }
    final wheel = variant.startsWith('wheel_');
    benchVariant = variant;
    final key = wheel
        ? 'wheel_steady'
        : variant.startsWith('grid_')
            ? 'grid_steady'
            : variant == 'slot_noimg'
                ? 'slot_raster'
                : variant;
    await runSteadyBench(binding, tester, key,
        wheelCacheMode: variant == 'wheel_raster'
            ? LuckyCacheMode.raster
            : wheel && variant != 'wheel_default'
                ? LuckyCacheMode.picture
                : null,
        wheelTexts: variant != 'wheel_no_text',
        wheelImages: variant != 'wheel_no_images');
  });
}
