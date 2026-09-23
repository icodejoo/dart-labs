import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/core/swap/ctl.dart';
import 'package:mova/src/core/swap/plan.dart';
import 'package:mova/src/core/swap/swap_engine.dart';
import 'package:mova/src/core/swap/trigger.dart';
import 'package:mova/src/core/swap/warm.dart';

import '../../support/fake_api.dart';

/// Yields a few microtasks so async chains inside [MovaSwapEngine] settle
/// before assertions.
///
/// 让出几个微任务，使 [MovaSwapEngine] 内部的异步链在断言前结算完毕。
Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('MovaSwapEngine — disabled by default (pure pass-through)', () {
    late List<FakeMovaApi> made;
    late MovaSwapEngine api;

    setUp(() {
      made = <FakeMovaApi>[];
      api = MovaSwapEngine(engineFactory: () {
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
      await api.switchQuality(MovaQual.auto());
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

    test('disabled: swapEnabled is false', () {
      expect(api.swapEnabled, isFalse);
    });

    test('disabled: prepare is a no-op, phase stays idle, factory still called once', () async {
      await api.prepare(const MovaSource('https://host/b.mp4'));
      await settle();
      expect(api.swapPhase, MovaSwapPhase.idle);
      expect(made, hasLength(1));
    });

    test('disabled: commit() returns false and does not open anything', () async {
      final ok = await api.commit();
      expect(ok, isFalse);
    });

    test('disabled: swapTo opens+seeks on active and returns false', () async {
      final ok = await api.swapTo(const MovaSource('https://host/c.mp4'), at: const Duration(seconds: 3));
      expect(ok, isFalse);
      expect(made.first.calls, contains('open'));
      expect(made.first.calls, contains('seek'));
      expect(made.first.lastSeek, const Duration(seconds: 3));
    });

    test('swapPhases does not push initially, and swapPhase starts idle', () async {
      final phases = <MovaSwapPhase>[];
      final sub = api.swapPhases.listen(phases.add);
      await settle();
      expect(phases, isEmpty);
      expect(api.swapPhase, MovaSwapPhase.idle);
      await sub.cancel();
    });
  });

  group('MovaSwapEngine — enabled, warm-up and atomic commit', () {
    late List<FakeMovaApi> made;
    late MovaSwapEngine api;
    const opts = MovaOpts(swap: MovaSwapConfig(enabled: true, muteWhileWarm: true));

    MovaSwapEngine build({MovaOpts o = opts}) {
      made = <FakeMovaApi>[];
      return MovaSwapEngine(engineFactory: () {
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

    test('muteWhileWarm true mutes the shadow; false does not', () async {
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      expect(made[1].lastVolume, 0);

      final api2 = build(o: const MovaOpts(swap: MovaSwapConfig(enabled: true, muteWhileWarm: false)));
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
      expect(api.swapPhase, MovaSwapPhase.idle);
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

    test('swapPhase becomes ready once the policy signals ready, and swapPhases sees warming then ready', () async {
      final phases = <MovaSwapPhase>[];
      final sub = api.swapPhases.listen(phases.add);
      await api.prepare(
        const MovaSource('https://host/content.mp4'),
        at: const Duration(seconds: 5),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      await warmToReady(made[1], at: const Duration(seconds: 5));
      expect(api.swapPhase, MovaSwapPhase.ready);
      expect(phases, [MovaSwapPhase.warming, MovaSwapPhase.ready]);
      await sub.cancel();
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

    test('setMini forwards to the currently active engine, and to the new one after a swap', () async {
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
        reason: 'swap bookkeeping must not be skipped just because there is no '
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

    test('a progress subscriber attached before the swap keeps receiving ticks from the new engine', () async {
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
        swap: MovaSwapConfig(enabled: true, readyPolicy: MovaBufferWarm(timeout: Duration.zero)),
      );
      final a = build(o: config);
      await a.prepare(
        const MovaSource('https://host/content.mp4'),
        cue: const MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10)),
      );
      await settle();
      final shadow = made[1];
      shadow.pushProgress(const MovaProg(position: Duration.zero, buffer: Duration.zero));
      await settle();
      expect(shadow.calls, contains('dispose'));
      expect(a.swapPhase, MovaSwapPhase.idle);
      final ok = await a.commit();
      expect(ok, isFalse);
    });

    test('commit(waitForReady: true) times out via the policy and returns false, already abandoned', () async {
      final config = MovaOpts(
        swap: MovaSwapConfig(enabled: true, readyPolicy: MovaBufferWarm(timeout: const Duration(milliseconds: 1))),
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
      shadow.pushProgress(const MovaProg(position: Duration.zero, buffer: Duration.zero));
      final ok = await commitFuture;
      await settle();
      expect(ok, isFalse);
      expect(shadow.calls, contains('dispose'));
    });

    test('swapTo returns true and switches active when enabled and ready', () async {
      final commitFuture = api.swapTo(const MovaSource('https://host/variant.m3u8'), at: const Duration(seconds: 2));
      await settle();
      expect(made, hasLength(2));
      final shadow = made[1];
      await warmToReady(shadow, at: const Duration(seconds: 2));
      final ok = await commitFuture;
      expect(ok, isTrue);
      expect(api.active, same(shadow));
    });

    test('swapTo falls back to open+seek on active and returns false when disabled', () async {
      final off = build(o: const MovaOpts());
      final ok = await off.swapTo(const MovaSource('https://host/variant.m3u8'), at: const Duration(seconds: 2));
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

  group('MovaSwapEngine — Task 8 contract: swapTo maps onto quality switching semantics', () {
    late List<FakeMovaApi> made;
    late MovaSwapEngine api;
    const opts = MovaOpts(swap: MovaSwapConfig(enabled: true));

    setUp(() {
      made = <FakeMovaApi>[];
      api = MovaSwapEngine(engineFactory: () {
        final f = FakeMovaApi(options: opts);
        made.add(f);
        return f;
      });
    });

    test('swapTo opens the variant uri on the shadow and seeks to the given position', () async {
      final commitFuture =
          api.swapTo(const MovaSource('https://host/720p.m3u8'), at: const Duration(seconds: 42));
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

    test('swapTo uses eager-trigger semantics: an empty cue still creates a shadow', () async {
      final commitFuture = api.swapTo(const MovaSource('https://host/720p.m3u8'));
      await settle();
      expect(made, hasLength(2), reason: 'MovaLeadWarm would reject an empty cue, but swapTo must not');
      unawaited(commitFuture);
      await api.abandon();
    });

    test('a live source is not seeked by swapTo', () async {
      final commitFuture = api.swapTo(
        const MovaSource('https://host/live.m3u8', type: MovaStreamType.live),
        at: const Duration(seconds: 10),
      );
      await settle();
      final shadow = made[1];
      expect(shadow.calls, isNot(contains('seek')));
      unawaited(commitFuture);
      await api.abandon();
    });

    test('swapTo returning false falls back exactly like switchQuality does today', () async {
      final config = MovaOpts(
        swap: MovaSwapConfig(enabled: true, readyPolicy: MovaBufferWarm(timeout: Duration.zero)),
      );
      final made2 = <FakeMovaApi>[];
      final a = MovaSwapEngine(engineFactory: () {
        final f = FakeMovaApi(options: config);
        made2.add(f);
        return f;
      });
      final future = a.swapTo(const MovaSource('https://host/720p.m3u8'), at: const Duration(seconds: 5));
      await settle();
      final shadow = made2[1];
      shadow.pushProgress(const MovaProg(position: Duration.zero, buffer: Duration.zero));
      final ok = await future;
      expect(ok, isFalse);
      expect(made2.first.calls, contains('open'));
      expect(made2.first.lastSeek, const Duration(seconds: 5));
    });
  });

  group('MovaSwapEngine — 0.5.0 Task 1: MovaWarmPlan overrides and latent-defect fixes', () {
    late List<FakeMovaApi> made;

    /// Builds an engine whose every produced fake engine carries [o].
    ///
    /// 构造一个引擎，其产出的每个假引擎都带有 [o]。
    MovaSwapEngine build(MovaOpts o) {
      made = <FakeMovaApi>[];
      return MovaSwapEngine(engineFactory: () {
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

    test('no plan: the trigger and readiness policy still come from MovaSwapConfig', () async {
      final trigger = RecordingTrigger();
      final policy = RecordingPolicy();
      final api = build(MovaOpts(
        swap: MovaSwapConfig(enabled: true, trigger: trigger, readyPolicy: policy),
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
      final api = build(MovaOpts(swap: MovaSwapConfig(enabled: true, trigger: configured)));
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
      final api = build(MovaOpts(swap: MovaSwapConfig(enabled: true, readyPolicy: configured)));
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
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));
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
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));

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
      expect(api.swapPhase, MovaSwapPhase.warming,
          reason: 'without reset() the stale count would have committed on one lucky tick');
      made[2].pushProgress(goodTick);
      await settle();
      expect(api.swapPhase, MovaSwapPhase.ready);
    });

    test('at == Duration.zero issues no seek on the shadow; at > zero still does', () async {
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));
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
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));
      await api.prepare(const MovaSource('https://host/a.mp4'), cue: okCue);
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      made[1].pushProgress(goodTick);
      await settle();
      expect(api.swapPhase, MovaSwapPhase.ready);
      expect(made[1].calls, isNot(contains('pause')));
    });

    test('pauseWhenReady true pauses on ready, and only seeks back when at > zero', () async {
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));
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
      expect(made[1].calls, isNot(contains('seek')), reason: 'at == 0, so no rewind is needed');
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

    test('pauseWhenReady true pauses exactly once however often the policy reports ready', () async {
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));
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
      final api = build(const MovaOpts(swap: MovaSwapConfig(enabled: true)));
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
      expect(api.swapPhase, MovaSwapPhase.idle);
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
