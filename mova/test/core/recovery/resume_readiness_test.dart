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

/// Drops seeks before presentation is ready, as an asynchronous load can.
///
/// 模拟异步加载：呈现就绪前的 seek 被丢弃。
class _LoadingKernel extends FakeStatsKernel {
  bool ready = false;
  Duration actualPosition = Duration.zero;
  final acceptedSeeks = <Duration>[];

  @override
  Future<void> open(String uri, {bool play = true}) async {
    ready = false;
    actualPosition = Duration.zero;
    await super.open(uri, play: play);
  }

  @override
  Future<void> seek(Duration position) async {
    await super.seek(position);
    if (!ready) return;
    actualPosition = position;
    acceptedSeeks.add(position);
    emitPosition(position);
  }

  /// Presents the file after metadata arrived, without repeating duration.
  ///
  /// 元数据到达后呈现文件，不重复发送时长。
  void land(FakeAsync a) {
    ready = true;
    emitRestart();
    a.flushMicrotasks();
  }
}

/// Builds an engine with deterministic recovery and no control timers.
///
/// 构建恢复行为确定且没有控制条计时器的引擎。
MovaEngine _engine(_LoadingKernel k, {bool failover = false}) => MovaEngine(
  kernel: k,
  options: MovaOpts(
    controls: const MovaCtrlsConfig(autoHide: false),
    recovery: MovaRecoveryConfig(
      enabled: true,
      policy: failover
          ? const MovaFailoverOnly()
          : const MovaRetryThenFailover(maxRetries: 3),
    ),
  ),
);

void main() {
  const position = Duration(milliseconds: 2840);
  const duration = Duration(milliseconds: 40023);
  for (final live in [false, true]) {
    for (final path in [
      'stallTimeout',
      'openThrew',
      'nativeEndError',
      'failover',
    ]) {
      test('HE V6 ${live ? "live" : "VOD"} $path waits for load readiness', () {
        fakeAsync((a) {
          final k = _LoadingKernel()..nativeRestartAvailable = true;
          final e = _engine(k, failover: path == 'failover');
          final events = <MovaEvent>[];
          e.events.listen(events.add);
          e.open(
            MovaSource(
              'https://h/a.mp4',
              type: live ? MovaStreamType.live : MovaStreamType.vod,
              alternatives: const ['https://h/b.mp4'],
            ),
          );
          a.flushMicrotasks();
          k.emitDuration(duration);
          k.land(a);
          k.emitPosition(position);
          k.emitBuffering(true);
          a.flushMicrotasks();
          if (path == 'nativeEndError' || path == 'failover') {
            k.emitEndFile(MovaEndFileReason.error);
            a.flushMicrotasks();
          } else {
            a.elapse(const Duration(seconds: 10));
          }
          if (path == 'openThrew') {
            k.openError = StateError('retry failed');
            a.elapse(const Duration(seconds: 1));
            expect(
              events.whereType<MovaPlayFailure>().last.fail.kind,
              MovaPlayFailKind.openThrew,
            );
            k.openError = null;
          }
          a.elapse(const Duration(seconds: 1));
          expect(k.openedUris.length, path == 'openThrew' ? 3 : 2);
          // Metadata precedes readiness; no second duration event follows.
          // 时长早于就绪，之后不再补发时长事件。
          k.emitDuration(duration);
          a.flushMicrotasks();
          expect(k.acceptedSeeks, isEmpty);
          expect(k.lastSeek, isNull);
          k.land(a);
          expect(k.actualPosition, live ? Duration.zero : position);
          expect(k.acceptedSeeks, live ? isEmpty : [position]);
          if (live) expect(k.calls.where((v) => v == 'seek'), isEmpty);
          expect(events.whereType<MovaRecovered>(), hasLength(1));
          if (path == 'failover') {
            expect(e.state.sourceIndex, 1);
            expect(k.lastUri, 'https://h/b.mp4');
          }
          unawaited(e.dispose());
          a.flushMicrotasks();
        });
      });
    }
  }

  for (final signal in ['restart', 'buffering', 'progress', 'pausedSize']) {
    test('HE V6 VOD resumes on $signal without a new duration', () {
      fakeAsync((a) {
        final k = _LoadingKernel();
        final e = _engine(k);
        e.open(const MovaSource('https://h/a.mp4'));
        a.flushMicrotasks();
        k.emitDuration(duration);
        k.land(a);
        k.emitPosition(position);
        k.emitEndFile(MovaEndFileReason.error);
        a.flushMicrotasks();
        if (signal == 'pausedSize') {
          e.pause();
          a.flushMicrotasks();
        }
        a.elapse(const Duration(seconds: 1));
        expect(k.lastSeek, isNull);
        expect(e.state.duration, Duration.zero);
        k.ready = true;
        switch (signal) {
          case 'restart':
            k.emitRestart();
          case 'buffering':
            k.emitBuffering(true);
            k.emitBuffering(false);
          case 'progress':
            k.emitPosition(const Duration(milliseconds: 40));
            k.emitPosition(const Duration(milliseconds: 80));
          case 'pausedSize':
            expect(k.lastPlay, isFalse);
            k.emitSize(640, 360);
        }
        a.flushMicrotasks();
        expect(k.actualPosition, position);
        expect(k.acceptedSeeks, [position]);
        unawaited(e.dispose());
        a.flushMicrotasks();
      });
    });
  }

  test('HE V6 late failed frame preserves resume point for the next retry', () {
    fakeAsync((a) {
      final k = _LoadingKernel();
      final e = _engine(k);
      e.open(const MovaSource('https://h/a.mp4'));
      a.flushMicrotasks();
      k.land(a);
      k.emitPosition(position);
      k.emitEndFile(MovaEndFileReason.error);
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 1));
      k.emitEndFile(MovaEndFileReason.error);
      a.flushMicrotasks();
      k.land(a);
      expect(k.acceptedSeeks, isEmpty);
      a.elapse(const Duration(seconds: 1));
      k.land(a);
      expect(k.actualPosition, position);
      expect(k.acceptedSeeks, [position]);
      unawaited(e.dispose());
      a.flushMicrotasks();
    });
  });

  test('HE V6 new session discards an unlanded recovery seek', () {
    fakeAsync((a) {
      final k = _LoadingKernel();
      final e = _engine(k);
      e.open(const MovaSource('https://h/a.mp4'));
      a.flushMicrotasks();
      k.land(a);
      k.emitPosition(position);
      k.emitEndFile(MovaEndFileReason.error);
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 1));
      e.open(const MovaSource('https://h/new.mp4'));
      a.flushMicrotasks();
      k.land(a);
      expect(k.acceptedSeeks, isEmpty);
      expect(k.actualPosition, Duration.zero);
      unawaited(e.dispose());
      a.flushMicrotasks();
    });
  });
}
