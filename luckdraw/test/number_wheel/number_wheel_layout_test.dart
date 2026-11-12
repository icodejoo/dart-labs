import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/number_wheel/model/number_wheel_config.dart';

import '../support/number_wheel_fixtures.dart';

/// 验证区间生成和数字环布局。
void main() {
  group('computeNumberWheelLayout', () {
    test('range min max step generates one pocket per number on the rim', () {
      final config = NumberWheelConfig.range(1, 9, step: 2);
      expect(config.pockets.map((p) => p.number), [1, 3, 5, 7, 9]);
      expect(config.pockets[0].fill, config.pockets[2].fill);
      expect(numberWheelLayout(config).count, 5);
      expect(() => NumberWheelConfig.range(0, 2, step: 0), throwsArgumentError);
      expect(() => NumberWheelConfig.range(2, 0), throwsArgumentError);
      expect(() => NumberWheelConfig.range(0, 2, palette: []),
          throwsArgumentError);
    });
    test('rim labels are decimated so they never overlap for 200 pockets', () {
      final config = NumberWheelConfig.range(0, 199);
      final layout = numberWheelLayout(config);
      expect(layout.labelEvery, greaterThan(1));
      expect(
          6.283185307179586 *
              layout.labelRadius /
              (200 / layout.labelEvery).ceil(),
          greaterThanOrEqualTo(config.style.fontSize * 1.6));
    });
    test('ball track lies outside the pockets and pocket radius inside', () {
      final layout = numberWheelLayout();
      expect(layout.trackRadius, greaterThan(layout.pocketRadius));
      expect(layout.pocketRadius, lessThan(layout.radius));
      expect(layout.hubRadius, lessThan(layout.pocketRadius));
      expect(layout.ballSize, greaterThan(0));
    });
    test('zero size yields an empty layout without throwing', () {
      expect(numberWheelLayout(numberWheelFixture, Size.zero).isEmpty, isTrue);
      expect(numberWheelLayout(const NumberWheelConfig(pockets: [])).isEmpty,
          isTrue);
    });
  });
}
