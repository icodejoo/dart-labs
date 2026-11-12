import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证阴影四段规则、括号感知和设备空间。
void main() {
  group('parseCssShadow', () {
    test('x y blur color with px stripped and device blur space', () {
      final warnings = <String>[];
      final shadow =
          parseCssShadow('-1px 2px 4px rgba(0, 0, 0, .5)', warnings.add);
      expect(
          shadow,
          const LuckyShadow(
              offsetX: -1,
              offsetY: 2,
              blur: 4,
              color: Color(0x80000000),
              blurSpace: LuckyShadowBlurSpace.device));
      expect(shadow!.sigma(2), 1);
      expect(warnings, isEmpty);
    });
    test('only the first of multiple shadows is used', () {
      final warnings = <String>[];
      final shadow =
          parseCssShadow('1 2 3 rgb(255, 0, 0), 4 5 6 blue', warnings.add);
      expect(shadow!.offsetX, 1);
      expect(shadow.color, const Color(0xFFFF0000));
      expect(warnings, isEmpty);
    });
    test('shadows without exactly four parts are ignored like upstream', () {
      final warnings = <String>[];
      expect(parseCssShadow(null, warnings.add), isNull);
      expect(parseCssShadow('', warnings.add), isNull);
      expect(warnings, isEmpty);
      for (final value in <Object>[
        false,
        '1 2 red',
        '1 2 3 4 red',
        'inset 1 2 3 red',
        '1 2 3 rgba(0,0,0,.5',
        'bad 2 3 red',
        '1 2 -3 red',
        '1 2 3 bad',
        '1 2 NaN red',
        '1 2 3 red)'
      ]) {
        final before = warnings.length;
        expect(parseCssShadow(value, warnings.add), isNull, reason: '$value');
        expect(warnings.length, before + 1);
      }
    });
  });
}
