import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/wheel.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/wheel_page.dart';

import 'support/flows.dart';

/// 后台期间不 pump，恢复后检查暂停前后的状态与有限角度。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('lifecycle', () {
    testWidgets('background for 10 seconds then resume keeps state bounded',
        (tester) async {
      await openDemo(tester, '转盘');
      final controller =
          tester.state<WheelPageState>(find.byType(WheelPage)).controller;
      await tester.tap(find.byKey(startKey));
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      final phase = controller.phase.value;
      final angle = controller.frame.rotateDeg;
      // AppLifecycleListener 要求 resumed 与 hidden 之间经过 inactive。
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      try {
        expect(controller.isPaused, isTrue);
        await Future<void>.delayed(const Duration(seconds: 10));
        expect(controller.frame.rotateDeg, angle);
        expect(controller.phase.value, phase);
      } finally {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pump();
      expect(controller.isPaused, isFalse);
      expect(controller.frame.rotateDeg.isFinite, isTrue);
      expect((controller.frame.rotateDeg - angle).abs(), lessThan(180));
      await serverResult(tester);
      await finishDemo(tester, () => controller.phase.value, '奖品：$demoTarget');
    });
  });
}
