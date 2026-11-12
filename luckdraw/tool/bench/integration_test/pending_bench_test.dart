import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '../pending_metrics.dart';
import 'bench_support.dart';

/// 同一待测 APK 用运行路由选择冷首帧、CPU 或四项帧时复测。
void main() {
  final binding = benchBinding();
  testWidgets('pending > selected device check', (tester) async {
    final route =
        ui.PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '');
    if (kPendingFirstFrames.contains(route)) {
      await runPendingFirstFrameBench(binding, tester, route);
    } else if (route.startsWith('cpu_') &&
        kPendingCpuScenes.contains(route.substring(4))) {
      await runPendingCpuBench(binding, tester, route.substring(4));
    } else if (kPendingRetests.contains(route)) {
      await runSteadyBench(binding, tester, route);
    } else {
      throw ArgumentError.value(route, 'route', '未知待测项目');
    }
  });
}
