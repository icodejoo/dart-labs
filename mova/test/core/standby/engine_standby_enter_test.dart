import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/standby_kernel.dart';

import '../../support/fake_kernel.dart';

/// A PiP port that always succeeds, to put the engine in system PiP.
///
/// 永远成功的画中画端口，用来让引擎进入系统画中画。
class _YesPip implements MovaPipPort {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> enter({int? width, int? height}) async => true;
}

/// An engine over [kernel] with the control bar's auto-hide off so the only
/// timers left pending are standby's own, plus recorders for standby events.
///
/// 基于 [kernel] 的引擎：关掉控制条自动隐藏，使剩余的挂起计时器只可能来自待机本身，
/// 并带待机事件记录器。
class _Rig {
  _Rig(
    this.kernel, {
    MovaStandbyConfig standby = const MovaStandbyConfig(),
    MovaRecoveryConfig recovery = const MovaRecoveryConfig(),
    MovaPipPort? pip,
  }) : engine = MovaEngine(
         kernel: kernel,
         pip: pip,
         options: MovaOpts(
           standby: standby,
           recovery: recovery,
           controls: const MovaCtrlsConfig(autoHide: false),
         ),
       ) {
    engine.events.listen(events.add);
  }

  final FakeKernel kernel;
  final MovaEngine engine;
  final List<MovaEvent> events = [];

  List<MovaStandbyChange> get changes => events.whereType<MovaStandbyChange>().toList();

  /// Opens a live source and reports the kernel as playing.
  ///
  /// 打开一条直播源并让内核报告在播。
  void playLive(FakeAsync async, {bool autoPlay = true, MovaStreamType type = MovaStreamType.live}) {
    engine.open(MovaSource('https://h/a.flv', type: type), autoPlay: autoPlay);
    async.flushMicrotasks();
    if (autoPlay) kernel.emitPlaying(true);
    async.flushMicrotasks();
  }

  /// Calls `setStandby` and lets microtasks settle; returns the settled phase.
  ///
  /// 调用 `setStandby` 并让微任务落定；返回落定后的阶段。
  MovaStandbyPhase? standby(FakeAsync async, bool on) {
    MovaStandbyPhase? result;
    engine.setStandby(on).then((p) => result = p);
    async.flushMicrotasks();
    return result;
  }
}

