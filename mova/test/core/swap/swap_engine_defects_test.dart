import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/swap/ctl.dart';
import 'package:mova/src/core/swap/retirable.dart';
import 'package:mova/src/core/swap/swap_engine.dart';
import 'package:mova/src/core/swap/trigger.dart';

import '../../support/fake_api.dart';
import '../../support/fake_kernel.dart';

/// A fake whose `pause()` blocks until [gate] completes, to hold a hand-off
/// mid-flight.
///
/// 让 `pause()` 阻塞到 [gate] 完成的假引擎，用来把换指卡在半途。
class _GatedPauseApi extends FakeMovaApi {
  /// Creates the fake with [options].
  ///
  /// 以 [options] 创建。
  _GatedPauseApi({super.options});

  /// Completer that releases the pending `pause()`.
  ///
  /// 放行挂起的 `pause()` 的 completer。
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> pause() async {
    await super.pause();
    await gate.future;
  }
}

/// Fake that records `markRetired` and whether it came before `dispose`.
///
/// 记录 `markRetired` 以及它是否先于 `dispose` 的假引擎。
class _RetirableApi extends FakeMovaApi implements MovaHandoffRetirable {
  /// Creates the fake with [options].
  ///
  /// 以 [options] 创建。
  _RetirableApi({super.options});

  /// Whether `markRetired` was called.
  ///
  /// 是否调用过 `markRetired`。
  bool retired = false;

  /// Whether `markRetired` had already been called when `dispose` ran.
  ///
  /// `dispose` 执行时是否已调用过 `markRetired`。
  bool retiredBeforeDispose = false;

  @override
  void markRetired() => retired = true;

  @override
  Future<void> dispose() {
    retiredBeforeDispose = retired;
    return super.dispose();
  }
}

/// Orientation port that counts `reset` calls.
///
/// 统计 `reset` 调用次数的方向端口。
class _CountingOrientationPort implements MovaOrientationPort {
  /// How many times `reset` was called.
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
  }) async {}

  @override
  Future<void> reset() async => resets++;
}

/// Fail policy that records every failure it is shown and skips the break.
///
/// 记录所有被告知的失败并跳过广告位的失败策略。
class _RecordingFail implements MovaAdFailPolicy {
  /// Every failure passed to [onFailure], in order.
  ///
  /// 依次传给 [onFailure] 的所有失败记录。
  final List<MovaAdFail> seen = <MovaAdFail>[];

  @override
  MovaAdFailAction onFailure(MovaAdFail failure) {
    seen.add(failure);
    return MovaAdFailAction.skipBreak;
  }
}

/// Number of `dispose` calls recorded on [f].
///
/// [f] 上记录的 `dispose` 调用次数。
int disposeCount(FakeMovaApi f) => f.calls.where((c) => c == 'dispose').length;

/// Pushes two matching ticks so the default buffer policy reports ready.
///
/// 推两次匹配的 tick，让默认缓冲判据报告就绪。
void pushReady(FakeMovaApi shadow) {
  const sig = MovaProg(position: Duration(seconds: 5), buffer: Duration(seconds: 6));
  shadow.pushProgress(sig);
  shadow.pushProgress(sig);
}

/// Fake whose `open()` blocks until [gate] completes, to let the ready timer
/// expire while the shadow is still opening.
///
/// 让 `open()` 阻塞到 [gate] 完成的假引擎，用来让就绪计时器在影子仍在打开时到期。
class _GatedOpenApi extends FakeMovaApi {
  /// Creates the fake with [options].
  ///
  /// 以 [options] 创建。
  _GatedOpenApi({super.options});

  /// Completer that releases the pending `open()`.
  ///
  /// 放行挂起的 `open()` 的 completer。
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> open(MovaSource source, {bool autoPlay = true}) async {
    await super.open(source, autoPlay: autoPlay);
    await gate.future;
  }
}

