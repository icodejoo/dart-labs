import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/wheel.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/wheel_page.dart';

import 'support/flows.dart';

/// 原生窗口测试通道，仅 LUCKDRAW_TEST_WINDOW=1 时启用。
const MethodChannel _window = MethodChannel('luckdraw/test_window');

/// Windows 原生尺寸或安卓视口改变均保留运动状态。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('resize', () {
    testWidgets('window resize mid spin keeps phase and angle', (tester) async {
      await openDemo(tester, '转盘');
      final controller =
          tester.state<WheelPageState>(find.byType(WheelPage)).controller;
      await tester.tap(find.byKey(startKey));
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      controller.pause();
      final angle = controller.frame.rotateDeg;
      final phase = controller.phase.value;
      final before = tester.getSize(find.byType(DemoShell));
      final wheelBefore = tester.getSize(find.byType(LuckyWheel));
      try {
        if (Platform.isWindows) {
          final initial =
              await _window.invokeMapMethod<String, Object?>('inspect');
          expect(initial?['foreground'], isFalse);
          final resized =
              await _window.invokeMapMethod<String, Object?>('resize', 280);
          expect(resized?['width'], 280);
          expect(resized?['height'], 720);
          expect(resized?['foreground'], isFalse);
        } else {
          // 与 Windows 的逻辑视口保持一致，不能把 280dp 当成 280 设备像素。
          tester.view.physicalSize =
              const Size(280, 720) * tester.view.devicePixelRatio;
        }
        await tester.pump();
        await waitFor(
            tester, () => tester.getSize(find.byType(DemoShell)) != before);
        expect(controller.phase.value, phase);
        expect(controller.frame.rotateDeg, angle);
        expect(tester.getSize(find.byType(LuckyWheel)).width,
            lessThan(wheelBefore.width));
      } finally {
        if (Platform.isWindows) {
          await _window.invokeMethod<void>('resize', 480);
        } else {
          tester.view.resetPhysicalSize();
        }
      }
      controller.resume();
      await tester.pump();
      await serverResult(tester);
      await finishDemo(tester, () => controller.phase.value, '奖品：$demoTarget');
    });
  });
}
