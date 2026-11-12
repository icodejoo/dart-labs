import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';

/// 检查布局与核心搅拌器的契约性质，不固定其位置数值。
void main() {
  group('computeLottoLayout', () {
    test('drums balls and result slots fit inside the box', () {
      for (final size in <Size>[
        lottoSize,
        const Size(80, 600),
        const Size(600, 80)
      ]) {
        final layout = lottoLayout(LottoConfig.superLotto(), size);
        final box = Offset.zero & size;
        for (final drum in layout.drums) {
          expect(
              drum.radius, math.min(size.width / 4 * 0.85, size.height * 0.28));
          expect(box.contains(drum.center + Offset(drum.radius, 0)), isTrue);
          expect(box.contains(drum.center - Offset(drum.radius, 0)), isTrue);
          for (final point in drum.rest) {
            expect(point.distance + drum.ballRadius,
                lessThanOrEqualTo(drum.radius + 1e-8));
          }
          for (final slot in drum.slots) {
            expect(
                box.contains(
                    slot + Offset(layout.slotRadius, layout.slotRadius)),
                isTrue);
            expect(
                box.contains(
                    slot - Offset(layout.slotRadius, layout.slotRadius)),
                isTrue);
          }
        }
        expect(box.contains(layout.button.topLeft), isTrue);
        expect(box.contains(layout.button.bottomRight), isTrue);
      }
      final one =
          lottoLayout(lottoConfig.copyWith(pools: [lottoConfig.pools.first]));
      expect(one.drums, hasLength(1));
      expect(one.drums.first.slots, hasLength(3));
    });
    test('one ball per number in every pool', () {
      final config = LottoConfig.superLotto();
      final a = lottoLayout(config);
      final b = lottoLayout(config);
      expect(a.drums.map((d) => d.rest.length), [35, 12]);
      expect(a.drums.first.rest, b.drums.first.rest);
      expect(a.drums.last.min, 1);
      expect(a.isEmpty, isFalse);
    });
    test('zero size yields an empty layout without throwing', () {
      for (final size in <Size>[
        Size.zero,
        const Size(0, 100),
        const Size(double.infinity, 10)
      ]) {
        final layout = lottoLayout(lottoConfig, size);
        expect(layout.isEmpty, isTrue);
        expect(layout.button, Rect.zero);
        expect(layout.slotRadius, 0);
      }
    });
  });
}
