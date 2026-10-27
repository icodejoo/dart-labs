import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';

void main() {
  const s = Duration(seconds: 1);

  group('看门狗派生值（兜底 = mpv 窗口 + 余量）', () {
    test('默认配置：非 WHEP 起播/卡顿 65s，WHEP 起播 85s、卡顿 10s', () {
      const c = MovaRecoveryConfig();
      expect(c.startTimeoutFor('https://a/x.flv'), Duration(seconds: 65));
      expect(c.stallTimeoutFor('https://a/x.flv'), Duration(seconds: 65));
      expect(c.startTimeoutFor('whep+http://h/x'), Duration(seconds: 85));
      expect(c.startTimeoutFor('WHEP://h/x'), Duration(seconds: 85));
      expect(c.stallTimeoutFor('whep+http://h/x'), Duration(seconds: 10));
    });

    test('随 timeouts 变化：network=10s、WHEP 握手5/首帧8/media5', () {
      const c = MovaRecoveryConfig(
        timeouts: MovaTimeouts(
          network: Duration(seconds: 10),
          whepHandshake: Duration(seconds: 5),
          whepFirstFrame: Duration(seconds: 8),
          whepMedia: Duration(seconds: 5),
        ),
      );
      expect(c.startTimeoutFor('https://a'), Duration(seconds: 16)); // max(10, 11 重连窗口) + 5
      expect(c.stallTimeoutFor('https://a'), Duration(seconds: 16));
      expect(c.startTimeoutFor('whep://h'), Duration(seconds: 28)); // 10+5+8+5
      expect(c.stallTimeoutFor('whep://h'), Duration(seconds: 10)); // 5+5
    });

    test('派生值总是大于 mpv 窗口，mpv 重连/握手期间看门狗不会先断开', () {
      for (final t in const [
        MovaTimeouts(),
        MovaTimeouts(network: Duration(seconds: 3)),
        MovaTimeouts(network: Duration(seconds: 20), whepHandshake: Duration(seconds: 7), whepMedia: Duration(seconds: 9)),
      ]) {
        final c = MovaRecoveryConfig(timeouts: t);
        for (final u in ['https://a', 'whep://h']) {
          expect(c.startTimeoutFor(u), greaterThan(t.startWindowFor(u)));
          expect(c.stallTimeoutFor(u)!, greaterThan(t.stallWindowFor(u)));
        }
      }
    });

    test('显式 startTimeout/stallTimeout 以用户值为准（含 WHEP）', () {
      const c = MovaRecoveryConfig(startTimeout: Duration(seconds: 3), stallTimeout: Duration(seconds: 4));
      expect(c.startTimeoutFor('https://a'), Duration(seconds: 3));
      expect(c.startTimeoutFor('whep://h'), Duration(seconds: 3));
      expect(c.stallTimeoutFor('https://a'), Duration(seconds: 4));
      expect(c.stallTimeoutFor('whep://h'), Duration(seconds: 4));
    });

    test('stallWatchdog:false 关闭卡顿看门狗', () {
      const c = MovaRecoveryConfig(stallWatchdog: false);
      expect(c.stallTimeoutFor('https://a'), isNull);
      expect(c.copyWith(stallWatchdog: true).stallTimeoutFor('https://a'), Duration(seconds: 65));
    });
  });

  test('defaults: off, derived (null) timeouts, stall watchdog on, live end is failure, no policy', () {
    const c = MovaRecoveryConfig();
    expect(c.enabled, isFalse);
    expect(c.startTimeout, isNull);
    expect(c.stallTimeout, isNull);
    expect(c.stallWatchdog, isTrue);
    expect(c.timeouts, const MovaTimeouts());
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
    expect(base.copyWith(stallTimeout: Duration(seconds: 3)).copyWith(clearStallTimeout: true).stallTimeout, isNull);
    expect(base.copyWith(timeouts: const MovaTimeouts(network: s)).timeouts.network, s);
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
