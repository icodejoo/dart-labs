import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/testing.dart';

import '../support/grid_fixtures.dart';

/// 状态边测试使用的动画时长。
const Duration _duration = Duration(milliseconds: 64);

/// 状态边测试配置。
final GridConfig _config = gridFixture.copyWith(
    options: const GridOptions(
        motion: LuckyMotionOptions(
            accelerationTime: _duration, decelerationTime: _duration)));

/// 为共享状态机矩阵执行真实九宫格控制器断言。
final class GridStateHarness {
  /// 验证指定迁移边；每次调用拥有独立时钟与控制器。
  static void verifyEdge(String edge) {
    final controller = GridController(random: SequenceRandom([0]));
    final clock = ManualLuckyClock();
    controller.attachHeadless(clock: clock, config: _config);
    addTearDown(() {
      controller.dispose();
      clock.dispose();
    });

    /// 推进到匀速。
    void cruise() {
      controller.play();
      clock.advanceFrames(6);
      expect(controller.phase.value, LuckyPhase.cruising);
    }

    /// 推进到减速。
    void decelerate() {
      cruise();
      controller.stop(2);
      clock.advanceFrames(1);
      expect(controller.phase.value, LuckyPhase.decelerating);
    }

    /// 推进一局到结算。
    void settle() {
      controller.play();
      controller.stop(2);
      clock.advanceFrames(20);
      expect(controller.phase.value, LuckyPhase.settled);
      expect(controller.lastResult!.index, 2);
    }

    switch (edge) {
      case 'E01':
        expect(controller.play(), isTrue);
        expect(controller.phase.value, LuckyPhase.accelerating);
      case 'E02':
        settle();
        expect(controller.play(), isTrue);
        expect(controller.phase.value, LuckyPhase.accelerating);
        expect(controller.frame.activeIndex, 2);
      case 'E03':
        controller.idleSpin();
        clock.advanceFrames(4);
        final before = controller.frame.currIndex;
        expect(controller.play(), isTrue);
        clock.advanceFrames(1);
        expect(controller.frame.currIndex, greaterThan(before));
        expect(controller.phase.value, LuckyPhase.accelerating);
      case 'E04':
        expect(controller.idleSpin(), isTrue);
        expect(controller.phase.value, LuckyPhase.idleSpinning);
      case 'E05':
        settle();
        expect(controller.idleSpin(), isTrue);
        expect(controller.frame.activeIndex, -1);
      case 'E06':
        controller.idleSpin();
        expect(controller.cancel(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(controller.lastResult!.cancelled, isTrue);
      case 'E07':
        cruise();
      case 'E08':
        controller.play();
        expect(controller.stop(2), isTrue);
        expect(controller.phase.value, LuckyPhase.accelerating);
      case 'E09':
        controller.play();
        controller.stop(2);
        clock.advanceFrames(4);
        expect(controller.phase.value, LuckyPhase.accelerating);
        final beforeCruise = controller.frame.currIndex;
        clock.advanceFrames(1);
        expect(controller.phase.value, LuckyPhase.decelerating);
        expect(controller.frame.currIndex - beforeCruise,
            closeTo(20 / 40 * 16 / (1000 / 60), 1e-12));
        clock.advanceFrames(1);
        expect(controller.phase.value, LuckyPhase.decelerating);
      case 'E10':
        decelerate();
      case 'E11':
        settle();
      case 'E12':
        controller.play();
        expect(controller.cancel(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(controller.lastResult!.cancelled, isTrue);
      case 'E13':
        cruise();
        expect(controller.cancel(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
      case 'E14':
        cruise();
        expect(controller.stop(-1), isTrue);
        expect(controller.lastResult!.cancelled, isTrue);
        expect(controller.frame.activeIndex, -1);
      case 'E15':
        controller.configure(
            _config.copyWith(prizes: [
              for (final prize in _config.prizes) prize.copyWith(weight: 0)
            ]),
            null);
        controller.play();
        expect(controller.stop(), isTrue);
        expect(controller.phase.value, LuckyPhase.idle);
        expect(controller.lastResult!.cancelled, isTrue);
      case 'E16':
        decelerate();
        expect(controller.stop(0), isFalse);
        expect(controller.cancel(), isFalse);
        expect(controller.phase.value, LuckyPhase.decelerating);
      case 'E17':
        expect(controller.stop(0), isFalse);
        settle();
        expect(controller.stop(0), isFalse);
      case 'E18':
        controller.play();
        expect(controller.play(), isFalse);
        clock.advanceFrames(6);
        expect(controller.play(), isFalse);
        controller.stop(0);
        clock.advanceFrames(1);
        expect(controller.play(), isFalse);
      case 'E19':
        cruise();
        expect(controller.pause(), isTrue);
        final position = controller.frame.currIndex;
        clock.advanceFrames(50);
        expect(controller.frame.currIndex, position);
        expect(controller.resume(), isTrue);
        clock.advanceFrames(1);
        expect(controller.frame.currIndex, position);
        clock.advanceFrames(1);
        expect(controller.frame.currIndex, greaterThan(position));
        expect(controller.frame.currIndex - position, lessThan(1));
      case 'E20':
        for (final phase in LuckyPhase.values) {
          controller.reset();
          switch (phase) {
            case LuckyPhase.idle:
              break;
            case LuckyPhase.idleSpinning:
              controller.idleSpin();
            case LuckyPhase.accelerating:
              controller.play();
            case LuckyPhase.cruising:
              cruise();
            case LuckyPhase.decelerating:
              decelerate();
            case LuckyPhase.settled:
              settle();
          }
          controller.reset();
          expect(controller.phase.value, LuckyPhase.idle);
          expect(controller.frame.currIndex, 0);
          expect(controller.frame.activeIndex, -1);
        }
      case 'E21':
        controller.play();
        clock.advanceFrames(2);
        final position = controller.frame.currIndex;
        controller.dispose();
        clock.advanceFrames(50);
        expect(controller.frame.currIndex, position);
        expect(clock.isTicking, isFalse);
      case 'E22':
        controller.idleSpin();
        expect(controller.stop(0), isFalse);
        expect(controller.phase.value, LuckyPhase.idleSpinning);
      case 'E23':
        for (var i = 0; i < 100; i++) {
          settle();
        }
      case 'E24':
        controller.play();
        expect(controller.stop(), isTrue);
        clock.advanceFrames(20);
        expect(controller.phase.value, LuckyPhase.settled);
        expect(controller.lastResult!.index, 0);
      case 'E26':
        expect(controller.pause(), isFalse);
        settle();
        expect(controller.pause(), isFalse);
      default:
        fail('未定义迁移边：$edge');
    }
  }
}
