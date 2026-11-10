import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/wheel.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/wheel_page.dart';

import 'support/flows.dart';

/// 转盘从菜单、点击、等待服务端到结算的真实桌面流程。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('wheel flow', () {
    testWidgets('tap start then server result settles on the target',
        (tester) async {
      await openDemo(tester, '转盘');
      final state = tester.state<WheelPageState>(find.byType(WheelPage));
      final controller = state.controller;
      await tester.tap(find.byType(LuckyWheel));
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      final angle = controller.frame.rotateDeg;
      await tester.pump(flowStep);
      expect(controller.frame.rotateDeg, greaterThan(angle));
      expect(controller.lastResult, isNull);
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      expect(controller.lastResult?.index, demoTarget);
      expect(controller.lastResult?.prize,
          WheelPageState.config.prizes[demoTarget]);
      expect(controller.frame.pointerIndex, demoTarget);
      await finishDemo(tester, () => controller.phase.value, '奖品：$demoTarget');
      expect(controller.isAttached, isFalse);
    });
  });
}
