import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';

import '../support/recording_canvas.dart';
import '../support/slot_fixtures.dart';

/// 各行可见符号的推导、判定回调及前景折线。
void main() {
  group('SlotPayline', () {
    test('visible symbols per row follow each reel order around the target',
        () {
      final seen = <List<int>>[];
      final config = slotTestConfig.copyWith(
          reels: [
            const SlotReel(order: [2, 0, 1]),
            const SlotReel(order: [1, 2, 0]),
            const SlotReel(order: [0, 1, 2])
          ],
          paylines: [
            const SlotPayline([-1, 0, 1]),
            const SlotPayline([1, -1, 0])
          ],
          paylinePredicate: (symbols) {
            seen.add(symbols);
            return false;
          });
      final h = SlotHarness(config);
      addTearDown(h.dispose);
      h.cruise();
      h.controller.stopEach([2, 2, 2]);
      h.settle();
      expect(seen, [
        [1, 2, 0],
        [0, 1, 2]
      ]);
      expect(h.results.single.winningPaylines, isEmpty);
    });
    test('default payline predicate wins when all symbols on the line match',
        () {
      expect(allEqualPaylinePredicate([2, 2, 2]), isTrue);
      expect(allEqualPaylinePredicate([2, 1, 2]), isFalse);
      expect(allEqualPaylinePredicate([]), isFalse);
      expect(allEqualPaylinePredicate([-1, -1]), isFalse);
      final h = SlotHarness(slotTestConfig.copyWith(paylines: [
        const SlotPayline([0, 0, 0])
      ]));
      addTearDown(h.dispose);
      h.decelerate();
      h.settle();
      expect(h.results.single.winningPaylines, [0]);
      expect(h.results.single.index, 1);
    });
    test(
        'winning paylines are reported in SlotResult and highlighted by SlotPaylineLayer',
        () {
      const lines = [
        SlotPayline([0, 0, 0]),
        SlotPayline([-1, 0, 1])
      ];
      final h = SlotHarness(slotTestConfig.copyWith(paylines: lines));
      addTearDown(h.dispose);
      h.decelerate();
      h.settle();
      final result = h.results.single;
      expect(result.winningPaylines, [0]);
      final context = LuckyLayerContext<SlotLayout, SlotFrame>()
        ..layout = slotLayout()
        ..frame = h.controller.frame;
      final layer = SlotPaylineLayer(result: result, paylines: lines);
      expect(layer.isStatic, isTrue);
      expect(layer.position, LuckyLayerPosition.foreground);
      for (final mode in SlotMode.values) {
        final canvas = TestRecordingCanvas();
        SlotPaylineLayer(result: result, paylines: lines, mode: mode)
            .paint(canvas, context);
        expect(canvas.countCalls(#drawPath), 1);
        final args = canvas.invocations.single.invocation.positionalArguments;
        expect(
            ((args[0] as Path).getBounds().center -
                    context.layout.prizeArea.center)
                .distance,
            lessThan(0.0001));
        expect((args[1] as Paint).color, isSameColorAs(lines.first.color));
      }
      expect(
          layer
              .shouldRepaint(SlotPaylineLayer(result: result, paylines: lines)),
          isFalse);
      expect(layer.shouldRepaint(const SlotPaylineLayer(result: null)), isTrue);
    });
    test('invalid definitions targets and holes cannot win', () {
      final variants = [
        [
          const SlotReel(order: [0, 99, 1]),
          const SlotReel(),
          const SlotReel()
        ],
        [const SlotReel(order: []), const SlotReel(), const SlotReel()],
        [
          const SlotReel(order: [0]),
          const SlotReel(),
          const SlotReel()
        ]
      ];
      for (final reels in variants) {
        final h = SlotHarness(slotTestConfig.copyWith(reels: reels, paylines: [
          const SlotPayline([0]),
          const SlotPayline([-1, 0, 0])
        ]));
        h.decelerate();
        h.settle();
        expect(h.results.single.winningPaylines, isEmpty);
        h.dispose();
      }
      final context = LuckyLayerContext<SlotLayout, SlotFrame>()
        ..layout = slotLayout();
      final canvas = TestRecordingCanvas();
      const SlotPaylineLayer(result: null).paint(canvas, context);
      const SlotPaylineLayer(
          result: SlotResult(indices: [], winningPaylines: [-1, 0, 1]),
          paylines: [
            SlotPayline([0])
          ]).paint(canvas, context);
      expect(canvas.countCalls(#drawPath), 0);
    });
  });
}
