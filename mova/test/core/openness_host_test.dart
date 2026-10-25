import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';

/// A recovery policy that records every call, so a test can prove it was
/// really consulted rather than the default silently winning.
///
/// 记录每次调用的恢复策略，供测试证明它真被使用，而非默认实现悄悄生效。
class _RecordingPolicy implements MovaRecoveryPolicy {
  int calls = 0;

  @override
  MovaRecoveryDecision onFailure(MovaPlayFail fail) {
    calls++;
    return const MovaRecoveryDecision.giveUp();
  }
}

void main() {
  group('host-ergonomics openness contract — every new behaviour is off by default and replaceable', () {
    test('everything defaults to off, and a default engine adds no timer and no stream', () {
      expect(const MovaOpts().recovery.enabled, isFalse);
      expect(const MovaSource('x').alternatives, isEmpty);
      const theme = MovaTheme();
      expect(theme.bufferingSize, isNull);
      expect(theme.bufferingStrokeWidth, isNull);
      expect(theme.bufferingColor, isNull);
      expect(movaObserveFlags(hasReporter: false, preciseFirstFrame: false).native, isFalse);
      expect(movaObserveFlags(hasReporter: false, preciseFirstFrame: false).qoe, isFalse);

      fakeAsync((async) {
        final k = FakeStatsKernel();
        final engine = MovaEngine(kernel: k, options: const MovaOpts(controls: MovaCtrlsConfig(autoHide: false)));
        engine.open(const MovaSource('https://h/a.m3u8'));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 10));
        expect(async.pendingTimers, isEmpty, reason: 'recovery off: no watchdog, no retry timer');
        expect(k.endFilesSubscribed, isFalse, reason: 'recovery off: END_FILE is not even subscribed');
        expect(engine.state.error, isNull);
        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('an injected MovaRecoveryPolicy replaces the default and is really consulted', () {
      expect(const MovaRecoveryConfig().effectivePolicy, isA<MovaRetryThenFailover>());
      fakeAsync((async) {
        final policy = _RecordingPolicy();
        final engine = MovaEngine(
          kernel: FakeKernel(),
          options: MovaOpts(
            controls: const MovaCtrlsConfig(autoHide: false),
            recovery: MovaRecoveryConfig(enabled: true, policy: policy),
          ),
        );
        engine.open(const MovaSource('https://h/a.m3u8'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(policy.calls, greaterThan(0));
        expect(engine.state.error, isA<MovaGiveUpError>(), reason: 'the injected give-up must win over the default retry');
        engine.dispose();
        async.flushMicrotasks();
      });
    });

    test('each knob is replaced on its own through copyWith without disturbing the rest', () {
      const base = MovaRecoveryConfig(enabled: true, startTimeout: Duration(seconds: 3));
      final next = base.copyWith(stallTimeout: const Duration(seconds: 4));
      expect(next.startTimeout, base.startTimeout);
      expect(next.enabled, isTrue);
      expect(next.stallTimeout, const Duration(seconds: 4));

      const opts = MovaOpts(mini: MovaMiniConfig(enabled: true), report: MovaReportConfig(qoe: true));
      final replaced = opts.copyWith(recovery: base);
      expect(replaced.recovery, base);
      expect(replaced.mini, opts.mini);
      expect(replaced.report, opts.report);
    });
  });
}
