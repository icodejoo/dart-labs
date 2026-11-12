import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/src/compat/css_color.dart' show kCompatCssNamedColors;

/// 验证 CSS 颜色的格式、通道、钳制和诊断。
void main() {
  group('parseCssColor', () {
    test('hex 3 4 6 and 8 digit forms', () {
      final warnings = <String>[];
      expect(parseCssColor('#abc', warnings.add), const Color(0xFFAABBCC));
      expect(parseCssColor('#abcd', warnings.add), const Color(0xDDAABBCC));
      expect(parseCssColor('#123456', warnings.add), const Color(0xFF123456));
      expect(parseCssColor('#12345678', warnings.add), const Color(0x78123456));
      expect(parseCssColor(' #FF0000 ', warnings.add), const Color(0xFFFF0000));
      expect(warnings, isEmpty);
    });
    test('rgb rgba hsl and hsla forms', () {
      final warnings = <String>[];
      expect(parseCssColor('rgb(255,0,128)', warnings.add),
          const Color(0xFFFF0080));
      expect(parseCssColor('rgba(255, 0, 0, .5)', warnings.add),
          const Color(0x80FF0000));
      expect(parseCssColor('rgb(100%,0%,0%)', warnings.add),
          const Color(0xFFFF0000));
      expect(parseCssColor('rgba(100%,0%,0%,50%)', warnings.add),
          const Color(0x80FF0000));
      expect(parseCssColor('rgb(999,-1,0)', warnings.add),
          const Color(0xFFFF0000));
      expect(parseCssColor('hsl(120,100%,50%)', warnings.add),
          const Color(0xFF00FF00));
      expect(parseCssColor('hsla(240deg, 100%, 50%, .5)', warnings.add),
          const Color(0x800000FF));
      expect(parseCssColor('hsl(-240,100%,50%)', warnings.add),
          const Color(0xFF00FF00));
      expect(parseCssColor('hsl(720,0%,100%)', warnings.add),
          const Color(0xFFFFFFFF));
      expect(warnings, isEmpty);
    });
    test('named colors and transparent', () {
      final warnings = <String>[];
      expect(kCompatCssNamedColors, hasLength(148));
      expect(parseCssColor(' RebeccaPurple ', warnings.add),
          const Color(0xFF663399));
      expect(parseCssColor('lightgoldenrodyellow', warnings.add),
          const Color(0xFFFAFAD2));
      expect(parseCssColor('darkslategrey', warnings.add),
          const Color(0xFF2F4F4F));
      expect(parseCssColor('grey', warnings.add), const Color(0xFF808080));
      expect(parseCssColor('cyan', warnings.add),
          parseCssColor('aqua', warnings.add));
      expect(parseCssColor(' TRANSPARENT ', warnings.add),
          const Color(0x00000000));
      expect(warnings, isEmpty);
    });
    test('invalid colors return null and add a warning', () {
      final warnings = <String>[];
      for (final value in [
        '',
        'unknown',
        '#12',
        '#12345',
        '#1234567',
        '#xxff00',
        'rgb(1,2)',
        'rgba(1,2,3)',
        'rgb(1,2,3,4)',
        'rgba(1,2,3,NaN)',
        'rgb(NaN,0,0)',
        'rgb(Infinity,0,0)',
        'rgb(0,0,1e999)',
        'hsl(0,1,1)',
        'hsl(NaN,100%,50%)',
        'hsl(1e999,100%,50%)',
        'hsl(0,NaN%,50%)',
        'hsl(0,100%,bad)',
        'rgb(1,2,3) trailing',
        'hsla(0,100%,50%,bad)'
      ]) {
        final before = warnings.length;
        expect(parseCssColor(value, warnings.add), isNull, reason: value);
        expect(warnings.length, before + 1);
      }
    });
  });
}
