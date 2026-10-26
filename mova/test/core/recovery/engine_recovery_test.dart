import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';
import 'package:mova/src/core/report/stats_probe.dart';

import '../../support/fake_kernel.dart';

/// A policy that throws, to prove a host rule can never break the engine.
///
/// 会抛异常的策略，用来证明宿主规则绝不能打断引擎。
class _ThrowingPolicy implements MovaRecoveryPolicy {
  @override
  MovaRecoveryDecision onFailure(MovaPlayFail fail) =>
      throw StateError('host bug');
}

/// An engine over [kernel] with recovery on (unless [recovery] says otherwise)
/// and the control bar's auto-hide timer off, so the only timers left pending
/// are the ones recovery itself creates.
///
/// 基于 [kernel] 的引擎：recovery 默认开启，并关掉控制条自动隐藏计时器，使得剩余的
/// 挂起计时器只可能来自 recovery 本身。
class _Rig {
  _Rig(
    this.kernel, {
    MovaRecoveryConfig recovery = const MovaRecoveryConfig(enabled: true),
  }) : engine = MovaEngine(
         kernel: kernel,
         options: MovaOpts(
           recovery: recovery,
           controls: const MovaCtrlsConfig(autoHide: false),
         ),
       ) {
    engine.events.listen(events.add);
  }

  final FakeKernel kernel;
  final MovaEngine engine;
  final List<MovaEvent> events = [];

  List<MovaPlayFailure> get failures =>
      events.whereType<MovaPlayFailure>().toList();

  /// Opens [uri] and lets microtasks settle.
  ///
  /// 打开 [uri] 并让微任务落定。
  void open(
    FakeAsync async, {
    String uri = 'https://h/a.m3u8',
    bool autoPlay = true,
    MovaStreamType type = MovaStreamType.vod,
  }) {
    engine.open(MovaSource(uri, type: type), autoPlay: autoPlay);
    async.flushMicrotasks();
  }

  /// Lands the first frame through the buffering falling edge.
  ///
  /// 经 buffering 下降沿让首帧落地。
  void land(FakeAsync async) {
    kernel.emitBuffering(true);
    kernel.emitBuffering(false);
    async.flushMicrotasks();
  }
}

