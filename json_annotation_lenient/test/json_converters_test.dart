// Table-driven coverage for the six scalar/DateTime Lenient*Converter
// classes — previously untested apart from LenientDateTimeConverter.

import 'package:json_annotation_lenient/json_annotation_lenient.dart';
import 'package:test/test.dart';

void main() {
  group('LenientIntConverter', () {
    const c = LenientIntConverter();

    test('passes through int', () => expect(c.fromJson(42), 42));
    test('truncates double', () => expect(c.fromJson(42.9), 42));
    test('parses integer string', () => expect(c.fromJson('42'), 42));
    test(
      'parses decimal string via double fallback',
      () => expect(c.fromJson('42.5'), 42),
    );
    test('null falls back to defaultValue', () => expect(c.fromJson(null), 0));
    test(
      'null falls back to explicit defaultValue',
      () => expect(c.fromJson(null, 7), 7),
    );
    test(
      'NaN throws',
      () => expect(() => c.fromJson(double.nan), throwsFormatException),
    );
    test(
      'non-numeric string throws',
      () => expect(() => c.fromJson('abc'), throwsFormatException),
    );
    test(
      'unsupported type throws',
      () => expect(() => c.fromJson(true), throwsFormatException),
    );
    test('toJson passes through', () => expect(c.toJson(5), 5));
  });

  group('LenientDoubleConverter', () {
    const c = LenientDoubleConverter();

    test('passes through double', () => expect(c.fromJson(4.2), 4.2));
    test('widens int', () => expect(c.fromJson(4), 4.0));
    test('parses numeric string', () => expect(c.fromJson('4.2'), 4.2));
    test(
      'null falls back to defaultValue',
      () => expect(c.fromJson(null), 0.0),
    );
    test(
      'non-numeric string throws',
      () => expect(() => c.fromJson('abc'), throwsFormatException),
    );
    test(
      'unsupported type throws',
      () => expect(() => c.fromJson(true), throwsFormatException),
    );
  });

  group('LenientNumConverter', () {
    const c = LenientNumConverter();

    test('keeps int subtype', () => expect(c.fromJson(4), isA<int>()));
    test('keeps double subtype', () => expect(c.fromJson(4.2), isA<double>()));
    test('parses numeric string', () => expect(c.fromJson('4.2'), 4.2));
    test('null falls back to defaultValue', () => expect(c.fromJson(null), 0));
    test(
      'non-numeric string throws',
      () => expect(() => c.fromJson('abc'), throwsFormatException),
    );
  });

  group('LenientBoolConverter', () {
    const c = LenientBoolConverter();

    test('passes through bool', () => expect(c.fromJson(true), isTrue));
    test('nonzero int is true', () => expect(c.fromJson(1), isTrue));
    test('zero int is false', () => expect(c.fromJson(0), isFalse));
    test('nonzero double is true', () => expect(c.fromJson(1.0), isTrue));
    test('zero double is false', () => expect(c.fromJson(0.0), isFalse));
    test('"true"/"1"/"yes" are true', () {
      expect(c.fromJson('true'), isTrue);
      expect(c.fromJson('TRUE'), isTrue);
      expect(c.fromJson('1'), isTrue);
      expect(c.fromJson('yes'), isTrue);
    });
    test('"false"/"0"/"no"/"" are false', () {
      expect(c.fromJson('false'), isFalse);
      expect(c.fromJson('0'), isFalse);
      expect(c.fromJson('no'), isFalse);
      expect(c.fromJson(''), isFalse);
    });
    test(
      'unrecognized string throws',
      () => expect(() => c.fromJson('banana'), throwsFormatException),
    );
    test(
      'null falls back to defaultValue',
      () => expect(c.fromJson(null), isFalse),
    );
    test(
      'unsupported type throws',
      () => expect(() => c.fromJson([1]), throwsFormatException),
    );
  });

  group('LenientStringConverter', () {
    const c = LenientStringConverter();

    test('passes through String', () => expect(c.fromJson('x'), 'x'));
    test('stringifies num', () => expect(c.fromJson(4.2), '4.2'));
    test('stringifies bool', () => expect(c.fromJson(true), 'true'));
    test('null falls back to defaultValue', () => expect(c.fromJson(null), ''));
    test(
      'unsupported type throws',
      () => expect(() => c.fromJson([1]), throwsFormatException),
    );
  });

  group('LenientDateTimeConverter yyyyMMdd', () {
    const c = LenientDateTimeConverter();

    test('8-digit compact date is read as yyyyMMdd, not epoch seconds', () {
      expect(c.fromJson('20240101'), DateTime(2024, 1, 1));
    });

    test('8-digit epoch-shaped but invalid date falls back to epoch seconds', () {
      // month=13 is not a valid yyyyMMdd -> treated as an epoch-seconds number.
      final result = c.fromJson('20241301');
      expect(
        result,
        DateTime.fromMillisecondsSinceEpoch(20241301 * 1000, isUtc: false),
      );
    });
  });
}
