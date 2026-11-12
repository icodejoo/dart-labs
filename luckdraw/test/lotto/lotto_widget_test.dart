import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';

/// 构建有固定环境的摇奖机。
Widget lottoHost(Widget child) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
        textDirection: TextDirection.ltr, child: Center(child: child)));

/// 按固定帧间隔推进到结算，避免 pumpAndSettle 跳过中间帧。
Future<void> settleLotto(
    WidgetTester tester, LottoController controller) async {
  for (var i = 0;
      i < 200 && controller.phase.value != LuckyPhase.settled;
      i++) {
    await tester.pump(lottoStep);
  }
  expect(controller.phase.value, LuckyPhase.settled);
}

/// 验证公开 Widget 的受控命令与回调。
void main() {
  group('LuckyLotto', () {
    testWidgets('onEnd receives the drawn front and back numbers',
        (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      final results = <LottoResult>[];
      await tester.pumpWidget(lottoHost(LuckyLotto(
          config: lottoConfig,
          controller: controller,
          width: lottoSize.width,
          height: lottoSize.height,
          onEnd: results.add)));
      controller.play();
      controller.stopWith(lottoDraw);
      await settleLotto(tester, controller);
      expect(results, hasLength(1));
      expect(results.single.draw, lottoDraw);
      expect(results.single.cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('onBallDrawn fires once per drawn ball', (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      final calls = <List<int>>[];
      final order = <String>[];
      await tester.pumpWidget(lottoHost(LuckyLotto(
          config: lottoConfig,
          controller: controller,
          width: lottoSize.width,
          height: lottoSize.height,
          onBallDrawn: (pool, number) {
            calls.add([pool, number]);
            order.add('ball');
          },
          onEnd: (_) => order.add('end'))));
      controller.play();
      controller.stopWith(lottoDraw);
      await settleLotto(tester, controller);
      await tester.pump(lottoStep);
      expect(calls, [
        [0, 7],
        [0, 1],
        [0, 4],
        [1, 14],
        [1, 11]
      ]);
      expect(order, ['ball', 'ball', 'ball', 'ball', 'ball', 'end']);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'tapping the start button calls onStart only in idle-like phases',
        (tester) async {
      final controller = LottoController();
      addTearDown(controller.dispose);
      var starts = 0;
      final buttons = <LuckyPhase>[];
      await tester.pumpWidget(lottoHost(LuckyLotto(
          config: lottoConfig,
          controller: controller,
          width: lottoSize.width,
          height: lottoSize.height,
          onStart: () => starts++,
          onButtonTap: (i, phase) {
            expect(i, 0);
            buttons.add(phase);
          })));
      final button = tester.getTopLeft(find.byType(LuckyLotto)) +
          lottoLayout().button.center;
      await tester.tapAt(button);
      expect(starts, 1);
      controller.play();
      await tester.pump();
      await tester.tapAt(button);
      expect(starts, 1);
      controller.stopWith(lottoDraw);
      await settleLotto(tester, controller);
      await tester.tapAt(button);
      expect(starts, 2);
      controller.idleSpin();
      await tester.pump();
      await tester.tapAt(button);
      expect(starts, 3);
      await tester.tapAt(tester.getTopLeft(find.byType(LuckyLotto)));
      expect(starts, 3);
      expect(buttons, [
        LuckyPhase.idle,
        LuckyPhase.accelerating,
        LuckyPhase.settled,
        LuckyPhase.idleSpinning
      ]);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
