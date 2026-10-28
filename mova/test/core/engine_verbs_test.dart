import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/preview/fetcher.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/core/state/ui_state.dart';

import '../support/fake_kernel.dart';

/// A VOD address shared by every case.
///
/// 各用例共用的点播地址。
const _vodUri = 'https://host/a.mp4';

/// A live address shared by the live cases.
///
/// 直播用例共用的直播地址。
const _liveUri = 'https://host/live.m3u8';

/// The VOD source every case opens.
///
/// 各用例打开的点播源。
const _vod = MovaSource(_vodUri);

/// Lets pending stream deliveries and microtasks run.
///
/// 让挂起的流投递与微任务跑完。
Future<void> _flush() => Future<void>.delayed(Duration.zero);

/// An orientation port that records every `apply`/`reset` it receives.
///
/// 记录每次 `apply`/`reset` 的方向端口。
class _SpyOrientation implements MovaOrientationPort {
  /// The `fullscreen` flag of each `apply`, in call order.
  ///
  /// 每次 `apply` 的 `fullscreen` 标志，按调用顺序。
  final List<bool> applied = <bool>[];

  /// How many times `reset` ran.
  ///
  /// `reset` 被调用的次数。
  int resets = 0;

  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrientation orientation,
  }) async {
    applied.add(fullscreen);
  }

  @override
  Future<void> reset() async {
    resets++;
  }
}

