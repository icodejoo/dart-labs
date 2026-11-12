import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/core/motion/motion.dart';
import 'package:luckdraw/src/lotto/motion/lotto_motion.dart';

import '../support/lotto_fixtures.dart';

/// 开启物理模式的测试配置。
final LottoConfig _physicsConfig = lottoConfig.copyWith(
    options: lottoOptions.copyWith(physics: const LuckyPhysics()));

/// 创建已配置的 motion。
LottoMotion _motion([LottoConfig? config]) {
  final c = config ?? _physicsConfig;
  return LottoMotion()..configure(c, lottoLayout(c));
}

/// 按固定步长 tick，直到 [done] 为真或超过 [limit] 帧，返回帧数。
int _tickUntil(LottoMotion m, bool Function() done,
    {double step = 10, int limit = 3000}) {
  var n = 0;
  while (!done() && n < limit) {
    m.tick(0, step);
    n++;
  }
  return n;
}

/// 逐帧记录的可比较快照：阶段、已落槽数、事件位与经过的条目。
List<Object> _record(LottoMotion m) {
  final out = <Object>[];
  expect(m.start(), isTrue);
  _tickUntil(m, () => m.phase == LuckyPhase.cruising, limit: 100);
  expect(m.stopWith(lottoDraw), isTrue);
  for (var i = 0; i < 3000 && m.phase != LuckyPhase.settled; i++) {
    final events = m.tick(0, 10);
    out.add([
      m.phase,
      m.frame.drawnCount,
      events & ~LuckyMotionEvents.repaint,
      if (events & LuckyMotionEvents.itemPassed != 0)
        [m.passedReel, m.passedIndex]
    ]);
  }
  out.add(m.takeResult()?.draw?.numbers ?? const []);
  return out;
}

