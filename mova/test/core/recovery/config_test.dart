import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';

void main() {
  test('defaults: off, 10s start, 10s stall, live end is failure, no policy', () {
    const c = MovaRecoveryConfig();
    expect(c.enabled, isFalse);
    expect(c.startTimeout, const Duration(seconds: 10));
    expect(c.stallTimeout, const Duration(seconds: 10));
    expect(c.liveEndIsFailure, isTrue);
    expect(c.policy, isNull);
  });

  test('effectivePolicy defaults to MovaDefaultRecovery (live reconnect off -> MovaRetryThenFailover) and prefers an injected one', () {
    expect(const MovaRecoveryConfig().effectivePolicy, isA<MovaDefaultRecovery>());
    expect(const MovaRecoveryConfig(liveReconnect: false).effectivePolicy, isA<MovaRetryThenFailover>());
    const failoverOnly = MovaFailoverOnly();
    expect(const MovaRecoveryConfig(policy: failoverOnly).effectivePolicy, same(failoverOnly));
  });

  test('copyWith replaces single fields and can clear the nullable ones', () {
    const base = MovaRecoveryConfig(policy: MovaFailoverOnly());
    expect(base.copyWith(enabled: true).enabled, isTrue);
    expect(base.copyWith(enabled: true).policy, base.policy);
    expect(base.copyWith(startTimeout: const Duration(seconds: 3)).startTimeout, const Duration(seconds: 3));
    expect(base.copyWith(clearStallTimeout: true).stallTimeout, isNull);
    expect(base.copyWith(clearPolicy: true).policy, isNull);
    expect(base.copyWith(liveEndIsFailure: false).liveEndIsFailure, isFalse);
    expect(const MovaRecoveryConfig(enabled: true), const MovaRecoveryConfig(enabled: true));
    expect(const MovaRecoveryConfig(enabled: true), isNot(const MovaRecoveryConfig()));
  });

  test('MovaOpts carries it: default equals the const default, copyWith leaves other sections alone', () {
    expect(const MovaOpts().recovery, const MovaRecoveryConfig());
    const opts = MovaOpts(mini: MovaMiniConfig(enabled: true));
    final next = opts.copyWith(recovery: const MovaRecoveryConfig(enabled: true));
    expect(next.recovery.enabled, isTrue);
    expect(next.mini, opts.mini);
    expect(next, isNot(opts));
    expect(opts.copyWith(), opts);
  });

  test('assertValid rejects non-positive timeouts', () {
    expect(const MovaRecoveryConfig().assertValid, returnsNormally);
    expect(const MovaRecoveryConfig(startTimeout: Duration.zero).assertValid, throwsA(isA<AssertionError>()));
    expect(const MovaRecoveryConfig(stallTimeout: Duration.zero).assertValid, throwsA(isA<AssertionError>()));
    expect(const MovaRecoveryConfig(stallTimeout: null).assertValid, returnsNormally);
  });
}
