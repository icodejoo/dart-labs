import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/lots/model/lots_config.dart';

import '../support/lots_fixtures.dart';

/// 验证抽签几何和确定性。
void main() {
  group('computeLotsLayout', () {
    test('cylinder and sticks fit inside the box', () {
      final l = lotsLayout();
      final bounds = Offset.zero & l.size;
      expect(bounds.contains(l.cylinder.topLeft), isTrue);
      expect(bounds.contains(l.cylinder.bottomRight), isTrue);
      for (final stick in l.sticks) {
        expect(bounds.contains(stick.topLeft), isTrue);
        expect(bounds.contains(stick.bottomRight), isTrue);
      }
      expect(l.sticks.length, 12);
    });
    test('stick fan arrangement is deterministic for the same config', () {
      final a = lotsLayout(), b = lotsLayout();
      expect(a.sticks, b.sticks);
      expect(a.angles, b.angles);
      expect(a.angles.first, lessThan(0));
      expect(a.angles.last, greaterThan(0));
      expect(
          lotsLayout(lotsFixture.copyWith(
                  options: lotsFixture.options.copyWith(visibleSticks: 1)))
              .angles,
          [0]);
    });
    test('zero size yields an empty layout without throwing', () {
      expect(lotsLayout(lotsFixture, Size.zero).isEmpty, isTrue);
      expect(lotsLayout(const LotsConfig()).isEmpty, isTrue);
    });
    test('rise path lifts the target stick above the cylinder', () {
      final l = lotsLayout();
      expect(l.raisedStick(1).top, lessThan(l.sticks[1].top));
      expect(l.raisedStick(1).bottom, lessThan(l.cylinder.top));
      expect(l.pivot, l.cylinder.bottomCenter);
      expect(l.card.bottom, lessThan(l.cylinder.center.dy));
    });
  });
}
