import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/grid_page.dart';

import 'support/flows.dart';

/// 九宫格高亮行走和服务端下标结算。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('grid flow', () {
    testWidgets('highlight walks and settles on the target', (tester) async {
      await openDemo(tester, '九宫格');
      final controller =
          tester.state<GridPageState>(find.byType(GridPage)).controller;
      final active = <int>{};

      /// 收集真实帧中到达过的格子。
      void record() => active.add(controller.frame.activeIndex);
      controller.frameListenable.addListener(record);
      await tester.tap(find.byType(LuckyGrid));
      await waitFor(tester, () => active.length >= 3);
      controller.frameListenable.removeListener(record);
      expect(controller.lastResult, isNull);
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      expect(controller.frame.activeIndex, demoTarget);
      expect(controller.lastResult?.index, demoTarget);
      await finishDemo(tester, () => controller.phase.value, '奖品：$demoTarget');
    });
  });
}
