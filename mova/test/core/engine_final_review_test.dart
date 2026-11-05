import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/testing/test_kernel.dart';

/// A shared source with no playlist probing.
///
/// 不触发播放列表探测的共用源。
const _vod = MovaSource('https://h/video.mp4');

/// A live source for keepAlive and URL time-shift cases.
///
/// 待机和 URL 时移用的直播源。
const _live = MovaSource('https://h/live.flv', type: MovaStreamType.live);

/// A manually selected rendition.
///
/// 手选清晰度档位。
const _quality = MovaQuality(label: '720p', uri: 'https://h/720.m3u8');

/// Adds explicit load, rewind and keepAlive gates to the shared test kernel.
///
/// 为共用测试内核增加加载、回退和待机闸门。
class _GatedKernel extends MovaTestKernel {
  /// Suspends the corresponding kernel operation when set.
  ///
  /// 非空时挂起对应内核操作。
  Completer<void>? openGate, seekGate, holdGate;

  /// Records a load before waiting for its completion.
  ///
  /// 先记录加载，再等待完成。
  @override
  Future<void> open(String uri, {bool play = true}) async {
    await super.open(uri, play: play);
    await openGate?.future;
  }

  /// Records a seek before waiting for its completion.
  ///
  /// 先记录跳转，再等待完成。
  @override
  Future<void> seek(Duration position) async {
    await super.seek(position);
    await seekGate?.future;
  }

  /// Suspends a successful hold before returning to the engine.
  ///
  /// 挂起成功的待机请求，再返回引擎。
  @override
  Future<bool> enterKeepAlive(MovaKeepAliveMode mode) async {
    final held = await super.enterKeepAlive(mode);
    await holdGate?.future;
    return held;
  }
}

/// Records the effective platform orientation and host resets.
///
/// 记录平台生效方向及宿主方向还原次数。
class _Orientation implements MovaOrientationPort {
  MovaOrientation? applied;
  bool? fullscreen;
  int resets = 0;

  /// Records the applied orientation and fullscreen flag.
  ///
  /// 记录应用的方向和全屏标记。
  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrientation orientation,
  }) async {
    applied = orientation;
    this.fullscreen = fullscreen;
  }

  /// Records a reset to host orientation preferences.
  ///
  /// 记录还原宿主方向设置。
  @override
  Future<void> reset() async => resets++;
}

/// Creates an isolated engine without network probes or controls timers.
///
/// 创建无网络探测及控制条计时器的隔离引擎。
MovaEngine _engine(
  MovaTestKernel kernel, {
  MovaLiveConfig live = const MovaLiveConfig(),
  MovaRecoveryConfig recovery = const MovaRecoveryConfig(),
  MovaOrientationPort? orientation,
  List<MovaHook> interceptors = const [],
}) => createMovaEngine(
  kernel: kernel,
  ownsKernel: true,
  interceptors: interceptors,
  pip: MovaNoopPipPort(),
  brightness: MovaFallbackBrightnessPort(),
  orientation: orientation ?? MovaNoopOrientationPort(),
  options: MovaOpts(
    controls: const MovaCtrlsConfig(autoHide: false),
    abr: const MovaAbrConfig(probeVariants: false),
    live: live,
    recovery: recovery,
  ),
);

/// Hook that allows opens until [gate] is set, then rejects after it completes.
///
/// 在设置 [gate] 前放行 open，设置后等它完成再拒绝。
class _RejectingHook extends MovaHook {
  /// When non-null, `beforeOpen` waits on it and rejects.
  ///
  /// 非空时 `beforeOpen` 等待它完成后拒绝。
  Completer<void>? gate;

  /// Allows until [gate] is set; afterwards waits and rejects.
  ///
  /// 设置 [gate] 前放行；之后等待并拒绝。
  @override
  Future<bool> beforeOpen(MovaSource source) async {
    final g = gate;
    if (g == null) return true;
    await g.future;
    return false;
  }
}

