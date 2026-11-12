import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/capsule_fixtures.dart';

/// 验证 T5.2 的几何与值语义。
void main() {
  group('computeCapsuleLayout', () {
    test('globe body knob chute and tray fit inside the box', () {
      final l = capsuleLayout();
      final box = Offset.zero & capsuleSize;
      expect(l.globeRadius, 126);
      expect(l.globeCenter, const Offset(150, 146));
      expect(
          l.body, const Rect.fromLTRB(11.399999999999977, 253.1, 288.6, 420));
      expect(l.knobRadius, 27.72);
      expect(box.contains(l.knobCenter), isTrue);
      final rectangles = [
        l.body,
        l.tray,
        l.card,
        Rect.fromCircle(center: l.globeCenter, radius: l.globeRadius)
      ];
      for (final r in rectangles) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(box.right));
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.bottom, lessThanOrEqualTo(box.bottom));
      }
      for (final point in l.dropPath) {
        expect(point.dx, inInclusiveRange(0, 300));
        expect(point.dy, inInclusiveRange(0, 500));
      }
    });
    test('rest pile is deterministic for the same config', () {
      final a = capsuleLayout(), b = capsuleLayout();
      expect(a.rest, b.rest);
      for (final p in a.rest) {
        expect(p.distance,
            lessThanOrEqualTo(a.globeRadius - a.capsuleRadius + 1e-9));
      }
      expect(() => a.rest.add(Offset.zero), throwsUnsupportedError);
    });
    test('capsule list defaults to capsulesPerPrize copies of each prize', () {
      expect(capsuleLayout().capsules, [0, 0, 0, 1, 1, 1]);
      expect(
          capsuleLayout(capsuleConfig.copyWith(capsules: [1, -1, 2, 0]))
              .capsules,
          [1, 0]);
      expect(
          capsuleLayout(capsuleConfig.copyWith(capsulesPerPrize: -1)).capsules,
          isEmpty);
    });
    test('capsule radius scales with the globe radius', () {
      final l = capsuleLayout();
      expect(l.capsuleRadius, l.globeRadius * 0.14);
      final small = capsuleLayout(capsuleConfig, const Size(150, 250));
      expect(small.capsuleRadius, l.capsuleRadius / 2);
    });
    test('zero size yields an empty layout without throwing', () {
      final l = capsuleLayout(capsuleConfig, Size.zero);
      expect(l.isEmpty, isTrue);
      expect(l.globeRadius, 0);
      expect(l.dropPosition(1), Offset.zero);
    });
    test('drop path starts at the globe exit and ends in the tray', () {
      final l = capsuleLayout();
      expect(l.dropPath.length, 4);
      expect(l.dropPath.first, l.exit);
      expect(l.dropPath.last, l.tray.center);
      expect(l.dropPosition(0), l.exit);
      expect(l.dropPosition(1), l.tray.center);
      expect(l.dropPosition(2), l.tray.center);
      var distance = 0.0;
      final total = l.lengths.fold(0.0, (a, b) => a + b);
      for (var i = 0; i < l.lengths.length; i++) {
        distance += l.lengths[i];
        expect((l.dropPosition(distance / total) - l.dropPath[i + 1]).distance,
            lessThan(1e-9));
      }
    });
  });
  test('Capsule models > copyWith equality and hash cover all fields', () {
    final values = <Object>[
      capsuleConfig,
      capsuleConfig.options,
      capsuleConfig.style,
      ...capsuleConfig.prizes
    ];
    expect(capsuleConfig.copyWith(), capsuleConfig);
    expect(capsuleConfig.copyWith().hashCode, capsuleConfig.hashCode);
    expect(capsuleConfig.copyWith(capsules: [1]), isNot(capsuleConfig));
    expect(capsuleConfig.options.copyWith(), capsuleConfig.options);
    expect(capsuleConfig.options.copyWith().hashCode,
        capsuleConfig.options.hashCode);
    expect(capsuleConfig.options.copyWith(revealOnSettle: false),
        isNot(capsuleConfig.options));
    expect(capsuleConfig.style.copyWith(), capsuleConfig.style);
    expect(
        capsuleConfig.style.copyWith().hashCode, capsuleConfig.style.hashCode);
    expect(capsuleConfig.style.copyWith(seamColor: const Color(0xFF000000)),
        isNot(capsuleConfig.style));
    final p = capsuleConfig.prizes.first;
    expect(p.copyWith(), p);
    expect(p.copyWith().hashCode, p.hashCode);
    expect(p.copyWith(disabled: true), isNot(p));
    for (final v in values) {
      expect(v == 'unrelated', isFalse);
    }
  });
}
