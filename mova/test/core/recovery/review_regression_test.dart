import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/preview/fetcher.dart';
import 'package:mova/src/core/recovery/fail.dart';

import '../../support/fake_kernel.dart';

/// Rejects only the replacement source.
///
/// 只拒绝替换源。
class _RejectB extends MovaHook {
  @override
  Future<bool> beforeOpen(MovaSource source) async =>
      !source.uri.contains('b.');
}

/// Holds an auxiliary request until a test settles it.
///
/// 挂起辅助请求直到测试完成它。
class _Fetch extends MovaHttpFetch {
  final result = Completer<Uint8List?>();
  @override
  Future<Uint8List?> get(Uri url) => result.future;
  @override
  Future<void> close() async {}
}

/// Builds a recovery engine without unrelated control timers.
///
/// 构建没有控制条计时器的恢复引擎。
MovaEngine _engine(
  FakeKernel k, {
  List<MovaHook> hooks = const [],
  MovaHttpFetch? fetcher,
  MovaRecoveryPolicy policy = const MovaRetryThenFailover(maxRetries: 3),
}) => MovaEngine(
  kernel: k,
  interceptors: hooks,
  fetcher: fetcher,
  options: MovaOpts(
    controls: const MovaCtrlsConfig(autoHide: false),
    recovery: MovaRecoveryConfig(enabled: true, policy: policy),
  ),
);

/// Lands a frame through the portable buffering signal.
///
/// 经可移植的缓冲信号落地首帧。
void _land(FakeKernel k, FakeAsync a) {
  k.emitBuffering(true);
  k.emitBuffering(false);
  a.flushMicrotasks();
}

