import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 'package:mova/src/testing/hooks.dart';

/// Records variant probes without using the network.
///
/// 记录清晰度探测，不访问网络。
class _Fetch extends MovaTestHttpFetch {
  final urls = <Uri>[];
  Uint8List? playlist;

  /// Records [url] and returns the configured playlist.
  ///
  /// 记录 [url] 并返回配置的播放列表。
  @override
  Future<Uint8List?> get(Uri url) async {
    urls.add(url);
    return playlist;
  }
}

/// Verifies synchronous callbacks cannot continue work for a replaced source.
///
/// 验证同步回调换源后不会继续旧源工作。
void main() {
  test('MovaDone synchronous open does not fail the next live source', () {
    fakeAsync((clock) {
      final kernel = MovaTestKernel();
      final engine = MovaEngine(
        kernel: kernel,
        fetcher: const MovaTestHttpFetch(),
        options: const MovaOpts(
          recovery: MovaRecoveryConfig(enabled: true),
        ),
      );
      final failures = <MovaEvent>[];
      engine.events.listen((event) {
        if (event is MovaDone) {
          unawaited(
            engine.open(
              const MovaSource(
                'https://h/next.m3u8',
                type: MovaStreamType.live,
              ),
            ),
          );
        }
        if (event is MovaPlayFailure || event is MovaErrorEvent) {
          failures.add(event);
        }
      });
      engine.open(
        const MovaSource('https://h/old.m3u8', type: MovaStreamType.live),
      );
      clock.flushMicrotasks();
      kernel.emitCompleted(true);
      clock.flushMicrotasks();
      expect(kernel.lastUri, 'https://h/next.m3u8');
      expect(engine.state.error, isNull);
      expect(failures, isEmpty);
      engine.dispose();
      clock.flushMicrotasks();
    });
  });

  for (final trigger in ['source', 'ready']) {
    for (final dispose in [false, true]) {
      test(
        '$trigger callback ${dispose ? 'dispose' : 'open'} stops old ready/probe work',
        () {
          fakeAsync((clock) {
            final kernel = MovaTestKernel();
            final fetch = _Fetch();
            final engine = MovaEngine(kernel: kernel, fetcher: fetch);
            final ready = <String?>[];
            var replaced = false;
            engine.events.listen((event) {
              if (event is MovaReady) ready.add(kernel.lastUri);
              if (!replaced &&
                  ((trigger == 'source' && event is MovaSourceChange) ||
                      (trigger == 'ready' && event is MovaReady))) {
                replaced = true;
                if (dispose) {
                  unawaited(engine.dispose());
                } else {
                  unawaited(
                    engine.open(const MovaSource('https://h/next.m3u8')),
                  );
                }
              }
            });
            engine.open(const MovaSource('https://h/old.m3u8'));
            clock.flushMicrotasks();
            expect(ready, [
              if (trigger == 'ready') 'https://h/old.m3u8',
              if (!dispose) 'https://h/next.m3u8',
            ]);
            expect(fetch.urls.map((url) => url.toString()), [
              if (!dispose) 'https://h/next.m3u8',
            ]);
            engine.dispose();
            clock.flushMicrotasks();
          });
        },
      );
    }
  }

  test(
    'MovaSeek synchronous open stops the old kernel seek and seeked event',
    () {
      fakeAsync((clock) {
        final kernel = MovaTestKernel();
        final engine = MovaEngine(
          kernel: kernel,
          fetcher: const MovaTestHttpFetch(),
        );
        engine.open(const MovaSource('https://h/old.mp4'));
        clock.flushMicrotasks();
        kernel.emitDuration(const Duration(seconds: 60));
        clock.flushMicrotasks();
        final seeked = <MovaSeeked>[];
        engine.events.listen((event) {
          if (event is MovaSeek) {
            unawaited(engine.open(const MovaSource('https://h/next.mp4')));
          }
          if (event is MovaSeeked) seeked.add(event);
        });
        kernel.calls.clear();
        engine.seek(const Duration(seconds: 5));
        clock.flushMicrotasks();
        expect(kernel.calls, isNot(contains('seek')));
        expect(seeked, isEmpty);
        expect(kernel.lastUri, 'https://h/next.mp4');
        engine.dispose();
        clock.flushMicrotasks();
      });
    },
  );
  for (final trigger in ['size', 'duration', 'buffering']) {
    test('$trigger callback open stops old frame and parked seek work', () {
      fakeAsync((clock) {
        final kernel = MovaTestKernel();
        final engine = MovaEngine(
          kernel: kernel,
          fetcher: const MovaTestHttpFetch(),
        );
        engine.open(
          MovaSource(
            'https://h/old.mp4',
            start: trigger == 'duration' ? const Duration(seconds: 5) : null,
          ),
        );
        clock.flushMicrotasks();
        if (trigger == 'buffering') {
          kernel.emitBuffering(true);
          clock.flushMicrotasks();
        }
        final frames = <MovaFirstFrame>[];
        engine.events.listen((event) {
          if ((trigger == 'size' && event is MovaSizeChange) ||
              (trigger == 'duration' && event is MovaDurationChange) ||
              (trigger == 'buffering' && event is MovaBufferChange)) {
            unawaited(engine.open(const MovaSource('https://h/next.mp4')));
          }
          if (event is MovaFirstFrame) frames.add(event);
        });
        kernel.calls.clear();
        switch (trigger) {
          case 'size':
            kernel.emitSize(1280, 720);
          case 'duration':
            kernel.emitDuration(const Duration(seconds: 60));
          case 'buffering':
            kernel.emitBuffering(false);
        }
        clock.flushMicrotasks();
        expect(kernel.lastUri, 'https://h/next.mp4');
        expect(kernel.calls, isNot(contains('seek')));
        expect(frames, isEmpty);
        expect(engine.state.rendered, isFalse);
        engine.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  test('terminal buffer callback open prevents old error and pause', () {
    fakeAsync((clock) {
      final kernel = MovaTestKernel();
      final engine = MovaEngine(
        kernel: kernel,
        fetcher: const MovaTestHttpFetch(),
      );
      engine.open(const MovaSource('https://h/old.mp4'));
      clock.flushMicrotasks();
      kernel.emitBuffering(true);
      clock.flushMicrotasks();
      final errors = <MovaErrorEvent>[];
      engine.events.listen((event) {
        if (event is MovaBufferChange && !event.buffering) {
          unawaited(engine.open(const MovaSource('https://h/next.mp4')));
        }
        if (event is MovaErrorEvent) errors.add(event);
      });
      kernel.calls.clear();
      kernel.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      expect(kernel.lastUri, 'https://h/next.mp4');
      expect(kernel.calls, isNot(contains('pause')));
      expect(errors, isEmpty);
      expect(engine.state.error, isNull);
      engine.dispose();
      clock.flushMicrotasks();
    });
  });
  test('quality list callback open suppresses the old current-quality event', () {
    fakeAsync((clock) {
      final kernel = MovaTestKernel();
      final fetch = _Fetch()
        ..playlist = Uint8List.fromList(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720\n720.m3u8\n'
              .codeUnits,
        );
      final engine = MovaEngine(kernel: kernel, fetcher: fetch);
      final changes = <MovaQualityChange>[];
      engine.events.listen((event) {
        if (event is MovaQualityListChange) {
          unawaited(engine.open(const MovaSource('https://h/next.mp4')));
        }
        if (event is MovaQualityChange) changes.add(event);
      });
      engine.open(const MovaSource('https://h/old.m3u8'));
      clock.flushMicrotasks();
      expect(kernel.lastUri, 'https://h/next.mp4');
      expect(changes, isEmpty);
      engine.dispose();
      clock.flushMicrotasks();
    });
  });

  test(
    'MovaDone synchronous open prevents old keepAlive ended degradation',
    () {
      fakeAsync((clock) {
        final kernel = MovaTestKernel()..hasAudio = true;
        final engine = MovaEngine(
          kernel: kernel,
          fetcher: const MovaTestHttpFetch(),
        );
        engine.open(
          const MovaSource('https://h/old.flv', type: MovaStreamType.live),
        );
        clock.flushMicrotasks();
        kernel.emitPlaying(true);
        kernel.emitSize(1280, 720);
        clock.flushMicrotasks();
        engine.setKeepAlive(true);
        clock.flushMicrotasks();
        expect(engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
        final phases = <MovaKeepAliveChange>[];
        engine.events.listen((event) {
          if (event is MovaDone) {
            unawaited(
              engine.open(
                const MovaSource(
                  'https://h/next.flv',
                  type: MovaStreamType.live,
                ),
              ),
            );
          }
          if (event is MovaKeepAliveChange) phases.add(event);
        });
        kernel.emitCompleted(true);
        clock.flushMicrotasks();
        expect(kernel.lastUri, 'https://h/next.flv');
        expect(
          phases.where((event) => event.reason == MovaKeepAliveReason.ended),
          isEmpty,
        );
        engine.dispose();
        clock.flushMicrotasks();
      });
    },
  );
}
