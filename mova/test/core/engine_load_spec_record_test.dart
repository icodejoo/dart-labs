import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/engine/load_spec.dart';

import '../support/fake_kernel.dart';

/// 创建只核对加载记录的引擎，恢复使用固定短退避。
MovaEngine _engine(FakeKernel k, {MovaLiveConfig live = const MovaLiveConfig()}) =>
    createMovaEngine(
      kernel: k,
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      brightness: MovaFallbackBrightnessPort(),
      options: MovaOpts(
        controls: const MovaCtrlsConfig(autoHide: false),
        recovery: const MovaRecoveryConfig(
          enabled: true,
          policy: MovaRetryThenFailover(retryDelay: Duration(milliseconds: 10)),
        ),
        live: live,
      ),
    );

void main() {
  test('A09 records open quality retry and failover without deciding playback', () {
    fakeAsync((clock) {
      final k = FakeStatsKernel();
      final e = _engine(k);
      expect(e.debugCurrentLoad, isNull);
      e.open(const MovaSource('https://h/a.mp4', alternatives: ['https://h/b.mp4']));
      clock.flushMicrotasks();
      expect(e.debugCurrentLoad!.reason, LoadReason.open);
      expect(e.debugCurrentLoad!.sourceIndex, 0);
      expect(e.debugCurrentLoad!.uri, k.lastUri);
      expect(e.debugCurrentLoad!.quality, isNull);
      expect(e.debugCurrentLoad!.resumeAt, isNull);
      expect(e.debugCurrentLoad!.timeshiftBehind, isNull);
      k.emitDuration(const Duration(minutes: 5));
      k.emitPosition(const Duration(seconds: 41));
      k.emitPosition(const Duration(seconds: 42));
      clock.flushMicrotasks();
      const q = MovaQuality(label: '720p', uri: 'https://h/720.mp4');
      e.switchQuality(q);
      clock.flushMicrotasks();
      expect(e.debugCurrentLoad!.reason, LoadReason.quality);
      expect(e.debugCurrentLoad!.uri, k.lastUri);
      expect(e.debugCurrentLoad!.quality, q);
      expect(e.debugCurrentLoad!.resumeAt, const Duration(seconds: 42));
      k.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 10));
      clock.flushMicrotasks();
      expect(e.debugCurrentLoad!.reason, LoadReason.retry);
      expect(e.debugCurrentLoad!.uri, k.lastUri);
      expect(e.debugCurrentLoad!.quality, e.state.currentQuality);
      k.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      clock.flushMicrotasks();
      expect(e.debugCurrentLoad!.reason, LoadReason.failover);
      expect(e.debugCurrentLoad!.sourceIndex, 1);
      expect(e.debugCurrentLoad!.uri, k.lastUri);
      expect(e.debugCurrentLoad!.quality, isNull);
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A09 records timeshift lag and live edge load', () {
    fakeAsync((clock) {
      final k = FakeKernel();
      final e = _engine(k, live: MovaLiveConfig(
        seekMode: MovaLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        urlBuilder: (uri, behind, now) => '$uri?behind=${behind.inSeconds}',
      ));
      e.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live));
      clock.flushMicrotasks();
      e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      expect(e.debugCurrentLoad!.reason, LoadReason.timeshift);
      expect(e.debugCurrentLoad!.uri, k.lastUri);
      expect(e.debugCurrentLoad!.timeshiftBehind, const Duration(minutes: 3));
      expect(e.debugCurrentLoad!.resumeAt, isNull);
      e.backToLiveEdge();
      clock.flushMicrotasks();
      expect(e.debugCurrentLoad!.reason, LoadReason.liveEdge);
      expect(e.debugCurrentLoad!.uri, k.lastUri);
      expect(e.debugCurrentLoad!.timeshiftBehind, isNull);
      expect(e.debugCurrentLoad!.sourceIndex, 0);
      e.dispose();
      clock.flushMicrotasks();
    });
  });
}