void main() {
  const source = MovaSource('https://h/a.m3u8');
  const variant = MovaQuality(label: '720p', uri: 'https://h/720.m3u8');
  test(
    '#1 pause during pending retry loads paused and play restarts watchdog',
    () {
      fakeAsync((a) {
        final k = FakeKernel();
        final e = _engine(k);
        final failures = <MovaPlayFailure>[];
        e.events
            .where((v) => v is MovaPlayFailure)
            .cast<MovaPlayFailure>()
            .listen(failures.add);
        e.open(source);
        a.flushMicrotasks();
        a.elapse(const Duration(seconds: 10));
        e.pause();
        a.flushMicrotasks();
        a.elapse(const Duration(seconds: 1));
        expect(k.lastPlay, isFalse);
        a.elapse(const Duration(minutes: 1));
        expect(failures, hasLength(1));
        e.play();
        a.flushMicrotasks();
        expect(k.calls.last, 'play');
        a.elapse(const Duration(seconds: 10));
        expect(failures, hasLength(2));
        e.dispose();
        a.flushMicrotasks();
      });
    },
  );

  for (final live in [false, true]) {
    test(
      '#4 replacement ${live ? "live edge" : "quality"} attempt cancels pending recovery',
      () {
        fakeAsync((a) {
          final k = FakeKernel();
          final e = _engine(k);
          e.open(
            MovaSource(
              source.uri,
              type: live ? MovaStreamType.live : MovaStreamType.vod,
            ),
          );
          a.flushMicrotasks();
          a.elapse(const Duration(seconds: 10));
          live ? e.backToLiveEdge() : e.switchQuality(variant);
          a.flushMicrotasks();
          _land(k, a);
          a.elapse(const Duration(seconds: 2));
          expect(k.openedUris, hasLength(2));
          expect(k.lastUri, live ? source.uri : variant.uri);
          e.dispose();
          a.flushMicrotasks();
        });
      },
    );
  }

  for (final live in [false, true]) {
    test(
      '#6 internal ${live ? "live edge" : "quality"} open error enters recovery',
      () {
        fakeAsync((a) {
          final k = FakeKernel();
          final e = _engine(k);
          final failures = <MovaPlayFailure>[];
          e.events
              .where((v) => v is MovaPlayFailure)
              .cast<MovaPlayFailure>()
              .listen(failures.add);
          e.open(
            MovaSource(
              source.uri,
              type: live ? MovaStreamType.live : MovaStreamType.vod,
            ),
          );
          a.flushMicrotasks();
          k.openError = StateError('internal load');
          live ? e.backToLiveEdge() : e.switchQuality(variant);
          a.flushMicrotasks();
          expect(failures.single.fail.kind, MovaPlayFailKind.openThrew);
          k.openError = null;
          a.elapse(const Duration(seconds: 1));
          expect(k.openedUris, hasLength(3));
          a.elapse(const Duration(seconds: 10));
          expect(failures.last.fail.kind, MovaPlayFailKind.startTimeout);
          e.dispose();
          a.flushMicrotasks();
        });
      },
    );
  }

  test('#7 recovery retains VOD position across a thrown retry', () {
    fakeAsync((a) {
      final k = FakeKernel();
      final e = _engine(k);
      e.open(source);
      a.flushMicrotasks();
      _land(k, a);
      k.emitPosition(const Duration(seconds: 37));
      k.emitBuffering(true);
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 10));
      k.openError = StateError('retry failed');
      a.elapse(const Duration(seconds: 1));
      k.openError = null;
      a.elapse(const Duration(seconds: 1));
      k.emitDuration(const Duration(minutes: 5));
      a.flushMicrotasks();
      expect(k.lastSeek, isNull);
      _land(k, a);
      expect(k.lastSeek, const Duration(seconds: 37));
      e.dispose();
      a.flushMicrotasks();
    });
  });

  test('#8 rejected open preserves accepted session recovery', () {
    fakeAsync((a) {
      final k = FakeKernel();
      final e = _engine(k, hooks: [_RejectB()]);
      e.open(source);
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 10));
      e.open(const MovaSource('https://h/b.m3u8'));
      a.flushMicrotasks();
      a.elapse(const Duration(seconds: 1));
      expect(k.openedUris, [source.uri, source.uri]);
      e.dispose();
      a.flushMicrotasks();
    });
  });

  test('#9 paused open replays size received before open completes', () {
    fakeAsync((a) {
      final k = FakeKernel()..openGate = Completer<void>();
      final e = _engine(k);
      e.open(source, autoPlay: false);
      a.flushMicrotasks();
      k.emitSize(640, 360);
      a.flushMicrotasks();
      expect(e.state.rendered, isFalse);
      k.openGate!.complete();
      a.flushMicrotasks();
      expect(e.state.rendered, isTrue);
      e.dispose();
      a.flushMicrotasks();
    });
  });

  for (final response in ['playlist', 'null', 'error', 'session']) {
    test('#11 stale quality $response response is discarded', () {
      fakeAsync((a) {
        final k = FakeKernel();
        final fetch = _Fetch();
        final e = _engine(k, fetcher: fetch, policy: const MovaFailoverOnly());
        final qualityEvents = <MovaQualityListChange>[];
        e.events
            .where((v) => v is MovaQualityListChange)
            .cast<MovaQualityListChange>()
            .listen(qualityEvents.add);
        e.open(
          const MovaSource(
            'https://h/a.m3u8',
            alternatives: ['https://h/b.m3u8'],
          ),
        );
        a.flushMicrotasks();
        e.loadQualities();
        if (response == 'session') {
          e.open(const MovaSource('https://h/c.mp4'));
          a.flushMicrotasks();
        } else {
          a.elapse(const Duration(seconds: 10));
          a.flushTimers();
        }
        if (response == 'error') {
          fetch.result.completeError(StateError('late network error'));
        } else if (response == 'null') {
          fetch.result.complete(null);
        } else {
          fetch.result.complete(
            Uint8List.fromList(
              utf8.encode(
                '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nold.m3u8',
              ),
            ),
          );
        }
        a.flushMicrotasks();
        expect(e.state.qualities, isEmpty);
        expect(qualityEvents, isEmpty);
        e.dispose();
        a.flushMicrotasks();
      });
    });
  }
}
