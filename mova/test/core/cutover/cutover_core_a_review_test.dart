import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 'package:mova/src/testing/hooks.dart';

import 'cutover_operation_test.dart' show DetachGatedApi, settleOperations;

/// Exposes the final play and settings awaits without replacing hand-off logic.
///
/// 暴露最终播放与设置的等待点，不替换换指逻辑。
class _Api extends DetachGatedApi implements IMovaKeepAlive {
  /// Enables cutover with silent warm-up disabled for the fake API.
  ///
  /// 启用切换，并为假 API 禁用预热静音。
  _Api()
    : super(
        options: const MovaOpts(
          cutover: MovaCutoverOpts(enabled: true, muteWhileWarm: false),
        ),
      );

  Completer<void>? finalPlayGate, rateGate, fullscreenGate;
  int playCount = 0;

  /// Blocks only the final reconciliation play.
  ///
  /// 仅阻塞最终协调时的播放。
  @override
  Future<void> play() async {
    if (++playCount >= 2) await finalPlayGate?.future;
    await super.play();
  }

  /// Lets tests change the outgoing view while inheritance is pending.
  ///
  /// 允许测试在继承挂起期间修改旧播放器视图。
  @override
  Future<void> setRate(double r) async {
    await rateGate?.future;
    await super.setRate(r);
    push(state.copyWith(rate: r));
  }

  /// Publishes fullscreen changes as a real player would.
  ///
  /// 像真实播放器一样发布全屏变化。
  @override
  Future<void> setFullscreen(bool v) async {
    await fullscreenGate?.future;
    await super.setFullscreen(v);
    push(state.copyWith(fullscreen: v));
  }

  /// Records and publishes the requested keep-alive phase.
  ///
  /// 记录并发布请求的待机阶段。
  @override
  Future<MovaKeepAlivePhase> setKeepAlive(bool on) async {
    calls.add('setKeepAlive:$on');
    final phase = on ? MovaKeepAlivePhase.holding : MovaKeepAlivePhase.off;
    push(state.copyWith(keepAlivePhase: phase));
    return phase;
  }
}

/// Owns fake players while exercising the real proxy.
///
/// 持有假播放器，同时运行真实代理。
class _Rig {
  /// Records each player and seeds explicit playback intent.
  ///
  /// 记录每个播放器，并设置明确的播放意图。
  _Rig() {
    api = MovaCutover(
      movaFactory: () {
        final mova = _Api();
        movas.add(mova);
        return mova;
      },
    );
    movas.first.push(movas.first.state.copyWith(playbackIntent: true));
  }

  final movas = <_Api>[];
  late final MovaCutover api;

  /// Warms and readies a shadow at [at] under [plan].
  ///
  /// 按 [plan] 在 [at] 预热影子并令其就绪。
  Future<_Api> warm({
    Duration at = Duration.zero,
    MovaWarmPlan plan = const MovaWarmPlan(trigger: MovaEagerWarm()),
  }) async {
    await api.prepare(
      const MovaSource('https://h/next.mp4'),
      at: at,
      plan: plan,
    );
    final shadow = movas.last;
    await ready(shadow, at);
    return shadow;
  }

  /// Delivers the consecutive observations required by the buffer policy.
  ///
  /// 发送缓冲策略要求的连续观测。
  Future<void> ready(_Api shadow, Duration at) async {
    final tick = MovaProg(
      position: at,
      buffer: at + const Duration(seconds: 10),
    );
    shadow.pushProgress(tick);
    await settleOperations();
    shadow.pushProgress(tick);
    await settleOperations();
  }
}

