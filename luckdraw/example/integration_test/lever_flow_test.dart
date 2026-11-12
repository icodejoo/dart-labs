import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw_example/pages/lever_page.dart';
import 'package:luckdraw_example/pages/slot_page.dart';

import 'support/flows.dart';

/// 拉杆拖动、轮子错峰停止的真实流程。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('lever flow', () {
    testWidgets('drag the lever then reels stop one by one on the targets',
        (tester) async {
      await openDemo(tester, '拉霸机');
      final state = tester.state<LeverPageState>(find.byType(LeverPage));
      final controller = state.controller;
      final semantics = tester.ensureSemantics();
      final Offset knobCenter;
      try {
        knobCenter = tester.getCenter(find.bySemanticsLabel('拉杆'));
      } finally {
        semantics.dispose();
      }
      final gesture = await tester.startGesture(knobCenter);
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 90));
      await gesture.up();
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      expect(state.pulls, 1);
      final config =
          tester.widget<LuckySlotMachine>(find.byType(LuckySlotMachine)).config;
      expect(config.reels.map((reel) => reel.stopDelay.inMilliseconds),
          [0, 300, 600]);
      await serverResult(tester);
      var sawFirstStopped = false;
      var sawSecondStopped = false;
      var previous = controller.frame.scroll.toList();
      await waitFor(tester, () {
        final current = controller.frame.scroll.toList();
        if (current[0] == previous[0] && current[1] != previous[1]) {
          sawFirstStopped = true;
        }
        if (current[1] == previous[1] && current[2] != previous[2]) {
          sawSecondStopped = true;
        }
        previous = current;
        return controller.phase.value == LuckyPhase.settled;
      });
      expect(sawFirstStopped, isTrue);
      expect(sawSecondStopped, isTrue);
      expect(controller.lastResult?.indices, SlotPageState.slotTargets);
      await finishDemo(tester, () => controller.phase.value,
          '奖品：${SlotPageState.slotTargets}');
    });
  });
}
