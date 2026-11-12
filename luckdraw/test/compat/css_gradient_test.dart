import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/luckdraw.dart';

/// 验证上游方向与改进的 CSS 色标解析。
void main() {
  group('parseCssFill', () {
    test('angle and keyword directions map to legacy linear fills', () {
      final warnings = <String>[];
      final angle =
          parseCssFill('linear-gradient(-30deg, red, blue)', warnings.add)
              as LuckyLegacyLinearFill;
      expect(angle.direction.degrees, -30);
      for (final word in ['top', 'bottom', 'left', 'right']) {
        final fill =
            parseCssFill('linear-gradient(to $word, red, blue)', warnings.add)
                as LuckyLegacyLinearFill;
        expect(fill.direction.keyword!.name, word);
      }
      final unknown =
          parseCssFill('linear-gradient(unknown, red, blue)', warnings.add)
              as LuckyLegacyLinearFill;
      expect(unknown.direction.keyword, LuckyGradientKeyword.none);
      expect(warnings, isEmpty);
    });
    test('upstream pos-color and CSS color-pos stops are both accepted', () {
      final warnings = <String>[];
      final upstream = parseCssFill(
              'linear-gradient(90deg, 0 red, 0.5 green, 1 blue)', warnings.add)
          as LuckyLegacyLinearFill;
      final css = parseCssFill(
              'linear-gradient(90deg, red 0%, green 50%, blue 1)', warnings.add)
          as LuckyLegacyLinearFill;
      expect(upstream, css);
      expect(css.stops.map((stop) => stop.offset), [0, .5, 1]);
      final mixed = parseCssFill(
              'linear-gradient(right, red 20%, green, blue 80%)', warnings.add)
          as LuckyLegacyLinearFill;
      expect(mixed.stops.map((stop) => stop.offset), [.2, .5, .8]);
      expect(warnings, isEmpty);
    });
    test('commas inside rgb() are not split', () {
      final warnings = <String>[];
      final fill = parseCssFill(
          'linear-gradient(to right, rgb(255, 0, 0), rgba(0, 0, 255, .5) 100%)',
          warnings.add) as LuckyLegacyLinearFill;
      expect(fill.stops, const [
        LuckyColorStop(Color(0xFFFF0000), 0),
        LuckyColorStop(Color(0x800000FF), 1),
      ]);
      expect(warnings, isEmpty);
    });
    test('more than two stops without positions spread evenly', () {
      final warnings = <String>[];
      final fill = parseCssFill(
          'linear-gradient(to right, red, green, blue, white)',
          warnings.add) as LuckyLegacyLinearFill;
      expect(fill.stops.map((stop) => stop.offset), [0, 1 / 3, 2 / 3, 1]);
      expect(() => fill.stops.add(const LuckyColorStop(Color(0xFFFFFFFF))),
          throwsUnsupportedError);
      expect(warnings, isEmpty);
    });
    test('plain colors parse as color fills', () {
      final warnings = <String>[];
      expect(parseCssFill('red', warnings.add),
          const LuckyFill.color(Color(0xFFFF0000)));
      expect(parseCssFill(' TRANSPARENT ', warnings.add), isNull);
      expect(parseCssFill('rgba(0,0,0,0)', warnings.add),
          const LuckyFill.color(Color(0x00000000)));
      expect(parseCssFill(null, warnings.add), isNull);
      expect(warnings, isEmpty);
      for (final value in <Object>[
        false,
        'unknown',
        'linear-gradient(right, red)',
        'linear-gradient(right, red, blue',
        'linear-gradient(right, rgb(1,2,3, blue)',
        'linear-gradient(baddeg, red, blue)',
        'linear-gradient(1e999deg, red, blue)',
        'linear-gradient(right, red -1%, blue)',
        'linear-gradient(right, red, blue 101%)',
        'linear-gradient(right, red 80%, blue 20%)',
        'linear-gradient(right, bad, blue)',
        'linear-gradient(right, red, blue))'
      ]) {
        final before = warnings.length;
        expect(parseCssFill(value, warnings.add), isNull, reason: '$value');
        expect(warnings.length, before + 1);
      }
    });
  });
}
