import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/capsule/control/capsule_controller.dart';
import 'package:luckdraw/src/grid/control/grid_controller.dart';
import 'package:luckdraw/src/lots/control/lots_controller.dart';
import 'package:luckdraw/src/number_wheel/control/number_wheel_controller.dart';
import 'package:luckdraw/src/slot/control/slot_controller.dart';
import 'package:luckdraw/testing.dart';

import 'support/capsule_fixtures.dart';
import 'support/grid_fixtures.dart';
import 'support/lots_fixtures.dart';
import 'support/lotto_fixtures.dart';
import 'support/number_wheel_fixtures.dart';
import 'support/slot_fixtures.dart';
import 'wheel/wheel_test_support.dart';

/// 推进时钟直到 [done] 为真，超过预算即断言失败。
void _until(ManualLuckyClock clock, bool Function() done) {
  for (var i = 0; i < 2000 && !done(); i++) {
    clock.advanceFrames(1);
  }
  expect(done(), isTrue, reason: '预算内没有到达目标状态');
}

/// 模拟游戏视图在待机慢转期间应用结构变更：立即配置，回到静止则续上待机。
void _applyDuringIdle(LuckyController<dynamic, dynamic, dynamic, dynamic> c,
    void Function() configure) {
  expect(c.phase.value, LuckyPhase.idleSpinning);
  configure();
  if (c.phase.value == LuckyPhase.idle) c.idleSpin();
  expect(c.phase.value, LuckyPhase.idleSpinning, reason: '待机轮播应保持');
}

/// 待机慢转期间改结构后，开局、停止并结算，结果必须指向新配置里的奖品。
void main() {
  test('转盘：奖品减少后结果仍是新配置里的那一格', () {
    final host = WheelTestHost();
    final c = wheelTestController(host);
    c.idleSpin();
    host.clock.advanceFrames(20);
    final fewer = wheelTestConfig()
        .copyWith(prizes: wheelTestConfig().prizes.sublist(0, 3));
    _applyDuringIdle(c, () => c.configure(fewer, null));
    expect(c.play(), isTrue);
    host.clock.advanceFrames(10);
    expect(c.stop(2), isTrue);
    _until(host.clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.cancelled, isFalse);
    expect(c.lastResult!.index, 2);
    expect(c.lastResult!.prize, same(fewer.prizes[2]));
  });

  test('九宫格：奖品减少后结果仍是新配置里的那一格', () {
    final c = GridController();
    final clock = ManualLuckyClock();
    addTearDown(() {
      c.dispose();
      clock.dispose();
    });
    c.attachHeadless(
        clock: clock, config: gridFixture, layout: gridLayout(gridFixture));
    c.idleSpin();
    clock.advanceFrames(20);
    final fewer =
        gridFixture.copyWith(prizes: gridFixture.prizes.sublist(0, 6));
    _applyDuringIdle(c, () => c.configure(fewer, gridLayout(fewer)));
    expect(c.play(), isTrue);
    clock.advanceFrames(10);
    expect(c.stop(5), isTrue);
    _until(clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.index, 5);
    expect(c.lastResult!.prize, same(fewer.prizes[5]));
  });

  test('抽签：签数减少后结果仍是新配置里的那一支', () {
    final c = LotsController();
    final clock = ManualLuckyClock();
    addTearDown(() {
      c.dispose();
      clock.dispose();
    });
    c.attachHeadless(
        clock: clock, config: lotsFixture, layout: lotsLayout(lotsFixture));
    c.idleSpin();
    clock.advanceFrames(20);
    final fewer =
        lotsFixture.copyWith(sticks: lotsFixture.sticks.sublist(0, 2));
    _applyDuringIdle(c, () => c.configure(fewer, lotsLayout(fewer)));
    expect(c.play(), isTrue);
    clock.advanceFrames(10);
    expect(c.stop(1), isTrue);
    _until(clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.index, 1);
    expect(c.lastResult!.prize, same(fewer.sticks[1]));
  });

  test('扭蛋机：奖品增加后结果可以落在新增的那一个', () {
    final c = CapsuleController();
    final clock = ManualLuckyClock();
    addTearDown(() {
      c.dispose();
      clock.dispose();
    });
    c.attachHeadless(
        clock: clock,
        config: capsuleConfig,
        layout: capsuleLayout(capsuleConfig));
    c.idleSpin();
    clock.advanceFrames(20);
    final more = capsuleConfig.copyWith(
        prizes: [...capsuleConfig.prizes, capsuleConfig.prizes.first]);
    _applyDuringIdle(c, () => c.configure(more, capsuleLayout(more)));
    expect(c.play(), isTrue);
    clock.advanceFrames(10);
    expect(c.stop(2), isTrue);
    _until(clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.index, 2);
    expect(c.lastResult!.prize, same(more.prizes[2]));
  });

  test('数字轮盘：号码减少后结果仍是新配置里的那个号码', () {
    final c = NumberWheelController();
    final clock = ManualLuckyClock();
    addTearDown(() {
      c.dispose();
      clock.dispose();
    });
    c.attachHeadless(
        clock: clock, config: numberWheelFixture, layout: numberWheelLayout());
    c.idleSpin();
    clock.advanceFrames(20);
    final fewer = numberWheelFixture.copyWith(
        pockets: numberWheelFixture.pockets.sublist(0, 2));
    _applyDuringIdle(c, () => c.configure(fewer, numberWheelLayout(fewer)));
    expect(c.play(), isTrue);
    clock.advanceFrames(10);
    expect(c.stop(1), isTrue);
    _until(clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.index, 1);
    expect(c.lastNumber, 20);
  });

  test('老虎机：列数减少后各列停在目标奖品并正常结算', () {
    final c = SlotController();
    final clock = ManualLuckyClock();
    addTearDown(() {
      c.dispose();
      clock.dispose();
    });
    c.attachHeadless(
        clock: clock, config: slotTestConfig, layout: slotLayout());
    c.idleSpin();
    clock.advanceFrames(20);
    final fewer =
        slotTestConfig.copyWith(reels: slotTestConfig.reels.sublist(0, 2));
    _applyDuringIdle(c, () => c.configure(fewer, slotLayout(fewer)));
    expect(c.play(), isTrue);
    clock.advanceFrames(10);
    expect(c.stop(1), isTrue);
    _until(clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.cancelled, isFalse);
    expect(c.frame.targets, hasLength(2));
    expect(c.frame.targets.every((t) => t == 1), isTrue);
  });

  test('大乐透：号码池减少后开奖结果就是新池里的号码', () {
    final c = LottoController();
    final clock = ManualLuckyClock();
    addTearDown(() {
      c.dispose();
      clock.dispose();
    });
    c.attachHeadless(
        clock: clock, config: lottoConfig, layout: lottoLayout(lottoConfig));
    c.idleSpin();
    clock.advanceFrames(20);
    final fewer = lottoConfig.copyWith(pools: [lottoConfig.pools.first]);
    _applyDuringIdle(c, () => c.configure(fewer, lottoLayout(fewer)));
    expect(c.play(), isTrue);
    clock.advanceFrames(10);
    const draw = LottoDraw([
      [7, 1, 4]
    ]);
    expect(c.stopWith(draw), isTrue);
    _until(clock, () => c.phase.value == LuckyPhase.settled);
    expect(c.lastResult!.draw!.numbers, draw.numbers);
  });
}
