import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/slot.dart';

import '../support/slot_fixtures.dart';

/// 验证上游布局公式及配置值语义。
void main() {
  group('computeSlotLayout', () {
    test(
        'vertical mode cell width is (w - colSpacing * (n - 1)) / n and square',
        () {
      final l = slotLayout();
      expect(l.cellWidth, (300 - 5 * 2) / 3);
      expect(l.cellHeight, l.cellWidth);
      expect(l.reels[1].clipRect.left, l.widthAndSpacing);
    });
    test(
        'horizontal mode cell height is (h - rowSpacing * (n - 1)) / n and square',
        () {
      final l = slotLayout(slotTestConfig.copyWith(
          options:
              const SlotOptions(mode: SlotMode.horizontal, rowSpacing: 6)));
      expect(l.cellHeight, (180 - 6 * 2) / 3);
      expect(l.cellWidth, l.cellHeight);
      expect(l.reels[1].clipRect.top, l.heightAndSpacing);
    });
    test('cellAspectRatio produces non-square cells (#265)', () {
      final v = slotLayout(slotTestConfig.copyWith(
          options: const SlotOptions(cellAspectRatio: 2)));
      final h = slotLayout(slotTestConfig.copyWith(
          options: const SlotOptions(
              mode: SlotMode.horizontal, cellAspectRatio: 2)));
      expect(v.cellWidth / v.cellHeight, 2);
      expect(h.cellWidth / h.cellHeight, 2);
    });
    test('cellAndSpacing follows the mode', () {
      final v = slotLayout();
      final h = slotLayout(slotTestConfig.copyWith(
          options: const SlotOptions(mode: SlotMode.horizontal)));
      expect(v.cellAndSpacing, v.heightAndSpacing);
      expect(h.cellAndSpacing, h.widthAndSpacing);
      expect(h.reels.first.stripStart[1], h.widthAndSpacing + 2.5);
    });
    test(
        'reel order defaults to prize order and keeps holes for invalid indices',
        () {
      final l = slotLayout(slotTestConfig.copyWith(reels: [
        const SlotReel(),
        const SlotReel(order: [2, 99, -2, 0]),
        const SlotReel(order: [])
      ]));
      expect(l.reels.first.stripPrizes, [0, 1, 2]);
      expect(l.reels[1].stripPrizes, [2, -1, -1, 0]);
      expect(l.reels[1].period, l.cellAndSpacing * 4);
      expect(l.reels.last.period, 0);
    });
    test('visible window start is -(h - heightAndSpacing) / 2', () {
      final l = slotLayout();
      expect(l.windowStart, -(l.prizeArea.height - l.heightAndSpacing) / 2);
      final h = slotLayout(slotTestConfig.copyWith(
          options: const SlotOptions(mode: SlotMode.horizontal)));
      expect(h.windowStart, -(h.prizeArea.width - h.widthAndSpacing) / 2);
    });
    test('a single reel lays out (#233)', () {
      final l = slotLayout(slotTestConfig.copyWith(reels: [const SlotReel()]));
      expect(l.isEmpty, isFalse);
      expect(l.cellWidth, slotTestSize.width);
      expect(l.reels.single.clipRect, Offset.zero & slotTestSize);
    });
    test('fifty prizes need no texture taller than maxRasterSide (#297)', () {
      final l = slotLayout(slotTestConfig.copyWith(
          prizes: List.filled(50, slotTestPrizes.first)));
      expect(l.cells, hasLength(50));
      expect(l.cells.every((c) => c.rect.height < 4096), isTrue);
      expect(l.reels.first.maxVisibleCells,
          (l.windowLength / l.cellAndSpacing).ceil() + 2);
      expect(l.reels.first.maxVisibleCells, lessThan(50));
    });
    test('zero size yields an empty layout without throwing', () {
      expect(slotLayout(slotTestConfig, Size.zero).isEmpty, isTrue);
      expect(slotLayout(const SlotConfig()).isEmpty, isTrue);
      expect(
          slotLayout(slotTestConfig.copyWith(
                  options: const SlotOptions(colSpacing: 1000)))
              .isEmpty,
          isTrue);
      expect(
          slotLayout(slotTestConfig.copyWith(
                  options: const SlotOptions(cellAspectRatio: 0)))
              .isEmpty,
          isTrue);
    });
    test('slot blocks fall back to the default style background', () {
      const bg = LuckyFill.color(Color(0xFF223344));
      final l = slotLayout(slotTestConfig.copyWith(
          blocks: [const LuckyBoxBlock(padding: LuckyEdgeInsets.all(8))],
          style: const SlotStyle(
              cell: LuckyCellStyle(background: bg, borderRadius: 20)),
          prizes: [const SlotPrize(borderRadius: 0)]));
      expect(l.blocks.single.background, bg);
      expect(l.prizeArea, const Rect.fromLTWH(8, 8, 284, 164));
      expect(l.cells.single.borderRadius, 0);
    });
  });
  group('Slot models', () {
    test('copyWith equality hash and predicates preserve every field', () {
      const reel = SlotReel(
          order: [1, 0],
          speed: -8,
          direction: -1,
          stopDelay: Duration(milliseconds: 8));
      const options = SlotOptions();
      const style = SlotStyle();
      const prize = SlotPrize(weight: 2);
      const line = SlotPayline([0, 0, 0]);
      expect(reel.copyWith(), reel);
      expect(reel.copyWith().hashCode, reel.hashCode);
      expect(options.copyWith(), options);
      expect(options.copyWith().hashCode, options.hashCode);
      expect(style.copyWith(), style);
      expect(style.copyWith().hashCode, style.hashCode);
      expect(prize.copyWith(), prize);
      expect(prize.copyWith().hashCode, prize.hashCode);
      expect(line.copyWith(), line);
      expect(line.copyWith().hashCode, line.hashCode);
      expect(slotTestConfig.copyWith(), slotTestConfig);
      expect(slotTestConfig.copyWith().hashCode, slotTestConfig.hashCode);
      expect(
          reel.copyWith(
              speed: 9, direction: 1, order: [2], stopDelay: Duration.zero),
          isNot(reel));
      expect(
          options.copyWith(
              mode: SlotMode.horizontal,
              direction: -1,
              rowSpacing: 1,
              colSpacing: 2,
              cellAspectRatio: 3,
              motion: slotTestMotion),
          isNot(options));
      expect(
          style.copyWith(
              cell: const LuckyCellStyle(borderRadius: 5),
              text: const LuckyTextDefaults(fontSize: 10)),
          isNot(style));
      expect(
          prize.copyWith(
              background: const LuckyFill.color(Color(0xFF111111)),
              borderRadius: 9,
              texts: [const LuckyText('X')],
              images: [],
              weight: 3,
              disabled: true,
              painter: (_, __, ___) {}),
          isNot(prize));
      expect(
          line.copyWith(
              rowOffsets: [1], color: const Color(0xFF000000), width: 5),
          isNot(line));
      expect(
          slotTestConfig.copyWith(
              paylines: [line],
              paylinePredicate: (_) => false,
              winPredicate: (_, __) => null),
          isNot(slotTestConfig));
      expect(allEqualPaylinePredicate([1, 1]), isTrue);
      expect(allEqualPaylinePredicate([]), isFalse);
      expect(allEqualPaylinePredicate([-1, -1]), isFalse);
      expect(allEqualPaylinePredicate([1, 2]), isFalse);
    });
  });
}
