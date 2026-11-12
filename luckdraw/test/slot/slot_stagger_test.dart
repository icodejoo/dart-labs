import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/slot/motion/slot_motion.dart';

import '../support/slot_fixtures.dart';

/// 独立翻译上游公式与错峰停止行为。
void main() {
  group('SlotMotion stagger', () {
    test('zero stopDelay keeps all reels identical to upstream', () {
      final config = slotTestConfig.copyWith(
          reels: [
            const SlotReel(order: [2, 0, 1]),
            const SlotReel(direction: -1, speed: 9),
            const SlotReel(speed: -3)
          ],
          options: slotTestConfig.options.copyWith(
              motion: slotTestMotion.copyWith(
                  stopSolver: const UpstreamStopSolver())));
      expect(config.reels.every((r) => r.stopDelay == Duration.zero), isTrue);
      final layout = slotLayout(config);
      final m = SlotMotion()
        ..configure(config, layout)
        ..start();
      final expected = Float64List(3);
      final stop = Float64List(3);
      final change = Float64List(3);
      var step = 1;
      var endTime = double.nan;
      var fps = 16.6;
      const targets = [1, 2, 0];
      // 上游 slot.ts:459–481、531–595；不调用被测求解器或缓动。
      for (var n = 0; n <= 10; n++) {
        final t = n * 16.0;
        final old = step;
        if (n == 3) expect(m.requestStop(targets), isTrue);
        if (old == 3 && endTime.isNaN) {
          endTime = t;
          for (var r = 0; r < 3; r++) {
            final order = config.reels[r].order ?? [0, 1, 2];
            final speed = config.reels[r].speed ?? 12;
            final dir = config.reels[r].direction ?? 1;
            stop[r] = expected[r];
            for (var i = 1;; i++) {
              final c = layout.cellAndSpacing * order.indexOf(targets[r]) +
                  (layout.reels[r].period * i * dir) -
                  stop[r];
              final x = fps / 64;
              if ((-c * x * (x - 2) + stop[r] - stop[r]).abs() > speed) {
                change[r] = c;
                break;
              }
            }
          }
        }
        for (var r = 0; r < 3; r++) {
          final speed = (config.reels[r].speed ?? 12).abs();
          final dir = config.reels[r].direction ?? 1;
          if (old == 1) {
            if (n > 0) fps = t / n;
            final x = t.clamp(0.0, 32.0) / 32;
            final current = speed * x * x;
            if (current == speed) step = 2;
            expected[r] =
                (expected[r] + current * dir).remainder(layout.reels[r].period);
          } else if (old == 2) {
            expected[r] =
                (expected[r] + speed * dir).remainder(layout.reels[r].period);
            if (n >= 3) step = 3;
          } else if (old == 3) {
            final elapsed = t - endTime;
            final x = elapsed.clamp(0.0, 64.0) / 64;
            // IMP-05 / U-06：只映射首减速帧，后续帧仍逐位对照上游。
            expected[r] =
                elapsed == 0 ? stop[r] : -change[r] * x * (x - 2) + stop[r];
            if (elapsed >= 64) step = 0;
          }
        }
        m.tick(t, 16);
        expect(
            m.frame.scroll.buffer.asUint8List(), expected.buffer.asUint8List(),
            reason: 'frame $n');
      }
      expect(m.phase, LuckyPhase.settled);
      expect(m.takeResult()!.indices, targets);
    });
    test(
        'stopDelay starts each reel deceleration later and settles after the last reel',
        () {
      final config = slotTestConfig.copyWith(reels: [
        const SlotReel(),
        const SlotReel(stopDelay: Duration(milliseconds: 32)),
        const SlotReel(stopDelay: Duration(milliseconds: 64))
      ]);
      final m = SlotMotion()
        ..configure(config, slotLayout(config))
        ..start()
        ..tick(0, 0)
        ..tick(32, 32)
        ..requestStop([0, 1, 2])
        ..tick(48, 16)
        ..tick(64, 16);
      expect(m.stopScroll[0], isNonZero);
      expect(m.stopScroll[1], 0);
      final before = m.frame.scroll[1];
      m.tick(80, 16);
      expect(m.frame.scroll[1] - before, 12);
      m.tick(96, 16);
      expect(m.stopScroll[1], isNonZero);
      expect(m.stopScroll[2], 0);
      m.tick(128, 32);
      expect(m.stopScroll[2], isNonZero);
      expect(m.phase, LuckyPhase.decelerating);
      m.tick(160, 32);
      expect(m.frame.scroll[0], m.stopScroll[0] + m.endScroll[0]);
      expect(m.phase, LuckyPhase.decelerating);
      expect(m.takeResult(), isNull);
      m.tick(192, 32);
      expect(m.phase, LuckyPhase.settled);
      expect(m.takeResult()!.indices, [0, 1, 2]);
    });
    test('staggered reels still land on their targets', () {
      final config = slotTestConfig.copyWith(reels: [
        const SlotReel(order: [2, 0, 1], stopDelay: Duration(milliseconds: 16)),
        const SlotReel(
            order: [1, 2, 0],
            direction: -1,
            stopDelay: Duration(milliseconds: 32)),
        const SlotReel(stopDelay: Duration(milliseconds: 48))
      ]);
      final h = SlotHarness(config);
      addTearDown(h.dispose);
      h.cruise();
      h.controller.stopEach([1, 2, 0]);
      h.settle();
      final layout = slotLayout(config);
      for (var r = 0; r < 3; r++) {
        expect(
            h.controller.frame.scroll[r] % layout.reels[r].period,
            closeTo(
                layout.reels[r].stripPrizes.indexOf([1, 2, 0][r]) *
                    layout.cellAndSpacing,
                1e-9));
      }
      expect(h.results, hasLength(1));
    });
  });
}
