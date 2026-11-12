import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/lots_page.dart';

import 'support/flows.dart';

/// 真实签筒命中、升签和签文展示。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('lots flow', () {
    testWidgets('tap then server result lifts and reveals the target stick',
        (tester) async {
      await openDemo(tester, '抽签');
      final controller =
          tester.state<LotsPageState>(find.byType(LotsPage)).controller;
      final machine = find.byType(LuckyLots);
      final input = LuckyLayoutInput.headless(tester.getSize(machine));
      final layout =
          const LotsGame().computeLayout(LotsPageState.config, input);
      input.measurer.dispose();
      final stages = <LotsStage>{};

      /// 复制阶段值，避免跨帧保留可变帧快照。
      void record() => stages.add(controller.frame.stage);
      controller.frameListenable.addListener(record);
      await tester.tapAt(tester.getTopLeft(machine) + layout.cylinder.center);
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      controller.frameListenable.removeListener(record);
      expect(
          stages,
          containsAll([
            LotsStage.shaking,
            LotsStage.rising,
            LotsStage.revealing,
            LotsStage.done
          ]));
      expect(controller.frame.targetIndex, demoTarget);
      expect(controller.frame.riseProgress, 1);
      expect(controller.frame.revealProgress, 1);
      expect(controller.lastResult?.prize,
          LotsPageState.config.sticks[demoTarget]);
      await finishDemo(tester, () => controller.phase.value,
          '签文：${LotsPageState.config.sticks[demoTarget].label}');
    });
  });
}
