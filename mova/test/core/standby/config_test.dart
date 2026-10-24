import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('MovaStandbyConfig', () {
    test('defaults are conservative', () {
      const c = MovaStandbyConfig();
      expect(c.maxDuration, const Duration(seconds: 30));
      expect(c.silentStreams, MovaSilentStandby.keepDecoding);
      expect(c.allowHls, isFalse);
      expect(c.resumeTimeout, const Duration(seconds: 5));
      expect(c.liveResumeGrace, const Duration(seconds: 3));
    });

    test('copyWith replaces exactly one field', () {
      const base = MovaStandbyConfig();
      expect(base.copyWith(maxDuration: const Duration(seconds: 9)).maxDuration, const Duration(seconds: 9));
      expect(base.copyWith(silentStreams: MovaSilentStandby.pause).silentStreams, MovaSilentStandby.pause);
      expect(base.copyWith(allowHls: true).allowHls, isTrue);
      expect(base.copyWith(resumeTimeout: const Duration(seconds: 7)).resumeTimeout, const Duration(seconds: 7));
      expect(base.copyWith(liveResumeGrace: Duration.zero).liveResumeGrace, Duration.zero);
      expect(base.copyWith(allowHls: true).maxDuration, base.maxDuration);
    });

    test('== and hashCode follow the fields', () {
      expect(const MovaStandbyConfig(), const MovaStandbyConfig());
      expect(const MovaStandbyConfig().hashCode, const MovaStandbyConfig().hashCode);
      expect(const MovaStandbyConfig(allowHls: true), isNot(const MovaStandbyConfig()));
      expect(
        const MovaStandbyConfig(maxDuration: Duration(seconds: 1)).hashCode,
        isNot(const MovaStandbyConfig().hashCode),
      );
    });

    test('MovaOpts carries the standby section and copyWith leaves others alone', () {
      expect(const MovaOpts().standby, const MovaStandbyConfig());
      const custom = MovaStandbyConfig(allowHls: true);
      final o = const MovaOpts().copyWith(standby: custom);
      expect(o.standby, custom);
      expect(o.recovery, const MovaOpts().recovery);
      expect(o.live, const MovaOpts().live);
      expect(const MovaOpts(), isNot(o));
    });

    test('assertValid rejects a zero maxDuration', () {
      expect(() => const MovaStandbyConfig().assertValid(), returnsNormally);
      expect(
        () => const MovaStandbyConfig(maxDuration: Duration.zero).assertValid(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
