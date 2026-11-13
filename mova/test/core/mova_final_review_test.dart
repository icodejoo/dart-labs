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

  /// Failure injected after the seek gate completes.
  ///
  /// seek 闸门完成后注入的失败。
  Object? seekError;

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
    final error = seekError;
    await seekGate?.future;
    if (error != null) throw error;
  }

  /// Suspends a successful hold before returning to the player.
  ///
  /// 挂起成功的待机请求，再返回播放器。
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
class _Orient implements IMovaOrient {
  MovaOrientMode? applied;
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
    required MovaOrientMode orient,
  }) async {
    applied = orient;
    this.fullscreen = fullscreen;
  }

  /// Records a reset to host orientation preferences.
  ///
  /// 记录还原宿主方向设置。
  @override
  Future<void> reset() async => resets++;
}

/// Creates an isolated player without network probes or controls timers.
///
/// 创建无网络探测及控制条计时器的隔离播放器。
Mova _mova(
  MovaTestKernel kernel, {
  MovaLiveOpts live = const MovaLiveOpts(),
  MovaRecoveryOpts recovery = const MovaRecoveryOpts(),
  IMovaOrient? orient,
  IMovaVolume? volume,
  List<MovaHook> interceptors = const [],
}) => createMova(
  kernel: kernel,
  ownsKernel: true,
  interceptors: interceptors,
  volume: volume,
  pip: MovaNoopPip(),
  brightness: MovaFallbackBrightness(),
  orient: orient ?? MovaNoopOrient(),
  options: MovaOpts(
    controls: const MovaCtrlsOpts(autoHide: false),
    abr: const MovaAbrOpts(probeVariants: false),
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

/// Gates each seek independently and records pipeline diagnostics.
///
/// 分别控制每次 seek 的返回，并记录管线诊断。
class _SeekHook extends MovaHook {
  final requests = <Completer<Duration?>>[];
  final errors = <Object>[];

  /// Waits for the test to approve, rewrite or reject [target].
  ///
  /// 等待测试放行、改写或拒绝 [target]。
  @override
  Future<Duration?> beforeSeek(Duration target) {
    final gate = Completer<Duration?>();
    requests.add(gate);
    return gate.future;
  }

  /// Records an isolated pipeline error.
  ///
  /// 记录隔离后的管线错误。
  @override
  void onError(Object error, StackTrace stack) => errors.add(error);
}

/// Runs the final-review player regressions with controlled interleavings.
///
/// 用可控交错执行终审播放器回归测试。
void main() {
  for (final latest in [const Duration(seconds: 80), null]) {
    test('A7 latest hook result $latest supersedes an older seek', () async {
      final k = MovaTestKernel();
      final hook = _SeekHook();
      final e = _mova(k, interceptors: [hook]);
      addTearDown(e.dispose);
      await e.open(_vod);
      k.emitDuration(const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);
      final old = e.seek(const Duration(seconds: 20));
      final newer = e.seek(const Duration(seconds: 80));
      hook.requests[1].complete(latest);
      await newer;
      hook.requests[0].complete(const Duration(seconds: 20));
      await old;
      expect(k.calls.where((v) => v == 'seek'), hasLength(latest == null ? 0 : 1));
      expect(k.lastSeek, latest);
    });
  }

  test('A8 DVR live edge replaces pending seek and accepts edge progress', () {
    fakeAsync((clock) {
      final k = MovaTestKernel();
      final e = _mova(k, live: const MovaLiveOpts(
        seekMode: MovaLiveSeekMode.dvr,
        dvrWindow: Duration(minutes: 10),
        backToLive: MovaBackToLive.seekEnd,
      ));
      e.open(_live);
      clock.flushMicrotasks();
      e.seek(const Duration(seconds: 20));
      clock.flushMicrotasks();
      expect(k.lastSeek, const Duration(seconds: 20));
      e.backToLiveEdge();
      clock.flushMicrotasks();
      expect(k.lastSeek, const Duration(minutes: 10));
      expect(e.progressValue.position, const Duration(minutes: 10));
      k.emitPosition(const Duration(seconds: 600));
      clock.flushMicrotasks();
      k.emitPosition(const Duration(seconds: 601));
      clock.flushMicrotasks();
      expect(e.progressValue.position, const Duration(seconds: 601));
      e.dispose();
      clock.flushMicrotasks();
    });
  });

  test('A8 live edge supersedes an older pending seek hook', () async {
    final k = MovaTestKernel();
    final hook = _SeekHook();
    final e = _mova(k, interceptors: [hook], live: const MovaLiveOpts(
      seekMode: MovaLiveSeekMode.dvr,
      dvrWindow: Duration(minutes: 10),
      backToLive: MovaBackToLive.seekEnd,
    ));
    addTearDown(e.dispose);
    await e.open(_live);
    final old = e.seek(const Duration(seconds: 20));
    await e.backToLiveEdge();
    hook.requests.single.complete(const Duration(seconds: 20));
    await old;
    expect(k.calls.where((v) => v == 'seek'), hasLength(1));
    expect(k.lastSeek, const Duration(minutes: 10));
    expect(e.progressValue.position, const Duration(minutes: 10));
  });

  for (final parked in [true, false]) {
    test('A10 ${parked ? "parked" : "retry"} seek failure clears filtering and reports error', () {
      fakeAsync((clock) {
        final k = _GatedKernel();
        final hook = _SeekHook();
        final e = _mova(k, interceptors: [hook]);
        final errors = <MovaErrorEvent>[];
        e.events.listen((event) {
          if (event is MovaErrorEvent) errors.add(event);
        });
        e.open(_vod);
        clock.flushMicrotasks();
        if (!parked) {
          k.emitDuration(const Duration(minutes: 5));
          clock.flushMicrotasks();
        }
        e.seek(const Duration(seconds: 80));
        hook.requests.single.complete(const Duration(seconds: 80));
        clock.flushMicrotasks();
        final failure = StateError('seek failed');
        k.seekError = failure;
        if (parked) {
          k.emitDuration(const Duration(minutes: 5));
          clock.flushMicrotasks();
        } else {
          clock.elapse(e.debugResumeVerifyDelay);
        }
        expect(hook.errors, [same(failure)]);
        expect(errors.single.error, same(failure));
        expect(errors.single.fatal, isFalse);
        expect(e.state.error, isNull);
        k.emitPosition(const Duration(seconds: 12));
        clock.flushMicrotasks();
        expect(e.progressValue.position, const Duration(seconds: 12));
        final seeks = k.calls.where((v) => v == 'seek').length;
        clock.elapse(const Duration(seconds: 6));
        expect(k.calls.where((v) => v == 'seek'), hasLength(seeks));
        e.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  for (final supersede in ['seek', 'open', 'dispose']) {
    test('A10 stale internal seek failure after $supersede is ignored', () {
      fakeAsync((clock) {
        final k = _GatedKernel();
        final hook = _SeekHook();
        final e = _mova(k, interceptors: [hook]);
        final errors = <MovaErrorEvent>[];
        e.events.listen((event) {
          if (event is MovaErrorEvent) errors.add(event);
        });
        e.open(_vod);
        clock.flushMicrotasks();
        e.seek(const Duration(seconds: 20));
        hook.requests.single.complete(const Duration(seconds: 20));
        clock.flushMicrotasks();
        final oldGate = Completer<void>();
        k.seekGate = oldGate;
        k.seekError = StateError('old seek failed');
        k.emitDuration(const Duration(minutes: 5));
        clock.flushMicrotasks();
        k.seekGate = null;
        k.seekError = null;
        if (supersede == 'seek') {
          e.seek(const Duration(seconds: 80));
          hook.requests.last.complete(const Duration(seconds: 80));
        } else if (supersede == 'open') {
          e.open(const MovaSource('https://h/next.mp4'));
        } else {
          e.dispose();
        }
        clock.flushMicrotasks();
        oldGate.complete();
        clock.flushMicrotasks();
        expect(hook.errors, isEmpty);
        expect(errors, isEmpty);
        if (supersede == 'seek') {
          k.emitPosition(const Duration(seconds: 20));
          clock.flushMicrotasks();
          expect(e.progressValue.position, const Duration(seconds: 80));
          k.emitPosition(const Duration(seconds: 80));
          clock.flushMicrotasks();
        }
        e.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  for (final touched in [false, true]) {
    test('A13 initial volume read ${touched ? "cannot overwrite a write" : "seeds untouched state"}', () async {
      final initial = Completer<double>();
      double? written;
      final e = _mova(MovaTestKernel(), volume: MovaCallbackVolume(
        (value) => written = value,
        onGet: () => initial.future,
      ));
      addTearDown(e.dispose);
      if (touched) await e.setVolume(20);
      initial.complete(60);
      await Future<void>.delayed(Duration.zero);
      expect(e.state.volume, touched ? 20 : 60);
      expect(written, touched ? 20 : isNull);
    });
  }

  test('A14 downshift stops at the lowest video variant before audio', () async {
    final k = MovaTestKernel();
    final e = _mova(k);
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
      final e = _mova(k);
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
        final e = _mova(k);
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
        final e = _mova(k, interceptors: [hook]);
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
        final e = _mova(k);
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
      final e = _mova(k);
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
      final e = _mova(
        k,
        recovery: const MovaRecoveryOpts(
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
      final e = _mova(
        k,
        live: MovaLiveOpts(
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
      final e = _mova(
        k,
        live: MovaLiveOpts(
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
      final e = _mova(
        k,
        live: MovaLiveOpts(
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
      final e = _mova(
        k,
        recovery: const MovaRecoveryOpts(
          enabled: true,
          policy: MovaRetryThenFailover(retryDelay: Duration(milliseconds: 10)),
        ),
        live: MovaLiveOpts(
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

  for (final orient in MovaOrientMode.values) {
    test('A12 fullscreen exit preserves $orient orientation', () async {
      final port = _Orient();
      final e = _mova(MovaTestKernel(), orient: port);
      addTearDown(e.dispose);
      await e.setOrient(orient);
      await e.setFullscreen(true);
      await e.setFullscreen(false);
      expect(e.state.orient, orient);
      if (orient == MovaOrientMode.auto) {
        expect(port.resets, 1);
      } else {
        expect(port.resets, 0);
        expect(port.applied, orient);
        expect(port.fullscreen, isFalse);
      }
    });
  }
}
