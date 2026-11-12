import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';

/// 测试中完整抽奖可在较短时间内结束。
const LuckyMotionOptions kWheelTestMotion = LuckyMotionOptions(
    accelerationTime: Duration(milliseconds: 64),
    decelerationTime: Duration(milliseconds: 96));

/// 创建短时、保留六扇区的测试配置。
WheelConfig wheelTestConfig({LuckyMotionOptions motion = kWheelTestMotion}) =>
    kLuckyWheelFixture.copyWith(options: WheelOptions(motion: motion));

/// 无头测试宿主，记录真实控制器回调。
final class WheelTestHost
    implements LuckyControllerHost<LuckyResult<WheelPrize>> {
  /// 创建并持有手动时钟。
  WheelTestHost();

  /// 手动时钟。
  @override
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 阶段回调记录。
  final List<LuckyPhase> phases = [];

  /// 结果回调记录。
  final List<LuckyResult<WheelPrize>> results = [];

  /// 跨扇区回调记录。
  final List<int> passed = [];

  /// 已接受的 play 数。
  int starts = 0;

  /// 记录阶段。
  @override
  void handlePhaseChanged(LuckyPhase phase) => phases.add(phase);

  /// 记录结果。
  @override
  void handleResult(LuckyResult<WheelPrize> result) => results.add(result);

  /// 记录扇区，转盘列号必须为零。
  @override
  void handleItemPassed(int reel, int index) {
    expect(reel, 0);
    passed.add(index);
  }

  /// 记录开始。
  @override
  void handleStarted() => starts++;
}

/// 创建挂接宿主的控制器，用例结束自动释放资源。
WheelController wheelTestController(WheelTestHost host,
    {WheelConfig? config,
    PrizePicker picker = const WeightedPrizePicker(),
    SequenceRandom? random}) {
  final controller = WheelController(
      picker: picker, random: random ?? SequenceRandom(List.filled(300, 0.5)));
  controller.attach(host);
  controller.configure(config ?? wheelTestConfig(), null);
  addTearDown(controller.dispose);
  addTearDown(host.clock.dispose);
  return controller;
}

/// 推进到期望阶段；超过帧预算立即以断言失败。
void wheelAdvanceTo(
    WheelController controller, ManualLuckyClock clock, LuckyPhase phase) {
  for (var i = 0; i < 1000 && controller.phase.value != phase; i++) {
    clock.advanceFrames(1);
  }
  expect(controller.phase.value, phase);
}

/// 不选择任何奖品的策略。
final class WheelNullPicker implements PrizePicker {
  /// 创建取消策略。
  const WheelNullPicker();

  /// 返回 null，触发作废语义。
  @override
  int? pick(PrizePickContext context) => null;
}