/// Covers coreA's cutover failures at their actual asynchronous boundaries.
///
/// 在真实异步边界覆盖 coreA 的切换问题。
void main() {
  for (final point in ['final play', 'late rate']) {
    test('coreA1 fatal shadow during $point prevents promotion', () async {
      final rig = _Rig();
      addTearDown(rig.api.dispose);
      final shadow = await rig.warm();
      final gate = shadow.finalPlayGate = Completer<void>();
      final committing = rig.api.commit();
      await settleOperations();
      expect(shadow.playCount, 2);
      if (point == 'late rate') {
        shadow.rateGate = Completer<void>();
        await rig.api.setRate(2);
        gate.complete();
        await settleOperations();
      }
      shadow.pushEvent(const MovaErrorEvent('fatal shadow'));
      await settleOperations();
      if (!gate.isCompleted) gate.complete();
      shadow.rateGate?.complete();
      expect(await committing, isFalse);
      expect(rig.api.active, same(rig.movas.first));
      expect(shadow.disposeCount, 1);
      expect(rig.movas.first.disposeCount, 0);
    });
  }

  for (final initiallyHeld in [false, true]) {
    test('coreA2 late keepAlive ${!initiallyHeld} reaches successor', () async {
      final rig = _Rig();
      addTearDown(rig.api.dispose);
      await rig.api.setKeepAlive(initiallyHeld);
      final shadow = await rig.warm();
      final gate = shadow.finalPlayGate = Completer<void>();
      final committing = rig.api.commit();
      await settleOperations();
      expect(shadow.playCount, 2);
      await rig.api.setKeepAlive(!initiallyHeld);
      gate.complete();
      expect(await committing, isTrue);
      expect(shadow.calls, contains('setKeepAlive:${!initiallyHeld}'));
      expect(
        shadow.state.keepAlivePhase,
        initiallyHeld ? MovaKeepAlivePhase.off : MovaKeepAlivePhase.holding,
      );
    });
  }

  test('coreA5 mini handoff disposes the retired real player', () async {
    final kernels = <MovaTestKernel>[];
    final api = MovaCutover(
      movaFactory: () {
        final kernel = MovaTestKernel();
        kernels.add(kernel);
        return Mova(
          kernel: kernel,
          ownsKernel: true,
          fetcher: const MovaTestHttpFetch(),
          options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)),
        );
      },
    );
    addTearDown(() async {
      await api.setMini(false);
      await api.dispose();
    });
    await api.open(const MovaSource('https://h/old.mp4'));
    await api.setMini(true);
    await api.prepare(
      const MovaSource('https://h/next.mp4'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    for (var i = 0; i < 3; i++) {
      kernels.last.emitPosition(Duration(seconds: i + 1));
      kernels.last.emitBuffer(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(api.cutoverPhase, MovaCutoverPhase.ready);
    expect(await api.commit(), isTrue);
    await settleOperations();
    expect(kernels.first.calls, contains('dispose'));
    expect(api.state.mini, isTrue);
  });

  for (final point in ['pause', 'final play']) {
    test('coreA6 abandon cancels claimed commit during $point', () async {
      final rig = _Rig();
      addTearDown(rig.api.dispose);
      final shadow = await rig.warm();
      final gate = Completer<void>();
      if (point == 'pause') rig.movas.first.pauseGate = gate;
      if (point == 'final play') shadow.finalPlayGate = gate;
      final committing = rig.api.commit();
      await settleOperations();
      await rig.api.abandon();
      gate.complete();
      expect(await committing, isFalse);
      expect(rig.api.active, same(rig.movas.first));
      expect(shadow.disposeCount, 1);
      expect(rig.api.state.renderEpoch, 0);
    });
  }

  for (final change in ['target', 'rate', 'holding', 'policy']) {
    test(
      'coreA7 same source with changed $change gets a fresh warm plan',
      () async {
        final rig = _Rig();
        addTearDown(rig.api.dispose);
        final first = await rig.warm(at: const Duration(seconds: 10));
        final at = Duration(seconds: change == 'target' ? 50 : 10);
        final plan = MovaWarmPlan(
          trigger: const MovaEagerWarm(),
          rate: change == 'rate' ? 2 : null,
          pauseWhenReady: change == 'holding',
          policy: change == 'policy' ? MovaBufferWarm() : null,
        );
        final next = await rig.warm(at: at, plan: plan);
        expect(next, isNot(same(first)));
        expect(first.disposeCount, 1);
        expect(next.lastSeek, at);
        expect(await rig.api.commit(), isTrue);
        if (change == 'rate') expect(next.state.rate, 2);
        if (change == 'holding') expect(next.calls, contains('pause'));
      },
    );
  }

  test(
    'coreA7 cutoverTo honors a new target and rate for the same source',
    () async {
      final rig = _Rig();
      addTearDown(rig.api.dispose);
      final oldShadow = await rig.warm(at: const Duration(seconds: 10));
      final switching = rig.api.cutoverTo(
        const MovaSource('https://h/next.mp4'),
        at: const Duration(seconds: 50),
        rate: 2,
      );
      await settleOperations();
      final next = rig.movas.last;
      expect(next, isNot(same(oldShadow)));
      await rig.ready(next, const Duration(seconds: 50));
      expect(await switching, isTrue);
      expect(next.lastSeek, const Duration(seconds: 50));
      expect(next.state.rate, 2);
    },
  );

  test(
    'coreA8 late fullscreen exit survives pending settings inheritance',
    () async {
      final rig = _Rig();
      addTearDown(rig.api.dispose);
      await rig.api.setRate(1.5);
      await rig.api.setFullscreen(true);
      final shadow = await rig.warm();
      final gate = shadow.rateGate = Completer<void>();
      final committing = rig.api.commit();
      await settleOperations();
      await rig.api.setFullscreen(false);
      gate.complete();
      expect(await committing, isTrue);
      expect(shadow.state.fullscreen, isFalse);
      expect(rig.api.state.fullscreen, isFalse);
    },
  );

  test(
    'coreA8 handoff waits for late view completion and preserves late rate',
    () async {
      final rig = _Rig();
      addTearDown(rig.api.dispose);
      await rig.api.setFullscreen(true);
      final shadow = await rig.warm(
        plan: const MovaWarmPlan(trigger: MovaEagerWarm(), rate: 1.5),
      );
      final gate = shadow.finalPlayGate = Completer<void>();
      final committing = rig.api.commit();
      await settleOperations();
      await rig.api.setRate(2);
      final viewGate = rig.movas.first.fullscreenGate = Completer<void>();
      final changing = rig.api.setFullscreen(false);
      gate.complete();
      await settleOperations();
      expect(rig.api.active, same(rig.movas.first));
      viewGate.complete();
      await changing;
      expect(await committing, isTrue);
      expect(shadow.state.fullscreen, isFalse);
      expect(shadow.state.rate, 2);
    },
  );

  for (final stream in ['events', 'phases']) {
    test(
      'coreA12 dispose completes with paused $stream subscription',
      () async {
        final rig = _Rig();
        var done = false;
        final sub =
            (stream == 'events' ? rig.api.events : rig.api.cutoverPhases)
                .listen((_) {}, onDone: () => done = true);
        sub.pause();
        await rig.api.dispose().timeout(const Duration(seconds: 1));
        expect(rig.movas.first.disposed, isTrue);
        expect(done, isFalse);
        sub.resume();
        await settleOperations();
        expect(done, isTrue);
        await sub.cancel();
      },
    );
  }
}
