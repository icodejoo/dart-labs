import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/report/report.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/core/cutover/ctl.dart';
import 'package:mova/src/core/cutover/plan.dart';
import 'package:mova/src/core/cutover/cutover_engine.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/cutover/warm.dart';

import '../../support/fake_api.dart';

/// Yields a few microtasks so async chains inside [MovaCutoverEngine] settle
/// before assertions.
///
/// 让出几个微任务，使 [MovaCutoverEngine] 内部的异步链在断言前结算完毕。
Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('MovaCutoverEngine — disabled by default (pure pass-through)', () {
    late List<FakeMovaApi> made;
    late MovaCutoverEngine api;

    setUp(() {
      made = <FakeMovaApi>[];
      api = MovaCutoverEngine(engineFactory: () {
        final f = FakeMovaApi();
        made.add(f);
        return f;
      });
    });

    test('construction calls the factory exactly once', () {
      expect(made, hasLength(1));
    });

    test('states forwards the underlying engine state, and new subscribers see the current snapshot', () async {
      final seen = <MovaState>[];
      final sub = api.states.listen(seen.add);
      await settle();
      made.first.push(const MovaState(playing: true));
      await settle();
      expect(seen.last.playing, isTrue);
      final seen2 = <MovaState>[];
      final sub2 = api.states.listen(seen2.add);
      await settle();
      expect(seen2.first.playing, isTrue);
      await sub.cancel();
      await sub2.cancel();
    });

    test('progress/events/uiStates all forward', () async {
      final progress = <MovaProg>[];
      final events = <MovaEvent>[];
      final ui = <MovaUiState>[];
      final s1 = api.progress.listen(progress.add);
      final s2 = api.events.listen(events.add);
      final s3 = api.uiStates.listen(ui.add);
      await settle();
      made.first.pushProgress(const MovaProg(position: Duration(seconds: 5)));
      made.first.pushEvent(const MovaPlay());
      made.first.pushUi(const MovaUiState(controlsVisible: false));
      await settle();
      expect(progress, isNotEmpty);
      expect(events, contains(isA<MovaPlay>()));
      expect(ui, isNotEmpty);
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
    });

    test('every capability method forwards to active', () async {
      await api.open(const MovaSource('https://host/a.mp4'));
      await api.play();
      await api.pause();
      await api.seek(const Duration(seconds: 1));
      await api.setVolume(50);
      await api.setRate(1.5);
      await api.setFit(MovaFit.cover);
      await api.setFullscreen(true);
      await api.setMini(true);
      await api.switchQuality(MovaQuality.auto());
      await api.reload();
      await api.backToLiveEdge();
      final calls = made.first.calls;
      for (final m in [
        'open',
        'play',
        'pause',
        'seek',
        'setVolume',
        'setRate',
        'setFit',
        'setFullscreen',
        'setMini',
        'switchQuality',
        'reload',
        'backToLiveEdge',
      ]) {
        expect(calls, contains(m), reason: 'missing forwarded call: $m');
      }
    });

    test('renderHandle/options/state/preview/stt forward to active', () {
      made.first.renderHandle = 'h';
      expect(api.renderHandle, 'h');
      expect(api.options, made.first.options);
      expect(api.state, made.first.state);
      expect(api.preview, same(made.first.preview));
      expect(api.stt, same(made.first.stt));
    });

    test('dispose releases the underlying engine and closes own streams', () async {
      await api.dispose();
      expect(made.first.calls, contains('dispose'));
      // Re-subscribing to closed streams must not throw.
      final sub = api.states.listen((_) {});
      await sub.cancel();
    });

    test('disabled: cutoverEnabled is false', () {
      expect(api.cutoverEnabled, isFalse);
    });

    test('disabled: prepare is a no-op, phase stays idle, factory still called once', () async {
      await api.prepare(const MovaSource('https://host/b.mp4'));
      await settle();
      expect(api.cutoverPhase, MovaCutoverPhase.idle);
      expect(made, hasLength(1));
    });

    test('disabled: commit() returns false and does not open anything', () async {
      final ok = await api.commit();
      expect(ok, isFalse);
    });

    test('disabled: cutoverTo opens+seeks on active and returns false', () async {
      final ok = await api.cutoverTo(const MovaSource('https://host/c.mp4'), at: const Duration(seconds: 3));
      expect(ok, isFalse);
      expect(made.first.calls, contains('open'));
      expect(made.first.calls, contains('seek'));
      expect(made.first.lastSeek, const Duration(seconds: 3));
    });

    test('disabled: preparing a hand-off emits no MovaCutoverChange at all', () async {
      final changes = <MovaEvent>[];
      final sub = api.events.where((e) => e is MovaCutoverChange).listen(changes.add);
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(changes, isEmpty);
      await sub.cancel();
    });

    test('cutoverPhases does not push initially, and cutoverPhase starts idle', () async {
      final phases = <MovaCutoverPhase>[];
      final sub = api.cutoverPhases.listen(phases.add);
      await settle();
      expect(phases, isEmpty);
      expect(api.cutoverPhase, MovaCutoverPhase.idle);
      await sub.cancel();
    });
  });

  group('MovaCutoverEngine — enabled, warm-up and atomic commit', () {
    late List<FakeMovaApi> made;
    late MovaCutoverEngine api;
    const opts = MovaOpts(cutover: MovaCutoverConfig(enabled: true, muteWhileWarm: true));

    MovaCutoverEngine build({MovaOpts o = opts}) {
      made = <FakeMovaApi>[];
      return MovaCutoverEngine(engineFactory: () {
        final f = FakeMovaApi(options: o);
        made.add(f);
        return f;
      });
    }

    setUp(() {
      api = build();
    });

    test('trigger allows: factory called a second time, shadow opened with autoPlay true, then seeked', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 7),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made, hasLength(2));
      final shadow = made[1];
      expect(shadow.lastAutoPlay, isTrue);
      expect(shadow.lastSeek, const Duration(seconds: 7));
    });

    test('warm-up touches the shadow renderHandle (lazy video pipeline) but not the active one', () async {
      expect(made.first.renderHandleReads, 0, reason: 'the active engine is only read when a widget mounts');
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 7),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made[1].renderHandleReads, greaterThanOrEqualTo(1), reason: 'shadow must build its video pipeline before commit');
      expect(made.first.renderHandleReads, 0);
    });

    test('unsupported warm mute never falls back to volume writes', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made[1].lastVolume, isNull);

      final api2 = build(o: const MovaOpts(cutover: MovaCutoverConfig(enabled: true, muteWhileWarm: false)));
      await api2.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made[1].lastVolume, isNull);
    });

    test('trigger declines (short ad): factory still called once, phase stays idle', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 4), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made, hasLength(1));
      expect(api.cutoverPhase, MovaCutoverPhase.idle);
    });

    test('commit() returns false without a promotion while the policy has not signalled ready', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final ok = await api.commit();
      expect(ok, isFalse);
      expect(api.active, same(made.first));
    });

    /// Drives the shadow's readiness policy to `ready` with two matching
    /// buffer/progress ticks (stableTicks defaults to 2).
    ///
    /// 用两次匹配的缓冲/进度 tick 把影子引擎的就绪判据推进到 `ready`
    /// （stableTicks 默认 2）。
    Future<void> warmToReady(MovaApi shadow, {Duration at = Duration.zero}) async {
      final sig = const MovaProg(position: Duration(seconds: 5), buffer: Duration(seconds: 6));
      shadow.progress; // no-op, keeps analyzer quiet about unused import edge cases
      (shadow as FakeMovaApi).pushProgress(sig);
      await settle();
      shadow.pushProgress(sig);
      await settle();
    }

    test('cutoverPhase becomes ready once the policy signals ready, and cutoverPhases sees warming then ready', () async {
      final phases = <MovaCutoverPhase>[];
      final sub = api.cutoverPhases.listen(phases.add);
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      await warmToReady(made[1], at: const Duration(seconds: 5));
      expect(api.cutoverPhase, MovaCutoverPhase.ready);
      expect(phases, [MovaCutoverPhase.warming, MovaCutoverPhase.ready]);
      await sub.cancel();
    });

    test('a live shadow becomes ready without catching up to the on-screen position (Q13)', () async {
      await api.prepare(
        const MovaSource('https://host/live.m3u8', type: MovaStreamType.live),
        at: const Duration(seconds: 7), // 正片已播 7s
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      // 直播影子刚从边缘起播：位置只有 1s、提前缓冲 1.5s，离正片位置还差 6s
      const sig = MovaProg(position: Duration(seconds: 1), buffer: Duration(milliseconds: 2500));
      (made[1]).pushProgress(sig);
      await settle();
      (made[1]).pushProgress(sig);
      await settle();
      expect(api.cutoverPhase, MovaCutoverPhase.ready);
    });

    test('a non-live shadow that has not reached the target is not ready (control for Q13)', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 7),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      const sig = MovaProg(position: Duration(seconds: 1), buffer: Duration(milliseconds: 2500));
      (made[1]).pushProgress(sig);
      await settle();
      (made[1]).pushProgress(sig);
      await settle();
      expect(api.cutoverPhase, MovaCutoverPhase.warming);
    });

    test('the events stream carries MovaCutoverChange for warming, ready and the return to idle', () async {
      final seen = <MovaCutoverPhase>[];
      final sub = api.events.where((e) => e is MovaCutoverChange).listen((e) => seen.add((e as MovaCutoverChange).phase));
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      await warmToReady(made[1], at: const Duration(seconds: 5));
      expect(await api.commit(), isTrue);
      await settle();
      expect(seen, [MovaCutoverPhase.warming, MovaCutoverPhase.ready, MovaCutoverPhase.idle]);
      await sub.cancel();
    });

    test('MovaCutoverChange on events always matches cutoverPhases one for one', () async {
      final phases = <MovaCutoverPhase>[];
      final changes = <MovaCutoverPhase>[];
      final s1 = api.cutoverPhases.listen(phases.add);
      final s2 = api.events.where((e) => e is MovaCutoverChange).listen((e) => changes.add((e as MovaCutoverChange).phase));
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      await warmToReady(made[1], at: const Duration(seconds: 5));
      await api.commit();
      await settle();
      expect(changes, phases);
      await s1.cancel();
      await s2.cancel();
    });

    test('commit() success: active becomes the shadow; old gets pause+dispose; new gets play', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final oldEngine = made[0];
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 5));

      final ok = await api.commit();
      expect(ok, isTrue);
      expect(api.active, same(shadow));
      expect(oldEngine.calls, contains('pause'));
      expect(oldEngine.calls, contains('dispose'));
      expect(shadow.calls, contains('play'));
    });

    test('setMini forwards to the currently active engine, and to the new one after a cutover', () async {
      await api.setMini(true);
      expect(made[0].lastMini, isTrue);

      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 5));
      await api.commit();

      await api.setMini(false);
      expect(shadow.lastMini, isFalse);
    });

    test('commit() success bumps renderEpoch, observable from states', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 5));
      final before = api.state.renderEpoch;

      final seen = <MovaState>[];
      final sub = api.states.listen(seen.add);
      await api.commit();
      await settle();
      expect(api.state.renderEpoch, before + 1);
      expect(seen.any((s) => s.renderEpoch == before + 1), isTrue);
      await sub.cancel();
    });

    test('commit() success points renderHandle at the new engine', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      shadow.renderHandle = 'shadow-handle';
      await warmToReady(shadow, at: const Duration(seconds: 5));
      await api.commit();
      expect(api.renderHandle, 'shadow-handle');
    });

    test('an audio-only engine (null renderHandle) forwards through without throwing', () {
      // FakeMovaApi's renderHandle defaults to null — exactly the audio-only
      // shape, where no VideoController was ever created.
      //
      // FakeMovaApi 的 renderHandle 默认就是 null——正是仅音频形态：从未创建
      // 过 VideoController。
      expect(made.first.renderHandle, isNull);
      expect(api.renderHandle, isNull);
    });

    test('commit() between two audio-only engines still bumps renderEpoch', () async {
      await api.prepare(
        const MovaSource('https://host/content.m4a'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      expect(shadow.renderHandle, isNull);
      await warmToReady(shadow, at: const Duration(seconds: 5));
      final before = api.state.renderEpoch;

      final ok = await api.commit();
      await settle();

      expect(ok, isTrue);
      expect(api.renderHandle, isNull);
      expect(
        api.state.renderEpoch,
        before + 1,
        reason: 'cutover bookkeeping must not be skipped just because there is no '
            'render handle / 切换簿记不得因为没有渲染句柄就被跳过',
      );
    });

    test('commit() success: old engine state no longer forwarded, new engine state is', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final oldEngine = made[0];
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 5));
      await api.commit();
      await settle();

      final seen = <MovaState>[];
      final sub = api.states.listen(seen.add);
      oldEngine.push(oldEngine.state.copyWith(volume: 1));
      await settle();
      expect(seen.any((s) => s.volume == 1), isFalse);

      shadow.push(shadow.state.copyWith(volume: 2));
      await settle();
      expect(seen.any((s) => s.volume == 2), isTrue);
      await sub.cancel();
    });

    test('a progress subscriber attached before the cutover keeps receiving ticks from the new engine', () async {
      final ticks = <MovaProg>[];
      final sub = api.progress.listen(ticks.add);
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 5));
      await api.commit();
      await settle();
      ticks.clear();

      shadow.pushProgress(const MovaProg(position: Duration(seconds: 99)));
      await settle();
      expect(ticks.any((p) => p.position == const Duration(seconds: 99)), isTrue);
      await sub.cancel();
    });

    test('giveUp verdict disposes the shadow, returns phase to idle, commit() returns false', () async {
      final config = MovaOpts(
        cutover: MovaCutoverConfig(enabled: true, readyPolicy: MovaBufferWarm(timeout: Duration.zero)),
      );
      final a = build(o: config);
      await a.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      // The deadline timer now abandons the shadow on its own; no signal needed.
      //
      // 期限计时器现在会自行放弃影子，无需再推信号。
      await settle();
      expect(shadow.calls, contains('dispose'));
      expect(a.cutoverPhase, MovaCutoverPhase.idle);
      final ok = await a.commit();
      expect(ok, isFalse);
    });

    test('commit(waitForReady: true) times out via the policy and returns false, already abandoned', () async {
      final config = MovaOpts(
        cutover: MovaCutoverConfig(enabled: true, readyPolicy: MovaBufferWarm(timeout: const Duration(milliseconds: 1))),
      );
      final a = build(o: config);
      await a.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      final commitFuture = a.commit(waitForReady: true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final ok = await commitFuture;
      await settle();
      expect(ok, isFalse);
      expect(shadow.calls, contains('dispose'));
    });

    test(
        'two overlapping commit(waitForReady: true) calls both resolve once ready, and only one '
        'promotes the shadow (regression: the second call used to overwrite _readyCompleter and '
        'orphan the first forever; simply fixing that by itself would have let both calls run '
        '_commitNow concurrently once unblocked)', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      final first = api.commit(waitForReady: true);
      final second = api.commit(waitForReady: true);
      await warmToReady(shadow);
      final results = await Future.wait([first, second]);
      // Exactly one of the two calls actually promoted the shadow; the other
      // found it already claimed and backed off.
      //
      // 两次调用里恰好有一次真正把影子转正；另一次发现它已被认领，随即退出。
      expect(results.where((r) => r).length, 1,
          reason: 'exactly one overlapping commit() should promote the shadow');
      expect(api.active, same(shadow));
      // Promoting an engine calls pause() on the outgoing one exactly once;
      // a double _commitNow would call it twice.
      //
      // 转正一次只会对被换下的引擎调用一次 pause()；若发生了两次并发的
      // _commitNow，会被调用两次。
      expect(made.first.calls.where((c) => c == 'pause').length, 1);
    });

    test('cutoverTo returns true and switches active when enabled and ready', () async {
      final commitFuture = api.cutoverTo(const MovaSource('https://host/variant.m3u8'), at: const Duration(seconds: 2));
      await settle();
      expect(made, hasLength(2));
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 2));
      final ok = await commitFuture;
      expect(ok, isTrue);
      expect(api.active, same(shadow));
    });

    test('cutoverTo falls back to open+seek on active and returns false when disabled', () async {
      final off = build(o: const MovaOpts());
      final ok = await off.cutoverTo(const MovaSource('https://host/variant.m3u8'), at: const Duration(seconds: 2));
      expect(ok, isFalse);
      expect(made.first.calls, contains('open'));
      expect(made.first.lastSeek, const Duration(seconds: 2));
    });

    test('repeated prepare with an already-warming shadow does not create a second one', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made, hasLength(2));
    });

    test('dispose during warm-up also disposes the shadow, and late verdicts do not throw', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      // Queue a progress event (delivered asynchronously) right before
      // dispose() cancels the subscription that would have consumed it —
      // this must not throw even though the callback never fires.
      //
      // 在 dispose() 取消订阅之前排入一个进度事件（异步投递）——即便该回调
      // 最终不会触发，也不应抛出异常。
      shadow.pushProgress(const MovaProg(position: Duration(seconds: 5), buffer: Duration(seconds: 6)));
      await api.dispose();
      await settle();
      expect(shadow.calls, contains('dispose'));
    });
  });

  group('MovaCutoverEngine — verbs after dispose are no-ops', () {
    late List<FakeMovaApi> made;
    late MovaCutoverEngine api;
    const opts = MovaOpts(cutover: MovaCutoverConfig(enabled: true));

    setUp(() {
      made = <FakeMovaApi>[];
      api = MovaCutoverEngine(engineFactory: () {
        final f = FakeMovaApi(options: opts);
        made.add(f);
        return f;
      });
    });

    test('no verb reaches the released engine and none throws', () async {
      await api.dispose();
      final before = made.first.calls.length;
      await api.open(const MovaSource('https://host/a.mp4'));
      await api.play();
      await api.pause();
      await api.playOrPause();
      await api.seek(const Duration(seconds: 5));
      await api.seekBy(const Duration(seconds: 5));
      await api.setVolume(10);
      await api.setBrightness(0.5);
      await api.setRate(2);
      await api.setFit(MovaFit.cover);
      await api.setZoom(2);
      await api.setLocked(true);
      await api.setFullscreen(true);
      await api.setMini(true);
      await api.setOrientation(MovaOrientation.landscape);
      await api.loadQualities();
      await api.switchQuality(const MovaQuality(label: 'x', uri: 'https://host/x.m3u8'));
      await api.enterPip();
      await api.reload();
      await api.backToLiveEdge();
      await api.setKeepAlive(true);
      api
        ..showControls()
        ..hideControls()
        ..showHud(MovaHud.volume)
        ..setDragging(true)
        ..report(MovaReportName.play);
      expect(made.first.calls.sublist(before), isEmpty);
    });

    test('prepare, cutoverTo and commit after dispose build no shadow engine', () async {
      await api.dispose();
      await api.prepare(const MovaSource('https://host/b.mp4'));
      expect(await api.cutoverTo(const MovaSource('https://host/c.mp4')), isFalse);
      expect(await api.commit(waitForReady: true), isFalse);
      expect(made, hasLength(1));
    });
  });

  group('MovaCutoverEngine — Task 8 contract: cutoverTo maps onto quality switching semantics', () {
    late List<FakeMovaApi> made;
    late MovaCutoverEngine api;
    const opts = MovaOpts(cutover: MovaCutoverConfig(enabled: true));

    setUp(() {
      made = <FakeMovaApi>[];
      api = MovaCutoverEngine(engineFactory: () {
        final f = FakeMovaApi(options: opts);
        made.add(f);
        return f;
      });
    });

    test('cutoverTo opens the variant uri on the shadow and seeks to the given position', () async {
      final commitFuture =
          api.cutoverTo(const MovaSource('https://host/720p.m3u8'), at: const Duration(seconds: 42));
      await settle();
      final shadow = made[1];
      expect(shadow.source?.uri, 'https://host/720p.m3u8');
      expect(shadow.lastSeek, const Duration(seconds: 42));
      shadow.pushProgress(const MovaProg(position: Duration(seconds: 42), buffer: Duration(seconds: 43)));
      await settle();
      shadow.pushProgress(const MovaProg(position: Duration(seconds: 42), buffer: Duration(seconds: 43)));
      await settle();
      await commitFuture;
    });

    test('cutoverTo uses eager-trigger semantics: an empty cue still creates a shadow', () async {
      final commitFuture = api.cutoverTo(const MovaSource('https://host/720p.m3u8'));
      await settle();
      expect(made, hasLength(2), reason: 'MovaLeadWarm would reject an empty cue, but cutoverTo must not');
      unawaited(commitFuture);
      await api.abandon();
    });

    test('a live source is not seeked by cutoverTo', () async {
      final commitFuture = api.cutoverTo(
        const MovaSource('https://host/live.m3u8', type: MovaStreamType.live),
        at: const Duration(seconds: 10),
      );
      await settle();
      final shadow = made[1];
      expect(shadow.calls, isNot(contains('seek')));
      unawaited(commitFuture);
      await api.abandon();
    });

    test('cutoverTo returning false falls back exactly like switchQuality does today', () async {
      final config = MovaOpts(
        cutover: MovaCutoverConfig(enabled: true, readyPolicy: MovaBufferWarm(timeout: Duration.zero)),
      );
      final made2 = <FakeMovaApi>[];
      final a = MovaCutoverEngine(engineFactory: () {
        final f = FakeMovaApi(options: config);
        made2.add(f);
        return f;
      });
      final future = a.cutoverTo(const MovaSource('https://host/720p.m3u8'), at: const Duration(seconds: 5));
      await settle();
      final ok = await future;
      expect(ok, isFalse);
      expect(made2.first.calls, contains('open'));
      expect(made2.first.lastSeek, const Duration(seconds: 5));
    });
  });

  group('MovaCutoverEngine — 0.5.0 Task 1: MovaWarmPlan overrides and latent-defect fixes', () {
    late List<FakeMovaApi> made;

    /// Builds an engine whose every produced fake engine carries [o].
    ///
    /// 构造一个引擎，其产出的每个假引擎都带有 [o]。
    MovaCutoverEngine build(MovaOpts o) {
      made = <FakeMovaApi>[];
      return MovaCutoverEngine(engineFactory: () {
        final f = FakeMovaApi(options: o);
        made.add(f);
        return f;
      });
    }

    /// A cue that the default [MovaLeadWarm] accepts.
    ///
    /// 默认 [MovaLeadWarm] 会接受的一条线索。
    const okCue = MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10));

    /// A satisfying warm-up tick for the default [MovaBufferWarm].
    ///
    /// 对默认 [MovaBufferWarm] 而言满足条件的一次预热 tick。
    const goodTick = MovaProg(position: Duration(seconds: 5), buffer: Duration(seconds: 6));

    test('no plan: the trigger and readiness policy still come from MovaCutoverConfig', () async {
      final trigger = RecordingTrigger();
      final policy = RecordingPolicy();
      final api = build(MovaOpts(
        cutover: MovaCutoverConfig(enabled: true, trigger: trigger, readyPolicy: policy),
      ));
      await api.prepare(const MovaSource('https://host/a.mp4'), cue: okCue);
      await settle();
      expect(trigger.calls, 1, reason: 'configured trigger must still be consulted');
      made[1].pushProgress(goodTick);
      await settle();
      expect(policy.log, contains('onSignal'), reason: 'configured policy must still be fed');
    });

    test('plan.trigger wins: the configured trigger is never consulted', () async {
      final configured = RecordingTrigger(answer: false);
      final injected = RecordingTrigger();
      final api = build(MovaOpts(cutover: MovaCutoverConfig(enabled: true, trigger: configured)));
      await api.prepare(
        const MovaSource('https://host/a.mp4'),
        plan: MovaWarmPlan(trigger: injected),
      );
      await settle();
      expect(configured.calls, 0);
      expect(injected.calls, 1);
      expect(made, hasLength(2), reason: 'the injected trigger said yes, so a shadow exists');
    });

    test('plan.policy wins: the configured readiness policy is never fed', () async {
      final configured = RecordingPolicy();
      final injected = RecordingPolicy();
      final api = build(MovaOpts(cutover: MovaCutoverConfig(enabled: true, readyPolicy: configured)));
      await api.prepare(
        const MovaSource('https://host/a.mp4'),
        cue: okCue,
        plan: MovaWarmPlan(policy: injected),
      );
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(configured.log, isEmpty);
      expect(injected.log, contains('onSignal'));
    });

    test('an injected policy is reset() before it sees its first signal', () async {
      final injected = RecordingPolicy();
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(
        const MovaSource('https://host/a.mp4'),
        cue: okCue,
        plan: MovaWarmPlan(policy: injected),
      );
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(injected.log, ['reset', 'onSignal']);
    });

    test('reusing one policy instance across two warm-ups restarts its consecutive count', () async {
      final policy = MovaBufferWarm();
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));

      await api.prepare(
        const MovaSource('https://host/a.mp4'),
        cue: okCue,
        plan: MovaWarmPlan(policy: policy),
      );
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(policy.stable, 1, reason: 'one satisfying tick, stableTicks defaults to 2');
      await api.abandon();

      await api.prepare(
        const MovaSource('https://host/b.mp4'),
        cue: okCue,
        plan: MovaWarmPlan(policy: policy),
      );
      await settle();
      made[2].pushProgress(goodTick);
      await settle();
      expect(api.cutoverPhase, MovaCutoverPhase.warming,
          reason: 'without reset() the stale count would have committed on one lucky tick');
      made[2].pushProgress(goodTick);
      await settle();
      expect(api.cutoverPhase, MovaCutoverPhase.ready);
    });

    test('at == Duration.zero issues no seek on the shadow; at > zero still does', () async {
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(const MovaSource('https://host/a.mp4'), cue: okCue);
      await settle();
      expect(made[1].calls, isNot(contains('seek')));
      await api.abandon();

      await api.prepare(
        const MovaSource('https://host/a.mp4'),
        at: const Duration(seconds: 7),
        cue: okCue,
      );
      await settle();
      expect(made[2].lastSeek, const Duration(seconds: 7));
    });

    test('pauseWhenReady false (the default) never pauses the shadow on ready', () async {
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(const MovaSource('https://host/a.mp4'), cue: okCue);
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(api.cutoverPhase, MovaCutoverPhase.ready);
      expect(made[1].calls, isNot(contains('pause')));
    });

    test('pauseWhenReady true pauses on ready and rewinds to the target, zero included', () async {
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(
        const MovaSource('https://host/ad.mp4'),
        cue: okCue,
        plan: const MovaWarmPlan(pauseWhenReady: true),
      );
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(made[1].calls, contains('pause'));
      // Regression: the shadow has been decoding in real time since open(), so
      // by the ready tick it has drifted past frame zero. Skipping the rewind
      // here delivers a headless ad — the exact thing pauseWhenReady exists
      // to prevent.
      //
      // 回归点：影子自 open() 起就在按真实时间解码，到就绪那一 tick 早已漂过
      // 第 0 帧。此处省掉回绕，交付出去的就是一条缺头广告——正是
      // pauseWhenReady 要防的那件事。
      expect(made[1].lastSeek, Duration.zero);
      await api.abandon();

      await api.prepare(
        const MovaSource('https://host/ad.mp4'),
        at: const Duration(seconds: 3),
        cue: okCue,
        plan: const MovaWarmPlan(pauseWhenReady: true),
      );
      await settle();
      made[2].pushProgress(goodTick);
      await settle();
      made[2].pushProgress(goodTick);
      await settle();
      expect(made[2].calls, contains('pause'));
      expect(made[2].lastSeek, const Duration(seconds: 3));
    });

    test('pauseWhenReady true on a live source pauses but never seeks', () async {
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(
        const MovaSource('https://host/live.m3u8', type: MovaStreamType.live),
        cue: okCue,
        plan: const MovaWarmPlan(pauseWhenReady: true),
      );
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(made[1].calls, contains('pause'));
      expect(made[1].calls, isNot(contains('seek')),
          reason: 'a live stream has no fixed target frame to rewind to');
    });

    test('pauseWhenReady true pauses exactly once however often the policy reports ready', () async {
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(
        const MovaSource('https://host/ad.mp4'),
        cue: okCue,
        plan: const MovaWarmPlan(pauseWhenReady: true),
      );
      await settle();
      for (var i = 0; i < 5; i++) {
        made[1].pushProgress(goodTick);
        await settle();
      }
      expect(made[1].calls.where((c) => c == 'pause'), hasLength(1));
    });

    test('a MovaErrorEvent from the shadow abandons the warm-up and fails an awaiting commit', () async {
      final api = build(const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
      await api.prepare(const MovaSource('https://host/ad.mp4'), cue: okCue);
      await settle();
      final shadow = made[1];
      final commitFuture = api.commit(waitForReady: true);
      await settle();
      shadow.pushEvent(MovaErrorEvent('boom'));
      final ok = await commitFuture;
      await settle();
      expect(ok, isFalse);
      expect(shadow.calls, contains('dispose'));
      expect(api.cutoverPhase, MovaCutoverPhase.idle);
      expect(api.active, same(made.first));
    });
  });
}

