import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';
import '../support/keep_alive_rig.dart';
import 'ads_open_failure_test.dart' show RecordingAdPolicy;
import 'package:mova/src/core/kernel/attempt_event_kernel.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';
import 'package:mova/src/core/kernel/mpv_event_pump.dart';
import 'package:mova/src/core/kernel/mpv_event_backend.dart';
import '../support/fake_mpv_event_backend.dart';

/// open 可挂起，验证终结通知不会在打开返回前暂停内核。
class _OpeningKernel extends FakeStatsKernel {
  /// 打开返回门。
  final gate = Completer<void>();

  @override
  Future<void> open(String uri, {bool play = true}) async {
    await super.open(uri, play: play);
    await gate.future;
  }
}

/// 用真实泵模拟弱客户端队列，并保留通知产生时的尝试。
class _AttemptKernel extends FakeStatsKernel implements MovaAttemptEventKernel {
  /// 构造可手动投递原生通知的内核。
  _AttemptKernel() {
    pump = MovaMpvEventPump(backend, name: 'attempt', onRestart: () {},
      onEndFile: (_) {
        ends.add((attempt: attempt, reason: MovaEndFileReason.error));
        emitEndFile(MovaEndFileReason.error);
      });
  }

  /// 弱客户端队列。
  final backend = FakeMpvEventBackend();

  /// 带身份的异步通知。
  final ends = StreamController<MovaAttemptEnd>.broadcast();

  /// 真实排空逻辑。
  late final MovaMpvEventPump pump;

  /// 当前加载身份。
  int attempt = 0;

  @override
  void prepareAttempt(int value) {
    pump.discardPending();
    attempt = value;
  }

  @override
  Stream<MovaAttemptEnd> get attemptEnds => ends.stream;

  @override
  bool get endFileAvailable => pump.isActive;

  @override
  Future<void> dispose() async {
    await pump.dispose();
    await ends.close();
    await super.dispose();
  }
}

