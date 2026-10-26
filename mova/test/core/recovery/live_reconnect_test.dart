import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';

import '../../support/fake_kernel.dart';

MovaPlayFail _fail({int attempt = 1, int index = 0, int count = 1, bool live = true}) => MovaPlayFail(
  kind: MovaPlayFailKind.startTimeout,
  sourceIndex: index,
  uri: 'https://h/$index',
  sourceCount: count,
  attempt: attempt,
  streak: attempt,
  isLive: live,
);

void main() {
  group('MovaPlayFail.isLive', () {
    test('默认 false', () {
      const f = MovaPlayFail(
        kind: MovaPlayFailKind.startTimeout,
        sourceIndex: 0,
        uri: 'a',
        sourceCount: 1,
        attempt: 1,
        streak: 1,
      );
      expect(f.isLive, isFalse);
    });
  });

  group('MovaLiveReconnect 策略', () {
    const p = MovaLiveReconnect();

    test('单地址：指数退避 1s,2s,4s... 封顶 30s，永不放弃', () {
      final delays = [for (var a = 1; a <= 8; a++) p.onFailure(_fail(attempt: a)).delay.inSeconds];
      expect(delays, [1, 2, 4, 8, 16, 30, 30, 30]);
      for (var a = 1; a <= 8; a++) {
        expect(p.onFailure(_fail(attempt: a)).action, MovaRecoveryAction.retry);
      }
      final huge = p.onFailure(_fail(attempt: 100000));
      expect(huge.action, MovaRecoveryAction.retry);
      expect(huge.delay, const Duration(seconds: 30));
    });

    test('多地址：每个非末地址先重试 retriesPerAddress 次再切换，末地址持续重试', () {
      expect(p.onFailure(_fail(count: 2)).action, MovaRecoveryAction.retry);
      final d = p.onFailure(_fail(attempt: 2, count: 2));
      expect(d.action, MovaRecoveryAction.failover);
      expect(d.delay, Duration.zero);
      expect(p.onFailure(_fail(attempt: 9, index: 1, count: 2)).action, MovaRecoveryAction.retry);
    });

    test('initialDelay / maxDelay / factor / retriesPerAddress 生效', () {
      const q = MovaLiveReconnect(
        initialDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 3),
        factor: 3,
        retriesPerAddress: 0,
      );
      expect(q.onFailure(_fail()).delay, const Duration(milliseconds: 500));
      expect(q.onFailure(_fail(attempt: 2)).delay, const Duration(milliseconds: 1500));
      expect(q.onFailure(_fail(attempt: 3)).delay, const Duration(seconds: 3));
      expect(q.onFailure(_fail(count: 2)).action, MovaRecoveryAction.failover);
    });

    test('maxAttempts 非空时末地址超限放弃', () {
      const q = MovaLiveReconnect(maxAttempts: 3);
      expect(q.onFailure(_fail(attempt: 3)).action, MovaRecoveryAction.retry);
      expect(q.onFailure(_fail(attempt: 4)).action, MovaRecoveryAction.giveUp);
    });
  });

  group('MovaDefaultRecovery 默认策略', () {
    const p = MovaDefaultRecovery();

    test('点播与旧默认 MovaRetryThenFailover 逐项一致', () {
      const old = MovaRetryThenFailover();
      for (final count in [1, 2]) {
        for (final attempt in [1, 2, 3]) {
          for (final index in [0, count - 1]) {
            final f = _fail(attempt: attempt, index: index, count: count, live: false);
            final a = p.onFailure(f);
            final b = old.onFailure(f);
            expect((a.action, a.delay), (b.action, b.delay));
          }
        }
      }
    });

    test('直播走 MovaLiveReconnect', () {
      final d = p.onFailure(_fail(attempt: 5));
      expect(d.action, MovaRecoveryAction.retry);
      expect(d.delay, const Duration(seconds: 16));
    });
  });

  group('MovaRecoveryConfig.liveReconnect', () {
    test('默认 true，effectivePolicy 为 MovaDefaultRecovery；false 回到 MovaRetryThenFailover', () {
      expect(const MovaRecoveryConfig().liveReconnect, isTrue);
      expect(const MovaRecoveryConfig().effectivePolicy, isA<MovaDefaultRecovery>());
      expect(const MovaRecoveryConfig(liveReconnect: false).effectivePolicy, isA<MovaRetryThenFailover>());
    });

    test('显式 policy 优先；copyWith/==/hashCode 带上该字段', () {
      const custom = MovaFailoverOnly();
      expect(const MovaRecoveryConfig(policy: custom).effectivePolicy, same(custom));
      const base = MovaRecoveryConfig(enabled: true);
      expect(base.copyWith(liveReconnect: false).liveReconnect, isFalse);
      expect(base.copyWith().liveReconnect, isTrue);
      expect(base, isNot(base.copyWith(liveReconnect: false)));
      expect(base.hashCode, isNot(base.copyWith(liveReconnect: false).hashCode));
    });
  });

  group('引擎：直播源推流端重启后自动恢复', () {
    test('直播连续多次失败也不放弃，源恢复后 MovaRecovered 且清错误', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final engine = MovaEngine(
          kernel: k,
          options: const MovaOpts(
            recovery: MovaRecoveryConfig(enabled: true),
            controls: MovaCtrlsConfig(autoHide: false),
          ),
        );
        final events = <MovaEvent>[];
        engine.events.listen(events.add);
        engine.open(const MovaSource('whep+http://h/x/whep', type: MovaStreamType.live));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 10));
        expect(engine.state.error, isNull, reason: '直播不应放弃');
        expect(events.whereType<MovaErrorEvent>(), isEmpty);
        final failures = events.whereType<MovaPlayFailure>().toList();
        expect(failures.length, greaterThan(5));
        expect(failures.every((f) => f.action == MovaRecoveryAction.retry), isTrue);
        expect(failures.every((f) => f.fail.isLive), isTrue);
        // 推流端回来了：等到下一次重试加载真的发出，再出画面。
        final loads = k.openedUris.length;
        while (k.openedUris.length == loads) {
          async.elapse(const Duration(seconds: 1));
        }
        k.emitBuffering(true);
        k.emitBuffering(false);
        async.flushMicrotasks();
        expect(events.whereType<MovaRecovered>(), hasLength(1));
      });
    });

    test('liveReconnect:false 时直播沿用旧默认：第二次失败即放弃', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final engine = MovaEngine(
          kernel: k,
          options: const MovaOpts(
            recovery: MovaRecoveryConfig(enabled: true, liveReconnect: false),
            controls: MovaCtrlsConfig(autoHide: false),
          ),
        );
        engine.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(engine.state.error, isA<MovaGiveUpError>());
      });
    });

    test('点播默认行为不变：第二次失败即放弃', () {
      fakeAsync((async) {
        final k = FakeKernel();
        final engine = MovaEngine(
          kernel: k,
          options: const MovaOpts(
            recovery: MovaRecoveryConfig(enabled: true),
            controls: MovaCtrlsConfig(autoHide: false),
          ),
        );
        engine.open(const MovaSource('https://h/a.mp4'));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(engine.state.error, isA<MovaGiveUpError>());
      });
    });
  });
}
