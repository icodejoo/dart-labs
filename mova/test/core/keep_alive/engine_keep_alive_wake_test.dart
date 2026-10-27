import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';

import '../../support/fake_kernel.dart';
import '../../support/keep_alive_rig.dart';

const _unknown = MovaKeepAliveMedia(audio: MovaAudioPresence.unknown, format: 'flv');
const _silent = MovaKeepAliveMedia(audio: MovaAudioPresence.absent, format: 'flv');

/// Just the keepAlive change/resume events, as compact strings.
///
/// 只保留待机的变化/恢复事件，转成紧凑字符串。
List<String> _sequence(KeepAliveRig r) => r.events
    .where((e) => e is MovaKeepAliveChange || e is MovaKeepAliveResume)
    .map((e) => e is MovaKeepAliveChange ? '${e.phase.name}/${e.reason.name}' : 'RESUME')
    .toList();

void main() {
  test('1. waking a muted hold waits for a fresh size, then reports one resume and no first frame', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.land();
      expect(r.engine.state.rendered, isTrue);
      final firstFrames = r.events.whereType<MovaFirstFrame>().length;
      r.keepAlive(true);
      expect(r.keepAlive(false), MovaKeepAlivePhase.resuming);
      expect(k.calls.last, 'exitKeepAlive');
      k.emitSize(1280, 720);
      r.settle();
      expect(r.resumes, hasLength(1));
      expect(r.resumes.single.signal, MovaFirstFrameSignal.size);
      expect(r.resumes.single.from, MovaKeepAliveMode.muted);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.off);
      expect(_sequence(r), ['holding/requested', 'resuming/woke', 'RESUME', 'off/resumed']);
      expect(r.changes[1].mode, MovaKeepAliveMode.muted);
      expect(r.events.whereType<MovaFirstFrame>().length, firstFrames);
      expect(r.engine.state.rendered, isTrue);
    });
  });

  test('2. a hold whose video never stopped resumes at once with no signal', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..exitRestartsVideo = false;
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      expect(r.keepAlive(false), MovaKeepAlivePhase.off);
      expect(r.resumes.single.signal, isNull);
      expect(r.resumes.single.from, MovaKeepAliveMode.muted);
    });
  });

  test('3. decodeOnly wakes straight to off without arming the gate', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = _silent;
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      expect(r.keepAlive(false), MovaKeepAlivePhase.off);
      expect(r.resumes.single.signal, isNull);
      expect(r.resumes.single.from, MovaKeepAliveMode.decodeOnly);
      k.emitSize(1280, 720);
      r.settle();
      expect(r.resumes, hasLength(1));
    });
  });

  test('4. with the native signal live, a restart lands the resume and no grace leftover follows', () {
    fakeAsync((async) {
      final k = FakeKeepAliveStatsKernel()..nativeRestartAvailable = true;
      final r = KeepAliveRig(async, k)..playLive();
      k.emitRestart();
      r.settle();
      r.keepAlive(true);
      r.keepAlive(false);
      k.emitRestart();
      r.settle();
      expect(r.resumes.single.signal, MovaFirstFrameSignal.restart);
      final count = r.events.length;
      async.elapse(const Duration(milliseconds: 1500));
      r.settle();
      expect(r.events.length, count);
    });
  });

  test('5. positions alone never land a resume; resumeTimeout ends it with grace and the timeout as elapsed', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      r.keepAlive(false);
      for (final ms in [0, 40, 80, 120]) {
        k.emitPosition(Duration(milliseconds: ms));
      }
      r.settle();
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.resuming);
      async.elapse(const Duration(seconds: 5));
      r.settle();
      expect(r.resumes.single.signal, MovaFirstFrameSignal.grace);
      expect(r.resumes.single.elapsed, const Duration(seconds: 5));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.off);
      k.emitSize(1280, 720);
      r.settle();
      expect(r.resumes, hasLength(1));
    });
  });

  test('6. a hold that timed out wakes by going back to the live edge', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.land();
      r.keepAlive(true);
      async.elapse(const Duration(seconds: 30));
      r.settle();
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      final opens = k.openedUris.length;
      r.keepAlive(false);
      expect(k.openedUris.length, opens + 1);
      expect(k.openedUris.last, 'https://h/a.flv');
      expect(k.lastPlay, isTrue);
      expect(r.events.whereType<MovaLiveEdgeReach>(), isNotEmpty);
      k.emitBuffering(true);
      k.emitBuffering(false);
      r.settle();
      expect(r.resumes.single.signal, MovaFirstFrameSignal.buffering);
      expect(r.resumes.single.from, isNull);
    });
  });

  test('7. a short fallback just plays again: no reconnect, straight to off, no resume event', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = _unknown;
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      async.elapse(const Duration(milliseconds: 500));
      k.calls.clear();
      expect(r.keepAlive(false), MovaKeepAlivePhase.off);
      expect(k.calls, ['play']);
      expect(r.trail.last, 'off/woke');
      expect(r.resumes, isEmpty);
    });
  });

  test('8. a fallback paused for 3s or more reconnects to the edge and reports a resume', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = _unknown;
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      async.elapse(const Duration(seconds: 3));
      k.calls.clear();
      r.keepAlive(false);
      expect(k.calls, contains('open'));
      k.emitBuffering(true);
      k.emitBuffering(false);
      r.settle();
      expect(r.resumes, hasLength(1));
      expect(r.resumes.single.from, isNull);
    });
  });

  test('9. a VOD fallback wakes with a plain play and no resume event', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive(type: MovaStreamType.vod);
      r.keepAlive(true);
      k.calls.clear();
      expect(r.keepAlive(false), MovaKeepAlivePhase.off);
      expect(k.calls, ['play']);
      expect(r.resumes, isEmpty);
    });
  });

  test('10. after a wake the stall watch runs, not the start deadline', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k, recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true))..playLive();
      r.land();
      r.keepAlive(true);
      k.emitBuffering(true);
      async.elapse(const Duration(seconds: 20));
      r.settle();
      expect(r.events.whereType<MovaPlayFailure>(), isEmpty, reason: 'a hold must not time out');
      r.keepAlive(false);
      k.emitSize(1280, 720);
      r.settle();
      async.elapse(const Duration(seconds: 10));
      r.settle();
      final failures = r.events.whereType<MovaPlayFailure>().toList();
      expect(failures, hasLength(1));
      expect(failures.single.fail.kind, MovaPlayFailKind.stallTimeout);
    });
  });

  test('11. a paused load during a fallback has nobody wanting playback, so waking only settles', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = _unknown;
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      r.engine.open(const MovaSource('https://h/a.flv', type: MovaStreamType.live), autoPlay: false);
      r.settle();
      final opens = k.openedUris.length;
      k.calls.clear();
      expect(r.keepAlive(false), MovaKeepAlivePhase.off);
      expect(k.calls, isNot(contains('play')));
      expect(k.openedUris.length, opens);
      expect(r.trail.last, 'off/woke');
    });
  });
}
