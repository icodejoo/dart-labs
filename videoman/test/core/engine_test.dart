import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/engine.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/interceptor/interceptor.dart';
import 'package:videoman/src/core/model/quality.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/platform/ports.dart';
import 'package:videoman/src/core/state/ui_state.dart';

import '../support/fake_kernel.dart';

void main() {
  late FakeKernel k;
  late VmEngine e;

  setUp(() {
    k = FakeKernel();
    e = VmEngine(kernel: k);
  });

  tearDown(() => e.dispose());

  test('open emits VmSourceChanged then forwards to the kernel', () async {
    final events = <VmEvent>[];
    final sub = e.events.listen(events.add);
    await e.open(const VmSource('https://host/a.mp4'));
    await Future<void>.delayed(Duration.zero);
    expect(k.lastUri, 'https://host/a.mp4');
    expect(events.whereType<VmSourceChanged>(), isNotEmpty);
    expect(e.state.type, VmStreamType.vod);
    await sub.cancel();
  });

  test('kernel state is reduced into VmState', () async {
    k.emitPlaying(true);
    k.emitDuration(const Duration(minutes: 2));
    k.emitSize(1920, 1080);
    await Future<void>.delayed(Duration.zero);
    expect(e.state.playing, isTrue);
    expect(e.state.duration, const Duration(minutes: 2));
    expect(e.state.width, 1920);
  });

  test('position is exposed on the throttled progress stream, not states', () async {
    final states = <int>[];
    final sub = e.states.listen((_) => states.add(1));
    k.emitPosition(const Duration(seconds: 1));
    k.emitPosition(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    expect(states.length, 1); // 只有初始快照，position 不进 states
    await sub.cancel();
  });

  test('seek is ignored for live sources when seekMode is off', () async {
    await e.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k.calls.clear();
    await e.seek(const Duration(seconds: 5));
    expect(k.calls, isEmpty);
  });

  test('seek is allowed for live sources in dvr mode and clamped to the window', () async {
    final e2 = VmEngine(
      kernel: k,
      options: const VmOptions(live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr)),
    );
    await e2.open(const VmSource('https://host/l.m3u8', type: VmStreamType.live));
    k.emitDuration(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
    k.calls.clear();
    await e2.seek(const Duration(seconds: 90));
    expect(k.lastSeek, const Duration(seconds: 60));
    await e2.dispose();
  });

  test('beforeSeek can cancel a seek', () async {
    final e2 = VmEngine(kernel: k, interceptors: [_CancelSeek()]);
    await e2.open(const VmSource('https://host/a.mp4'));
    k.calls.clear();
    await e2.seek(const Duration(seconds: 5));
    expect(k.calls, isEmpty);
    await e2.dispose();
  });

  test('beforePlay can veto playback', () async {
    final e2 = VmEngine(kernel: k, interceptors: [_DenyPlay()]);
    k.calls.clear();
    await e2.play();
    expect(k.calls, isEmpty);
    await e2.dispose();
  });

  test('kernel errors surface on state and events', () async {
    final events = <VmEvent>[];
    final sub = e.events.listen(events.add);
    k.emitError('boom');
    await Future<void>.delayed(Duration.zero);
    expect(e.state.error, 'boom');
    expect(events.whereType<VmErrorEvent>(), isNotEmpty);
    await sub.cancel();
  });

  test('showHud/hideControls drive VmUiState', () async {
    e.showHud(VmHud.volume);
    expect(e.uiState.hud, VmHud.volume);
    e.hideControls();
    expect(e.uiState.controlsVisible, isFalse);
  });

  test('setDragging carries the preview position and clears it on release', () {
    e.setDragging(true, previewAt: const Duration(seconds: 12));
    expect(e.uiState.dragging, isTrue);
    expect(e.uiState.previewAt, const Duration(seconds: 12));
    e.setDragging(false);
    expect(e.uiState.previewAt, isNull);
  });

  test('ABR downshifts after the configured number of stalls', () async {
    // Seed two pinned variants (not auto) plus an auto entry, and select the
    // higher-bandwidth one as current — mirrors what loadQualities() would
    // produce from a real HLS master playlist, without the HTTP round trip.
    //
    // 注入两档非自动清晰度（外加一档自动）并选中较高档为当前档——模拟
    // loadQualities() 从真实 HLS master playlist 解析出的结果，但省去 HTTP
    // 往返。
    const auto = VmQuality(label: '自动', uri: '', isAuto: true);
    const high = VmQuality(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
    const low = VmQuality(label: '480p', uri: 'https://host/480.m3u8', height: 480);
    e.debugSetQualities(const [auto, high, low], current: high);

    final events = <VmEvent>[];
    final sub = e.events.listen(events.add);

    // Three buffering rising edges (threshold defaults to 3) should trigger
    // exactly one downshift from `high` to `low`.
    //
    // 三次缓冲上升沿（默认阈值 3）应恰好触发一次从 `high` 到 `low` 的降档。
    for (var i = 0; i < 3; i++) {
      k.emitBuffering(true);
      k.emitBuffering(false);
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(Duration.zero);

    expect(k.lastUri, low.uri);
    expect(e.state.currentQuality, low);
    expect(events.whereType<VmAbrDownshift>().length, 1);
    final downshift = events.whereType<VmAbrDownshift>().single;
    expect(downshift.from, high);
    expect(downshift.to, low);

    await sub.cancel();
  });

  test('rapid sequential stall-cycles each produce exactly one downshift '
      'without corrupting currentQuality', () async {
    // Three pinned variants so two consecutive downshifts are observable
    // (high -> mid -> low). Regression test for the ABR reentrancy guard:
    // without `_abrDownshiftInFlight`, overlapping in-flight downshifts
    // could race on `_kernel` and double-fire/swallow VmAbrDownshift or
    // leave currentQuality inconsistent with what was actually `open()`ed.
    //
    // Note: `downshiftQuality()`'s only awaited work in this harness is a
    // `FakeKernel.open()`/`seek()` call that resolves on the next
    // microtask (no real async gap), so within a single test process we
    // cannot force two `downshiftQuality()` futures to be genuinely
    // in-flight at the same instant — the guard is exercised by asserting
    // that back-to-back full stall cycles, fired without any inter-cycle
    // delay, still resolve to exactly one VmAbrDownshift per cycle and a
    // consistent final quality. A true concurrent race (two overlapping
    // async kernel round-trips) isn't practically triggerable without
    // instrumenting FakeKernel to insert an artificial delay inside
    // open()/seek(), which this harness does not do.
    //
    // 用三档清晰度以便观察两次连续降档（high -> mid -> low）。这是 ABR
    // 重入保护的回归测试：没有 `_abrDownshiftInFlight` 时，重叠的进行中降档
    // 可能在 `_kernel` 上竞争，导致 VmAbrDownshift 重复/漏发，或
    // currentQuality 与实际 `open()` 的清晰度不一致。
    //
    // 说明：本测试用的 `downshiftQuality()` 唯一的 await 点是
    // `FakeKernel.open()`/`seek()`，其在下一个微任务即可完成（没有真实的
    // 异步间隔），因此单个测试进程内无法强制让两个 `downshiftQuality()`
    // future 真正同时在途——本测试改为验证：不留 cycle 间隔地连续触发两轮
    // 完整的 stall 周期，仍能得到每轮恰好一次 VmAbrDownshift，且最终清晰度
    // 一致。要制造真正并发的竞争（两个重叠的异步内核往返），需要给
    // FakeKernel 的 open()/seek() 插入人为延迟，本测试骨架未做这件事。
    const auto = VmQuality(label: '自动', uri: '', isAuto: true);
    const high = VmQuality(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
    const mid = VmQuality(label: '720p', uri: 'https://host/720.m3u8', height: 720);
    const low = VmQuality(label: '480p', uri: 'https://host/480.m3u8', height: 480);
    e.debugSetQualities(const [auto, high, mid, low], current: high);

    final events = <VmEvent>[];
    final sub = e.events.listen(events.add);

    // First stall cycle: high -> mid. Fire all six buffering edges (two
    // full cycles' worth) back-to-back with no await in between, so any
    // overlap in the downshift's async tail would surface here.
    //
    // 第一轮 stall 周期：high -> mid。把两轮完整周期的六个缓冲沿一次性连续
    // 触发，不在中间 await，这样降档异步尾部的任何重叠都会在此暴露。
    for (var i = 0; i < 3; i++) {
      k.emitBuffering(true);
      k.emitBuffering(false);
    }
    for (var i = 0; i < 3; i++) {
      k.emitBuffering(true);
      k.emitBuffering(false);
    }
    // Drain microtasks/timers until both downshifts have settled.
    //
    // 排空微任务/定时器直到两次降档都已完成。
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final downshifts = events.whereType<VmAbrDownshift>().toList();
    expect(downshifts.length, 2);
    expect(downshifts[0].from, high);
    expect(downshifts[0].to, mid);
    expect(downshifts[1].from, mid);
    expect(downshifts[1].to, low);
    expect(e.state.currentQuality, low);
    expect(k.lastUri, low.uri);

    await sub.cancel();
  });

  test('setFullscreen re-applies orientation when size arrives later while '
      'fullscreen', () async {
    final spy = _SpyOrientationPort();
    final e2 = VmEngine(kernel: k, orientation: spy);

    // Enter fullscreen before the kernel has reported any real size.
    //
    // 在内核报告真实尺寸之前进入全屏。
    await e2.setFullscreen(true);
    expect(spy.calls.length, 1);
    expect(spy.calls.single, (0, 0));

    // Size arrives later (e.g. HLS manifest resolved) — orientation should
    // be re-derived/re-applied using the fresh dimensions.
    //
    // 尺寸随后才到达（如 HLS manifest 解析完成）——应使用新尺寸重新推导并
    // 应用方向。
    k.emitSize(1920, 1080);
    await Future<void>.delayed(Duration.zero);
    expect(spy.calls.length, 2);
    expect(spy.calls.last, (1920, 1080));

    await e2.dispose();
  });

  test('size changes while NOT fullscreen do not re-apply orientation', () async {
    final spy = _SpyOrientationPort();
    final e2 = VmEngine(kernel: k, orientation: spy);

    k.emitSize(1280, 720);
    await Future<void>.delayed(Duration.zero);
    expect(spy.calls, isEmpty);

    await e2.dispose();
  });
}

/// A spy [VmOrientationPort] that records every `apply(...)` call's
/// width/height so tests can assert re-application behavior.
///
/// 记录每次 `apply(...)` 调用的宽高的 [VmOrientationPort] 间谍实现，供测试
/// 断言重新应用行为。
class _SpyOrientationPort implements VmOrientationPort {
  /// Every (width, height) pair passed to [apply], in call order.
  ///
  /// 每次 [apply] 调用传入的 (width, height)，按调用顺序记录。
  final List<(int, int)> calls = [];

  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
  }) async {
    calls.add((width, height));
  }

  @override
  Future<void> reset() async {}
}

class _CancelSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

class _DenyPlay extends VmInterceptor {
  @override
  Future<bool> beforePlay() async => false;
}
