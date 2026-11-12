import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

/// 无 Widget 的确定性测试；用手动时钟推进动画，用固定随机序列选奖。
///
/// 返回结算后的奖品下标；没有结果时为 null。
int? runHeadlessWheel() {
  final clock = ManualLuckyClock();
  final controller = WheelController(random: SequenceRandom([0.5]));
  controller.attachHeadless(
    clock: clock,
    config: const WheelConfig(prizes: [
      WheelPrize(texts: [LuckyText('A')]),
      WheelPrize(texts: [LuckyText('B')]),
      WheelPrize(texts: [LuckyText('C')]),
    ]),
  );
  controller.play();
  controller.stop(2);
  // 每帧 16ms；到达 settled 即停止推进。
  while (controller.phase != LuckyPhase.settled) {
    clock.advanceFrames(1);
  }
  final index = controller.lastResult!.index;
  controller.dispose();
  clock.dispose();
  return index;
}
