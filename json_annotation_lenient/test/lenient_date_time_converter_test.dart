import 'package:json_annotation_lenient/json_annotation_lenient.dart';
import 'package:test/test.dart';

void main() {
  group('LenientDateTimeConverter', () {
    const local = LenientDateTimeConverter();
    const utc = LenientDateTimeConverter(dateTimeUtc: true);

    test('missing/null falls back to epoch', () {
      expect(local.fromJson(null), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    });

    test('passes through an existing DateTime', () {
      final now = DateTime.now();
      expect(local.fromJson(now), now);
    });

    test('parses standard ISO 8601 string with explicit Z regardless of flag', () {
      final expected = DateTime.parse('2024-01-01T10:00:00Z');
      expect(local.fromJson('2024-01-01T10:00:00Z'), expected);
      expect(utc.fromJson('2024-01-01T10:00:00Z'), expected);
    });

    test('space-separated date-time is normalized to ISO 8601', () {
      expect(
        local.fromJson('2024-01-01 10:00:00'),
        DateTime.parse('2024-01-01T10:00:00'),
      );
    });

    test('slash-separated date is normalized', () {
      expect(
        local.fromJson('2024/01/01 10:00:00'),
        DateTime.parse('2024-01-01T10:00:00'),
      );
    });

    test('date-only string still parses', () {
      expect(local.fromJson('2024-01-01'), DateTime.parse('2024-01-01'));
    });

    test('dateTimeUtc appends Z to a timezone-less string', () {
      expect(
        utc.fromJson('2024-01-01 10:00:00'),
        DateTime.parse('2024-01-01T10:00:00Z'),
      );
    });

    test('seconds-magnitude epoch int', () {
      final result = local.fromJson(1704067200);
      expect(result, DateTime.fromMillisecondsSinceEpoch(1704067200 * 1000, isUtc: false));
    });

    test('milliseconds-magnitude epoch int', () {
      final result = local.fromJson(1704067200000);
      expect(result, DateTime.fromMillisecondsSinceEpoch(1704067200000, isUtc: false));
    });

    test('microseconds-magnitude epoch int', () {
      final result = local.fromJson(1704067200000000);
      expect(result, DateTime.fromMicrosecondsSinceEpoch(1704067200000000, isUtc: false));
    });

    test('epoch double is rounded', () {
      final result = local.fromJson(1704067200000.6);
      expect(result, DateTime.fromMillisecondsSinceEpoch(1704067200001, isUtc: false));
    });

    test('numeric string is treated as epoch by magnitude', () {
      expect(local.fromJson('1704067200000'), DateTime.fromMillisecondsSinceEpoch(1704067200000, isUtc: false));
      expect(local.fromJson('1704067200'), DateTime.fromMillisecondsSinceEpoch(1704067200 * 1000, isUtc: false));
    });

    test('dateTimeUtc affects epoch isUtc flag', () {
      expect(utc.fromJson(1704067200000).isUtc, isTrue);
      expect(local.fromJson(1704067200000).isUtc, isFalse);
    });

    test('unsupported type throws', () {
      expect(() => local.fromJson(true), throwsFormatException);
    });

    test('toJson serializes to ISO 8601', () {
      final dt = DateTime.utc(2024, 1, 1);
      expect(local.toJson(dt), dt.toIso8601String());
    });
  });
}
