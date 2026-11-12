import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw_example/demo_shell.dart';
import 'package:luckdraw_example/pages/lotto_page.dart';

import 'support/flows.dart';

/// 七球真实逐球开奖与回调顺序。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('lotto flow', () {
    testWidgets('server draw lands seven balls in order', (tester) async {
      await openDemo(tester, '大乐透');
      final state = tester.state<LottoPageState>(find.byType(LottoPage));
      final controller = state.controller;
      await tester.tap(find.byKey(startKey));
      await waitFor(
          tester, () => controller.phase.value == LuckyPhase.cruising);
      expect(state.drawn, isEmpty);
      final counts = <int>{};

      /// 只保留落槽计数值，验证中间状态确实经过逐球完成。
      void record() => counts.add(controller.frame.drawnCount);
      controller.frameListenable.addListener(record);
      await serverResult(tester);
      await waitFor(tester, () => controller.phase.value == LuckyPhase.settled);
      controller.frameListenable.removeListener(record);
      expect(state.drawn,
          [(0, 7), (0, 1), (0, 18), (0, 25), (0, 35), (1, 12), (1, 3)]);
      expect(counts, containsAll([1, 2, 3, 4, 5, 6, 7]));
      expect(controller.frame.drawnCount, 7);
      expect(controller.frame.flight, everyElement(1));
      expect(controller.lastResult?.draw, LottoPageState.serverDraw);
      await finishDemo(tester, () => controller.phase.value,
          '号码：${LottoPageState.serverDraw.numbers}');
    });
  });
}
