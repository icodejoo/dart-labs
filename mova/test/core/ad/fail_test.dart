import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';

/// A break to attach failures to; its own fields are irrelevant here.
///
/// 用于挂载失败记录的广告位；其字段本身与本组测试无关。
const _adBreak = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/ad.mp4'),
);

/// Builds a failure record for [attempt] with [kind].
///
/// 构造一条 [attempt] 次、原因为 [kind] 的失败记录。
MovaAdFail fail(int attempt, [MovaAdFailKind kind = MovaAdFailKind.openThrew]) =>
    MovaAdFail(adBreak: _adBreak, kind: kind, attempt: attempt);

void main() {
  group('MovaAdRetrySkip', () {
    test('the default (maxRetries 0) skips the break on the very first failure', () {
      expect(const MovaAdRetrySkip().onFailure(fail(1)), MovaAdFailAction.skipBreak);
    });

    test('maxRetries 2 retries attempts 1 and 2, then skips on attempt 3', () {
      const policy = MovaAdRetrySkip(maxRetries: 2);
      expect(policy.onFailure(fail(1)), MovaAdFailAction.retry);
      expect(policy.onFailure(fail(2)), MovaAdFailAction.retry);
      expect(policy.onFailure(fail(3)), MovaAdFailAction.skipBreak);
    });

    test('the retry budget is decoupled from the failure reason', () {
      const policy = MovaAdRetrySkip(maxRetries: 1);
      for (final kind in MovaAdFailKind.values) {
        expect(policy.onFailure(fail(1, kind)), MovaAdFailAction.retry, reason: '$kind');
        expect(policy.onFailure(fail(2, kind)), MovaAdFailAction.skipBreak, reason: '$kind');
      }
    });
  });

  group('MovaAdAbandonPod', () {
    test('abandons the pod for every attempt and every failure kind', () {
      const policy = MovaAdAbandonPod();
      for (final kind in MovaAdFailKind.values) {
        for (final attempt in [1, 2, 99]) {
          expect(policy.onFailure(fail(attempt, kind)), MovaAdFailAction.abandonPod);
        }
      }
    });
  });

  group('MovaAdFail and policy statelessness', () {
    test('both built-in policies are stateless: repeated calls on one instance do not drift', () {
      const retry = MovaAdRetrySkip(maxRetries: 1);
      const abandon = MovaAdAbandonPod();
      for (var i = 0; i < 5; i++) {
        expect(retry.onFailure(fail(1)), MovaAdFailAction.retry);
        expect(abandon.onFailure(fail(1)), MovaAdFailAction.abandonPod);
      }
    });

    test('MovaAdFail carries all four fields, and error may be null', () {
      final err = StateError('boom');
      final withError = MovaAdFail(
        adBreak: _adBreak,
        kind: MovaAdFailKind.playerError,
        attempt: 3,
        error: err,
      );
      expect(withError.adBreak, same(_adBreak));
      expect(withError.kind, MovaAdFailKind.playerError);
      expect(withError.attempt, 3);
      expect(withError.error, same(err));
      expect(fail(1).error, isNull);
    });
  });
}