/// A master playlist with two variants.
///
/// 带两档的 master 列表。
const _master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1920x1080
1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720
720.m3u8
''';

/// A fetcher that always answers with [_master].
///
/// 总是返回 [_master] 的拉取器。
class _MasterFetch implements MovaHttpFetch {
  @override
  Future<Uint8List?> get(Uri url) async => Uint8List.fromList(utf8.encode(_master));

  @override
  Future<void> close() async {}
}

/// Opens [_vod] on [e] and gives it a known duration, so seeks go straight to
/// the kernel instead of parking.
///
/// 在 [e] 上打开 [_vod] 并给出已知时长，使 seek 直达内核而不是寄存。
Future<void> _openWithDuration(
  MovaEngine e,
  FakeKernel k,
  Duration duration,
) async {
  await e.open(_vod);
  k.emitDuration(duration);
  await _flush();
}

void main() {
  late FakeKernel k;
  late MovaEngine e;
  late List<MovaEvent> events;

  setUp(() {
    k = FakeKernel();
    e = MovaEngine(kernel: k);
    events = <MovaEvent>[];
    e.events.listen(events.add);
  });

  tearDown(() => e.dispose());

  group('A6 play / pause / playOrPause', () {
    test('kernel playing edges become MovaPlay / MovaPause and state.playing', () async {
      k.emitPlaying(true);
      await _flush();
      expect(e.state.playing, isTrue);
      k.emitPlaying(false);
      await _flush();
      expect(e.state.playing, isFalse);
      expect(
        events.where((x) => x is MovaPlay || x is MovaPause).map((x) => x.runtimeType),
        [MovaPlay, MovaPause],
      );
    });

    test('kernel completed=true emits exactly one MovaDone and sets state.completed', () async {
      k.emitCompleted(true);
      await _flush();
      expect(e.state.completed, isTrue);
      expect(events.whereType<MovaDone>(), hasLength(1));
      // The flag going back to false is not another "done".
      // 标志回落为 false 不算再次"完播"。
      k.emitCompleted(false);
      await _flush();
      expect(e.state.completed, isFalse);
      expect(events.whereType<MovaDone>(), hasLength(1));
    });

    test('play() / pause() drive playbackIntent independently of kernel.playing', () async {
      await e.open(_vod, autoPlay: false);
      expect(e.state.playbackIntent, isFalse);
      await e.play();
      expect(e.state.playbackIntent, isTrue);
      expect(k.calls.last, 'play');
      // The kernel never confirmed anything: playing stays false, intent is ours.
      // 内核没有任何确认：playing 仍为 false，意图归我们。
      expect(e.state.playing, isFalse);
      await e.pause();
      expect(e.state.playbackIntent, isFalse);
      expect(k.calls.last, 'pause');
    });

    test('pause() twice is safe and keeps the intent false', () async {
      await e.open(_vod);
      await e.pause();
      await expectLater(e.pause(), completes);
      expect(e.state.playbackIntent, isFalse);
    });

    test('play() twice is safe and keeps the intent true', () async {
      await e.open(_vod, autoPlay: false);
      await e.play();
      await expectLater(e.play(), completes);
      expect(e.state.playbackIntent, isTrue);
    });

    test('playOrPause() pauses when state.playing, plays otherwise', () async {
      await e.open(_vod, autoPlay: false);
      k.calls.clear();
      await e.playOrPause();
      expect(k.calls, ['play']);
      k.emitPlaying(true);
      await _flush();
      k.calls.clear();
      await e.playOrPause();
      expect(k.calls, ['pause']);
    });

    test('a kernel-side pause (e.g. audio focus loss) leaves playbackIntent true', () async {
      await e.open(_vod);
      expect(e.state.playbackIntent, isTrue);
      k.emitPlaying(true);
      k.emitPlaying(false);
      await _flush();
      expect(e.state.playing, isFalse);
      expect(events.whereType<MovaPause>(), hasLength(1));
      expect(e.state.playbackIntent, isTrue);
    });
  });

  group('A13 setLocked', () {
    test('flips state.locked and emits one MovaLockChange per call', () async {
      await e.setLocked(true);
      expect(e.state.locked, isTrue);
      await e.setLocked(false);
      expect(e.state.locked, isFalse);
      await _flush();
      expect(events.whereType<MovaLockChange>().map((x) => x.value), [true, false]);
    });
  });

  group('A7 seek / seekBy', () {
    test('a known duration clamps a negative seek to zero', () async {
      await _openWithDuration(e, k, const Duration(minutes: 10));
      await e.seek(const Duration(seconds: -5));
      expect(k.lastSeek, Duration.zero);
    });

    test('a known duration clamps an over-long seek to the duration', () async {
      await _openWithDuration(e, k, const Duration(minutes: 10));
      await e.seek(const Duration(minutes: 20));
      expect(k.lastSeek, const Duration(minutes: 10));
    });

    test('seek emits MovaSeek then MovaSeeked with the clamped target', () async {
      await _openWithDuration(e, k, const Duration(minutes: 10));
      await e.seek(const Duration(seconds: 120));
      await _flush();
      final seeks = events.where((x) => x is MovaSeek || x is MovaSeeked).toList();
      expect(seeks.map((x) => x.runtimeType), [MovaSeek, MovaSeeked]);
      expect((seeks[0] as MovaSeek).target, const Duration(seconds: 120));
      expect((seeks[1] as MovaSeeked).position, const Duration(seconds: 120));
    });

    test('the event payloads carry the clamped value, not the requested one', () async {
      await _openWithDuration(e, k, const Duration(minutes: 1));
      await e.seek(const Duration(minutes: 5));
      await _flush();
      expect(events.whereType<MovaSeek>().single.target, const Duration(minutes: 1));
      expect(events.whereType<MovaSeeked>().single.position, const Duration(minutes: 1));
    });

    test('seekBy offsets from the last reported position, with the same clamping', () async {
      await _openWithDuration(e, k, const Duration(minutes: 10));
      k.emitPosition(const Duration(seconds: 30));
      await _flush();
      await e.seekBy(const Duration(seconds: 15));
      expect(k.lastSeek, const Duration(seconds: 45));
      // The optimistic position now stands in for the kernel's own report.
      // 乐观位置此刻顶替内核自己的上报。
      await e.seekBy(const Duration(seconds: -100));
      expect(k.lastSeek, Duration.zero);
      await e.seekBy(const Duration(hours: 5));
      expect(k.lastSeek, const Duration(minutes: 10));
    });

    test('before the duration is known the seek only announces MovaSeek, '
        'MovaSeeked arrives with the replay', () async {
      await e.open(_vod);
      k.calls.clear();
      await e.seek(const Duration(seconds: 30));
      await _flush();
      expect(k.calls, isEmpty);
      expect(events.whereType<MovaSeek>().single.target, const Duration(seconds: 30));
      expect(events.whereType<MovaSeeked>(), isEmpty);
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      expect(k.lastSeek, const Duration(seconds: 30));
      expect(events.whereType<MovaSeeked>().single.position, const Duration(seconds: 30));
    });

    test('a parked seek past the eventual end reports the clamped MovaSeeked', () async {
      await e.open(_vod);
      await e.seek(const Duration(seconds: 600));
      k.emitDuration(const Duration(seconds: 120));
      await _flush();
      expect(events.whereType<MovaSeeked>().single.position, const Duration(seconds: 120));
    });

    test('seek is ignored for a live source with seeking off, and emits nothing', () async {
      await e.open(const MovaSource(_liveUri, type: MovaStreamType.live));
      events.clear();
      await e.seek(const Duration(seconds: 5));
      await _flush();
      expect(events.whereType<MovaSeek>(), isEmpty);
      expect(events.whereType<MovaSeeked>(), isEmpty);
    });

    // A negative seek parked before the duration is known used to be reported as
    // a negative position and replayed to the kernel as is.
    // 时长未知时被寄存的负向 seek，曾先上报负进度、再把负数原样下发给内核。
    test('a negative seek parked before the duration is known is clamped to zero', () async {
      await e.open(_vod);
      final seen = <Duration>[];
      e.progress.listen((p) => seen.add(p.position));
      await e.seek(const Duration(seconds: -5));
      await _flush();
      expect(seen, isNotEmpty);
      expect(seen.every((p) => p >= Duration.zero), isTrue, reason: 'progress never goes negative');
      expect(events.whereType<MovaSeek>().single.target, Duration.zero);
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      expect(k.lastSeek, Duration.zero);
      expect(events.whereType<MovaSeeked>().single.position, Duration.zero);
    });

    test('seekBy that lands below zero before the duration is known is clamped too', () async {
      await e.open(_vod);
      await e.seekBy(const Duration(seconds: -5));
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      expect(k.lastSeek, Duration.zero);
    });

    test('a negative seek with a known duration still lands on zero', () async {
      await e.open(_vod);
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      await e.seek(const Duration(seconds: -5));
      expect(k.lastSeek, Duration.zero);
    });
  });

  group('A11 / A12 / A14 verbs and their events', () {
    test('setFit stores the mode and emits one MovaFitChange', () async {
      await e.setFit(MovaFit.cover);
      expect(e.state.fit, MovaFit.cover);
      await _flush();
      expect(events.whereType<MovaFitChange>().map((x) => x.fit), [MovaFit.cover]);
    });

    test('setZoom emits MovaZoomChange with the stored (clamped) value', () async {
      await e.setZoom(2.5);
      await e.setZoom(0.2);
      await _flush();
      expect(events.whereType<MovaZoomChange>().map((x) => x.zoom), [2.5, 1.0]);
      expect(e.state.zoom, 1.0);
    });

    test('setFullscreen(true) then (false) restores state and re-applies the orientation port', () async {
      final spy = _SpyOrientation();
      final e2 = MovaEngine(kernel: k, orientation: spy);
      final seen = <MovaEvent>[];
      e2.events.listen(seen.add);
      await e2.setFullscreen(true);
      expect(e2.state.fullscreen, isTrue);
      await e2.setFullscreen(false);
      expect(e2.state.fullscreen, isFalse);
      await _flush();
      expect(seen.whereType<MovaFullScreenChange>().map((x) => x.value), [true, false]);
      expect(spy.applied, [true, false]);
      await e2.dispose();
    });

    test('a kernel size report becomes one MovaSizeChange and updates state', () async {
      k.emitSize(1920, 1080);
      await _flush();
      final sizes = events.whereType<MovaSizeChange>().toList();
      expect(sizes, hasLength(1));
      expect((sizes.single.width, sizes.single.height), (1920, 1080));
      expect((e.state.width, e.state.height), (1920, 1080));
    });

    test('a normal open() announces exactly one MovaReady', () async {
      await e.open(_vod);
      await _flush();
      expect(events.whereType<MovaReady>(), hasLength(1));
    });
  });

  group('A17 loadQualities', () {
    test('success emits one MovaQualityListChange that matches state.qualities, then the current variant', () async {
      final e2 = MovaEngine(kernel: k, fetcher: _MasterFetch());
      final seen = <MovaEvent>[];
      e2.events.listen(seen.add);
      await e2.open(const MovaSource('https://host/master.m3u8'));
      await e2.loadQualities();
      await _flush();
      final lists = seen.whereType<MovaQualityListChange>().toList();
      expect(lists, hasLength(1));
      expect(lists.single.qualities, e2.state.qualities);
      expect(lists.single.qualities.map((q) => q.label), ['自动', '1080p', '720p']);
      expect(seen.whereType<MovaQualityChange>().single.quality, e2.state.currentQuality);
      // The list is announced before the current pick.
      // 先宣布档位表，再宣布当前选择。
      expect(
        seen.indexWhere((x) => x is MovaQualityListChange),
        lessThan(seen.indexWhere((x) => x is MovaQualityChange)),
      );
      await e2.dispose();
    });

    test('a source that is not an m3u8 clears the list and announces nothing', () async {
      await e.open(_vod);
      events.clear();
      await e.loadQualities();
      await _flush();
      expect(e.state.qualities, isEmpty);
      expect(events.whereType<MovaQualityListChange>(), isEmpty);
    });
  });

  group('A19 reload', () {
    test('reopens the current source with the standing play intent', () async {
      await e.open(_vod);
      k.calls.clear();
      await e.reload();
      expect(k.openedUris, [_vodUri, _vodUri]);
      expect(k.lastPlay, isTrue);
    });

    test('after a pause() it reopens paused', () async {
      await e.open(_vod);
      await e.pause();
      await e.reload();
      expect(k.lastPlay, isFalse);
    });

    test('with nothing opened it is a no-op', () async {
      await expectLater(e.reload(), completes);
      expect(k.calls, isEmpty);
      expect(events, isEmpty);
    });
  });

  group('A21 controls and HUD timers', () {
    /// Runs [body] inside fakeAsync over a fresh engine with [controls].
    ///
    /// 在 fakeAsync 里用 [controls] 配置的新引擎执行 [body]。
    void withEngine(MovaCtrlsConfig controls, void Function(MovaEngine e, FakeAsync async) body) {
      fakeAsync((async) {
        final e2 = MovaEngine(kernel: FakeKernel(), options: MovaOpts(controls: controls));
        body(e2, async);
        unawaited(e2.dispose());
        async.flushMicrotasks();
      });
    }

    const delay = Duration(seconds: 3);
    const cfg = MovaCtrlsConfig(autoHide: true, autoHideDelay: delay);

    test('showControls() hides again after autoHideDelay', () {
      withEngine(cfg, (e2, async) {
        e2.hideControls();
        e2.showControls();
        expect(e2.uiState.controlsVisible, isTrue);
        async.elapse(delay - const Duration(milliseconds: 1));
        expect(e2.uiState.controlsVisible, isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(e2.uiState.controlsVisible, isFalse);
      });
    });

    test('showControls(sticky: true) never arms the timer', () {
      withEngine(cfg, (e2, async) {
        e2.hideControls();
        e2.showControls(sticky: true);
        async.elapse(delay * 10);
        expect(e2.uiState.controlsVisible, isTrue);
      });
    });

    test('a sticky show cancels a timer armed by an earlier plain show', () {
      withEngine(cfg, (e2, async) {
        e2.showControls();
        async.elapse(const Duration(seconds: 2));
        e2.showControls(sticky: true);
        async.elapse(delay * 10);
        expect(e2.uiState.controlsVisible, isTrue);
      });
    });

    test('repeated showControls() restarts the countdown', () {
      withEngine(cfg, (e2, async) {
        e2.showControls();
        async.elapse(const Duration(seconds: 2));
        e2.showControls();
        async.elapse(const Duration(seconds: 2));
        expect(e2.uiState.controlsVisible, isTrue, reason: '2s after the second show');
        async.elapse(const Duration(seconds: 1));
        expect(e2.uiState.controlsVisible, isFalse);
      });
    });

    test('autoHide: false keeps the bar visible however long it sits', () {
      withEngine(const MovaCtrlsConfig(autoHide: false, autoHideDelay: delay), (e2, async) {
        e2.showControls();
        async.elapse(delay * 10);
        expect(e2.uiState.controlsVisible, isTrue);
      });
    });

    test('hideControls() cancels a pending auto-hide and hides at once', () {
      withEngine(cfg, (e2, async) {
        e2.showControls();
        e2.hideControls();
        expect(e2.uiState.controlsVisible, isFalse);
        e2.showControls(sticky: true);
        async.elapse(delay * 2);
        expect(e2.uiState.controlsVisible, isTrue, reason: 'the cancelled timer must not fire');
      });
    });

    test('showHud clears itself (and hudText) after 800ms', () {
      withEngine(cfg, (e2, async) {
        e2.showHud(MovaHud.seek, text: '00:20');
        async.elapse(const Duration(milliseconds: 799));
        expect(e2.uiState.hud, MovaHud.seek);
        expect(e2.uiState.hudText, '00:20');
        async.elapse(const Duration(milliseconds: 1));
        expect(e2.uiState.hud, MovaHud.none);
        expect(e2.uiState.hudText, isNull);
      });
    });

    test('a second showHud restarts the 800ms window', () {
      withEngine(cfg, (e2, async) {
        e2.showHud(MovaHud.volume);
        async.elapse(const Duration(milliseconds: 500));
        e2.showHud(MovaHud.brightness);
        async.elapse(const Duration(milliseconds: 500));
        expect(e2.uiState.hud, MovaHud.brightness);
        async.elapse(const Duration(milliseconds: 300));
        expect(e2.uiState.hud, MovaHud.none);
      });
    });
  });

  group('G3.5 reopening a different stream type starts clean', () {
    test('live (seekable, timeshifted) then VOD drops every live-only field', () async {
      final e2 = MovaEngine(
        kernel: k,
        options: const MovaOpts(live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr)),
      );
      await e2.open(const MovaSource(_liveUri, type: MovaStreamType.live));
      k.emitDuration(const Duration(seconds: 60));
      await _flush();
      k.emitPosition(const Duration(seconds: 10));
      await _flush();
      expect(e2.state.liveSeekable, isTrue);
      expect(e2.state.seekableWindow, const Duration(seconds: 60));
      expect(e2.state.timeshiftBehind, isNotNull);

      await e2.open(_vod);
      await _flush();
      expect(e2.state.type, MovaStreamType.vod);
      expect(e2.state.liveSeekable, isFalse);
      expect(e2.state.seekableWindow, Duration.zero);
      expect(e2.state.timeshiftBehind, isNull);
      expect(e2.state.duration, Duration.zero);
      await e2.dispose();
    });

    test('VOD then live starts live with an empty duration baseline', () async {
      await e.open(_vod);
      k.emitDuration(const Duration(minutes: 5));
      await _flush();
      await e.open(const MovaSource(_liveUri, type: MovaStreamType.live));
      await _flush();
      expect(e.state.type, MovaStreamType.live);
      expect(e.state.duration, Duration.zero);
      expect(e.state.liveSeekable, isFalse);
      expect(e.state.timeshiftBehind, isNull);
    });
  });
}
