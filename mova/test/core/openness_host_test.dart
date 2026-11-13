import 'package:mova/src/testing/hooks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';

/// A recovery policy that records every call, so a test can prove it was
/// really consulted rather than the default silently winning.
///
/// 记录每次调用的恢复策略，供测试证明它真被使用，而非默认实现悄悄生效。
class _RecordingPolicy implements IMovaRecoveryPolicy {
  int calls = 0;

  @override
  MovaRecoveryDecision onFailure(MovaPlayFail fail) {
    calls++;
    return const MovaRecoveryDecision.giveUp();
  }
}

void main() {
  group('host-ergonomics openness contract — every new behaviour is off by default and replaceable', () {
    test('everything defaults to off, and a default player adds no timer and no stream', () {
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
        final mova = Mova(fetcher: const MovaTestHttpFetch(), kernel: k, options: const MovaOpts(controls: MovaCtrlsOpts(autoHide: false)));
        mova.open(const MovaSource('https://h/a.m3u8'));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 10));
        expect(async.pendingTimers, isEmpty, reason: 'recovery off: no watchdog, no retry timer');
        expect(k.endFilesSubscribed, isTrue, reason: 'END_FILE 判失败不依赖 recovery');
        expect(mova.state.error, isNull);
        mova.dispose();
        async.flushMicrotasks();
      });
    });

    test('an injected IMovaRecoveryPolicy replaces the default and is really consulted', () {
      expect(const MovaRecoveryOpts().effectivePolicy, isA<MovaDefaultRecovery>());
      fakeAsync((async) {
        final policy = _RecordingPolicy();
        final mova = Mova(fetcher: const MovaTestHttpFetch(),
          kernel: FakeKernel(),
          options: MovaOpts(
            controls: const MovaCtrlsOpts(autoHide: false),
            recovery: MovaRecoveryOpts(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true, policy: policy),
          ),
        );
        mova.open(const MovaSource('https://h/a.m3u8'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(policy.calls, greaterThan(0));
        expect(mova.state.error, isA<MovaGiveUpError>(), reason: 'the injected give-up must win over the default retry');
        mova.dispose();
        async.flushMicrotasks();
      });
    });

    test('each knob is replaced on its own through copyWith without disturbing the rest', () {
      const base = MovaRecoveryOpts(enabled: true, startTimeout: Duration(seconds: 3));
      final next = base.copyWith(stallTimeout: const Duration(seconds: 4));
      expect(next.startTimeout, base.startTimeout);
      expect(next.enabled, isTrue);
      expect(next.stallTimeout, const Duration(seconds: 4));

      const opts = MovaOpts(mini: MovaMiniOpts(enabled: true), report: MovaReportOpts(qoe: true));
      final replaced = opts.copyWith(recovery: base);
      expect(replaced.recovery, base);
      expect(replaced.mini, opts.mini);
      expect(replaced.report, opts.report);
    });
  });
}