/// Fake whose `dispose()` blocks until [gate] completes, to keep an
/// `abandon()` in flight while a new warm-up starts.
///
/// 让 `dispose()` 阻塞到 [gate] 完成的假引擎，用来让 `abandon()` 悬在半途、
/// 同时启动新的预热。
class _GatedDisposeApi extends FakeMovaApi {
  /// Creates the fake with [options].
  ///
  /// 以 [options] 创建。
  _GatedDisposeApi({super.options});

  /// Completer that releases the pending `dispose()`.
  ///
  /// 放行挂起的 `dispose()` 的 completer。
  final Completer<void> gate = Completer<void>();

  @override
  Future<void> dispose() async {
    await gate.future;
    await super.dispose();
  }
}

void main() {
  const opts = MovaOpts(
    swap: MovaSwapConfig(enabled: true, muteWhileWarm: false, readyTimeout: Duration(seconds: 2)),
  );
  const a = MovaSource('https://host/a.mp4');
  const b = MovaSource('https://host/b.mp4');
  const c = MovaSource('https://host/c.mp4');
  const cue = MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10));

  late List<FakeMovaApi> made;
  MovaSwapEngine build(FakeMovaApi Function(int i) make) {
    made = <FakeMovaApi>[];
    return MovaSwapEngine(engineFactory: () {
      final f = make(made.length);
      made.add(f);
      return f;
    });
  }

  test('#3 readyTimeout fires with no progress events: commit(waitForReady) resolves false', () async {
    const fast = MovaOpts(
      swap: MovaSwapConfig(enabled: true, muteWhileWarm: false, readyTimeout: Duration(milliseconds: 50)),
    );
    final api = build((_) => FakeMovaApi(options: fast));
    await api.prepare(a, cue: cue);
    // The shadow never emits progress; only the deadline timer can end this.
    //
    // 影子引擎从不发 progress，只有期限计时器能结束等待。
    final ok = await api.commit(waitForReady: true).timeout(const Duration(seconds: 2), onTimeout: () => true);
    expect(ok, isFalse);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(made[1].disposed, isTrue);
    expect(api.swapPhase, MovaSwapPhase.idle);
  });

  test('#4 shadow open() throwing is cleaned up: no throw, shadow disposed, swapTo falls back', () async {
    final api = build((i) {
      final f = FakeMovaApi(options: opts);
      if (i == 1) f.openThrows = StateError('boom');
      return f;
    });
    final errors = <MovaEvent>[];
    final sub = api.events.listen((e) {
      if (e is MovaErrorEvent) errors.add(e);
    });
    final ok = await api.swapTo(a);
    expect(ok, isFalse);
    // 影子预热失败只内部处理，不往主事件流发错误（否则会被广告控制器误判）。
    expect(errors, isEmpty);
    await sub.cancel();
    expect(made[1].disposed, isTrue);
    expect(made[0].openedUris, [a.uri]);
    // A later prepare is no longer ignored.
    await api.prepare(b, cue: cue);
    expect(made, hasLength(3));
  });

  test('#5 swapTo(C) while a shadow for B exists replaces it and commits C', () async {
    final api = build((_) => FakeMovaApi(options: opts));
    await api.prepare(b, cue: cue);
    expect(made, hasLength(2));
    final f = api.swapTo(c);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(made, hasLength(3));
    expect(made[1].disposed, isTrue);
    pushReady(made[2]);
    expect(await f, isTrue);
    expect(api.active, same(made[2]));
    expect(made[2].openedUris, [c.uri]);
  });

  test('swapTo right after an un-awaited abandon keeps the new warm-up alive', () async {
    final api = build((i) => i == 1 ? _GatedDisposeApi(options: opts) : FakeMovaApi(options: opts));
    await api.prepare(b, cue: cue);
    expect(api.swapPhase, MovaSwapPhase.warming);
    // Same shape as AdController._playAd's oneShot branch.
    unawaited(api.abandon());
    final f = api.swapTo(c);
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(made, hasLength(3));
    // The stale abandon finishes only now; it must not clobber the new warm-up.
    (made[1] as _GatedDisposeApi).gate.complete();
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(api.swapPhase, MovaSwapPhase.warming);
    pushReady(made[2]);
    expect(await f, isTrue);
    expect(api.active, same(made[2]));
  });

  test('#6 dispose during _commitNow: shadow disposed, old disposed once, not promoted', () async {
    final api = build((i) => i == 0 ? _GatedPauseApi(options: opts) : FakeMovaApi(options: opts));
    await api.prepare(a, cue: cue);
    pushReady(made[1]);
    await Future<void>.delayed(Duration.zero);
    final f = api.commit();
    await Future<void>.delayed(Duration.zero);
    final d = api.dispose();
    (made[0] as _GatedPauseApi).gate.complete();
    await d;
    expect(await f, isFalse);
    expect(made[1].disposed, isTrue);
    expect(disposeCount(made[0]), 1);
    expect(made[1].calls, isNot(contains('play')));
  });

  test('#17 commit migrates user view settings from the old engine onto the shadow before play', () async {
    final api = build((_) => FakeMovaApi(options: opts));
    made[0].push(made[0].state.copyWith(
          rate: 2.0,
          fit: MovaFit.cover,
          zoom: 1.5,
          volume: 0.4,
          locked: true,
          fullscreen: true,
          mini: true,
        ));
    await api.prepare(a, cue: cue);
    pushReady(made[1]);
    await Future<void>.delayed(Duration.zero);
    expect(await api.commit(), isTrue);
    final shadow = made[1];
    expect(shadow.lastRate, 2.0);
    expect(shadow.lastFit, MovaFit.cover);
    expect(shadow.lastZoom, 1.5);
    expect(shadow.lastVolume, 0.4);
    expect(shadow.lastLocked, isTrue);
    expect(shadow.lastFullscreen, isTrue);
    expect(shadow.lastMini, isTrue);
    // 必须在 play() 之前补齐，避免以默认设置先放出一小段。
    final playAt = shadow.calls.indexOf('play');
    expect(shadow.calls.indexOf('setRate'), lessThan(playAt));
    expect(shadow.calls.indexOf('setFullscreen'), lessThan(playAt));
  });

  test('#17 default settings produce no extra setter calls on the shadow', () async {
    final api = build((_) => FakeMovaApi(options: opts));
    await api.prepare(a, cue: cue);
    pushReady(made[1]);
    await Future<void>.delayed(Duration.zero);
    expect(await api.commit(), isTrue);
    expect(made[1].calls.where((c) => c.startsWith('set')), isEmpty);
  });

  test('#1 commit marks a retirable old engine retired before disposing it', () async {
    final api = build((i) => i == 0 ? _RetirableApi(options: opts) : FakeMovaApi(options: opts));
    await api.prepare(a, cue: cue);
    pushReady(made[1]);
    await Future<void>.delayed(Duration.zero);
    expect(await api.commit(), isTrue);
    final old = made[0] as _RetirableApi;
    expect(old.retired, isTrue);
    expect(old.retiredBeforeDispose, isTrue);
    expect(old.disposed, isTrue);
  });

  test('#1 commit with a non-retirable old engine does not throw', () async {
    final api = build((_) => FakeMovaApi(options: opts));
    await api.prepare(a, cue: cue);
    pushReady(made[1]);
    await Future<void>.delayed(Duration.zero);
    expect(await api.commit(), isTrue);
    expect(made[0].disposed, isTrue);
  });

  test('#1 fullscreen swap commit: old real engine does not reset orientation, new stays fullscreen', () async {
    final port = _CountingOrientationPort();
    final kernels = <FakeKernel>[];
    final api = MovaSwapEngine(engineFactory: () {
      final k = FakeKernel();
      kernels.add(k);
      return MovaEngine(kernel: k, orientation: port, options: opts);
    });
    await api.setFullscreen(true);
    await api.prepare(a, cue: cue);
    final old = api.active;
    expect(old.state.fullscreen, isTrue);
    final done = api.commit(waitForReady: true);
    for (var i = 0; i < 4; i++) {
      kernels[1].emitDuration(const Duration(seconds: 60));
      kernels[1].emitPosition(const Duration(seconds: 5));
      kernels[1].emitBuffer(const Duration(seconds: 6));
      // 引擎的 progress 有 200ms 节流，需真实时间间隔。
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(await done, isTrue);
    expect(api.active, isNot(same(old)));
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(port.resets, 0);
    expect(api.state.fullscreen, isTrue);
  });

  test('#3 non-fullscreen forced landscape migrates to the successor; its dispose resets once', () async {
    final port = _CountingOrientationPort();
    final kernels = <FakeKernel>[];
    final api = MovaSwapEngine(engineFactory: () {
      final k = FakeKernel();
      kernels.add(k);
      return MovaEngine(kernel: k, orientation: port, options: opts);
    });
    await api.setOrientation(MovaOrientation.landscape);
    await api.prepare(a, cue: cue);
    final old = api.active;
    final done = api.commit(waitForReady: true);
    for (var i = 0; i < 4; i++) {
      kernels[1].emitDuration(const Duration(seconds: 60));
      kernels[1].emitPosition(const Duration(seconds: 5));
      kernels[1].emitBuffer(const Duration(seconds: 6));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(await done, isTrue);
    expect(api.active, isNot(same(old)));
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // 旧引擎已退役，不复位；继任者必须带着强制方向。
    expect(port.resets, 0);
    expect(api.active.state.orientation, MovaOrientation.landscape);
    await api.dispose();
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(port.resets, 1);
  });

  test('#1 shadow warm-up open() throwing emits no MovaErrorEvent: a healthy ad is not failed', () async {
    final policy = _RecordingFail();
    final adOpts = MovaOpts(
      swap: const MovaSwapConfig(
        enabled: true,
        muteWhileWarm: false,
        readyTimeout: Duration(seconds: 2),
        trigger: MovaEagerWarm(),
      ),
      ads: MovaAdConfig(
        enabled: true,
        breaks: const [
          MovaAdBreak(
            kind: MovaAdBreakKind.mid,
            source: MovaSource('https://host/mid.mp4'),
            offset: Duration(seconds: 30),
          ),
        ],
        failPolicy: policy,
        waitForAdReady: const MovaAdWaitByKind(mid: false),
      ),
    );
    final api = build((i) {
      final f = FakeMovaApi(options: adOpts);
      if (i == 1) f.openThrows = StateError('shadow boom');
      return f;
    });
    final errors = <MovaErrorEvent>[];
    final sub = api.events.listen((e) {
      if (e is MovaErrorEvent) errors.add(e);
    });
    final ctl = MovaAdController(api, swap: api);
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    ctl.load(a);
    await settle();
    made[0].pushProgress(const MovaProg(position: Duration(seconds: 31)));
    await settle();
    expect(ctl.isShowingAd, isTrue);
    // 广告在播时的 progress 会触发后台预热正片；影子 open 抛错。
    made[0].pushProgress(const MovaProg(position: Duration(seconds: 1)));
    await settle();
    expect(made, hasLength(greaterThan(1)), reason: 'the warm-up was really attempted');
    expect(errors, isEmpty);
    expect(policy.seen, isEmpty);
    expect(ctl.isShowingAd, isTrue);
    await ctl.dispose();
    await sub.cancel();
  });

  test('abandoned during shadow open(): no seek on the disposed shadow, disposed once', () async {
    const fast = MovaOpts(
      swap: MovaSwapConfig(enabled: true, muteWhileWarm: false, readyTimeout: Duration(milliseconds: 50)),
    );
    late _GatedOpenApi gated;
    final api = build((i) {
      if (i == 1) return gated = _GatedOpenApi(options: fast);
      return FakeMovaApi(options: fast);
    });
    // 目标位置 > 0，才会走 open 之后的 seek 分支。
    final warm = api.prepare(a, at: const Duration(seconds: 5), cue: cue);
    // 等 readyTimeout 在 open 挂起期间到期，abandon 已销毁影子。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(gated.disposed, isTrue);
    gated.gate.complete();
    await warm;
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(gated.calls, isNot(contains('seek')));
    expect(disposeCount(gated), 1);
  });
}