void main() {
  test('2. a kernel without the capability pauses and reports fallback(unsupported)', () {
    fakeAsync((async) {
      final k = FakeKernel();
      final r = _Rig(k)..playLive(async);
      expect(r.standby(async, true), MovaStandbyPhase.fallback);
      expect(k.calls.last, 'pause');
      expect(r.changes, hasLength(1));
      expect(r.changes.single.phase, MovaStandbyPhase.fallback);
      expect(r.changes.single.reason, MovaStandbyReason.unsupported);
    });
  });

  test('3. a playing live stream with audio is held muted and never paused', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k)..playLive(async);
      expect(r.standby(async, true), MovaStandbyPhase.holding);
      expect(k.calls, containsAllInOrder(['inspectStandby', 'enterStandby:muted']));
      expect(k.calls, isNot(contains('pause')));
      expect(r.engine.state.standby, MovaStandbyPhase.holding);
      final c = r.changes.single;
      expect(c.phase, MovaStandbyPhase.holding);
      expect(c.reason, MovaStandbyReason.requested);
      expect(c.mode, MovaStandbyMode.muted);
    });
  });

  test('4. no audio holds decodeOnly, or falls back when silentStreams is pause', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel()..media = const MovaStandbyMedia(audio: MovaAudioPresence.absent, format: 'flv');
      final r = _Rig(k)..playLive(async);
      expect(r.standby(async, true), MovaStandbyPhase.holding);
      expect(k.calls, contains('enterStandby:decodeOnly'));

      final k2 = FakeStandbyKernel()..media = const MovaStandbyMedia(audio: MovaAudioPresence.absent, format: 'flv');
      final r2 = _Rig(k2, standby: const MovaStandbyConfig(silentStreams: MovaSilentStandby.pause))..playLive(async);
      expect(r2.standby(async, true), MovaStandbyPhase.fallback);
      expect(r2.changes.single.reason, MovaStandbyReason.silentStream);
    });
  });

  test('5. unknown media pauses with fallback(mediaUnknown)', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel()..media = const MovaStandbyMedia(audio: MovaAudioPresence.unknown, format: 'flv');
      final r = _Rig(k)..playLive(async);
      expect(r.standby(async, true), MovaStandbyPhase.fallback);
      expect(r.changes.single.reason, MovaStandbyReason.mediaUnknown);
      expect(k.calls.last, 'pause');
    });
  });

  test('6. hls falls back by default and is held with allowHls', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel()..media = const MovaStandbyMedia(audio: MovaAudioPresence.present, format: 'hls');
      final r = _Rig(k)..playLive(async);
      expect(r.standby(async, true), MovaStandbyPhase.fallback);
      expect(r.changes.single.reason, MovaStandbyReason.hls);

      final k2 = FakeStandbyKernel()..media = const MovaStandbyMedia(audio: MovaAudioPresence.present, format: 'hls');
      final r2 = _Rig(k2, standby: const MovaStandbyConfig(allowHls: true))..playLive(async);
      expect(r2.standby(async, true), MovaStandbyPhase.holding);
    });
  });

  test('7. VOD pauses with fallback(vod) and never touches the hold calls', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k)..playLive(async, type: MovaStreamType.vod);
      expect(r.standby(async, true), MovaStandbyPhase.fallback);
      expect(r.changes.single.reason, MovaStandbyReason.vod);
      expect(k.calls.last, 'pause');
      expect(k.calls, isNot(contains('enterStandby:muted')));
      expect(k.calls, isNot(contains('exitStandby')));
    });
  });

  test('8. standby reads the play intent: not playing does nothing, a later play() starts held, a kernel pause does not matter', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k)..playLive(async, autoPlay: false);
      expect(r.standby(async, true), MovaStandbyPhase.off);
      expect(r.changes, isEmpty);
      expect(k.calls, isNot(contains('enterStandby:muted')));
      r.engine.play();
      async.flushMicrotasks();
      expect(k.calls.indexOf('enterStandby:muted'), isNonNegative);
      expect(k.calls.indexOf('enterStandby:muted'), lessThan(k.calls.lastIndexOf('play')));
      expect(r.engine.state.standby, MovaStandbyPhase.holding);

      final k2 = FakeStandbyKernel();
      final r2 = _Rig(k2)..playLive(async);
      k2.emitPlaying(false);
      async.flushMicrotasks();
      expect(r2.engine.state.playing, isFalse);
      expect(r2.standby(async, true), MovaStandbyPhase.holding);
    });
  });

  test('9. PiP and the mini window are exempt; after waking, play() takes the plain path', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k, pip: _YesPip())..playLive(async);
      r.engine.setMini(true);
      async.flushMicrotasks();
      expect(r.standby(async, true), MovaStandbyPhase.off);
      expect(r.standby(async, false), MovaStandbyPhase.off);
      r.engine.setMini(false);
      async.flushMicrotasks();

      final k2 = FakeStandbyKernel();
      final r2 = _Rig(k2, pip: _YesPip())..playLive(async);
      r2.engine.enterPip();
      async.flushMicrotasks();
      expect(r2.engine.state.pip, isTrue);
      expect(r2.standby(async, true), MovaStandbyPhase.off);
      expect(r2.standby(async, false), MovaStandbyPhase.off);
      k2.calls.clear();
      r2.engine.play();
      async.flushMicrotasks();
      expect(k2.calls, ['play']);
    });
  });

  test('10. a hold past maxDuration pauses, restores, and falls back; the intent stays', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k)..playLive(async);
      r.standby(async, true);
      k.calls.clear();
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(k.calls, ['pause', 'exitStandby']);
      expect(r.engine.state.standby, MovaStandbyPhase.fallback);
      expect(r.changes.last.phase, MovaStandbyPhase.fallback);
      expect(r.changes.last.reason, MovaStandbyReason.maxDuration);
      expect(r.engine.state.playbackIntent, isTrue);
    });
  });

  test('11. repeated requests are idempotent; a request cancelled before it runs enters nothing', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k)..playLive(async);
      r.standby(async, true);
      expect(r.standby(async, true), MovaStandbyPhase.holding);
      expect(k.calls.where((c) => c == 'enterStandby:muted'), hasLength(1));

      final k2 = FakeStandbyKernel();
      final r2 = _Rig(k2)..playLive(async);
      r2.engine.setStandby(true);
      r2.engine.setStandby(false);
      async.flushMicrotasks();
      expect(r2.engine.state.standby, MovaStandbyPhase.off);
      expect(k2.calls, isNot(contains('enterStandby:muted')));
    });
  });

  test('12. a failed kernel hold pauses and reports fallback(unsupported)', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel()..enterResult = false;
      final r = _Rig(k)..playLive(async);
      expect(r.standby(async, true), MovaStandbyPhase.fallback);
      expect(k.calls.last, 'pause');
      expect(r.changes.single.reason, MovaStandbyReason.unsupported);
    });
  });

  test('13. a recovery retry waiting in its delay is cancelled and reported as fallback(failed)', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel()..openError = StateError('boom');
      final r = _Rig(k, recovery: const MovaRecoveryConfig(enabled: true))..playLive(async, autoPlay: true);
      expect(k.openedUris, hasLength(1));
      expect(r.standby(async, true), MovaStandbyPhase.fallback);
      expect(r.changes.single.reason, MovaStandbyReason.failed);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(k.openedUris, hasLength(1), reason: 'the pending retry must not reload');
    });
  });

  test('14. dispose() while holding leaves no timer, no event and no restore', () {
    fakeAsync((async) {
      final k = FakeStandbyKernel();
      final r = _Rig(k)..playLive(async);
      r.standby(async, true);
      final before = r.events.length;
      unawaited(r.engine.dispose());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(r.events.length, before);
      expect(k.calls, isNot(contains('exitStandby')));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
