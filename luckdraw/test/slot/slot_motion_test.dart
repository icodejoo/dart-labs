import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/src/core/motion/motion.dart';
import 'package:luckdraw/src/slot/motion/slot_motion.dart';

import '../support/slot_fixtures.dart';

/// 配置并启动无宿主状态机。
SlotMotion _motion([SlotConfig config = slotTestConfig]) => SlotMotion()
  ..configure(config, slotLayout(config))
  ..start()
  ..tick(0, 0);

/// 进入减速求解首帧。
void _carve(SlotMotion m, [List<int> indices = const [1, 1, 1]]) {
  m.tick(32, 32);
  m.requestStop(indices);
  m.tick(48, 16);
  m.tick(64, 16);
}

/// 返回指定的自定义中奖下标。
int? _customWin(List<int> indices, SlotConfig config) => indices[1];

/// 只读取核心默认时间上限的 SPI 探针，未实现命令不可调用。
class _DefaultDeltaMotion
    extends LuckyMotion<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 明确拒绝本探针未提供的抽奖接口。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('仅探测默认时间上限');
}

/// 验证逐帧公式、停止求解和尺寸变更。
void main() {
  group('SlotMotion', () {
    test('scroll advances with remainder semantics for negative direction', () {
      final m = _motion(slotTestConfig.copyWith(
          options: slotTestConfig.options.copyWith(direction: -1)));
      m.tick(16, 16);
      expect(m.frame.scroll.first, -3);
      m.tick(32, 16);
      expect(m.frame.scroll.first, -15);
      expect(m.frame.scroll.first, lessThan(0));
    });
    test('acceleration and cruising use per-reel speed and direction', () {
      final m = _motion(slotTestConfig.copyWith(reels: [
        const SlotReel(speed: -8, direction: -1),
        const SlotReel(speed: 4),
        const SlotReel(speed: 0)
      ]));
      m.tick(16, 16);
      expect(m.frame.scroll, [-2, 1, 0]);
      m.tick(32, 16);
      m.tick(48, 16);
      expect(m.frame.scroll, [-18, 9, 0]);
    });
    test(
        'carve picks the first candidate whose speed magnitude exceeds the reel speed',
        () {
      final config = slotTestConfig.copyWith(
          options: slotTestConfig.options.copyWith(
              motion: slotTestMotion.copyWith(
                  stopSolver: const UpstreamStopSolver())));
      final m = _motion(config);
      _carve(m);
      final layout = slotLayout(config);
      final stop = m.stopScroll.first;
      final fps = 16.0;
      final first = layout.cellAndSpacing + layout.reels.first.period - stop;
      expect(
          slotTestMotion.decelerationEasing.easeOut(fps, stop, first, 64) -
              stop,
          greaterThan(12));
      expect(m.endScroll.first, first);
      final negative = _motion(config.copyWith(reels: [
        const SlotReel(speed: -1, direction: -1),
        const SlotReel(),
        const SlotReel()
      ]));
      _carve(negative);
      expect(
          negative.endScroll.first,
          slotLayout(config).cellAndSpacing -
              layout.reels.first.period -
              negative.stopScroll.first);
    });
    test('final scroll centers the target prize in the window', () {
      final config = slotTestConfig.copyWith(reels: [
        const SlotReel(order: [2, 0, 1]),
        const SlotReel(order: [1, 2, 0]),
        const SlotReel(direction: -1)
      ]);
      final m = _motion(config);
      _carve(m, [2, 0, 1]);
      m.tick(128, 64);
      final l = slotLayout(config);
      expect(m.phase, LuckyPhase.settled);
      for (var r = 0; r < 3; r++) {
        final pos = l.reels[r].stripPrizes.indexOf(m.frame.targets[r]);
        expect(m.frame.scroll[r] % l.reels[r].period,
            closeTo(l.cellAndSpacing * pos, 1e-9));
        expect(m.frame.scroll[r], m.stopScroll[r] + m.endScroll[r]);
      }
      expect(m.takeResult()!.indices, [2, 0, 1]);
      expect(m.takeResult(), isNull);
    });
    test(
        'first deceleration tick holds stopScroll instead of jumping to 0 (IMP-05)',
        () {
      final m = _motion();
      _carve(m);
      expect(m.stopScroll.first, isNonZero);
      expect(m.frame.scroll, m.stopScroll);
    });
    test(
        'default win predicate requires equal indices contained in every order',
        () {
      expect(upstreamSlotWinPredicate([1, 1, 1], slotTestConfig), 1);
      expect(upstreamSlotWinPredicate([], slotTestConfig), isNull);
      expect(upstreamSlotWinPredicate([1], slotTestConfig), isNull);
      expect(upstreamSlotWinPredicate([-1, -1, -1], slotTestConfig), isNull);
      expect(upstreamSlotWinPredicate([9, 9, 9], slotTestConfig), isNull);
      expect(upstreamSlotWinPredicate([1, 0, 1], slotTestConfig), isNull);
      expect(
          upstreamSlotWinPredicate(
              [1, 1, 1],
              slotTestConfig.copyWith(reels: [
                const SlotReel(order: [0]),
                const SlotReel(),
                const SlotReel()
              ])),
          isNull);
    });
    test('a custom win predicate decides the prize (#182)', () {
      final m = _motion(slotTestConfig.copyWith(winPredicate: _customWin));
      _carve(m, [0, 2, 1]);
      m.tick(128, 64);
      final result = m.takeResult()!;
      expect(result.index, 2);
      expect(result.prize, slotTestPrizes[2]);
    });
    test('resize mid-spin rescales scroll by the cellAndSpacing ratio', () {
      final m = _motion();
      _carve(m);
      final scroll = m.frame.scroll.toList(),
          stop = m.stopScroll.toList(),
          end = m.endScroll.toList();
      final l = slotLayout(slotTestConfig, const Size(600, 360));
      final ratio = l.cellAndSpacing / slotLayout().cellAndSpacing;
      m.configure(slotTestConfig, l);
      for (var r = 0; r < 3; r++) {
        expect(m.frame.scroll[r], scroll[r] * ratio);
        expect(m.stopScroll[r], stop[r] * ratio);
        expect(m.endScroll[r], end[r] * ratio);
      }
      m.tick(128, 64);
      expect(m.frame.scroll.first, m.stopScroll.first + m.endScroll.first);
    });
    test('onCellPassed fires per reel per cell boundary (#265)', () {
      final h = SlotHarness(slotTestConfig.copyWith(
          options: slotTestConfig.options
              .copyWith(motion: slotTestMotion.copyWith(speed: 120))));
      addTearDown(h.dispose);
      h.cruise();
      expect(h.passed.map((p) => p.$1).toSet(), {0, 1, 2});
      expect(h.passed.every((p) => p.$2 >= 0 && p.$2 < 3), isTrue);
    });
    test('monotonic solver never scrolls against the reel direction', () {
      final config = slotTestConfig.copyWith(
          options: slotTestConfig.options.copyWith(
              direction: -1,
              motion: slotTestMotion.copyWith(
                  decelerationTime: const Duration(milliseconds: 1))));
      final m = _motion(config);
      _carve(m);
      expect(m.endScroll.every((d) => d < 0), isTrue);
      final previous = m.frame.scroll.toList();
      m.tick(65, 1);
      for (var r = 0; r < 3; r++) {
        expect(m.frame.scroll[r], lessThan(previous[r]));
      }
    });
    test('reel order change during deceleration is deferred until settled', () {
      final h = SlotHarness();
      addTearDown(h.dispose);
      h.decelerate();
      final next = slotTestConfig.copyWith(reels: [
        const SlotReel(order: [2, 1, 0]),
        const SlotReel(),
        const SlotReel()
      ]);
      h.controller.configure(next, slotLayout(next));
      h.settle();
      expect(h.results.single.indices, [1, 1, 1]);
      expect(h.controller.play(), isTrue);
      expect(h.controller.stop(2), isTrue);
      h.settle();
      final l = slotLayout(next);
      expect(h.controller.frame.scroll.first % l.reels.first.period,
          closeTo(0, 1e-9));
    });
    test('empty orders delayed reels and time ticks stay finite and settle',
        () {
      expect(_DefaultDeltaMotion().maxFrameDelta,
          const Duration(milliseconds: 100));
      final config = slotTestConfig.copyWith(
          reels: [
            const SlotReel(order: []),
            const SlotReel(
                order: [99, 2], stopDelay: Duration(milliseconds: 32)),
            const SlotReel()
          ],
          options: slotTestConfig.options.copyWith(
              motion: slotTestMotion.copyWith(timebase: LuckyTimebase.time)));
      final m = _motion(config);
      _carve(m, [0, 2, 1]);
      expect(m.phase, LuckyPhase.decelerating);
      m.tick(80, 16);
      m.tick(96, 16);
      m.tick(160, 64);
      expect(m.phase, LuckyPhase.settled);
      expect(m.frame.scroll.every((s) => s.isFinite), isTrue);
      expect(m.takeResult()!.index, isNull);
      expect(m.tick(176, 16), LuckyMotionEvents.none);
      m.reset();
      expect(m.frame.scroll, [0, 0, 0]);
      m.configure(config, null);
      expect(m.start(), isFalse);
    });
  });
}
