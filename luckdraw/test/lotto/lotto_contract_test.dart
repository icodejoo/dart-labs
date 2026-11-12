import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/src/lotto/motion/lotto_motion.dart';

import '../support/lotto_fixtures.dart';

/// 只验证基类默认时间上限，其它抽象命令不在此测试使用。
final class _DefaultDeltaMotion
    extends LuckyMotion<LottoConfig, LottoLayout, LottoFrame, LottoResult> {
  /// 未使用的抽象命令应明确失败。
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('仅测试默认时间上限');
}

/// 验证边界、重配置以及共享运动学契约。
void main() {
  group('Lotto contracts', () {
    test(
        'mixer outputs are bounded deterministic continuous and respect exclusion',
        () {
      final rest =
          packCirclesInCircle(count: 20, containerRadius: 10, bodyRadius: 9);
      final a = LuckySwirlMixer(rest: rest, containerRadius: 10, bodyRadius: 9);
      final b = LuckySwirlMixer(rest: rest, containerRadius: 10, bodyRadius: 9);
      final x = a.x;
      for (var i = 0; i < 30; i++) {
        final angle = i * 37.0;
        a.update(angle, 1);
        b.update(angle, 1);
        expect(a.x, b.x);
        expect(a.y, b.y);
        expect(a.angle, b.angle);
        for (var j = 0; j < rest.length; j++) {
          expect(math.sqrt(a.x[j] * a.x[j] + a.y[j] * a.y[j]),
              lessThanOrEqualTo(1 + 1e-8));
        }
      }
      final previousX = a.x.toList();
      final previousY = a.y.toList();
      a.update(29 * 37 + 0.001, 1);
      expect(identical(x, a.x), isTrue);
      for (var j = 0; j < rest.length; j++) {
        expect((a.x[j] - previousX[j]).abs(), lessThan(0.01));
        expect((a.y[j] - previousY[j]).abs(), lessThan(0.01));
      }
      final before = [a.x[0], a.y[0], a.angle[0]];
      a.update(10000, 0, excluded: List.generate(rest.length, (j) => j == 0));
      expect([a.x[0], a.y[0], a.angle[0]], before);
      final full =
          packCirclesInCircle(count: 3, containerRadius: 10, bodyRadius: 10);
      expect(full, hasLength(3));
      expect(full.every((p) => p.distance <= 0), isTrue);
      expect(packCirclesInCircle(count: 0, containerRadius: 10, bodyRadius: 1),
          isEmpty);
    });
    test('missing layouts stay idle and the default frame limit is available',
        () {
      final motion = LottoMotion();
      expect(motion.maxFrameDelta, _DefaultDeltaMotion().maxFrameDelta);
      expect(motion.start(), isFalse);
      expect(motion.idleSpin(), isFalse);
      motion.configure(lottoConfig, null);
      expect(motion.phase, LuckyPhase.idle);
      motion.configure(lottoConfig, lottoLayout(lottoConfig, Size.zero));
      expect(motion.start(), isFalse);
      motion.configure(lottoConfig, lottoLayout());
      expect(motion.start(), isTrue);
      motion.tick(0, -10);
      expect(motion.frame.swirlDeg, 0);
    });
    test('resizing and appearance updates preserve a drawing and its buffers',
        () {
      final rig = LottoRig();
      addTearDown(rig.dispose);
      final c = rig.controller;
      final layout = lottoLayout();
      c.configure(lottoConfig, layout);
      c.configure(lottoConfig, layout);
      c.play();
      c.stopWith(lottoDraw);
      rig.until(LuckyPhase.decelerating);
      rig.clock.advanceFrames(12, step: lottoStep);
      final angle = c.frame.swirlDeg;
      final flight = c.frame.flight;
      final drawn = c.frame.drawnCount;
      final updated =
          lottoConfig.copyWith(style: const LottoStyle(buttonText: '开奖'));
      c.configure(updated, lottoLayout(updated, Size.zero));
      expect(c.phase.value, LuckyPhase.decelerating);
      expect(c.frame.drawnCount, drawn);
      c.configure(updated, lottoLayout(updated, const Size(600, 400)));
      expect(c.phase.value, LuckyPhase.decelerating);
      expect(c.frame.swirlDeg, angle);
      expect(c.frame.flight, same(flight));
      expect(c.frame.drawnCount, drawn);
      rig.until(LuckyPhase.settled);
      expect(c.lastResult!.draw, lottoDraw);
      expect(c.frame.drawnCount, 5);
      final resized = lottoLayout(updated, const Size(200, 500));
      c.configure(updated, resized);
      expect(c.phase.value, LuckyPhase.settled);
      for (var p = 0; p < resized.drums.length; p++) {
        final drum = resized.drums[p];
        for (final number in lottoDraw.numbers[p]) {
          final b = number - drum.min;
          final slot = drum.slots[c.frame.slotOf[p][b]];
          expect(c.frame.x[p][b] + drum.center.dx, slot.dx);
          expect(c.frame.y[p][b] + drum.center.dy, slot.dy);
        }
      }
      c.configure(updated, lottoLayout(updated, Size.zero));
      expect(c.phase.value, LuckyPhase.settled);
      expect(c.play(), isFalse);
      expect(c.idleSpin(), isFalse);
      c.configure(updated, resized);
      expect(c.play(), isTrue);
    });
    test(
        'structural updates preserve cruising and queued draws use the applied pools',
        () {
      final rig = LottoRig();
      addTearDown(rig.dispose);
      final c = rig.controller;
      c.play();
      rig.until(LuckyPhase.cruising);
      final angle = c.frame.swirlDeg;
      final one = lottoConfig.copyWith(pools: [
        lottoConfig.pools.first.copyWith(min: 5, max: 8, count: 1),
      ]);
      c.configure(one, lottoLayout(one), structural: true);
      expect(c.phase.value, LuckyPhase.cruising);
      expect(c.frame.swirlDeg, angle);
      expect(c.stop(), isTrue);
      rig.until(LuckyPhase.decelerating);
      c.configure(lottoConfig, lottoLayout(), structural: true);
      rig.until(LuckyPhase.settled);
      expect(c.lastResult!.draw!.numbers.single, hasLength(1));
      expect(c.play(), isTrue);
      expect(c.stop(), isTrue);
      rig.until(LuckyPhase.settled);
      expect(c.lastResult!.draw!.numbers.map((p) => p.length), [3, 2]);
      final motion = LottoMotion()..configure(lottoConfig, lottoLayout());
      motion.configure(
          one.copyWith(pools: [
            one.pools.first.copyWith(max: 9),
            lottoConfig.pools.last,
          ]),
          lottoLayout(one.copyWith(pools: [
            one.pools.first.copyWith(max: 9),
            lottoConfig.pools.last,
          ])));
      expect(motion.phase, LuckyPhase.idle);
    });
    test(
        'frame timebase advances once per tick and options latch at phase boundaries',
        () {
      final config = lottoConfig.copyWith(
          options: lottoOptions.copyWith(
              motion:
                  lottoOptions.motion.copyWith(timebase: LuckyTimebase.frame)));
      final motion = LottoMotion()..configure(config, lottoLayout(config));
      motion.start();
      motion.tick(40, 40);
      expect(motion.frame.swirlDeg, 12);
      final old = motion.frame.swirlDeg;
      final changed = config.copyWith(
          options: config.options
              .copyWith(motion: config.options.motion.copyWith(speed: 24)));
      motion.configure(changed, lottoLayout(changed));
      motion.tick(50, 10);
      expect(motion.frame.swirlDeg - old, 12);
      motion.stopWith(lottoDraw);
      motion.tick(60, 10);
      motion.tick(100, 40);
      expect(motion.frame.mix, lottoOptions.drawMix);
      final slow = lottoConfig.copyWith(
          options: lottoOptions.copyWith(
              motion:
                  lottoOptions.motion.copyWith(speed: 1, idleSpinSpeed: 2)));
      final idle = LottoMotion()..configure(slow, lottoLayout(slow));
      expect(idle.idleSpin(), isTrue);
      idle.tick(10, 10);
      expect(idle.frame.mix, 1);
    });
  });
}