/// A [MovaWarmTrigger] that counts how often it was consulted.
///
/// 一个记录被咨询次数的 [MovaWarmTrigger]。
class RecordingTrigger implements MovaWarmTrigger {
  /// What [shouldWarm] answers.
  ///
  /// [shouldWarm] 的回答。
  final bool answer;

  /// How many times [shouldWarm] was called.
  ///
  /// [shouldWarm] 被调用的次数。
  int calls = 0;

  /// Creates a recording trigger answering [answer].
  ///
  /// 创建一个回答 [answer] 的记录型触发策略。
  RecordingTrigger({this.answer = true});

  @override
  bool shouldWarm(MovaWarmCue cue) {
    calls++;
    return answer;
  }
}

/// A [MovaWarmPolicy] that records the order of its calls.
///
/// 一个记录调用顺序的 [MovaWarmPolicy]。
class RecordingPolicy implements MovaWarmPolicy {
  /// Ordered method names invoked on this policy.
  ///
  /// 在该判据上被调用的方法名有序列表。
  final List<String> log = <String>[];

  /// What [onSignal] answers.
  ///
  /// [onSignal] 的回答。
  final MovaWarmVerdict verdict;

  /// Creates a recording policy answering [verdict].
  ///
  /// 创建一个回答 [verdict] 的记录型判据。
  RecordingPolicy({this.verdict = MovaWarmVerdict.waiting});

  @override
  MovaWarmVerdict onSignal(MovaWarmSignal signal) {
    log.add('onSignal');
    return verdict;
  }

  @override
  void reset() => log.add('reset');
}
