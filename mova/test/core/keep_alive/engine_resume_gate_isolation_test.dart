import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_kernel.dart';
import '../../support/gated.dart';

/// 创建独立闸门回归用引擎；关闭 UI 计时并缩短恢复退避。
MovaEngine _engine(FakeKernel k) => createMovaEngine(
  kernel: k,
  pip: MovaNoopPipPort(),
  orientation: MovaNoopOrientationPort(),
  brightness: MovaFallbackBrightnessPort(),
  options: const MovaOpts(
    controls: MovaCtrlsConfig(autoHide: false),
    recovery: MovaRecoveryConfig(
      enabled: true,
      policy: MovaRetryThenFailover(retryDelay: Duration(milliseconds: 10)),
    ),
  ),
);

/// 打开直播，进入待机后唤醒至等待新画面。
void _wake(MovaEngine e, FakeKernel k, FakeAsync clock) {
  e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
  clock.flushMicrotasks();
  k.emitPlaying(true);
  e.setKeepAlive(true);
  clock.flushMicrotasks();
  e.setKeepAlive(false);
  clock.flushMicrotasks();
  expect(e.state.keepAlivePhase, MovaKeepAlivePhase.resuming);
}

void main() {
  for (final operation in ['open', 'quality', 'recover']) {
    test('A08 $operation ends resume without a measurement event', () {
      fakeAsync((clock) {
        final k = FakeKeepAliveStatsKernel();
        final e = _engine(k);
        final events = <MovaEvent>[];
        e.events.listen(events.add);
        _wake(e, k, clock);
        final log = CommandLog();
        if (operation == 'open') {
          e.open(const MovaSource('https://h/new.mp4'));
        } else if (operation == 'quality') {
          e.switchQuality(const MovaQuality(label: '720p', uri: 'https://h/720.flv'));
        } else {
          k.emitEndFile(MovaEndFileReason.error);
          clock.flushMicrotasks();
          clock.elapse(const Duration(milliseconds: 10));
        }
        clock.flushMicrotasks();
        log.record(0, operation);
        expect(log.entries.single.verb, operation);
        expect(e.state.keepAlivePhase, MovaKeepAlivePhase.off);
        expect(events.whereType<MovaKeepAliveChange>().last.reason, MovaKeepAliveReason.reloaded);
        expect(events.whereType<MovaKeepAliveResume>(), isEmpty);
        clock.elapse(const Duration(seconds: 6));
        k.emitBuffering(true);
        k.emitBuffering(false);
        clock.flushMicrotasks();
        expect(e.state.rendered, isTrue, reason: 'old timeout must not reset new attempt');
        expect(events.whereType<MovaKeepAliveResume>(), isEmpty);
        e.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  test('A08 resume size does not land the unrendered playing attempt', () {
    fakeAsync((clock) {
      final k = FakeKeepAliveStatsKernel();
      final e = _engine(k);
      final events = <MovaEvent>[];
      e.events.listen(events.add);
      _wake(e, k, clock);
      k.emitSize(1280, 720);
      clock.flushMicrotasks();
      expect(events.whereType<MovaKeepAliveResume>(), hasLength(1));
      expect(e.state.rendered, isFalse);
      k.emitPosition(const Duration(seconds: 1));
      k.emitPosition(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(e.state.rendered, isTrue);
      expect(events.whereType<MovaFirstFrame>(), hasLength(1));
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A08 fallback reload keeps resume until attempt lands', () {
    fakeAsync((clock) {
      final k = FakeKeepAliveStatsKernel();
      final e = _engine(k);
      final events = <MovaEvent>[];
      e.events.listen(events.add);
      e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
      clock.flushMicrotasks();
      k.emitPlaying(true);
      e.setKeepAlive(true);
      clock.flushMicrotasks();
      k.emitCompleted(true);
      clock.flushMicrotasks();
      e.setKeepAlive(false);
      clock.flushMicrotasks();
      expect(e.state.keepAlivePhase, MovaKeepAlivePhase.resuming);
      expect(events.whereType<MovaKeepAliveResume>(), isEmpty);
      k.emitBuffering(true);
      k.emitBuffering(false);
      clock.flushMicrotasks();
      expect(e.state.keepAlivePhase, MovaKeepAlivePhase.off);
      expect(events.whereType<MovaKeepAliveResume>(), hasLength(1));
      e.dispose();
      clock.flushMicrotasks();
    });
  });
}
