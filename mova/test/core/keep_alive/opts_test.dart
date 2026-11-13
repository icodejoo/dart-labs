import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

void main() {
  group('MovaKeepAliveOpts', () {
    test('defaults are conservative', () {
      const c = MovaKeepAliveOpts();
      expect(c.maxDuration, const Duration(seconds: 30));
      expect(c.silentStreams, MovaSilentKeepAlive.keepDecoding);
      expect(c.allowHls, isFalse);
      expect(c.resumeTimeout, const Duration(seconds: 5));
      expect(c.liveResumeGrace, const Duration(seconds: 3));
    });

    test('copyWith replaces exactly one field', () {
      const base = MovaKeepAliveOpts();
      expect(base.copyWith(maxDuration: const Duration(seconds: 9)).maxDuration, const Duration(seconds: 9));
      expect(base.copyWith(silentStreams: MovaSilentKeepAlive.pause).silentStreams, MovaSilentKeepAlive.pause);
      expect(base.copyWith(allowHls: true).allowHls, isTrue);
      expect(base.copyWith(resumeTimeout: const Duration(seconds: 7)).resumeTimeout, const Duration(seconds: 7));
      expect(base.copyWith(liveResumeGrace: Duration.zero).liveResumeGrace, Duration.zero);
      expect(base.copyWith(allowHls: true).maxDuration, base.maxDuration);
    });

    test('== and hashCode follow the fields', () {
      expect(const MovaKeepAliveOpts(), const MovaKeepAliveOpts());
      expect(const MovaKeepAliveOpts().hashCode, const MovaKeepAliveOpts().hashCode);
      expect(const MovaKeepAliveOpts(allowHls: true), isNot(const MovaKeepAliveOpts()));
      expect(
        const MovaKeepAliveOpts(maxDuration: Duration(seconds: 1)).hashCode,
        isNot(const MovaKeepAliveOpts().hashCode),
      );
    });

    test('MovaOpts carries the keepAlive section and copyWith leaves others alone', () {
      expect(const MovaOpts().keepAlive, const MovaKeepAliveOpts());
      const custom = MovaKeepAliveOpts(allowHls: true);
      final o = const MovaOpts().copyWith(keepAlive: custom);
      expect(o.keepAlive, custom);
      expect(o.recovery, const MovaOpts().recovery);
      expect(o.live, const MovaOpts().live);
      expect(const MovaOpts(), isNot(o));
    });

    test('assertValid rejects a zero maxDuration', () {
      expect(() => const MovaKeepAliveOpts().assertValid(), returnsNormally);
      expect(
        () => const MovaKeepAliveOpts(maxDuration: Duration.zero).assertValid(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
