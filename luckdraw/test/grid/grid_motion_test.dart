import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/src/grid/motion/grid_motion.dart';
import 'package:luckdraw/testing.dart';

import '../support/grid_fixtures.dart';

/// 测试每帧有效时长。
const double _stepMs = 16;

/// 短动画配置。
const LuckyMotionOptions gridTestMotion = LuckyMotionOptions(
    accelerationTime: Duration(milliseconds: 64),
    decelerationTime: Duration(milliseconds: 96),
    timebase: LuckyTimebase.frame);

/// 创建短动画状态机。
GridMotion gridMotion(
        {LuckyMotionOptions options = gridTestMotion}) =>
    GridMotion()
      ..configure(
          gridFixture.copyWith(options: GridOptions(motion: options)), null);

/// 推进到结算或失败。
void settleGridMotion(GridMotion motion, {double start = 0}) {
  var time = start;
  for (var i = 0; i < 500 && motion.phase != LuckyPhase.settled; i++) {
    motion.tick(time, _stepMs);
    time += _stepMs;
  }
  expect(motion.phase, LuckyPhase.settled);
}

/// 九宫格逐帧数值与通知契约。
void main() {
  group('GridMotion', () {
    test(
        'acceleration uses easeIn(t, 0.1, speed - 0.1) with speed = config.speed / 40',
        () {
      final motion = gridMotion();
      expect(motion.start(), isTrue);
      var expected = 0.0;
      for (var i = 0; i <= 4; i++) {
        expected += LuckyEasings.quad
            .easeIn(i * _stepMs, 0.1, 20 / 40 - 0.1, 64)
            .remainder(8);
        motion.tick(i * _stepMs, _stepMs);
        expect(motion.frame.currIndex, expected);
      }
      expect(motion.phase, LuckyPhase.cruising);
    });
    test('active index is the truncated currIndex remainder prizes length', () {
      final motion = gridMotion()..start();
      for (var i = 0; i < 80; i++) {
        motion.tick(i * _stepMs, _stepMs);
        expect(motion.frame.activeIndex,
            motion.frame.currIndex.remainder(8).toInt());
      }
      expect(motion.frame.currIndex, greaterThan(8));
      expect(motion.passedReel, 0);
      expect(motion.passedIndex, motion.frame.activeIndex);
    });
    test('no cell is active before the first play and after cancel', () {
      final motion = gridMotion();
      expect(motion.frame.activeIndex, -1);
      motion.start();
      expect(motion.frame.activeIndex, 0);
      motion.tick(0, _stepMs);
      expect(motion.cancel(), isTrue);
      expect(motion.frame.activeIndex, -1);
      expect(motion.takeResult()!.cancelled, isTrue);
      expect(motion.takeResult(), isNull);
    });
    test('the active cell stays highlighted after settling', () {
      final motion = gridMotion()..start();
      expect(motion.requestStop(5), isTrue);
      settleGridMotion(motion);
      expect(motion.frame.activeIndex, 5);
      expect(motion.tick(10000, _stepMs), LuckyMotionEvents.none);
      expect(motion.frame.activeIndex, 5);
      final result = motion.takeResult()!;
      expect(result.index, 5);
      expect(result.prize, gridFixture.prizes[5]);
    });
    test('final currIndex lands on prizes.length * i + target', () {
      final motion = gridMotion()..start();
      motion.requestStop(11, extraLaps: 2);
      settleGridMotion(motion);
      expect(motion.frame.currIndex.remainder(8), 3);
      expect(motion.frame.currIndex, greaterThanOrEqualTo(19));
    });
    test(
        'monotonic solver never decreases currIndex on a short deceleration grid',
        () {
      for (final speed in [0.1, 1.0, 20.0, 40.0, 100.0]) {
        final motion = gridMotion(
            options: gridTestMotion.copyWith(
                speed: speed,
                decelerationTime: const Duration(milliseconds: 1)))
          ..start();
        motion.requestStop(0);
        var previous = 0.0;
        for (var i = 0; i < 20; i++) {
          motion.tick(i * _stepMs, _stepMs);
          expect(motion.frame.currIndex, greaterThanOrEqualTo(previous));
          previous = motion.frame.currIndex;
        }
        expect(motion.phase, LuckyPhase.settled);
      }
    });
    test('repaint notifier fires only when the active index changes', () {
      final motion = gridMotion()..start();
      for (var i = 0; i < 40; i++) {
        final previous = motion.frame.activeIndex;
        final events = motion.tick(i * _stepMs, _stepMs);
        expect(events & LuckyMotionEvents.repaint != 0,
            previous != motion.frame.activeIndex);
        expect(events & LuckyMotionEvents.itemPassed != 0,
            previous != motion.frame.activeIndex);
      }
    });
    test('onActiveChanged fires for every index step', () {
      final motion = gridMotion()..start();
      final passed = <int>[];
      for (var i = 0; i < 40; i++) {
        if (motion.tick(i * _stepMs, _stepMs) & LuckyMotionEvents.itemPassed !=
            0) {
          passed.add(motion.passedIndex);
        }
      }
      expect(passed.length, greaterThan(8));
      for (var i = 1; i < passed.length; i++) {
        expect(passed[i], (passed[i - 1] + 1).remainder(8));
      }
    });
    test('zero prizes refuses to play and activates nothing', () {
      final motion = GridMotion()..configure(const GridConfig(), null);
      expect(motion.start(), isFalse);
      expect(motion.idleSpin(), isFalse);
      expect(motion.frame.activeIndex, -1);
      expect(motion.tick(0, _stepMs), 0);
    });
  });
  test(
      'GridController commands > headless stop picker playUntil and structural updates',
      () async {
    final controller = GridController(random: SequenceRandom([0]));
    final clock = ManualLuckyClock();
    controller.attachHeadless(
        clock: clock,
        config: gridFixture.copyWith(
            options: const GridOptions(motion: gridTestMotion)));
    expect(controller.stop(), isFalse);
    expect(controller.play(), isTrue);
    clock.advanceFrames(8);
    expect(controller.stopAt(10, extraLaps: 1), isTrue);
    expect(controller.stop(), isTrue);
    clock.advanceFrames(30);
    expect(controller.lastResult!.index, 0);
    final pending = controller.playUntil(() => 2);
    await Future<void>.delayed(Duration.zero);
    clock.advanceFrames(30);
    expect((await pending).index, 2);
    final cancelled = controller.playUntil(() => null);
    await Future<void>.delayed(Duration.zero);
    expect((await cancelled).cancelled, isTrue);
    controller.reset();
    expect(controller.frame.currIndex, 0);
    controller.dispose();
    clock.dispose();
  });
  test(
      'GridMotion edges > time mode idle promotion empty reconfiguration and rejected commands',
      () {
    final motion = gridMotion(
        options: gridTestMotion.copyWith(timebase: LuckyTimebase.time));
    expect(motion.requestStop(0), isFalse);
    expect(motion.cancel(), isFalse);
    expect(motion.idleSpin(), isTrue);
    expect(motion.idleSpin(), isFalse);
    motion.tick(0, 1000 / 60);
    expect(motion.frame.currIndex, 2 / 40);
    expect(motion.frame.activeIndex, -1);
    expect(motion.start(), isTrue);
    expect(motion.start(), isFalse);
    motion.tick(0, 1000 / 60);
    expect(motion.frame.currIndex, 0.1);
    motion.requestStop(3);
    motion.tick(64, 1000 / 60);
    motion.tick(80, 1000 / 60);
    expect(motion.phase, LuckyPhase.decelerating);
    expect(motion.cancel(), isFalse);
    expect(motion.requestStop(0), isFalse);
    motion.tick(96, 1000 / 60);
    motion.tick(200, 1000 / 60);
    expect(motion.phase, LuckyPhase.settled);
    expect(motion.idleSpin(), isTrue);
    expect(motion.frame.activeIndex, -1);
    motion.configure(const GridConfig(), null);
    final events = motion.tick(220, 16);
    expect(events & LuckyMotionEvents.cancelled, isNot(0));
    expect(motion.phase, LuckyPhase.idle);
    motion.configure(gridFixture, gridLayout(gridFixture, size: Size.zero));
    expect(motion.start(), isFalse);
    expect(motion.idleSpin(), isFalse);
  });
  test(
      'GridMotion reconfigure > settled target wraps to the new prize count without resetting position',
      () {
    final motion = gridMotion()..start();
    motion.requestStop(5);
    settleGridMotion(motion);
    final position = motion.frame.currIndex;
    motion.configure(
        gridFixture.copyWith(prizes: gridFixture.prizes.take(2).toList()),
        null);
    expect(motion.frame.currIndex, position);
    expect(motion.frame.activeIndex, 1);
    expect(motion.start(), isTrue);
  });
  test('GridMotion defaults > plugins inherit the bounded core frame budget',
      () {
    final defaults = _CoreMotionDefaults();
    expect(defaults.maxFrameDelta, const Duration(milliseconds: 100));
    final grid = gridMotion(
        options: gridTestMotion.copyWith(
            maxFrameDelta: const Duration(milliseconds: 32)));
    expect(grid.maxFrameDelta, const Duration(milliseconds: 32));
    final empty = GridMotion()..configure(const GridConfig(), null);
    expect(empty.start(), isFalse);
    expect(empty.start(), isFalse);
    expect(empty.frame.activeIndex, -1);
  });
}

/// 仅验证核心默认策略的抽象接口替身，未使用成员明确拒绝访问。
final class _CoreMotionDefaults extends LuckyMotion<GridConfig, GridLayout,
    GridFrame, LuckyResult<GridPrize>> {
  /// 意外调用未提供的运动方法时让测试立即失败。
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('测试替身只提供核心默认策略');
}
