import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('MovaKeepAliveConfig', () {
    test('defaults are conservative', () {
      const c = MovaKeepAliveConfig();
      expect(c.maxDuration, const Duration(seconds: 30));
      expect(c.silentStreams, MovaSilentKeepAlive.keepDecoding);
      expect(c.allowHls, isFalse);
      expect(c.resumeTimeout, const Duration(seconds: 5));
      expect(c.liveResumeGrace, const Duration(seconds: 3));
    });

    test('copyWith replaces exactly one field', () {
      const base = MovaKeepAliveConfig();
      expect(base.copyWith(maxDuration: const Duration(seconds: 9)).maxDuration, const Duration(seconds: 9));
      expect(base.copyWith(silentStreams: MovaSilentKeepAlive.pause).silentStreams, MovaSilentKeepAlive.pause);
      expect(base.copyWith(allowHls: true).allowHls, isTrue);
      expect(base.copyWith(resumeTimeout: const Duration(seconds: 7)).resumeTimeout, const Duration(seconds: 7));
      expect(base.copyWith(liveResumeGrace: Duration.zero).liveResumeGrace, Duration.zero);
      expect(base.copyWith(allowHls: true).maxDuration, base.maxDuration);
    });

    test('== and hashCode follow the fields', () {
      expect(const MovaKeepAliveConfig(), const MovaKeepAliveConfig());
      expect(const MovaKeepAliveConfig().hashCode, const MovaKeepAliveConfig().hashCode);
      expect(const MovaKeepAliveConfig(allowHls: true), isNot(const MovaKeepAliveConfig()));
      expect(
        const MovaKeepAliveConfig(maxDuration: Duration(seconds: 1)).hashCode,
        isNot(const MovaKeepAliveConfig().hashCode),
      );
    });

    test('MovaOpts carries the keepAlive section and copyWith leaves others alone', () {
      expect(const MovaOpts().keepAlive, const MovaKeepAliveConfig());
      const custom = MovaKeepAliveConfig(allowHls: true);
      final o = const MovaOpts().copyWith(keepAlive: custom);
      expect(o.keepAlive, custom);
      expect(o.recovery, const MovaOpts().recovery);
      expect(o.live, const MovaOpts().live);
      expect(const MovaOpts(), isNot(o));
    });

    test('assertValid rejects a zero maxDuration', () {
      expect(() => const MovaKeepAliveConfig().assertValid(), returnsNormally);
      expect(
        () => const MovaKeepAliveConfig(maxDuration: Duration.zero).assertValid(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
