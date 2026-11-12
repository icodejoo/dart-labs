import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/luckdraw.dart';
import 'package:luckdraw/src/compat/css_length.dart' show resolveBaseless;

/// 验证长度单位与上游无基准行为。
void main() {
  const options = LuckyCanvasCompatOptions();
  group('parseCssLength', () {
    test('px number and unitless values parse as px', () {
      final warnings = <String>[];
      for (final value in <Object>[12, 12.5, '12', '12px']) {
        final length = parseCssLength(value, options, warnings.add);
        expect(length, LuckyLength.px(value == 12.5 ? 12.5 : 12));
      }
      expect(
          parseCssLength('', options, warnings.add), const LuckyLength.px(0));
      expect(parseCssLength('-2.5px', options, warnings.add),
          const LuckyLength.px(-2.5));
      expect(warnings, isEmpty);
    });
    test('percent parses as LuckyPercent', () {
      final warnings = <String>[];
      final length = parseCssLength('50%', options, warnings.add);
      expect(length, const LuckyLength.percent(50));
      expect(length!.resolve(240), 120);
      expect(warnings, isEmpty);
    });
    test('rem uses remBase and vw uses viewportWidth', () {
      final warnings = <String>[];
      const configured =
          LuckyCanvasCompatOptions(remBase: 20, viewportWidth: 320);
      expect(parseCssLength('1.5rem', configured, warnings.add),
          const LuckyLength.px(30));
      expect(parseCssLength('25vw', configured, warnings.add),
          const LuckyLength.px(80));
      expect(parseCssLength('1rem', options, warnings.add),
          const LuckyLength.px(16));
      expect(warnings, isEmpty);
      expect(parseCssLength('25vw', options, warnings.add),
          const LuckyLength.px(25));
      expect(warnings.single, contains('viewportWidth'));
    });
    test('unknown units go to handleCssUnit or fall back to the number', () {
      final warnings = <String>[];
      final seen = <(double, String)>[];
      final configured = LuckyCanvasCompatOptions(handleCssUnit: (value, unit) {
        seen.add((value, unit));
        return value * 3;
      });
      expect(parseCssLength('2em', configured, warnings.add),
          const LuckyLength.px(6));
      expect(seen, [(2.0, 'em')]);
      expect(parseCssLength('2em', options, warnings.add),
          const LuckyLength.px(2));
      expect(warnings, isEmpty);
    });
    test(
        'base-less percent resolves as n / 100 px like getLength without maxLength',
        () {
      final warnings = <String>[];
      expect(
          resolveBaseless(parseCssLength('75%', options, warnings.add)!), .75);
      expect(
          resolveBaseless(parseCssLength('75px', options, warnings.add)!), 75);
      expect(warnings, isEmpty);
    });
    test('malformed values return null with a warning (DEV-16)', () {
      final warnings = <String>[];
      for (final value in <Object?>[
        '10 px',
        ' 10px',
        '10PX',
        '--1px',
        '.',
        '1.2.3',
        null,
        true,
        [],
        double.nan,
        double.infinity
      ]) {
        final before = warnings.length;
        expect(parseCssLength(value, options, warnings.add), isNull,
            reason: '$value');
        expect(warnings.length, before + 1);
      }
      final overflow = LuckyCanvasCompatOptions(
          handleCssUnit: (value, unit) => double.infinity);
      expect(parseCssLength('1em', overflow, warnings.add), isNull);
      expect(warnings.last, contains('有限'));
      expect(
          parseCssLength(
              '1rem',
              const LuckyCanvasCompatOptions(remBase: double.nan),
              warnings.add),
          isNull);
    });
  });
}
