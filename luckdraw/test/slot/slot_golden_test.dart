@Tags(['golden'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';

import '../support/slot_fixtures.dart';

/// Golden 截图边界。
const Key _boundary = ValueKey<String>('slot-golden');

/// 录制指定模式；中途帧通过真实宿主时钟推进。
Future<void> _golden(WidgetTester tester, SlotConfig config, String file,
    {bool moving = false}) async {
  config = config.copyWith(
      style: config.style
          .copyWith(text: config.style.text.copyWith(fontFamily: 'Roboto')));
  final controller = SlotController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 1),
          child: Center(
              child: RepaintBoundary(
                  key: _boundary,
                  child: ColoredBox(
                      color: const Color(0xFFFFFFFF),
                      child: LuckySlotMachine(
                          config: config,
                          controller: controller,
                          width: 300,
                          height: 180)))))));
  if (moving) {
    controller.play();
    await tester.pump();
    await tester.pump(slotTestStep);
  }
  await expectLater(find.byKey(_boundary), matchesGoldenFile(file));
  await tester.pumpWidget(const SizedBox());
}

/// 固定字体和逻辑像素下的老虎机视觉基线。
void main() {
  group('slot goldens', () {
    testWidgets('vertical three reel slot at rest', (tester) async {
      await _golden(tester, slotTestConfig, 'goldens/slot_vertical.png');
    });
    testWidgets('horizontal slot mid scroll', (tester) async {
      await _golden(
          tester,
          slotTestConfig.copyWith(
              options:
                  slotTestConfig.options.copyWith(mode: SlotMode.horizontal)),
          'goldens/slot_horizontal.png',
          moving: true);
    });
    testWidgets('non-square cells', (tester) async {
      await _golden(
          tester,
          slotTestConfig.copyWith(
              options: slotTestConfig.options.copyWith(cellAspectRatio: 2)),
          'goldens/slot_non_square.png');
    });
    testWidgets('lever slot machine with a winning payline', (tester) async {
      final c = SlotController();
      addTearDown(c.dispose);
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 1),
              child: Center(
                  child: RepaintBoundary(
                      key: _boundary,
                      child: ColoredBox(
                          color: const Color(0xFFFFFFFF),
                          child: LuckyLeverSlotMachine(
                              controller: c,
                              width: 340,
                              height: 180,
                              lever: const LeverOptions(
                                  staggerStop: Duration.zero),
                              config: slotTestConfig.copyWith(
                                  paylines: [
                                    const SlotPayline([0, 0, 0])
                                  ],
                                  style: slotTestConfig.style.copyWith(
                                      text: slotTestConfig.style.text.copyWith(
                                          fontFamily: 'Roboto'))))))))));
      c.play();
      c.stop(1);
      await tester.pumpAndSettle();
      expect(c.lastResult!.winningPaylines, [0]);
      await expectLater(find.byKey(_boundary),
          matchesGoldenFile('goldens/slot_lever_payline.png'));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
