import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';
import 'package:luckdraw/src/lots/control/lots_controller.dart';
import 'package:luckdraw/src/lotto/motion/lotto_motion.dart';
import 'package:luckdraw/src/number_wheel/control/number_wheel_controller.dart';
import 'package:luckdraw/src/slot/model/slot_config.dart';
import 'package:luckdraw/testing.dart';

import 'support/capsule_fixtures.dart';
import 'support/lots_fixtures.dart';
import 'support/lotto_fixtures.dart';
import 'support/number_wheel_fixtures.dart';
import 'support/slot_fixtures.dart';

/// 评审修复的回归：每条对应一个已确认的缺陷。
void main() {
  test('扭蛋机物理模式：结算后再开局重置世界，落下的胶囊不会留成幽灵球', () {
    final config = capsuleConfig.copyWith(
        options: const CapsuleOptions(physics: LuckyPhysics()));
    final m = CapsuleMotion()..configure(config, capsuleLayout(config));
    expect(m.start(), isTrue);
    for (var i = 0; i < 40; i++) {
      m.tick(0, kLuckyReferenceFrameMs);
    }
    expect(m.requestStop(0), isTrue);
    for (var i = 0; i < 4000 && m.phase != LuckyPhase.settled; i++) {
      m.tick(0, kLuckyReferenceFrameMs);
    }
    expect(m.phase, LuckyPhase.settled);
    m.takeResult();
    final dropped = m.frame.droppedCapsule;
    expect(m.start(), isTrue);
    // 新开局的世界与全新 motion 一致：落下的那颗球回到初始堆叠位置。
    final fresh = CapsuleMotion()..configure(config, capsuleLayout(config));
    expect(fresh.start(), isTrue);
    expect(m.frame.x[dropped], fresh.frame.x[dropped]);
    expect(m.frame.y[dropped], fresh.frame.y[dropped]);
    // 待机慢转同样从结算态重置。
    m.cancel();
    expect(m.idleSpin(), isTrue);
  });

  test('控制器 configure 触发 motion 取消时同步阶段并完成 playUntil', () async {
    final c = LotsController();
    final clock = ManualLuckyClock();
    c.attachHeadless(clock: clock, config: lotsFixture, layout: lotsLayout());
    final pending = c.playUntil(() => Completer<int?>().future);
    clock.advanceFrames(5);
    expect(c.phase.value, LuckyPhase.accelerating);
    final fewer = lotsFixture.copyWith(sticks: [lotsFixture.sticks.first]);
    c.configure(fewer, lotsLayout(fewer));
    expect(c.phase.value, LuckyPhase.idle);
    expect((await pending).cancelled, isTrue);
    c.dispose();
    clock.dispose();
  });

  test('playUntil 解析为 null 时作废本局，而不是随机选奖', () async {
    final wheel = NumberWheelController();
    final wheelClock = ManualLuckyClock();
    wheel.attachHeadless(
        clock: wheelClock,
        config: numberWheelFixture,
        layout: numberWheelLayout());
    final wheelResult = wheel.playUntil(() => null);
    await Future<void>.delayed(Duration.zero);
    expect((await wheelResult).cancelled, isTrue);
    expect(wheel.phase.value, LuckyPhase.idle);
    wheel.dispose();
    wheelClock.dispose();

    final lots = LotsController();
    final lotsClock = ManualLuckyClock();
    lots.attachHeadless(
        clock: lotsClock, config: lotsFixture, layout: lotsLayout());
    final lotsResult = lots.playUntil(() => null);
    await Future<void>.delayed(Duration.zero);
    expect((await lotsResult).cancelled, isTrue);
    expect(lots.phase.value, LuckyPhase.idle);
    lots.dispose();
    lotsClock.dispose();
  });

  test('老虎机结构比较按值而不是列表引用，仅换样式不触发重规划', () {
    final same = _withRebuiltReels(slotTestConfig);
    expect(identical(same.reels, slotTestConfig.reels), isFalse);
    expect(slotStructureChanged(slotTestConfig, same), isFalse);
  });

  test('数字轮盘：取消或重置时排队的偏移角配置不丢', () {
    final motion = numberWheelMotion();
    cruiseNumberWheel(motion);
    final shifted = numberWheelFixture.copyWith(
        options: numberWheelFixture.options.copyWith(offsetDegree: 120));
    motion.configure(shifted, numberWheelLayout(shifted));
    expect(motion.config.options.offsetDegree,
        numberWheelFixture.options.offsetDegree);
    expect(motion.cancel(), isTrue);
    expect(motion.config.options.offsetDegree, 120);
  });

  test('数字轮盘：排队后到达的新配置覆盖旧排队，结算时不被旧配置反盖', () {
    final motion = numberWheelMotion();
    cruiseNumberWheel(motion);
    motion.stop(1);
    motion.tick(120, 20);
    final first = numberWheelFixture.copyWith(
        options: numberWheelFixture.options.copyWith(offsetDegree: 120));
    final newer = numberWheelFixture.copyWith(
        options: numberWheelFixture.options.copyWith(offsetDegree: 60));
    motion.configure(first, numberWheelLayout(first));
    motion.configure(newer, numberWheelLayout(newer));
    expect(motion.config.options.offsetDegree,
        numberWheelFixture.options.offsetDegree);
    settleNumberWheel(motion);
    expect(motion.config.options.offsetDegree, 60);
  });

  test('大乐透：无布局时号码池不变的选项变化被吸收', () {
    final motion = LottoMotion()..configure(lottoConfig, lottoLayout());
    final faster = lottoConfig.copyWith(
        options: lottoOptions.copyWith(
            motion: lottoOptions.motion.copyWith(speed: 33)));
    motion.configure(faster, null);
    expect(motion.config!.options.motion.speed, 33);
  });

  test('大乐透：开奖飞行中途换驱动，球不会跳到圆心再飞出', () {
    final physics = lottoConfig.copyWith(
        options: lottoOptions.copyWith(physics: const LuckyPhysics()));
    final motion = LottoMotion()..configure(physics, lottoLayout(physics));
    expect(motion.start(), isTrue);
    for (var i = 0; i < 100 && motion.phase != LuckyPhase.cruising; i++) {
      motion.tick(0, 10);
    }
    expect(motion.stopWith(lottoDraw), isTrue);
    // 小步长推进，捕捉飞行刚开始的瞬间。
    for (var i = 0;
        i < 20000 && motion.frame.flight.every((f) => f == 0);
        i++) {
      motion.tick(0, 1);
    }
    final started = [
      for (var i = 0; i < motion.frame.flight.length; i++)
        if (motion.frame.flight[i] > 0) i
    ];
    expect(started, isNotEmpty);
    final i = started.first;
    final plain = physics.copyWith(options: lottoOptions);
    // 第一池按出球顺序占槽：槽号等于出球序号的那颗球就是正在飞的球。
    const pool = 0;
    final ball = motion.frame.slotOf[pool].indexOf(i);
    expect(ball, isNonNegative);
    final beforeX = motion.frame.x[pool][ball];
    motion.configure(plain, lottoLayout(plain));
    motion.tick(0, 1);
    final jump = (motion.frame.x[pool][ball] - beforeX).abs();
    expect(jump, lessThan(1));
  });
}

/// 复制老虎机配置并重建 reels 列表，内容不变。
SlotConfig _withRebuiltReels(SlotConfig config) =>
    config.copyWith(reels: [...config.reels]);
