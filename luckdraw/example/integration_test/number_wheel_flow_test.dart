import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw_example/pages/number_wheel_page.dart';

import 'support/flows.dart';

/// 验证服务端号码落入对应的外缘格。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('number wheel flow', () {
    testWidgets('stopNumber on a server number lands the ball in that pocket',
        (tester) async {
      await openDemo(tester, '数字转盘');
      final controller = tester
          .state<NumberWheelPageState>(find.byType(NumberWheelPage))
          .controller;
      await tester.tap(find.byType(LuckyNumberWheel));
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      final disc = controller.frame.discDeg;
      final ball = controller.frame.ballDeg;
      await tester.pump(flowStep);
      expect(
          (controller.frame.discDeg - disc) * (controller.frame.ballDeg - ball),
          lessThan(0));
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      expect(controller.lastNumber, NumberWheelPageState.targetNumber);
      final target = NumberWheelPageState.config.pockets.indexWhere(
          (pocket) => pocket.number == NumberWheelPageState.targetNumber);
      expect(controller.frame.ballPocket, target);
      expect(controller.frame.targetIndex, target);
      expect(controller.frame.ballRadius.isFinite, isTrue);
      await finishDemo(tester, () => controller.phase.value,
          '号码：${NumberWheelPageState.targetNumber}');
    });
  });
}
