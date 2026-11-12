import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';
import 'package:luckdraw/testing.dart';

import '../support/capsule_fixtures.dart';

/// 开启物理模式的配置。
final CapsuleConfig _physicsConfig = capsuleConfig.copyWith(
    options: const CapsuleOptions(physics: LuckyPhysics()));

/// 一帧六十赫兹。
const Duration _frame = Duration(microseconds: 16667);

/// 创建已配置的物理模式 motion。
CapsuleMotion _motion([CapsuleConfig? config]) {
  final c = config ?? _physicsConfig;
  return CapsuleMotion()..configure(c, capsuleLayout(c));
}

/// 按参考帧 tick 到 [done] 为真或超过 [limit] 帧，返回用掉的帧数。
int _tickUntil(CapsuleMotion m, bool Function() done, {int limit = 2000}) {
  var n = 0;
  while (!done() && n < limit) {
    m.tick(0, kLuckyReferenceFrameMs);
    n++;
  }
  return n;
}

/// 最高的球心纵坐标（数值越小越靠上）。
double _top(CapsuleMotion m) => m.frame.y.reduce(math.min);

/// 验证扭蛋机物理模式的接入契约。
void main() {
  test('物理模式构造即落入，静止阶段持续模拟直至休眠后不再需要时钟', () {
    final m = _motion();
    expect(m.phase, LuckyPhase.idle);
    expect(m.isSimulating, isTrue);
    final top = _top(m);
    expect(m.tick(0, kLuckyReferenceFrameMs), LuckyMotionEvents.repaint);
    final frames = _tickUntil(m, () => !m.isSimulating);
    expect(frames, lessThan(600));
    expect(m.phase, LuckyPhase.idle);
    expect(m.isSimulating, isFalse);
    expect(_top(m), greaterThan(top));
    expect(m.tick(0, kLuckyReferenceFrameMs), LuckyMotionEvents.none);
  });

  test('参数化模式不模拟，静止 tick 不产生事件', () {
    final m = _motion(capsuleConfig);
    expect(m.isSimulating, isFalse);
    expect(m.tick(0, kLuckyReferenceFrameMs), LuckyMotionEvents.none);
    expect(m.frame.stirDeg, 0);
  });

  test('物理模式搅拌时拨杆角变化，停止后胶囊落入托盘并得到目标奖品', () {
    for (final target in [0, 1]) {
      final m = _motion();
      _tickUntil(m, () => !m.isSimulating);
      expect(m.start(), isTrue);
      _tickUntil(m, () => m.phase == LuckyPhase.cruising);
      for (var i = 0; i < 60; i++) {
        m.tick(0, kLuckyReferenceFrameMs);
      }
      expect(m.frame.stirDeg, greaterThan(0));
      expect(m.requestStop(target), isTrue);
      _tickUntil(m, () => m.phase == LuckyPhase.settled);
      expect(m.phase, LuckyPhase.settled);
      expect(m.frame.targetPrize, target);
      final dropped = m.frame.droppedCapsule;
      expect(capsuleLayout(_physicsConfig).capsules[dropped], target,
          reason: 'target=$target');
      expect(m.takeResult()?.index, target);
    }
  });

  test('进入掉落的第一帧胶囊位置与减速末帧连续，不跳变', () {
    final m = _motion();
    _tickUntil(m, () => !m.isSimulating);
    m.start();
    _tickUntil(m, () => m.phase == LuckyPhase.cruising);
    m.requestStop(1);
    _tickUntil(m, () => m.frame.stage == CapsuleStage.dropping);
    expect(m.frame.stage, CapsuleStage.dropping);
    final i = m.frame.droppedCapsule;
    final first = (m.frame.x[i], m.frame.y[i]);
    m.tick(0, kLuckyReferenceFrameMs);
    final next = (m.frame.x[i], m.frame.y[i]);
    final radius = capsuleLayout(_physicsConfig).capsuleRadius;
    expect(
        math.sqrt(
            math.pow(next.$1 - first.$1, 2) + math.pow(next.$2 - first.$2, 2)),
        lessThan(radius));
  });

  test('相同布局重新配置时沿用世界，容器缩放只改换算比例', () {
    final m = _motion();
    for (var i = 0; i < 20; i++) {
      m.tick(0, kLuckyReferenceFrameMs);
    }
    final before = List<double>.of(m.frame.x);
    final old = capsuleLayout(_physicsConfig);
    final bigger = capsuleLayout(_physicsConfig, const Size(600, 1000));
    m.configure(_physicsConfig, bigger);
    final scale = bigger.globeRadius / old.globeRadius;
    for (var i = 0; i < before.length; i++) {
      expect(m.frame.x[i], closeTo(before[i] * scale, 1e-9));
    }
    expect(m.isSimulating, isTrue);
  });

  test('球数或物理参数变化时重建世界并重新落入', () {
    final m = _motion();
    _tickUntil(m, () => !m.isSimulating);
    final restHigh = _top(m);
    final changed = capsuleConfig.copyWith(
        options: const CapsuleOptions(physics: LuckyPhysics(gravity: 5)));
    m.configure(changed, capsuleLayout(changed));
    expect(m.isSimulating, isTrue);
    expect(_top(m), lessThan(restHigh));
  });

  test('重置让胶囊重新落入，作废则保持当前位置', () {
    final m = _motion();
    _tickUntil(m, () => !m.isSimulating);
    m.reset();
    expect(m.isSimulating, isTrue);
    final dropping = _top(m);
    _tickUntil(m, () => !m.isSimulating);
    expect(_top(m), greaterThan(dropping));
    m.start();
    for (var i = 0; i < 10; i++) {
      m.tick(0, kLuckyReferenceFrameMs);
    }
    final before = List<double>.of(m.frame.y);
    expect(m.cancel(), isTrue);
    expect(m.phase, LuckyPhase.idle);
    for (var i = 0; i < before.length; i++) {
      expect(m.frame.y[i], before[i]);
    }
    expect(m.takeResult()?.cancelled, isTrue);
  });

  test('球数超过上限或半径比越界时回退参数化轨迹', () {
    final capped = capsuleConfig.copyWith(
        options: const CapsuleOptions(physics: LuckyPhysics(maxBodies: 3)));
    expect(_motion(capped).isSimulating, isFalse);
    final huge = capsuleConfig.copyWith(
        options: const CapsuleOptions(
            capsuleRadiusFactor: 0.9, physics: LuckyPhysics()));
    expect(_motion(huge).isSimulating, isFalse);
    final zero = capsuleConfig.copyWith(
        options: const CapsuleOptions(
            capsuleRadiusFactor: 0, physics: LuckyPhysics()));
    expect(_motion(zero).isSimulating, isFalse);
  });

  test('非法物理参数在配置时抛出 ArgumentError', () {
    final bad = capsuleConfig.copyWith(
        options: const CapsuleOptions(physics: LuckyPhysics(gravity: -1)));
    expect(() => _motion(bad), throwsArgumentError);
  });

  test('扭蛋机选项的物理字段参与副本、相等性与哈希', () {
    const base = CapsuleOptions();
    const withPhysics = CapsuleOptions(physics: LuckyPhysics());
    expect(base.physics, isNull);
    expect(base.copyWith(physics: const LuckyPhysics()), withPhysics);
    expect(withPhysics, isNot(base));
    expect(withPhysics.hashCode, isNot(base.hashCode));
    expect(withPhysics.copyWith().physics, const LuckyPhysics());
    expect(withPhysics.copyWith(physics: const LuckyPhysics(stirArms: 3)),
        isNot(withPhysics));
  });

  test('控制器挂接后物理落入自动启动时钟，休眠后停表', () {
    final clock = ManualLuckyClock();
    final c = CapsuleController()
      ..attachHeadless(
          clock: clock,
          config: _physicsConfig,
          layout: capsuleLayout(_physicsConfig));
    expect(c.phase.value, LuckyPhase.idle);
    expect(clock.isTicking, isTrue);
    var frames = 0;
    while (clock.isTicking && frames < 1000) {
      clock.advance(_frame);
      frames++;
    }
    expect(clock.isTicking, isFalse);
    expect(frames, lessThan(700));
    expect(c.play(), isTrue);
    expect(clock.isTicking, isTrue);
    c.dispose();
    clock.dispose();
  });

  test('两种模式的相位序列、结果与总耗时完全一致', () {
    List<Object> run(CapsuleConfig config) {
      final clock = ManualLuckyClock();
      final c = CapsuleController()
        ..attachHeadless(
            clock: clock, config: config, layout: capsuleLayout(config));
      final phases = <LuckyPhase>[c.phase.value];
      c.phase.addListener(() => phases.add(c.phase.value));
      var ends = 0;
      var frames = 0;
      while (clock.isTicking && frames < 1000) {
        clock.advance(_frame);
        frames++;
      }
      c.play();
      for (var f = 0; f < 90; f++) {
        clock.advance(_frame);
      }
      c.stop(1);
      var settledAt = -1;
      for (var f = 0; f < 600 && settledAt < 0; f++) {
        clock.advance(_frame);
        if (c.phase.value == LuckyPhase.settled) settledAt = f;
      }
      final result = c.lastResult;
      if (result != null && !result.cancelled) ends++;
      final out = <Object>[phases, settledAt, result?.index ?? -1, ends];
      c.dispose();
      clock.dispose();
      return out;
    }

    final kinematic = run(capsuleConfig);
    final physics = run(_physicsConfig);
    expect(physics, kinematic);
    expect(kinematic[1] as int, greaterThan(0));
  });
}
