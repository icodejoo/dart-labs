import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/keep_alive_kernel.dart';

import '../../support/fake_kernel.dart';
import '../../support/keep_alive_rig.dart';

void main() {
  test('2. a kernel without the capability pauses and reports fallback(unsupported)', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = KeepAliveRig(async, k)..playLive();
      expect(r.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(k.calls.last, 'pause');
      expect(r.changes, hasLength(1));
      expect(r.changes.single.phase, MovaKeepAlivePhase.fallback);
      expect(r.changes.single.reason, MovaKeepAliveReason.unsupported);
    });
  });

  test('3. a playing live stream with audio is held muted and never paused', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      expect(r.keepAlive(true), MovaKeepAlivePhase.holding);
      expect(k.calls, containsAllInOrder(['inspectKeepAlive', 'enterKeepAlive:muted']));
      expect(k.calls, isNot(contains('pause')));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);
      final c = r.changes.single;
      expect(c.phase, MovaKeepAlivePhase.holding);
      expect(c.reason, MovaKeepAliveReason.requested);
      expect(c.mode, MovaKeepAliveMode.muted);
    });
  });

  test('4. no audio holds decodeOnly, or falls back when silentStreams is pause', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = const MovaKeepAliveMedia(audio: MovaAudioPresence.absent, format: 'flv');
      final r = KeepAliveRig(async, k)..playLive();
      expect(r.keepAlive(true), MovaKeepAlivePhase.holding);
      expect(k.calls, contains('enterKeepAlive:decodeOnly'));

      final k2 = FakeKeepAliveKernel()..media = const MovaKeepAliveMedia(audio: MovaAudioPresence.absent, format: 'flv');
      final r2 = KeepAliveRig(async, k2, keepAlive: const MovaKeepAliveConfig(silentStreams: MovaSilentKeepAlive.pause))..playLive();
      expect(r2.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(r2.changes.single.reason, MovaKeepAliveReason.silentStream);
    });
  });

  test('5. unknown media pauses with fallback(mediaUnknown)', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = const MovaKeepAliveMedia(audio: MovaAudioPresence.unknown, format: 'flv');
      final r = KeepAliveRig(async, k)..playLive();
      expect(r.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(r.changes.single.reason, MovaKeepAliveReason.mediaUnknown);
      expect(k.calls.last, 'pause');
    });
  });

  test('6. hls falls back by default and is held with allowHls', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..media = const MovaKeepAliveMedia(audio: MovaAudioPresence.present, format: 'hls');
      final r = KeepAliveRig(async, k)..playLive();
      expect(r.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(r.changes.single.reason, MovaKeepAliveReason.hls);

      final k2 = FakeKeepAliveKernel()..media = const MovaKeepAliveMedia(audio: MovaAudioPresence.present, format: 'hls');
      final r2 = KeepAliveRig(async, k2, keepAlive: const MovaKeepAliveConfig(allowHls: true))..playLive();
      expect(r2.keepAlive(true), MovaKeepAlivePhase.holding);
    });
  });

  test('7. VOD pauses with fallback(vod) and never touches the hold calls', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive(type: MovaStreamType.vod);
      expect(r.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(r.changes.single.reason, MovaKeepAliveReason.vod);
      expect(k.calls.last, 'pause');
      expect(k.calls, isNot(contains('enterKeepAlive:muted')));
      expect(k.calls, isNot(contains('exitKeepAlive')));
    });
  });

  test('8. keepAlive reads the play intent: not playing does nothing, a later play() starts held, a kernel pause does not matter', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive(autoPlay: false);
      expect(r.keepAlive(true), MovaKeepAlivePhase.off);
      expect(r.changes, isEmpty);
      expect(k.calls, isNot(contains('enterKeepAlive:muted')));
      r.engine.play();
      async.flushMicrotasks();
      expect(k.calls.indexOf('enterKeepAlive:muted'), isNonNegative);
      expect(k.calls.indexOf('enterKeepAlive:muted'), lessThan(k.calls.lastIndexOf('play')));
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.holding);

      final k2 = FakeKeepAliveKernel();
      final r2 = KeepAliveRig(async, k2)..playLive();
      k2.emitPlaying(false);
      async.flushMicrotasks();
      expect(r2.engine.state.playing, isFalse);
      expect(r2.keepAlive(true), MovaKeepAlivePhase.holding);
    });
  });

  test('9. PiP and the mini window are exempt; after waking, play() takes the plain path', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k, pip: YesPip())..playLive();
      r.engine.setMini(true);
      async.flushMicrotasks();
      expect(r.keepAlive(true), MovaKeepAlivePhase.off);
      expect(r.keepAlive(false), MovaKeepAlivePhase.off);
      r.engine.setMini(false);
      async.flushMicrotasks();

      final k2 = FakeKeepAliveKernel();
      final r2 = KeepAliveRig(async, k2, pip: YesPip())..playLive();
      r2.engine.enterPip();
      async.flushMicrotasks();
      expect(r2.engine.state.pip, isTrue);
      expect(r2.keepAlive(true), MovaKeepAlivePhase.off);
      expect(r2.keepAlive(false), MovaKeepAlivePhase.off);
      k2.calls.clear();
      r2.engine.play();
      async.flushMicrotasks();
      expect(k2.calls, ['play']);
    });
  });

  test('10. a hold past maxDuration pauses, restores, and falls back; the intent stays', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      k.calls.clear();
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(k.calls, ['pause', 'exitKeepAlive']);
      expect(r.engine.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      expect(r.changes.last.phase, MovaKeepAlivePhase.fallback);
      expect(r.changes.last.reason, MovaKeepAliveReason.maxDuration);
      expect(r.engine.state.playbackIntent, isTrue);
    });
  });

  test('11. repeated requests are idempotent; a request cancelled before it runs enters nothing', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      expect(r.keepAlive(true), MovaKeepAlivePhase.holding);
      expect(k.calls.where((c) => c == 'enterKeepAlive:muted'), hasLength(1));

      final k2 = FakeKeepAliveKernel();
      final r2 = KeepAliveRig(async, k2)..playLive();
      r2.engine.setKeepAlive(true);
      r2.engine.setKeepAlive(false);
      async.flushMicrotasks();
      expect(r2.engine.state.keepAlivePhase, MovaKeepAlivePhase.off);
      expect(k2.calls, isNot(contains('enterKeepAlive:muted')));
    });
  });

  test('12. a failed kernel hold pauses and reports fallback(unsupported)', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..enterResult = false;
      final r = KeepAliveRig(async, k)..playLive();
      expect(r.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(k.calls.last, 'pause');
      expect(r.changes.single.reason, MovaKeepAliveReason.unsupported);
    });
  });

  test('13. a recovery retry waiting in its delay is cancelled and reported as fallback(failed)', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel()..openError = StateError('boom');
      final r = KeepAliveRig(async, k, recovery: const MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true))..playLive(autoPlay: true);
      expect(k.openedUris, hasLength(1));
      expect(r.keepAlive(true), MovaKeepAlivePhase.fallback);
      expect(r.changes.single.reason, MovaKeepAliveReason.failed);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(k.openedUris, hasLength(1), reason: 'the pending retry must not reload');
    });
  });

  test('14. dispose() while holding leaves no timer, no event and no restore', () {
    fakeAsync((async) {
      final k = FakeKeepAliveKernel();
      final r = KeepAliveRig(async, k)..playLive();
      r.keepAlive(true);
      final before = r.events.length;
      unawaited(r.engine.dispose());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(r.events.length, before);
      expect(k.calls, isNot(contains('exitKeepAlive')));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