/// 验证大乐透物理模式的接入契约。
void main() {
  test('物理模式构造即落入，静止阶段持续模拟直至休眠', () {
    final m = _motion();
    expect(m.phase, LuckyPhase.idle);
    expect(m.isSimulating, isTrue);
    expect(m.tick(0, 16.67), LuckyMotionEvents.repaint);
    final frames = _tickUntil(m, () => !m.isSimulating, step: 16.67);
    expect(frames, lessThan(700));
    expect(m.phase, LuckyPhase.idle);
    expect(m.tick(0, 16.67), LuckyMotionEvents.none);
  });

  test('参数化模式不模拟，静止 tick 不产生事件', () {
    final m = _motion(lottoConfig);
    expect(m.isSimulating, isFalse);
    expect(m.tick(0, 16.67), LuckyMotionEvents.none);
    expect(m.frame.stirDeg, everyElement(0));
  });

  test('两种模式的相位、落槽事件、已落槽数与结果逐帧一致', () {
    final kinematic = _motion(lottoConfig);
    final physics = _motion();
    _tickUntil(physics, () => !physics.isSimulating, step: 16.67);
    final a = _record(kinematic);
    final b = _record(physics);
    expect(b, a);
    expect(a.length, greaterThan(20));
  });

  test('物理模式整局开奖：每颗球最终落在结果槽内且结果与指定一致', () {
    final rig = LottoRig(config: _physicsConfig);
    addTearDown(rig.dispose);
    rig.draw();
    final layout = lottoLayout(_physicsConfig);
    final frame = rig.controller.frame;
    var checked = 0;
    for (var p = 0; p < lottoDraw.numbers.length; p++) {
      final drum = layout.drums[p];
      final sorted = [...lottoDraw.numbers[p]]..sort();
      for (final number in lottoDraw.numbers[p]) {
        final b = number - drum.min;
        final slot = drum.slots[sorted.indexOf(number)];
        expect(frame.x[p][b], closeTo(slot.dx - drum.center.dx, 1e-6));
        expect(frame.y[p][b], closeTo(slot.dy - drum.center.dy, 1e-6));
        checked++;
      }
    }
    expect(checked, 5);
  });

  test('被导引的球在起飞前多帧被标记置顶，进度过半时恰在出口', () {
    int markedBeforeFlight(LottoConfig config) {
      final m = _motion(config);
      _tickUntil(m, () => !m.isSimulating, step: 16.67);
      expect(m.start(), isTrue);
      _tickUntil(m, () => m.phase == LuckyPhase.cruising, limit: 100);
      expect(m.stopWith(lottoDraw), isTrue);
      final drum = lottoLayout(config).drums[0];
      final ball = lottoDraw.numbers[0][0] - drum.min;
      var marked = 0;
      var handoff = false;
      for (var i = 0; i < 400 && m.phase != LuckyPhase.settled; i++) {
        m.tick(0, 10);
        final progress = m.frame.flight[0];
        if (progress == 0 && m.frame.slotOf[0][ball] >= 0) marked++;
        if (config.options.physics != null && progress >= 0.5 && !handoff) {
          handoff = true;
          final dx = m.frame.x[0][ball] - (drum.exit.dx - drum.center.dx);
          final dy = m.frame.y[0][ball] - (drum.exit.dy - drum.center.dy);
          expect(math.sqrt(dx * dx + dy * dy), lessThan(drum.ballRadius));
        }
      }
      if (config.options.physics != null) expect(handoff, isTrue);
      return marked;
    }

    expect(markedBeforeFlight(lottoConfig), lessThanOrEqualTo(1));
    expect(markedBeforeFlight(_physicsConfig), greaterThanOrEqualTo(3));
  });

  test('搅拌时各池拨杆角变化，结算后球继续下沉直至休眠', () {
    final m = _motion();
    _tickUntil(m, () => !m.isSimulating, step: 16.67);
    expect(m.start(), isTrue);
    for (var i = 0; i < 30; i++) {
      m.tick(0, 16.67);
    }
    expect(m.frame.stirDeg.every((d) => d > 0), isTrue);
    expect(m.stopWith(lottoDraw), isTrue);
    _tickUntil(m, () => m.phase == LuckyPhase.settled);
    expect(m.phase, LuckyPhase.settled);
    _tickUntil(m, () => !m.isSimulating, step: 16.67);
    expect(m.isSimulating, isFalse);
  });

  test('重置让球重新落入，作废则保持当前位置', () {
    final m = _motion();
    _tickUntil(m, () => !m.isSimulating, step: 16.67);
    final rest = m.frame.y[0].reduce(math.min);
    m.reset();
    expect(m.isSimulating, isTrue);
    expect(m.frame.y[0].reduce(math.min), lessThan(rest));
    _tickUntil(m, () => !m.isSimulating, step: 16.67);
    expect(m.start(), isTrue);
    for (var i = 0; i < 10; i++) {
      m.tick(0, 16.67);
    }
    final before = List<double>.of(m.frame.y[0]);
    expect(m.cancel(), isTrue);
    expect(m.frame.y[0], before);
    expect(m.takeResult()?.cancelled, isTrue);
  });

  test('结算后再次开始时球重新装填，已抽出的球回到容器', () {
    final m = _motion();
    _tickUntil(m, () => !m.isSimulating, step: 16.67);
    expect(m.start(), isTrue);
    _tickUntil(m, () => m.phase == LuckyPhase.cruising, limit: 100);
    expect(m.stopWith(lottoDraw), isTrue);
    _tickUntil(m, () => m.phase == LuckyPhase.settled);
    expect(m.start(), isTrue);
    expect(m.isSimulating, isTrue);
    for (final slots in m.frame.slotOf) {
      expect(slots, everyElement(-1));
    }
    expect(m.frame.drawnCount, 0);
  });

  test('容器缩放沿用物理世界与缓冲，仅改换算比例', () {
    final m = _motion();
    for (var i = 0; i < 20; i++) {
      m.tick(0, 16.67);
    }
    final buffer = m.frame.x[0];
    final before = List<double>.of(buffer);
    final old = lottoLayout(_physicsConfig);
    final bigger = lottoLayout(_physicsConfig, const Size(800, 720));
    m.configure(_physicsConfig, bigger);
    expect(identical(m.frame.x[0], buffer), isTrue);
    final scale = bigger.drums[0].radius / old.drums[0].radius;
    for (var i = 0; i < before.length; i++) {
      expect(buffer[i], closeTo(before[i] * scale, 1e-9));
    }
    expect(m.isSimulating, isTrue);
  });

  test('球数超过上限或半径比越界时该池回退参数化轨迹', () {
    final capped = lottoConfig.copyWith(
        options:
            lottoOptions.copyWith(physics: const LuckyPhysics(maxBodies: 5)));
    final m = _motion(capped);
    expect(m.isSimulating, isTrue);
    final all = lottoConfig.copyWith(
        options:
            lottoOptions.copyWith(physics: const LuckyPhysics(maxBodies: 3)));
    expect(_motion(all).isSimulating, isFalse);
  });

  test('非法物理参数在校验时抛出 ArgumentError', () {
    final bad = lottoConfig.copyWith(
        options:
            lottoOptions.copyWith(physics: const LuckyPhysics(gravity: -1)));
    expect(bad.validate, throwsArgumentError);
    expect(() => _motion(bad), throwsArgumentError);
  });

  test('大乐透选项的物理字段参与副本、相等性与哈希', () {
    const base = LottoOptions();
    const withPhysics = LottoOptions(physics: LuckyPhysics());
    expect(base.physics, isNull);
    expect(base.copyWith(physics: const LuckyPhysics()), withPhysics);
    expect(withPhysics, isNot(base));
    expect(withPhysics.hashCode, isNot(base.hashCode));
    expect(withPhysics.copyWith().physics, const LuckyPhysics());
  });

  test('控制器挂接后物理落入自动启动时钟，休眠后停表', () {
    final rig = LottoRig(config: _physicsConfig);
    addTearDown(rig.dispose);
    expect(rig.clock.isTicking, isTrue);
    var frames = 0;
    while (rig.clock.isTicking && frames < 1000) {
      rig.clock.advance(const Duration(microseconds: 16667));
      frames++;
    }
    expect(rig.clock.isTicking, isFalse);
    expect(rig.controller.play(), isTrue);
    expect(rig.clock.isTicking, isTrue);
  });

  test('十分钟的帧间隔也让物理模式保持有限坐标并正常结算', () {
    final m = _motion();
    expect(m.start(), isTrue);
    m.tick(0, 600000);
    expect(m.stopWith(lottoDraw), isTrue);
    _tickUntil(m, () => m.phase == LuckyPhase.settled);
    expect(m.phase, LuckyPhase.settled);
    for (final list in [...m.frame.x, ...m.frame.y, ...m.frame.angle]) {
      expect(list.every((v) => v.isFinite), isTrue);
    }
    expect(Offset(m.frame.x[0][0], m.frame.y[0][0]).distance.isFinite, isTrue);
  });
}
