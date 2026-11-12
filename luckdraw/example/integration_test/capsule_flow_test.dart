import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/capsule_page.dart';

import 'support/flows.dart';

/// 真实旋钮命中、胶囊掉落及奖品卡展示。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('capsule flow', () {
    testWidgets(
        'knob tap then server result drops and reveals the target capsule',
        (tester) async {
      await openDemo(tester, '扭蛋机');
      final controller =
          tester.state<CapsulePageState>(find.byType(CapsulePage)).controller;
      final machine = find.byType(LuckyCapsuleMachine);
      final input = LuckyLayoutInput.headless(tester.getSize(machine));
      final layout =
          const CapsuleGame().computeLayout(CapsulePageState.config, input);
      input.measurer.dispose();
      final stages = <CapsuleStage>{};

      /// 复制阶段值验证掉落与开蛋确实经过真实帧。
      void record() => stages.add(controller.frame.stage);
      controller.frameListenable.addListener(record);
      await tester.tapAt(tester.getTopLeft(machine) + layout.knobCenter);
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      controller.frameListenable.removeListener(record);
      expect(
          stages,
          containsAll([
            CapsuleStage.mixing,
            CapsuleStage.dropping,
            CapsuleStage.revealing,
            CapsuleStage.done
          ]));
      expect(controller.frame.targetPrize, demoTarget);
      expect(controller.frame.dropProgress, 1);
      expect(controller.frame.revealProgress, 1);
      expect(controller.lastResult?.prize,
          CapsulePageState.config.prizes[demoTarget]);
      await finishDemo(tester, () => controller.phase.value, '奖品：$demoTarget');
    });
  });
}