void main() {
  const tenSeconds = Duration(seconds: 10);
  const oneSecond = Duration(seconds: 1);

  test(
    '1. disabled (default): open() still throws, no failure events, no stream or timer added',
    () {
      fakeAsync((async) {
        final k = FakeStatsKernel()..openError = StateError('boom');
        final r = _Rig(k, recovery: const MovaRecoveryConfig());
        Object? thrown;
        r.engine
            .open(const MovaSource('https://h/a.m3u8'))
            .catchError((Object e) {
              thrown = e;
              return false;
            });
        async.flushMicrotasks();
        expect(thrown, isA<StateError>());
        async.elapse(const Duration(minutes: 5));
        expect(r.failures, isEmpty);
        expect(k.endFilesSubscribed, isFalse);
        expect(async.pendingTimers, isEmpty);

        final ok = _Rig(
          FakeStatsKernel(),
          recovery: const MovaRecoveryConfig(),
        );
        ok.open(async);
        expect(
          async.pendingTimers,
          isEmpty,
          reason: 'no watchdog timer may exist when recovery is off',
        );
      });
    },
  );

  test(
    '2. enabled: no first frame by startTimeout fails once with retry, then reloads the same uri after 1s',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async);
        async.elapse(tenSeconds);
        expect(r.failures, hasLength(1));
        final f = r.failures.single;
        expect(f.fail.kind, MovaPlayFailKind.startTimeout);
        expect(f.fail.attempt, 1);
        expect(f.action, MovaRecoveryAction.retry);
        expect(k.openedUris, hasLength(1));
        async.elapse(oneSecond);
        expect(k.openedUris, ['https://h/a.m3u8', 'https://h/a.m3u8']);
      });
    },
  );

  test(
    '3. the second timeout gives up: MovaGiveUpError in state, exactly one error event, kernel paused',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async);
        async.elapse(tenSeconds + oneSecond + tenSeconds);
        expect(r.failures, hasLength(2));
        expect(r.failures.last.fail.attempt, 2);
        expect(r.failures.last.action, MovaRecoveryAction.giveUp);
        expect(r.engine.state.error, isA<MovaGiveUpError>());
        final errors = r.events.whereType<MovaErrorEvent>().toList();
        expect(errors, hasLength(1));
        expect(errors.single.error, isA<MovaGiveUpError>());
        expect(k.calls, contains('pause'));
        async.elapse(const Duration(minutes: 5));
        expect(
          r.failures,
          hasLength(2),
          reason: 'nothing more happens after giving up',
        );
      });
    },
  );

  test(
    '4. a first frame inside the deadline: no failure however long we wait',
    () {
      fakeAsync((async) {
        final r = _Rig(FakeKernel());
        r.open(async);
        async.elapse(const Duration(seconds: 3));
        r.land(async);
        async.elapse(const Duration(minutes: 10));
        expect(r.failures, isEmpty);
      });
    },
  );

  test(
    '5. autoPlay:false does not time out; play() starts the clock from zero',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async, autoPlay: false);
        async.elapse(const Duration(minutes: 5));
        expect(r.failures, isEmpty);
        r.engine.play();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 9));
        expect(r.failures, isEmpty);
        async.elapse(oneSecond);
        expect(r.failures.single.fail.kind, MovaPlayFailKind.startTimeout);
      });
    },
  );

  test(
    '6. a stall after the first frame fails with stallTimeout; a VOD retry resumes at the failed position',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async);
        k.emitDuration(const Duration(minutes: 10));
        r.land(async);
        k.emitPosition(const Duration(seconds: 30));
        async.flushMicrotasks();
        k.emitBuffering(true);
        async.flushMicrotasks();
        async.elapse(tenSeconds);
        final f = r.failures.single.fail;
        expect(f.kind, MovaPlayFailKind.stallTimeout);
        expect(f.afterFirstFrame, isTrue);
        expect(f.waited, tenSeconds);
        async.elapse(oneSecond);
        expect(k.openedUris, hasLength(2));
        k.emitDuration(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(k.lastSeek, isNull);
        r.land(async);
        expect(k.lastSeek, const Duration(seconds: 30));
      });
    },
  );

  test('7. pausing during a stall stops the stall clock', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async);
      r.land(async);
      k.emitBuffering(true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      r.engine.pause();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(r.failures, isEmpty);
    });
  });

  test(
    '8. enabled + open() throwing: open() completes, openThrew is reported, the retry succeeds and announces ready once',
    () {
      fakeAsync((async) {
        final k = FakeKernel()..openError = StateError('boom');
        final r = _Rig(k);
        var completed = false;
        r.engine
            .open(const MovaSource('https://h/a.m3u8'))
            .then((_) => completed = true);
        async.flushMicrotasks();
        expect(completed, isTrue);
        expect(r.failures.single.fail.kind, MovaPlayFailKind.openThrew);
        expect(r.failures.single.fail.error, isA<StateError>());
        expect(r.events.whereType<MovaReady>(), isEmpty);
        k.openError = null;
        async.elapse(oneSecond);
        expect(k.openedUris, hasLength(2));
        expect(r.events.whereType<MovaReady>(), hasLength(1));
        expect(r.events.whereType<MovaSourceChange>(), hasLength(1));
      });
    },
  );

  test(
    '9. a live source reaching its end is liveEnded; liveEndIsFailure:false ignores it',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async, type: MovaStreamType.live);
        k.emitCompleted(true);
        async.flushMicrotasks();
        expect(r.failures.single.fail.kind, MovaPlayFailKind.liveEnded);

        final k2 = FakeKernel();
        final quiet = _Rig(
          k2,
          recovery: const MovaRecoveryConfig(
            enabled: true,
            liveEndIsFailure: false,
          ),
        );
        quiet.open(async, type: MovaStreamType.live);
        k2.emitCompleted(true);
        async.flushMicrotasks();
        expect(quiet.failures, isEmpty);

        final k3 = FakeKernel();
        final vod = _Rig(k3);
        vod.open(async);
        k3.emitCompleted(true);
        async.flushMicrotasks();
        expect(
          vod.failures,
          isEmpty,
          reason: 'a VOD source finishing is not a failure',
        );
      });
    },
  );

  test(
    '10. native END_FILE(error) fails immediately; END_FILE(stop) does not',
    () {
      fakeAsync((async) {
        final k = FakeStatsKernel();
        final r = _Rig(k);
        r.open(async);
        k.emitEndFile(MovaEndFileReason.stop);
        async.flushMicrotasks();
        expect(r.failures, isEmpty);
        k.emitEndFile(MovaEndFileReason.error);
        async.flushMicrotasks();
        expect(r.failures.single.fail.kind, MovaPlayFailKind.nativeEndError);
        expect(r.failures.single.fail.waited, Duration.zero);
      });
    },
  );

  test(
    '11. opening another source during the retry delay cancels the pending retry',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async);
        async.elapse(tenSeconds);
        expect(r.failures, hasLength(1));
        r.open(async, uri: 'https://h/b.m3u8');
        async.elapse(const Duration(seconds: 3));
        expect(k.openedUris, ['https://h/a.m3u8', 'https://h/b.m3u8']);
      });
    },
  );

  test(
    '12. landing after a failure announces MovaRecovered and restarts the attempt count',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(k);
        r.open(async);
        async.elapse(tenSeconds + oneSecond);
        expect(k.openedUris, hasLength(2));
        r.land(async);
        final recovered = r.events.whereType<MovaRecovered>().toList();
        expect(recovered, hasLength(1));
        expect(recovered.single.attempts, 1);
        k.emitBuffering(true);
        async.flushMicrotasks();
        async.elapse(tenSeconds);
        expect(r.failures.last.fail.kind, MovaPlayFailKind.stallTimeout);
        expect(r.failures.last.fail.attempt, 1);
        expect(r.failures.last.fail.streak, 1);
      });
    },
  );

  test(
    '13. a throwing policy is treated as give-up and never breaks the engine',
    () {
      fakeAsync((async) {
        final k = FakeKernel();
        final r = _Rig(
          k,
          recovery: MovaRecoveryConfig(
            enabled: true,
            policy: _ThrowingPolicy(),
          ),
        );
        r.open(async);
        expect(() => async.elapse(tenSeconds), returnsNormally);
        expect(r.failures.single.action, MovaRecoveryAction.giveUp);
        expect(r.engine.state.error, isA<MovaGiveUpError>());
      });
    },
  );

  test('14. dispose() during the retry delay: nothing fires afterwards', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k);
      r.open(async);
      async.elapse(tenSeconds);
      expect(r.failures, hasLength(1));
      final before = r.events.length;
      unawaited(r.engine.dispose());
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 5));
      expect(r.events.length, before);
      expect(k.openedUris, hasLength(1));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