/// Runs the final-review engine regressions with controlled interleavings.
///
/// 用可控交错执行终审引擎回归测试。
void main() {
  test('A14 downshift stops at the lowest video variant before audio', () async {
    final k = MovaTestKernel();
    final e = _engine(k);
    addTearDown(e.dispose);
    await e.open(_vod);
    final qualities = parseHlsMasterPlaylist('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=128000
audio.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080
high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360
low.m3u8
''', base: Uri.parse('https://h/master.m3u8'));
    final high = qualities[1];
    final low = qualities[2];
    expect(qualities.last.height, isNull);
    e.debugSetQualities(qualities, current: high);
    final changes = <MovaQualityChange>[];
    e.events.listen((event) {
      if (event is MovaQualityChange) changes.add(event);
    });

    await e.downshiftQuality();
    expect(e.state.currentQuality, same(low));
    expect(changes, hasLength(1));
    k.calls.clear();
    changes.clear();

    await e.downshiftQuality();
    expect(e.state.currentQuality, same(low));
    expect(k.calls, isEmpty);
    expect(changes, isEmpty);
  });

  for (final stream in ['events', 'states', 'uiStates', 'progress']) {
    test('A2 dispose releases kernel with paused $stream subscriber', () async {
      final k = MovaTestKernel();
      final e = _engine(k);
      final Stream<dynamic> publicStream = switch (stream) {
        'events' => e.events,
        'states' => e.states,
        'uiStates' => e.uiStates,
        _ => e.progress,
      };
      var done = false;
      final sub = publicStream.listen((_) {}, onDone: () => done = true)
        ..pause();
      try {
        await e.dispose().timeout(const Duration(seconds: 1));
        expect(k.calls, contains('dispose'));
        expect(done, isFalse);
        sub.resume();
        await pumpEventQueue();
        expect(done, isTrue);
      } finally {
        await sub.cancel();
        await e.dispose();
      }
    });
  }

  for (final durationDuringLoad in [false, true]) {
    test('A3 quality reload preserves seek issued during load '
        '(durationDuringLoad: $durationDuringLoad)', () {
      fakeAsync((clock) {
        final k = _GatedKernel();
        final e = _engine(k);
        e.open(_vod);
        clock.flushMicrotasks();
        k.emitDuration(const Duration(minutes: 2));
        k.emitPosition(const Duration(seconds: 42));
        clock.flushMicrotasks();
        k.openGate = Completer<void>();
        e.switchQuality(_quality);
        clock.flushMicrotasks();
        expect(e.state.duration, Duration.zero);
        e.seek(const Duration(seconds: 80));
        clock.flushMicrotasks();
        if (durationDuringLoad) {
          k.emitDuration(const Duration(minutes: 2));
          clock.flushMicrotasks();
        }
        k.openGate!.complete();
        clock.flushMicrotasks();
        k.emitDuration(const Duration(minutes: 2));
        k.emitSize(1280, 720);
        k.emitBuffering(true);
        k.emitBuffering(false);
        clock.flushMicrotasks();
        expect(k.lastSeek, const Duration(seconds: 80));
        e.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  for (final rejectFirst in [false, true]) {
    test('rejected host open during quality reload keeps the resume seek '
        '(rejectFirst: $rejectFirst)', () {
      fakeAsync((clock) {
        final k = _GatedKernel();
        final hook = _RejectingHook();
        final e = _engine(k, interceptors: [hook]);
        e.open(_vod);
        clock.flushMicrotasks();
        k.emitDuration(const Duration(minutes: 2));
        k.emitPosition(const Duration(seconds: 42));
        clock.flushMicrotasks();
        k.openGate = Completer<void>();
        e.switchQuality(_quality);
        clock.flushMicrotasks();
        hook.gate = Completer<void>();
        bool? opened;
        e.open(const MovaSource('https://h/next.mp4')).then((v) => opened = v);
        clock.flushMicrotasks();
        if (rejectFirst) {
          hook.gate!.complete();
          clock.flushMicrotasks();
        }
        k.openGate!.complete();
        clock.flushMicrotasks();
        if (!rejectFirst) {
          hook.gate!.complete();
          clock.flushMicrotasks();
        }
        expect(opened, isFalse);
        k.emitDuration(const Duration(minutes: 2));
        k.emitSize(1280, 720);
        k.emitBuffering(true);
        k.emitBuffering(false);
        clock.flushMicrotasks();
        expect(k.lastSeek, const Duration(seconds: 42));
        expect(e.state.currentQuality, _quality);
        e.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  for (final supersede in ['pause', 'open']) {
    test('A4 replay does not play after $supersede during rewind', () {
      fakeAsync((clock) {
        final k = _GatedKernel();
        final e = _engine(k);
        e.open(_vod);
        clock.flushMicrotasks();
        k.emitCompleted(true);
        clock.flushMicrotasks();
        k.seekGate = Completer<void>();
        e.play();
        clock.flushMicrotasks();
        expect(k.lastSeek, Duration.zero);
        if (supersede == 'pause') {
          e.pause();
        } else {
          e.open(const MovaSource('https://h/next.mp4'), autoPlay: false);
        }
        clock.flushMicrotasks();
        final plays = k.calls.where((v) => v == 'play').length;
        k.seekGate!.complete();
        clock.flushMicrotasks();
        expect(k.calls.where((v) => v == 'play'), hasLength(plays));
        expect(e.state.playbackIntent, isFalse);
        e.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  test('A4 keepAlive play respects pause during queued hold', () {
    fakeAsync((clock) {
      final k = _GatedKernel();
      final e = _engine(k);
      e.open(_live);
      clock.flushMicrotasks();
      e.setKeepAlive(true);
      clock.flushMicrotasks();
      expect(e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      k.hasAudio = true;
      k.holdGate = Completer<void>();
      e.play();
      clock.flushMicrotasks();
      expect(k.calls, contains('enterKeepAlive:muted'));
      e.pause();
      k.holdGate!.complete();
      clock.flushMicrotasks();
      expect(k.calls.where((v) => v == 'play'), isEmpty);
      expect(e.state.playbackIntent, isFalse);
      expect(e.state.keepAlivePhase, MovaKeepAlivePhase.off);
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A5 terminal decoder error cancels scheduled retry', () {
    fakeAsync((clock) {
      final k = MovaTestKernel();
      final e = _engine(
        k,
        recovery: const MovaRecoveryConfig(
          enabled: true,
          policy: MovaRetryThenFailover(retryDelay: Duration(seconds: 2)),
        ),
      );
      final errors = <MovaErrorEvent>[];
      final failures = <MovaPlayFailure>[];
      e.events.listen((event) {
        if (event is MovaErrorEvent) errors.add(event);
        if (event is MovaPlayFailure) failures.add(event);
      });
      e.open(_vod);
      clock.flushMicrotasks();
      k.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      expect(failures.single.action, MovaRecoveryAction.retry);
      k.emitError('Failed to initialize a decoder.');
      clock.flushMicrotasks();
      expect(e.state.error, isNotNull);
      expect(errors.where((v) => v.fatal), hasLength(1));
      clock.elapse(const Duration(seconds: 3));
      expect(k.calls.where((v) => v == 'open'), hasLength(1));
      expect(k.calls.where((v) => v == 'play'), isEmpty);
      expect(e.state.error, isNotNull);
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A9 URL timeshift ticks preserve lag and relative seek coordinates', () {
    fakeAsync((clock) {
      final behinds = <Duration>[];
      final k = MovaTestKernel();
      final e = _engine(
        k,
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(minutes: 10),
          urlBuilder: (base, behind, now) {
            behinds.add(behind);
            return '$base?behind=${behind.inSeconds}';
          },
        ),
      );
      e.open(_live);
      clock.flushMicrotasks();
      e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, const Duration(minutes: 3));
      for (final seconds in [0, 1, 30]) {
        k.emitPosition(Duration(seconds: seconds));
        clock.flushMicrotasks();
        expect(e.state.timeshiftBehind, const Duration(minutes: 3));
        expect(e.progressValue.position, Duration(seconds: seconds));
      }
      e.seekBy(const Duration(seconds: 10));
      clock.flushMicrotasks();
      expect(behinds, [
        const Duration(seconds: 180),
        const Duration(seconds: 170),
      ]);
      k.emitPosition(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, const Duration(seconds: 170));
      e.backToLiveEdge();
      clock.flushMicrotasks();
      k.emitPosition(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, isNull);
      e.seekBy(const Duration(seconds: -20));
      clock.flushMicrotasks();
      expect(behinds.last, const Duration(seconds: 20));
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A9 URL timeshift adds paused time, preserves it on play and clears at edge', () {
    fakeAsync((clock) {
      final k = MovaTestKernel();
      final e = _engine(
        k,
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(minutes: 10),
          urlBuilder: (base, behind, now) => '$base?behind=${behind.inSeconds}',
        ),
      )..debugClock = () => DateTime.utc(2026).add(clock.elapsed);
      final changes = <Duration>[];
      e.events.listen((event) {
        if (event is MovaTimeShiftChange) {
          expect(event.behind, e.state.timeshiftBehind);
          changes.add(event.behind);
        }
      });
      e.open(_live);
      clock.flushMicrotasks();
      e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      k.emitPosition(const Duration(seconds: 10));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, const Duration(seconds: 180));

      e.pause();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 15));
      e.pause();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 15));
      expect(e.state.timeshiftBehind, const Duration(seconds: 210));
      expect(changes.last, const Duration(seconds: 210));
      expect(changes, hasLength(31));
      e.play();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 20));
      k.emitPosition(const Duration(seconds: 30));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, const Duration(seconds: 210));
      expect(changes, hasLength(31));

      e.pause();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      expect(e.state.timeshiftBehind, const Duration(seconds: 215));
      e.backToLiveEdge();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 30));
      k.emitPosition(const Duration(seconds: 1));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, isNull);
      expect(e.debugCurrentLoad!.timeshiftBehind, isNull);
      e.seekBy(const Duration(seconds: -20));
      clock.flushMicrotasks();
      expect(e.state.timeshiftBehind, const Duration(seconds: 20));
      e.dispose();
      clock.flushMicrotasks();
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('A9 URL timeshift seekBy includes ongoing pause and rebases its clock', () {
    fakeAsync((clock) {
      final behinds = <Duration>[];
      final k = MovaTestKernel();
      final e = _engine(
        k,
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(minutes: 10),
          urlBuilder: (base, behind, now) {
            expect(now, DateTime.utc(2026).add(clock.elapsed));
            behinds.add(behind);
            return '$base?behind=${behind.inSeconds}';
          },
        ),
      )..debugClock = () => DateTime.utc(2026).add(clock.elapsed);
      e.open(_live);
      clock.flushMicrotasks();
      e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      e.pause();
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 30500));
      e.seekBy(const Duration(seconds: 10));
      clock.flushMicrotasks();
      expect(behinds, [const Duration(seconds: 180), const Duration(seconds: 200)]);
      expect(e.state.timeshiftBehind, const Duration(seconds: 200));
      clock.elapse(const Duration(seconds: 10));
      expect(e.state.timeshiftBehind, const Duration(seconds: 210));
      e.play();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      expect(e.state.timeshiftBehind, const Duration(seconds: 210));
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A9 URL timeshift retry preserves accumulated pause without double counting', () {
    fakeAsync((clock) {
      final behinds = <Duration>[];
      final k = MovaTestKernel();
      final e = _engine(
        k,
        recovery: const MovaRecoveryConfig(
          enabled: true,
          policy: MovaRetryThenFailover(retryDelay: Duration(milliseconds: 10)),
        ),
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(minutes: 10),
          urlBuilder: (base, behind, now) {
            behinds.add(behind);
            return '$base?behind=${behind.inSeconds}';
          },
        ),
      )..debugClock = () => DateTime.utc(2026).add(clock.elapsed);
      e.open(_live);
      clock.flushMicrotasks();
      e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      e.pause();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 30));
      k.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 10));
      expect(behinds, [
        const Duration(seconds: 180),
        const Duration(milliseconds: 210010),
      ]);
      expect(e.state.timeshiftBehind, const Duration(seconds: 210));
      clock.elapse(const Duration(seconds: 10));
      expect(e.state.timeshiftBehind, const Duration(seconds: 220));
      e.play();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      expect(e.state.timeshiftBehind, const Duration(seconds: 220));
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  for (final orientation in MovaOrientation.values) {
    test('A12 fullscreen exit preserves $orientation orientation', () async {
      final port = _Orientation();
      final e = _engine(MovaTestKernel(), orientation: port);
      addTearDown(e.dispose);
      await e.setOrientation(orientation);
      await e.setFullscreen(true);
      await e.setFullscreen(false);
      expect(e.state.orientation, orientation);
      if (orientation == MovaOrientation.auto) {
        expect(port.resets, 1);
      } else {
        expect(port.resets, 0);
        expect(port.applied, orientation);
        expect(port.fullscreen, isFalse);
      }
    });
  }
}
