import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/recovery/fail.dart';

MovaPlayFail _fail({int attempt = 1, int index = 0, int count = 1}) => MovaPlayFail(
      kind: MovaPlayFailKind.startTimeout,
      sourceIndex: index,
      uri: 'https://h/$index',
      sourceCount: count,
      attempt: attempt,
      streak: attempt,
    );

void main() {
  const policy = MovaRetryThenFailover();

  test('default policy: first failure retries after 1s', () {
    final d = policy.onFailure(_fail());
    expect(d.action, MovaRecoveryAction.retry);
    expect(d.delay, const Duration(seconds: 1));
  });

  test('default policy: retries used up with an alternative left fails over', () {
    final d = policy.onFailure(_fail(attempt: 2, count: 2));
    expect(d.action, MovaRecoveryAction.failover);
    expect(d.delay, Duration.zero);
  });

  test('default policy: retries used up with no alternative gives up', () {
    expect(policy.onFailure(_fail(attempt: 2)).action, MovaRecoveryAction.giveUp);
    expect(policy.onFailure(_fail(attempt: 2, index: 1, count: 2)).action, MovaRecoveryAction.giveUp);
  });

  test('maxRetries 0 fails over on the very first failure', () {
    const p = MovaRetryThenFailover(maxRetries: 0);
    expect(p.onFailure(_fail(count: 2)).action, MovaRecoveryAction.failover);
  });

  test('maxRetries and retryDelay are honoured', () {
    const p = MovaRetryThenFailover(maxRetries: 2, retryDelay: Duration(milliseconds: 250));
    final d = p.onFailure(_fail(attempt: 2));
    expect(d.action, MovaRecoveryAction.retry);
    expect(d.delay, const Duration(milliseconds: 250));
    expect(p.onFailure(_fail(attempt: 3)).action, MovaRecoveryAction.giveUp);
  });

  test('MovaFailoverOnly never retries: next alternative when there is one, else give up', () {
    const p = MovaFailoverOnly();
    expect(p.onFailure(_fail(count: 2)).action, MovaRecoveryAction.failover);
    expect(p.onFailure(_fail()).action, MovaRecoveryAction.giveUp);
  });

  test('MovaGiveUpError.toString names the kind and the uri; hasNextSource follows the counts', () {
    final f = _fail(count: 2);
    expect(f.hasNextSource, isTrue);
    expect(_fail(index: 1, count: 2).hasNextSource, isFalse);
    final text = MovaGiveUpError(f).toString();
    expect(text, contains('startTimeout'));
    expect(text, contains('https://h/0'));
  });
}
