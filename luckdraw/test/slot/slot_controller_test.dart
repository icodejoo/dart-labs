import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/testing.dart';

import '../support/slot_fixtures.dart';

/// 验证类型化停止命令及异步生命周期。
void main() {
  group('SlotController', () {
    test('stop(index) fills every reel', () {
      final h = SlotHarness();
      addTearDown(h.dispose);
      h.cruise();
      expect(h.controller.stop(2), isTrue);
      expect(h.controller.frame.targets, [2, 2, 2]);
      h.settle();
      expect(h.results.single.index, 2);
    });
    test('stopEach requires one index per reel', () {
      final h = SlotHarness();
      addTearDown(h.dispose);
      h.cruise();
      expect(() => h.controller.stopEach([0]), throwsArgumentError);
      expect(h.phase, LuckyPhase.cruising);
      expect(h.controller.frame.targets, [-1, -1, -1]);
    });
    test('stop() without index uses the picker for all reels', () {
      final c = SlotController(random: SequenceRandom([0.5]));
      final clock = ManualLuckyClock();
      addTearDown(c.dispose);
      addTearDown(clock.dispose);
      c.attachHeadless(
          clock: clock, config: slotTestConfig, layout: slotLayout());
      expect(c.play(), isTrue);
      expect(c.stop(), isTrue);
      expect(c.frame.targets, [1, 1, 1]);
      clock.advanceFrames(20);
      expect(c.lastResult!.prize, slotTestPrizes[1]);
    });
    test('any negative index cancels like upstream -1', () {
      final h = SlotHarness();
      addTearDown(h.dispose);
      const negativeIndices = [-1, -2, -999];
      for (final value in negativeIndices) {
        h.cruise();
        expect(h.controller.stopEach([0, value, 1]), isTrue);
        expect(h.phase, LuckyPhase.idle);
        expect(h.controller.lastResult!.cancelled, isTrue);
      }
      expect(h.results, isEmpty);
    });
    test('E25 cancel emits no end callback like upstream', () {
      final h = SlotHarness();
      addTearDown(h.dispose);
      h.cruise();
      expect(h.controller.cancel(), isTrue);
      expect(h.results, isEmpty);
      expect(h.controller.lastResult!.cancelled, isTrue);
      expect(h.clock.isTicking, isFalse);
    });
    test('no reels or no prizes refuses to play', () {
      final emptyConfigs = [
        slotTestConfig.copyWith(reels: []),
        slotTestConfig.copyWith(prizes: [])
      ];
      for (final config in emptyConfigs) {
        final h = SlotHarness(config);
        addTearDown(h.dispose);
        expect(h.controller.play(), isFalse);
        expect(h.controller.idleSpin(), isFalse);
      }
    });
    test('stopEach result carries indices and the winning prize', () {
      final h = SlotHarness();
      addTearDown(h.dispose);
      h.cruise();
      expect(h.controller.stopEach([0, 1, 2]), isTrue);
      h.settle();
      expect(h.results.single.indices, [0, 1, 2]);
      expect(h.results.single.prize, isNull);
      h.cruise();
      expect(h.controller.stopEach([1, 1, 1]), isTrue);
      h.settle();
      expect(h.results.last.prize, slotTestPrizes[1]);
      expect(() => h.results.last.indices.add(2), throwsUnsupportedError);
    });
    test('playUntil completes success null error and disposal paths', () async {
      final h = SlotHarness();
      addTearDown(h.dispose);
      final result = h.controller
          .playUntil(() => [2, 2, 2], minSpinDuration: slotTestStep);
      await Future<void>.delayed(Duration.zero);
      h.settle();
      expect((await result).indices, [2, 2, 2]);
      final cancelled = h.controller.playUntil(() => null);
      await Future<void>.delayed(Duration.zero);
      expect((await cancelled).cancelled, isTrue);
      final error = h.controller.playUntil(() => throw StateError('失败'));
      await expectLater(error, throwsStateError);
      final disposed = h.controller.playUntil(() => [0, 0, 0]);
      h.controller.dispose();
      expect((await disposed).cancelled, isTrue);
      expect(h.controller.stop(), isFalse);
    });
  });
}
