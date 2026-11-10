import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';

import '../support/slot_fixtures.dart';

/// 为老虎机提供有界环境。
Widget _host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child:
        MediaQuery(data: const MediaQueryData(), child: Center(child: child)));

/// 推进到短动画完成。
Future<void> _finish(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(slotTestStep);
  }
}

/// 验证完整宿主接线和层级。
void main() {
  group('LuckySlotMachine', () {
    testWidgets('renders reels and settles on the requested indices',
        (tester) async {
      final c = SlotController();
      addTearDown(c.dispose);
      final passed = <(int, int)>[];
      await tester.pumpWidget(_host(LuckySlotMachine(
          config: slotTestConfig,
          controller: c,
          width: 300,
          height: 180,
          onCellPassed: (r, i) => passed.add((r, i)))));
      expect(find.byType(CustomPaint), findsOneWidget);
      expect(c.play(), isTrue);
      expect(c.stopEach([0, 1, 2]), isTrue);
      await _finish(tester);
      expect(c.phase.value, LuckyPhase.settled);
      expect(c.lastResult!.indices, [0, 1, 2]);
      expect(passed.map((p) => p.$1).toSet(), {0, 1, 2});
      expect(tester.takeException(), isNull);
    });
    testWidgets('onEnd receives a SlotResult with indices and prize',
        (tester) async {
      final c = SlotController();
      addTearDown(c.dispose);
      final results = <SlotResult>[];
      await tester.pumpWidget(_host(LuckySlotMachine(
          config: slotTestConfig,
          controller: c,
          width: 300,
          height: 180,
          onEnd: results.add)));
      c.play();
      c.stop(1);
      await _finish(tester);
      expect(results.single.indices, [1, 1, 1]);
      expect(results.single.prize, slotTestPrizes[1]);
      c.play();
      c.cancel();
      await tester.pump();
      expect(results, hasLength(1));
      final changed = slotTestConfig.copyWith(reels: [
        const SlotReel(order: [2, 1, 0]),
        const SlotReel(),
        const SlotReel()
      ]);
      expect(
          const SlotGame().isStructuralChange(slotTestConfig, changed), isTrue);
      expect(
          const SlotGame().isStructuralChange(slotTestConfig, slotTestConfig),
          isFalse);
    });
    testWidgets('foreground indicator layer paints above reels (#227)',
        (tester) async {
      final stages = <String>[];
      final layer = LuckyCallbackLayer<SlotLayout, SlotFrame>((canvas, ctx) {
        stages.add('indicator');
        canvas.drawRect(ctx.layout.prizeArea.deflate(10),
            Paint()..color = const Color(0x66FFFFFF));
      });
      await tester.pumpWidget(_host(LuckySlotMachine(
          config: slotTestConfig,
          width: 300,
          height: 180,
          layers: [layer],
          hooks: LuckyHooks(
              beforeDraw: (_, __) => stages.add('before'),
              afterDraw: (_, __) => stages.add('after')))));
      expect(stages, ['before', 'indicator', 'after']);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  });
}