/// 验证 END_FILE 与终结日志共用尝试及待机处理。
void main() {
  test('F-J delivered A END_FILE with captured attempt cannot terminate B', () async {
    final k = _AttemptKernel();
    await k.pump.start(Future.value());
    final e = MovaEngine(kernel: k, options: const MovaOpts(
      controls: MovaCtrlsConfig(autoHide: false),
    ));
    await e.open(const MovaSource('https://h/A.mp4'));
    final oldAttempt = k.attempt;
    await e.open(const MovaSource('https://h/B.mp4'));
    k.ends.add((attempt: oldAttempt, reason: MovaEndFileReason.error));
    await pumpEventQueue();
    expect(e.state.error, isNull);
    expect(k.calls, isNot(contains('pause')));
    k.ends.add((attempt: k.attempt, reason: MovaEndFileReason.error));
    await pumpEventQueue();
    expect(e.state.error, MovaEndFileReason.error);
    await e.dispose();
  });

  test('F-L diagnostic 404 does not consume terminal END_FILE', () async {
    final k = FakeStatsKernel();
    final e = MovaEngine(kernel: k, options: const MovaOpts(
      controls: MovaCtrlsConfig(autoHide: false),
    ));
    final errors = <MovaErrorEvent>[];
    e.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(errors.add);
    await e.open(const MovaSource('https://h/missing.mp4'));
    k.emitError('HTTP error 404 Not Found');
    await pumpEventQueue();
    expect(e.state.error, isNull);
    k.emitEndFile(MovaEndFileReason.error);
    await pumpEventQueue();
    expect(errors.map((v) => v.fatal), [false, true]);
    expect(e.state.error, MovaEndFileReason.error);
    await e.dispose();
  });

  for (final endFirst in [true, false]) {
    test('F-L ad retry ignores interleaved old END_FILE endFirst=$endFirst', () async {
      final k = _AttemptKernel();
      await k.pump.start(Future.value());
      final policy = RecordingAdPolicy(MovaAdFailAction.retry);
      final e = MovaEngine(kernel: k, options: MovaOpts(
        controls: const MovaCtrlsConfig(autoHide: false),
        ads: MovaAdConfig(enabled: true, failPolicy: policy, breaks: const [
          MovaAdBreak(kind: MovaAdBreakKind.pre,
            source: MovaSource('https://h/ad.mp4'), waitForReady: false),
        ]),
      ));
      final ads = MovaAds(e);
      await ads.load(const MovaSource('https://h/content.mp4'));
      final failedAttempt = k.attempt;
      k.backend.events.add(const MovaRawEvent(7, endFileReason: 4));
      if (endFirst) k.backend.wake();
      k.emitError('Failed to recognize file format.');
      await pumpEventQueue();
      expect(k.openedUris.where((v) => v == 'https://h/ad.mp4'), hasLength(2));
      // 重试已经打开新尝试，再交付旧尝试通知，不能二次结算广告策略。
      k.ends.add((attempt: failedAttempt, reason: MovaEndFileReason.error));
      k.emitEndFile(MovaEndFileReason.error);
      k.backend.wake();
      await pumpEventQueue();
      expect(policy.failures, hasLength(1));
      expect(e.state.error, isNull);
      expect(ads.isShowingAd, isTrue);
      await ads.dispose();
      await e.dispose();
    });
  }

  for (final endFirst in [true, false]) {
    test('F-L one fatal per attempt endFirst=$endFirst', () async {
      final k = FakeStatsKernel();
      final e = MovaEngine(kernel: k, options: const MovaOpts(
        controls: MovaCtrlsConfig(autoHide: false),
      ));
      final errors = <MovaErrorEvent>[];
      e.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(errors.add);
      await e.open(const MovaSource('https://h/bad.mp4'));
      void end() => k.emitEndFile(MovaEndFileReason.error);
      void log() => k.emitError('Failed to recognize file format.');
      (endFirst ? end : log)();
      await pumpEventQueue();
      (endFirst ? log : end)();
      await pumpEventQueue();
      expect(errors.where((v) => v.fatal), hasLength(1));
      expect(k.calls.where((v) => v == 'pause'), hasLength(1));
      if (endFirst) expect(errors.last.fatal, isFalse);
      await e.dispose();
    });
  }

  test('F-K END_FILE during open waits for return without recovery', () async {
    final k = _OpeningKernel();
    final e = MovaEngine(kernel: k, options: const MovaOpts(
      controls: MovaCtrlsConfig(autoHide: false),
    ));
    final opening = e.open(const MovaSource('https://h/bad.mp4'));
    await pumpEventQueue();
    k.emitEndFile(MovaEndFileReason.error);
    await pumpEventQueue();
    expect(e.state.error, isNull);
    expect(k.calls, isNot(contains('pause')));
    k.gate.complete();
    await opening;
    await pumpEventQueue();
    expect(e.state.error, MovaEndFileReason.error);
    expect(k.calls, contains('pause'));
    await e.dispose();
  });

  for (final holding in [true, false]) {
    test('F-K recovery off quiet END_FILE holding=$holding wakes by reopen', () {
      fakeAsync((async) {
        final k = FakeKeepAliveStatsKernel();
        if (!holding) k.media = const MovaKeepAliveMedia(audio: MovaAudioPresence.unknown);
        final r = KeepAliveRig(async, k)..playLive();
        if (holding) r.land();
        r.keepAlive(true);
        expect(r.engine.state.keepAlivePhase,
            holding ? MovaKeepAlivePhase.holding : MovaKeepAlivePhase.fallback);
        final opens = k.openedUris.length;
        k.emitEndFile(MovaEndFileReason.error);
        r.settle();
        expect(r.events.whereType<MovaErrorEvent>(), isEmpty);
        expect(r.engine.state.error, isNull);
        expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
        if (holding) expect(r.changes.last.reason, MovaKeepAliveReason.failed);
        r.keepAlive(false);
        expect(k.openedUris.length, opens + 1);
        r.engine.dispose();
        r.settle();
      });
    });
  }
}
