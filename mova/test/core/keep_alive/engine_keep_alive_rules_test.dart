import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';

import '../../support/fake_kernel.dart';
import '../../support/keep_alive_rig.dart';

const _unknown = MovaKeepAliveMedia(audio: MovaAudioPresence.unknown, format: 'flv');
const _present = MovaKeepAliveMedia(audio: MovaAudioPresence.present, format: 'flv');
const _silent = MovaKeepAliveMedia(audio: MovaAudioPresence.absent, format: 'flv');
const _liveB = MovaSource('https://h/b.flv', type: MovaStreamType.live);
const _high = MovaQuality(label: '720p', uri: 'https://h/720.m3u8', height: 720);
const _low = MovaQuality(label: '480p', uri: 'https://h/480.m3u8', height: 480);

/// Puts a rig into a live hold with the first frame landed.
///
/// 让夹具进入"首帧已落地的直播待机"。
void _hold(KeepAliveRig r) {
  r.playLive();
  r.land();
  r.keepAlive(true);
}

void main() {
  test('1. pause() out of a hold stops first, restores second, clears the request', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      k.calls.clear();
      r.engine.pause();
      r.settle();
      expect(k.calls, ['pause', 'exitKeepAlive']);
      expect(r.trail.last, 'off/paused');
      expect(r.engine.state.playbackIntent, isFalse);
      k.calls.clear();
      r.engine.play();
      r.settle();
      expect(k.calls, ['play'], reason: 'the request is gone, so play() takes the plain path');
    });
  });

  test('2. pause() on an engine that never used keepAlive is a single kernel pause', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      k.calls.clear();
      r.engine.pause();
      r.settle();
      expect(k.calls, ['pause']);
      expect(r.changes, isEmpty);
    });
  });

  test('3. play() while holding changes nothing: it is already playing, silently', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      k.calls.clear();
      r.engine.play();
      r.settle();
      expect(k.calls, isNot(contains('play')));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
    });
  });

  test('4. play() in a fallback retries the hold: succeeds once the media is known, stays paused otherwise', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = _unknown;
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      k.media = _present;
      k.calls.clear();
      r.engine.play();
      r.settle();
      expect(k.calls.indexOf('enterKeepAlive:muted'), isNonNegative);
      expect(k.calls.indexOf('enterKeepAlive:muted'), lessThan(k.calls.lastIndexOf('play')));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);

      final k2 = FakeKeepAliveKernel()..media = _unknown;
      final r2 = KeepAliveRig(async, k2)..playLive();
      r2.keepAlive(true);
      k2.calls.clear();
      r2.engine.play();
      r2.settle();
      expect(k2.calls, isNot(contains('play')));
      expect(r2.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      expect(r2.changes, hasLength(1), reason: 'no repeated event');
    });
  });

  test('5. a new source during a hold restores first, loads paused, and is held again once it shows a frame', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      k.calls.clear();
      r.engine.open(_liveB);
      r.settle();
      expect(k.calls.indexOf('exitKeepAlive'), lessThan(k.calls.indexOf('open')));
      expect(k.lastPlay, isFalse);
      expect(r.trail.last, 'fallback/reloaded');
      final frames = r.events.whereType<MovaFirstFrame>().length;
      k.emitSize(1280, 720);
      r.settle();
      expect(r.events.whereType<MovaFirstFrame>().length, frames + 1);
      expect(k.calls, containsAllInOrder(['enterKeepAlive:muted', 'play']));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
    });
  });

  test('6. a reloaded source that cannot be held stays paused', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k, keepAlive: const MovaKeepAliveConfig(silentStreams: MovaSilentKeepAlive.pause));
      _hold(r);
      k.media = _silent;
      k.calls.clear();
      r.engine.reload();
      r.settle();
      k.emitSize(1280, 720);
      r.settle();
      expect(k.calls, isNot(contains('play')));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
    });
  });

  test('7. entering the mini window wakes the hold first', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      r.engine.setMini(true);
      r.settle();
      expect(r.trail, contains('resuming/woke'));
      expect(r.engine.state.mini, isTrue);
    });
  });

  test('8. entering system PiP wakes the hold first', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k, pip: YesPip());
      _hold(r);
      r.engine.enterPip();
      r.settle();
      expect(r.trail, contains('resuming/woke'));
      expect(r.engine.state.pip, isTrue);
    });
  });

  test('9. seeking and going back to the edge keep the hold, load playing, and never time out', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(
        async,
        k,
        options: const MovaOpts(
          live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr, backToLive: MovaBackToLive.reopen),
        ),
        recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true),
      );
      r.playLive();
      k.emitDuration(const Duration(seconds: 300));
      r.land();
      r.keepAlive(true);
      expect(r.engine.state.liveSeekable, isTrue);
      k.calls.clear();
      r.engine.seek(const Duration(seconds: 100));
      r.settle();
      expect(k.calls, contains('seek'));
      r.engine.backToLiveEdge();
      r.settle();
      expect(k.calls, isNot(contains('exitKeepAlive')));
      expect(k.calls.where((c) => c == 'open'), hasLength(1));
      expect(k.lastPlay, isTrue);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
      async.elapse(const Duration(seconds: 12));
      r.settle();
      expect(r.events.whereType<MovaPlayFailure>(), isEmpty);
    });
  });

  test('10. in a fallback, edge and quality reloads stay paused; the wake then plays', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      async.elapse(const Duration(seconds: 30));
      r.settle();
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      r.engine.backToLiveEdge();
      r.settle();
      expect(k.lastPlay, isFalse);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      r.engine.debugSetQualities(const [_high, _low], current: _high);
      r.engine.switchQuality(_low);
      r.settle();
      expect(k.lastUri, _low.uri);
      expect(k.lastPlay, isFalse);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      r.keepAlive(false);
      expect(k.lastPlay, isTrue);
    });
  });

  test('11. while holding, buffering feeds neither ABR nor the automatic return to the edge', () {
    fakeAsync((async) {
      void stall(FakeKernel k) {
        for (var i = 0; i < 4; i++) {
          k.emitBuffering(true);
          k.emitBuffering(false);
        }
      }

      // Control: the same stalls outside keepAlive do trigger a downshift.
      final kc = FakeKeepAliveKernel();
      final rc = KeepAliveRig(async, kc, options: const MovaOpts(abr: MovaAbrConfig(stallThreshold: 2)))..playLive();
      rc.engine.debugSetQualities(const [_high, _low], current: _high);
      stall(kc);
      rc.settle();
      expect(rc.events.whereType<MovaAbrDownShift>(), isNotEmpty);

      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(
        async,
        k,
        options: const MovaOpts(
          abr: MovaAbrConfig(stallThreshold: 2),
          live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr, autoBackToLiveOnStall: true),
        ),
      )..playLive();
      k.emitDuration(const Duration(seconds: 300));
      // Two rising positions land the first frame without a buffering edge,
      // which would itself trigger the automatic return to the edge.
      //
      // 两个递增位置让首帧落地，不产生 buffering 边沿（那本身会触发自动回边缘）。
      k.emitPosition(const Duration(seconds: 100));
      k.emitPosition(const Duration(seconds: 101));
      r.settle();
      r.engine.debugSetQualities(const [_high, _low], current: _high);
      r.keepAlive(true);
      expect(r.engine.state.timeshiftBehind, isNotNull);
      final opens = k.openedUris.length;
      k.calls.clear();
      stall(k);
      r.settle();
      expect(r.events.whereType<MovaAbrDownShift>(), isEmpty);
      expect(k.openedUris.length, opens);
      expect(k.calls, isNot(contains('seek')));
    });
  });

  test('12. a native error while holding degrades quietly and the wake reopens at once', () {
    fakeAsync((async) {
      final k = FakeKeepAliveStatsKernel();
      final r = KeepAliveRig(async, k, recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true));
      _hold(r);
      k.calls.clear();
      k.emitEndFile(MovaEndFileReason.error);
      r.settle();
      expect(r.events.whereType<MovaPlayFailure>(), isEmpty);
      expect(k.calls, ['pause', 'exitKeepAlive']);
      expect(r.trail.last, 'fallback/failed');
      final opens = k.openedUris.length;
      r.keepAlive(false);
      expect(k.openedUris.length, opens + 1);
      expect(k.openedUris.last, 'https://h/a.flv');
    });
  });

  test('13. a native error during a fallback is remembered, so even a quick wake reopens', () {
    fakeAsync((async) {
      final k = FakeKeepAliveStatsKernel()..media = _unknown;
      final r = KeepAliveRig(async, k, recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true))..playLive();
      r.land();
      r.keepAlive(true);
      final opens = k.openedUris.length;
      k.emitEndFile(MovaEndFileReason.error);
      r.settle();
      expect(r.events.whereType<MovaPlayFailure>(), isEmpty);
      expect(k.openedUris.length, opens);
      async.elapse(const Duration(seconds: 1));
      r.keepAlive(false);
      expect(k.openedUris.length, opens + 1);
    });
  });

  test('14. with recovery off, a live stream ending during a hold still announces the end and falls back as ended', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      k.emitCompleted(true);
      r.settle();
      expect(r.events.whereType<MovaDone>(), hasLength(1));
      expect(r.trail.last, 'fallback/ended');
    });
  });

  test('15. changing the volume during a hold leaves it alone', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k);
      _hold(r);
      k.calls.clear();
      r.engine.setVolume(50);
      r.settle();
      expect(k.calls, contains('setVolume'));
      expect(k.calls, isNot(contains('exitKeepAlive')));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
      expect(r.engine.state.volume, 50);
    });
  });
}
