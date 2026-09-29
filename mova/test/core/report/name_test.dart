import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/report/report.dart';

void main() {
  group('MovaReportName — const value class (was enum before 0.2.x)', () {
    test('built-in .value/.name/.toString are the wire name', () {
      expect(MovaReportName.play.value, 'play');
      expect(MovaReportName.play.name, 'play');
      expect(MovaReportName.play.toString(), 'play');
    });

    test('values contains exactly the 19 built-ins, no custom', () {
      expect(MovaReportName.values.length, 19);
      expect(MovaReportName.values, isNot(contains(const MovaReportName.custom('x'))));
    });

    test('two identical const custom names are canonicalized (identical)', () {
      const a = MovaReportName.custom('x');
      const b = MovaReportName.custom('x');
      expect(identical(a, b), isTrue);
      expect(a, b);
    });

    test('a runtime-constructed custom name equals its const twin by value', () {
      final via = 'x'.toUpperCase().toLowerCase();
      final runtime = MovaReportName.custom(via);
      const constVersion = MovaReportName.custom('x');
      expect(runtime, constVersion);
      expect(identical(runtime, constVersion), isFalse);
    });

    test('usable as Map/Set keys, compared by value', () {
      final map = {MovaReportName.play: 1};
      expect(map[const MovaReportName.custom('play')], 1);
    });

    test('custom("") triggers an assert in debug mode', () {
      expect(() => MovaReportName.custom(''), throwsA(isA<AssertionError>()));
    });
  });
}
