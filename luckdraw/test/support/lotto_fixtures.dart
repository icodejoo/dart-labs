import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/core/game/layout.dart';
import 'package:luckdraw/src/lotto/layout/lotto_layout.dart';
import 'package:luckdraw/testing.dart';

/// 单元测试帧间隔。
const Duration lottoStep = Duration(milliseconds: 10);

/// 测试用的短动画配置。
const LottoOptions lottoOptions = LottoOptions(
    drawInterval: Duration(milliseconds: 60),
    ballFlightTime: Duration(milliseconds: 40),
    motion: LuckyMotionOptions(
        speed: 12,
        accelerationTime: Duration(milliseconds: 40),
        decelerationTime: Duration(milliseconds: 40)));

/// 测试号码池，包含非一开头的号码。
const LottoConfig lottoConfig = LottoConfig(pools: [
  LottoPool(
      min: 1, max: 7, count: 3, ballFill: LuckyFill.color(Color(0xFFE53935))),
  LottoPool(
      min: 11, max: 14, count: 2, ballFill: LuckyFill.color(Color(0xFF1E88E5))),
], options: lottoOptions);

/// 顺序刻意不同于升序的固定开奖。
const LottoDraw lottoDraw = LottoDraw([
  [7, 1, 4],
  [14, 11]
]);

/// 标准测试画布。
const Size lottoSize = Size(400, 360);

