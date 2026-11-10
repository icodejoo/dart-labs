import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/slot_page.dart';

import 'support/flows.dart';

/// 三轮分别接收服务端下标的真实流程。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('slot flow', () {
    testWidgets('three reels settle on stopEach indices', (tester) async {
      await openDemo(tester, '老虎机');
      final controller =
          tester.state<SlotPageState>(find.byType(SlotPage)).controller;
      await tester.tap(find.byKey(startKey));
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      final scroll = controller.frame.scroll.toList();
      await tester.pump(flowStep);
      for (var reel = 0; reel < scroll.length; reel++) {
        expect(controller.frame.scroll[reel], isNot(scroll[reel]));
      }
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      expect(controller.lastResult?.indices, SlotPageState.slotTargets);
      expect(
          controller.frame.targets, orderedEquals(SlotPageState.slotTargets));
      await finishDemo(tester, () => controller.phase.value,
          '奖品：${SlotPageState.slotTargets}');
    });
  });
}
