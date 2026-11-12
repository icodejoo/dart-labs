import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/number_wheel/control/number_wheel_controller.dart';
import 'package:luckdraw/testing.dart';

import '../support/number_wheel_fixtures.dart';

/// 验证 NumberWheel 对共享状态机每条迁移边的适配。
void verifyNumberWheelEdge(String edge) {
  final c = NumberWheelController();
  final clock = ManualLuckyClock();
  c.attachHeadless(
      clock: clock, config: numberWheelFixture, layout: numberWheelLayout());
  try {
    /// 推进到匀速；首帧先建立时间轴基准。
    void cruise() {
      c.play();
      clock.advanceFrames(10);
      expect(c.phase.value, LuckyPhase.cruising);
    }

    /// 完成一局并验证结果下标。
    void settle() {
      clock.advanceFrames(100);
      expect(c.phase.value, LuckyPhase.settled);
      expect(c.lastResult?.index, 1);
    }

    switch (edge) {
      case 'E01':
        expect(c.play(), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E02':
        cruise();
        c.stop(1);
        settle();
        expect(c.play(), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E03':
        c.idleSpin();
        clock.advanceFrames(2);
        expect(c.play(), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E04':
        expect(c.idleSpin(), isTrue);
        expect(c.phase.value, LuckyPhase.idleSpinning);
      case 'E05':
        cruise();
        c.stop(1);
        settle();
        expect(c.idleSpin(), isTrue);
        expect(c.phase.value, LuckyPhase.idleSpinning);
      case 'E06':
        c.idleSpin();
        expect(c.cancel(), isTrue);
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.lastResult, isNull);
        expect(clock.isTicking, isFalse);
      case 'E07':
        cruise();
        expect(c.phase.value, LuckyPhase.cruising);
      case 'E08':
        c.play();
        expect(c.stop(1), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E09':
        c.play();
        c.stop(1);
        clock.advance(Duration.zero);
        clock.advance(const Duration(milliseconds: 100));
        expect(c.phase.value, LuckyPhase.cruising);
        clock.advance(const Duration(milliseconds: 16));
        expect(c.phase.value, LuckyPhase.decelerating);
      case 'E10':
        cruise();
        c.stop(1);
        expect(c.phase.value, LuckyPhase.cruising);
        clock.advanceFrames(1);
        expect(c.phase.value, LuckyPhase.decelerating);
      case 'E11':
        cruise();
        c.stop(1);
        settle();
        expect(c.lastResult?.cancelled, isFalse);
      case 'E12':
        c.play();
        expect(c.cancel(), isTrue);
        expect(c.lastResult?.cancelled, isTrue);
        expect(c.phase.value, LuckyPhase.idle);
      case 'E13':
        cruise();
        expect(c.cancel(), isTrue);
        expect(c.lastResult?.cancelled, isTrue);
        expect(c.phase.value, LuckyPhase.idle);
      case 'E14':
        cruise();
        expect(c.stop(-3), isTrue);
        expect(c.lastResult?.cancelled, isTrue);
        expect(c.phase.value, LuckyPhase.idle);
      case 'E15':
        c.configure(
            numberWheelFixture.copyWith(pockets: [
              for (final item in numberWheelFixture.pockets)
                item.copyWith(weight: 0)
            ]),
            numberWheelLayout());
        cruise();
        c.stop();
        expect(c.lastResult?.cancelled, isTrue);
        expect(c.phase.value, LuckyPhase.idle);
      case 'E16':
        cruise();
        c.stop(1);
        clock.advanceFrames(1);
        expect(c.stop(2), isFalse);
        expect(c.cancel(), isFalse);
        expect(c.phase.value, LuckyPhase.decelerating);
      case 'E17':
        expect(c.stop(1), isFalse);
        cruise();
        c.stop(1);
        settle();
        expect(c.stop(1), isFalse);
      case 'E18':
        c.play();
        expect(c.play(), isFalse);
        clock.advanceFrames(10);
        expect(c.play(), isFalse);
        c.stop(1);
        clock.advanceFrames(1);
        expect(c.play(), isFalse);
      case 'E19':
        cruise();
        expect(c.pause(), isTrue);
        final before = c.frame.discDeg;
        clock.advance(const Duration(minutes: 10));
        expect(c.frame.discDeg, before);
        expect(c.resume(), isTrue);
        clock.advanceFrames(1);
        expect(c.frame.discDeg, before);
        clock.advanceFrames(1);
        expect(c.frame.discDeg, greaterThan(before));
      case 'E20':
        c.reset();
        expect(c.phase.value, LuckyPhase.idle);
        c.idleSpin();
        c.reset();
        expect(c.phase.value, LuckyPhase.idle);
        c.play();
        c.reset();
        expect(c.lastResult?.cancelled, isTrue);
        cruise();
        c.stop(1);
        clock.advanceFrames(1);
        c.reset();
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.frame.discDeg, 0);
        cruise();
        c.stop(1);
        settle();
        c.reset();
        expect(c.phase.value, LuckyPhase.idle);
      case 'E21':
        c.play();
        final before = c.frame.discDeg;
        c.dispose();
        clock.advanceFrames(20);
        expect(clock.isTicking, isFalse);
        expect(c.frame.discDeg, before);
      case 'E22':
        c.idleSpin();
        expect(c.stop(1), isFalse);
        expect(c.phase.value, LuckyPhase.idleSpinning);
      case 'E23':
        for (var i = 0; i < 100; i++) {
          expect(c.play(), isTrue);
          c.stop(1);
          settle();
        }
      case 'E24':
        cruise();
        expect(c.stop(), isTrue);
        settle();
      case 'E26':
        expect(c.pause(), isFalse);
        cruise();
        c.stop(1);
        settle();
        expect(c.pause(), isFalse);
      default:
        fail('未知迁移边 $edge');
    }
  } finally {
    c.dispose();
    clock.dispose();
  }
}