/// 计算布局并释放测量器。
LottoLayout lottoLayout(
    [LottoConfig config = lottoConfig, Size size = lottoSize]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return computeLottoLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 注入手动时间的控制器夹具。
final class LottoRig {
  /// 配置无头摇奖机。
  LottoRig(
      {LottoConfig config = lottoConfig,
      LottoSampler sampler = const UniformLottoSampler(),
      int seed = 42})
      : controller =
            LottoController(sampler: sampler, random: math.Random(seed)) {
    controller.attachHeadless(
        clock: clock, config: config, layout: lottoLayout(config));
  }

  /// 调用者拥有的时钟。
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 待测控制器。
  final LottoController controller;

  /// 推进到指定阶段，超限直接失败。
  void until(LuckyPhase phase) {
    for (var i = 0; i < 2000 && controller.phase.value != phase; i++) {
      clock.advance(lottoStep);
    }
    expect(controller.phase.value, phase);
  }

  /// 开始并请求固定号码开奖。
  void draw() {
    expect(controller.play(), isTrue);
    expect(controller.stopWith(lottoDraw), isTrue);
    until(LuckyPhase.settled);
    expect(controller.lastResult!.draw, lottoDraw);
  }

  /// 释放夹具资源。
  void dispose() {
    controller.dispose();
    clock.dispose();
  }
}

/// 可作废本局的测试抽样器。
final class NullLottoSampler implements LottoSampler {
  /// 创建空结果抽样器。
  const NullLottoSampler();

  /// 返回 null 表示取消。
  @override
  LottoDraw? sample(LottoConfig config, math.Random random) => null;
}

/// 验证通用状态机迁移；lotto 的负下标映射为 cancel，空 picker 映射为空 sampler。
void verifyLottoEdge(String edge) {
  final rig = LottoRig(
      sampler: edge == 'E15'
          ? const NullLottoSampler()
          : const UniformLottoSampler());
  final c = rig.controller;
  addTearDown(rig.dispose);
  switch (edge) {
    case 'E01':
      expect(c.play(), isTrue);
      expect(c.phase.value, LuckyPhase.accelerating);
    case 'E02':
      rig.draw();
      expect(c.play(), isTrue);
      expect(c.phase.value, LuckyPhase.accelerating);
    case 'E03':
      expect(c.idleSpin(), isTrue);
      rig.clock.advanceFrames(2);
      final angle = c.frame.swirlDeg;
      expect(c.play(), isTrue);
      expect(c.frame.swirlDeg, angle);
      rig.clock.advanceFrames(2);
      expect(c.frame.swirlDeg, greaterThan(angle));
    case 'E04':
      expect(c.idleSpin(), isTrue);
      expect(c.phase.value, LuckyPhase.idleSpinning);
    case 'E05':
      rig.draw();
      expect(c.idleSpin(), isTrue);
      expect(c.phase.value, LuckyPhase.idleSpinning);
    case 'E06':
      c.idleSpin();
      expect(c.cancel(), isTrue);
      expect(c.phase.value, LuckyPhase.idle);
      expect(c.lastResult, isNull);
    case 'E07':
      c.play();
      rig.until(LuckyPhase.cruising);
      expect(c.frame.mix, 1);
    case 'E08':
      c.play();
      expect(c.stopWith(lottoDraw), isTrue);
      expect(c.phase.value, LuckyPhase.accelerating);
    case 'E09':
      c.play();
      c.stopWith(lottoDraw);
      rig.until(LuckyPhase.cruising);
      rig.clock.advance(lottoStep);
      expect(c.phase.value, LuckyPhase.decelerating);
    case 'E10':
      c.play();
      rig.until(LuckyPhase.cruising);
      c.stopWith(lottoDraw);
      expect(c.phase.value, LuckyPhase.cruising);
      rig.clock.advance(lottoStep);
      expect(c.phase.value, LuckyPhase.decelerating);
    case 'E11':
      rig.draw();
      expect(c.lastResult!.cancelled, isFalse);
    case 'E12':
      c.play();
      expect(c.cancel(), isTrue);
      expect(c.phase.value, LuckyPhase.idle);
      expect(c.lastResult!.cancelled, isTrue);
    case 'E13':
    case 'E14':
      c.play();
      rig.until(LuckyPhase.cruising);
      expect(c.cancel(), isTrue);
      expect(c.phase.value, LuckyPhase.idle);
      expect(c.lastResult!.cancelled, isTrue);
    case 'E15':
      c.play();
      expect(c.stop(), isTrue);
      expect(c.lastResult!.cancelled, isTrue);
    case 'E16':
      c.play();
      c.stopWith(lottoDraw);
      rig.until(LuckyPhase.decelerating);
      expect(c.cancel(), isFalse);
      expect(c.stop(), isFalse);
    case 'E17':
      expect(c.stop(), isFalse);
      rig.draw();
      expect(c.stop(), isFalse);
    case 'E18':
      c.play();
      expect(c.play(), isFalse);
      rig.until(LuckyPhase.cruising);
      expect(c.play(), isFalse);
      c.stopWith(lottoDraw);
      rig.until(LuckyPhase.decelerating);
      expect(c.play(), isFalse);
    case 'E19':
      c.play();
      rig.clock.advanceFrames(3);
      expect(c.pause(), isTrue);
      final angle = c.frame.swirlDeg;
      rig.clock.advance(const Duration(minutes: 10));
      expect(c.frame.swirlDeg, angle);
      expect(c.resume(), isTrue);
      rig.clock.advance(lottoStep);
      expect(c.frame.swirlDeg, angle);
      rig.clock.advance(lottoStep);
      expect(c.frame.swirlDeg, greaterThan(angle));
    case 'E20':
      c.play();
      c.reset();
      expect(c.phase.value, LuckyPhase.idle);
      expect(c.frame.swirlDeg, 0);
      c.idleSpin();
      c.reset();
      c.play();
      rig.until(LuckyPhase.cruising);
      c.reset();
      c.play();
      c.stopWith(lottoDraw);
      rig.until(LuckyPhase.decelerating);
      c.reset();
      expect(c.frame.drawnCount, 0);
      rig.draw();
      c.reset();
      expect(c.phase.value, LuckyPhase.idle);
    case 'E21':
      c.play();
      c.dispose();
      final angle = c.frame.swirlDeg;
      rig.clock.advanceFrames(10);
      expect(c.frame.swirlDeg, angle);
      expect(rig.clock.isTicking, isFalse);
    case 'E22':
      c.idleSpin();
      expect(c.stop(), isFalse);
    case 'E23':
      for (var i = 0; i < 100; i++) {
        rig.draw();
      }
      expect(c.phase.value, LuckyPhase.settled);
    case 'E24':
      c.play();
      expect(c.stop(), isTrue);
      rig.until(LuckyPhase.settled);
      expect(c.lastResult!.draw!.numbers.map((p) => p.length), [3, 2]);
    case 'E26':
      expect(c.pause(), isFalse);
      rig.draw();
      expect(c.pause(), isFalse);
    default:
      fail('未知迁移边 $edge');
  }
}
