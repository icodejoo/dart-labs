import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

// Regression tests for the full-lib-review fixes.
//
// 全量 review 修复的回归测试。
void main() {
  group('TimeParts negative clamp', () {
    test('negative value clamps stored value and components to zero', () {
      final p = TimeParts.of(const Duration(seconds: -5));
      // Stored value clamped (was previously left negative while components zeroed).
      expect(p.value, Duration.zero);
      expect(p.inMilliseconds, 0);
      expect(p.days, 0);
      expect(p.hours, 0);
      expect(p.minutes, 0);
      expect(p.seconds, 0);
      expect(p.millis, 0);
    });

    test('non-negative value decomposes normally', () {
      final p = TimeParts.of(const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4));
      expect(p.hours, 1);
      expect(p.minutes, 2);
      expect(p.seconds, 3);
      expect(p.millis, 4);
      expect(p.value, const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4));
    });
  });

  group('CountdownFormat days-aware', () {
    test('dhms shows days when >= 1 day, else falls back to hms', () {
      expect(CountdownFormat.dhms(TimeParts.of(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5))),
          '2d 03:04:05');
      expect(CountdownFormat.dhms(TimeParts.of(const Duration(hours: 5, minutes: 6, seconds: 7))),
          '05:06:07');
    });

    test('auto uses dhms past a day', () {
      expect(CountdownFormat.auto(TimeParts.of(const Duration(days: 1, hours: 1))), '1d 01:00:00');
    });
  });
}
