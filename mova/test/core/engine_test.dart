import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/interceptor/interceptor.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/core/model/quality.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/core/stt/cue.dart';
import 'package:mova/src/core/stt/port.dart';

import '../support/fake_kernel.dart';

void main() {
  late FakeKernel k;
  late MovaEngine e;

  setUp(() {
    k = FakeKernel();
    e = MovaEngine(kernel: k);
  });

  tearDown(() => e.dispose());

  test('open emits MovaSourceChg then forwards to the kernel', () async {
    final events = <MovaEvent>[];
    final sub = e.events.listen(events.add);
    await e.open(const MovaSource('https://host/a.mp4'));
    await Future<void>.delayed(Duration.zero);
    expect(k.lastUri, 'https://host/a.mp4');
    expect(events.whereType<MovaSourceChg>(), isNotEmpty);
    expect(e.state.type, MovaStreamType.vod);
    await sub.cancel();
  });

  test('kernel state is reduced into MovaState', () async {
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
    await e.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k.calls.clear();
    await e.seek(const Duration(seconds: 5));
    expect(k.calls, isEmpty);
  });

  test('seek is allowed for live sources in dvr mode and clamped to the window', () async {
    final e2 = MovaEngine(
      kernel: k,
      options: const MovaOpts(live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr)),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k.emitDuration(const Duration(seconds: 60));
    await Future<void>.delayed(Duration.zero);
    k.calls.clear();
    await e2.seek(const Duration(seconds: 90));
    expect(k.lastSeek, const Duration(seconds: 60));
    await e2.dispose();
  });

  test('beforeSeek can cancel a seek', () async {
    final e2 = MovaEngine(kernel: k, interceptors: [_CancelSeek()]);
    await e2.open(const MovaSource('https://host/a.mp4'));
    k.calls.clear();
    await e2.seek(const Duration(seconds: 5));
    expect(k.calls, isEmpty);
    await e2.dispose();
  });

  test('a VOD seek before duration is known is parked, then replayed on duration', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    k.calls.clear();
    // Duration not reported yet — mpv drops such a seek, so it must be parked.
    await e.seek(const Duration(seconds: 30));
    expect(k.calls, isEmpty, reason: 'seek must not reach the kernel pre-duration');
    // Duration arrives → the parked seek is replayed to the kernel.
    k.emitDuration(const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);
    expect(k.calls, contains('seek'));
    expect(k.lastSeek, const Duration(seconds: 30));
  });

  test('a parked VOD seek is clamped into the duration once it is known', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    k.calls.clear();
    await e.seek(const Duration(seconds: 600)); // past the eventual end
    expect(k.calls, isEmpty);
    k.emitDuration(const Duration(seconds: 120));
    await Future<void>.delayed(Duration.zero);
    expect(k.lastSeek, const Duration(seconds: 120));
  });

  test('opening a new source discards a still-parked seek', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    await e.seek(const Duration(seconds: 30)); // parked (no duration reported)
    await e.open(const MovaSource('https://host/b.mp4')); // clears the park
    k.calls.clear();
    k.emitDuration(const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);
    expect(k.calls, isEmpty,
        reason: 'a parked seek from the previous source must not fire');
  });

  test('beforePlay can veto playback', () async {
    final e2 = MovaEngine(kernel: k, interceptors: [_DenyPlay()]);
    k.calls.clear();
    await e2.play();
    expect(k.calls, isEmpty);
    await e2.dispose();
  });

  test('kernel errors surface on state and events', () async {
    final events = <MovaEvent>[];
    final sub = e.events.listen(events.add);
    k.emitError('boom');
    await Future<void>.delayed(Duration.zero);
    expect(e.state.error, 'boom');
    expect(events.whereType<MovaErrorEvent>(), isNotEmpty);
    await sub.cancel();
  });

  test('showHud/hideControls drive MovaUiState', () async {
    e.showHud(MovaHud.volume);
    expect(e.uiState.hud, MovaHud.volume);
    e.hideControls();
    expect(e.uiState.controlsVisible, isFalse);
  });

  test('showHud with text populates hudText (regression: double-tap seek toast was empty)', () {
    e.showHud(MovaHud.seek, text: '00:20');
    expect(e.uiState.hud, MovaHud.seek);
    expect(e.uiState.hudText, '00:20');
  });

  test('showHud without text clears any previously set hudText', () {
    e.showHud(MovaHud.seek, text: '00:20');
    e.showHud(MovaHud.volume);
    expect(e.uiState.hudText, isNull);
  });

  test('open() arms the auto-hide timer per showOnStart/autoHideDelay (regression)', () async {
    final e2 = MovaEngine(
      kernel: k,
      options: const MovaOpts(controls: MovaCtrlsConfig(autoHideDelay: Duration(milliseconds: 10))),
    );
    await e2.open(const MovaSource('https://host/a.mp4'));
    expect(e2.uiState.controlsVisible, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(e2.uiState.controlsVisible, isFalse);
    await e2.dispose();
  });

  test('play() after completion restarts VOD from zero '
      '(regression: replay left the progress bar stuck at the end)', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    k.calls.clear();
    k.emitCompleted(true);
    await Future<void>.delayed(Duration.zero);
    expect(e.state.completed, isTrue);

    await e.play();

    expect(k.calls, ['seek', 'play']);
    expect(k.lastSeek, Duration.zero);
  });

  test('play() after completion does not seek for a live source', () async {
    await e.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k.calls.clear();
    k.emitCompleted(true);
    await Future<void>.delayed(Duration.zero);

    await e.play();

    expect(k.calls, ['play']);
  });

  test('open() leaves controls hidden when showOnStart is false', () async {
    final e2 = MovaEngine(
      kernel: k,
      options: const MovaOpts(controls: MovaCtrlsConfig(showOnStart: false)),
    );
    await e2.open(const MovaSource('https://host/a.mp4'));
    expect(e2.uiState.controlsVisible, isFalse);
    await e2.dispose();
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
    const auto = MovaQual(label: '自动', uri: '', isAuto: true);
    const high = MovaQual(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
    const low = MovaQual(label: '480p', uri: 'https://host/480.m3u8', height: 480);
    e.debugSetQualities(const [auto, high, low], current: high);

    final events = <MovaEvent>[];
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
    expect(events.whereType<MovaAbrDownShift>().length, 1);
    final downshift = events.whereType<MovaAbrDownShift>().single;
    expect(downshift.from, high);
    expect(downshift.to, low);

    await sub.cancel();
  });

  test('rapid sequential stall-cycles each produce exactly one downshift '
      'without corrupting currentQuality', () async {
    // Three pinned variants so two consecutive downshifts are observable
    // (high -> mid -> low). Regression test for the ABR reentrancy guard:
    // without `_abrDownshiftInFlight`, overlapping in-flight downshifts
    // could race on `_kernel` and double-fire/swallow MovaAbrDownShift or
    // leave currentQuality inconsistent with what was actually `open()`ed.
    //
    // Note: `downshiftQuality()`'s only awaited work in this harness is a
    // `FakeKernel.open()`/`seek()` call that resolves on the next
    // microtask (no real async gap), so within a single test process we
    // cannot force two `downshiftQuality()` futures to be genuinely
    // in-flight at the same instant — the guard is exercised by asserting
    // that back-to-back full stall cycles, fired without any inter-cycle
    // delay, still resolve to exactly one MovaAbrDownShift per cycle and a
    // consistent final quality. A true concurrent race (two overlapping
    // async kernel round-trips) isn't practically triggerable without
    // instrumenting FakeKernel to insert an artificial delay inside
    // open()/seek(), which this harness does not do.
    //
    // 用三档清晰度以便观察两次连续降档（high -> mid -> low）。这是 ABR
    // 重入保护的回归测试：没有 `_abrDownshiftInFlight` 时，重叠的进行中降档
    // 可能在 `_kernel` 上竞争，导致 MovaAbrDownShift 重复/漏发，或
    // currentQuality 与实际 `open()` 的清晰度不一致。
    //
    // 说明：本测试用的 `downshiftQuality()` 唯一的 await 点是
    // `FakeKernel.open()`/`seek()`，其在下一个微任务即可完成（没有真实的
    // 异步间隔），因此单个测试进程内无法强制让两个 `downshiftQuality()`
    // future 真正同时在途——本测试改为验证：不留 cycle 间隔地连续触发两轮
    // 完整的 stall 周期，仍能得到每轮恰好一次 MovaAbrDownShift，且最终清晰度
    // 一致。要制造真正并发的竞争（两个重叠的异步内核往返），需要给
    // FakeKernel 的 open()/seek() 插入人为延迟，本测试骨架未做这件事。
    const auto = MovaQual(label: '自动', uri: '', isAuto: true);
    const high = MovaQual(label: '1080p', uri: 'https://host/1080.m3u8', height: 1080);
    const mid = MovaQual(label: '720p', uri: 'https://host/720.m3u8', height: 720);
    const low = MovaQual(label: '480p', uri: 'https://host/480.m3u8', height: 480);
    e.debugSetQualities(const [auto, high, mid, low], current: high);

    final events = <MovaEvent>[];
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

    final downshifts = events.whereType<MovaAbrDownShift>().toList();
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
    final e2 = MovaEngine(kernel: k, orientation: spy);

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
    final e2 = MovaEngine(kernel: k, orientation: spy);

    k.emitSize(1280, 720);
    await Future<void>.delayed(Duration.zero);
    expect(spy.calls, isEmpty);

    await e2.dispose();
  });

  test('setOrientation forces the orientation, updates state, and emits an event', () async {
    final spy = _SpyOrientationPort();
    final e2 = MovaEngine(kernel: k, orientation: spy);
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);

    await e2.setOrientation(MovaOrient.landscape);
    expect(e2.state.orientation, MovaOrient.landscape);
    expect(spy.orientations.last, MovaOrient.landscape);
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<MovaOrientChg>().single.orientation, MovaOrient.landscape);

    await sub.cancel();
    await e2.dispose();
  });

  test('forced orientation is carried into the fullscreen apply call', () async {
    final spy = _SpyOrientationPort();
    final e2 = MovaEngine(kernel: k, orientation: spy);

    await e2.setOrientation(MovaOrient.portrait);
    await e2.setFullscreen(true);
    // Every apply since forcing portrait must carry that override, regardless
    // of the (landscape) video size, so fullscreen never flips it back.
    //
    // 强制竖屏之后的每次 apply 都必须带上该覆盖，无论视频尺寸（横向）如何，
    // 全屏都不会把它翻回去。
    expect(spy.orientations.last, MovaOrient.portrait);

    await e2.dispose();
  });

  test('preview is exposed on the api surface', () {
    expect(e.preview, isNotNull);
    expect(e.preview.current, isNull);
  });

  test('opening a source attaches it to the preview service', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    e.preview.requestAt(const Duration(seconds: 5));
    // With no sources able to serve this media the request resolves to
    // nothing, but attaching must not throw and must clear any old thumb.
    //
    // 没有来源能服务该媒体时请求解析为空，但 attach 不得抛异常，且必须清掉
    // 旧缩略图。
    expect(e.preview.current, isNull);
  });

  test('a disabled preview config emits MovaPrevBlock on the event stream', () async {
    final e2 = MovaEngine(
      kernel: FakeKernel(),
      options: const MovaOpts(
        preview: MovaPrevConfig(
          enabled: false,
          debounce: Duration.zero,
          network: MovaPrevNet.always,
        ),
      ),
    );
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.open(const MovaSource('https://host/a.mp4'));
    e2.preview.requestAt(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.whereType<MovaPrevBlock>(), isNotEmpty);
    expect(
      events.whereType<MovaPrevBlock>().first.reason,
      MovaPrevBlockReason.disabled,
    );
    await sub.cancel();
    await e2.dispose();
  });

  test('the configured onBlocked callback also fires', () async {
    final reasons = <MovaPrevBlockReason>[];
    final e2 = MovaEngine(
      kernel: FakeKernel(),
      options: MovaOpts(
        preview: MovaPrevConfig(
          enabled: false,
          debounce: Duration.zero,
          network: MovaPrevNet.always,
          onBlocked: reasons.add,
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/a.mp4'));
    e2.preview.requestAt(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reasons, [MovaPrevBlockReason.disabled]);
    await e2.dispose();
  });

  test('disposing the engine disposes the preview service', () async {
    final e2 = MovaEngine(kernel: FakeKernel());
    await e2.dispose();
    // A closed preview stream is the observable proof the service was torn
    // down; requesting after dispose must be a silent no-op.
    //
    // 预览流已关闭即是服务已销毁的可观测证据；dispose 之后再请求必须静默无操作。
    e2.preview.requestAt(const Duration(seconds: 1));
    expect(e2.preview.current, isNull);
  });

  test('stt is exposed on the api surface and defaults to no languages', () {
    expect(e.stt, isNotNull);
    expect(e.stt.languages, isEmpty);
    expect(e.stt.current, isNull);
  });

  test('starting stt with no engine configured emits MovaSttBlock(noEngine)', () async {
    final e2 = MovaEngine(kernel: FakeKernel(), options: const MovaOpts(stt: MovaSttConfig(enabled: true)));
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.open(const MovaSource('https://host/a.mp4'));
    await e2.stt.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.whereType<MovaSttBlock>().first.reason, MovaSttBlockReason.noEngine);
    await sub.cancel();
    await e2.dispose();
  });

  test('starting stt before a source is open emits MovaSttBlock(noSource)', () async {
    final e2 = MovaEngine(
      kernel: FakeKernel(),
      options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: _FakeSttEngine())),
    );
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.stt.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.whereType<MovaSttBlock>().first.reason, MovaSttBlockReason.noSource);
    await sub.cancel();
    await e2.dispose();
  });

  test('a disabled stt config emits MovaSttBlock(disabled) even with an engine configured',
      () async {
    final e2 = MovaEngine(
      kernel: FakeKernel(),
      options: MovaOpts(stt: MovaSttConfig(engine: _FakeSttEngine())),
    );
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.open(const MovaSource('https://host/a.mp4'));
    await e2.stt.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events.whereType<MovaSttBlock>().first.reason, MovaSttBlockReason.disabled);
    await sub.cancel();
    await e2.dispose();
  });

  test('the configured stt onBlocked callback also fires', () async {
    final reasons = <MovaSttBlockReason>[];
    final e2 = MovaEngine(kernel: FakeKernel(), options: MovaOpts(stt: MovaSttConfig(onBlocked: reasons.add)));
    await e2.open(const MovaSource('https://host/a.mp4'));
    await e2.stt.start();
    expect(reasons, [MovaSttBlockReason.disabled]);
    await e2.dispose();
  });

  test('a configured engine reports languages and forwards cues once started', () async {
    final engine = _FakeSttEngine();
    final e2 = MovaEngine(
      kernel: FakeKernel(),
      options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: engine)),
    );
    await e2.open(const MovaSource('https://host/a.mp4'));
    expect(e2.stt.languages, ['zh', 'en']);

    final cues = <MovaSttCue>[];
    final sub = e2.stt.cues.listen(cues.add);
    await e2.stt.start();
    expect(engine.started, isTrue);
    engine.emit(const MovaSttCue(text: 'hi', start: Duration.zero, end: Duration(seconds: 1)));
    await Future<void>.delayed(Duration.zero);
    expect(cues, hasLength(1));

    await e2.stt.stop();
    expect(engine.stopped, isTrue);
    await sub.cancel();
    await e2.dispose();
  });

  test('current tracks the cue covering the latest reported playback position', () async {
    final k2 = FakeKernel();
    final engine = _FakeSttEngine();
    final e2 = MovaEngine(
      kernel: k2,
      options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: engine)),
    );
    await e2.open(const MovaSource('https://host/a.mp4'));
    await e2.stt.start();
    engine.emit(const MovaSttCue(text: 'hi', start: Duration.zero, end: Duration(seconds: 2)));
    await Future<void>.delayed(Duration.zero);

    // `MovaApi.progress` is throttled (200ms); wait past that window for the
    // position tick to reach the stt service.
    //
    // `MovaApi.progress` 有节流（200ms）；等过这个窗口，位置 tick 才会到达
    // stt 服务。
    k2.emitPosition(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(e2.stt.current?.text, 'hi');

    k2.emitPosition(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(e2.stt.current, isNull);

    await e2.dispose();
  });

  test('disposing the engine disposes the stt service and its engine', () async {
    final engine = _FakeSttEngine();
    final e2 = MovaEngine(
      kernel: FakeKernel(),
      options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: engine)),
    );
    await e2.dispose();
    expect(engine.disposed, isTrue);
  });

  test('timeshiftBehind stays null for a VOD source', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    k.emitDuration(const Duration(seconds: 600));
    k.emitPosition(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    expect(e.state.timeshiftBehind, isNull);
  });

  test('a dvr live stream reports how far behind the edge it is', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr)),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    k2.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.liveSeekable, isTrue);
    expect(e2.state.seekableWindow, const Duration(seconds: 300));
    expect(e2.state.timeshiftBehind, const Duration(seconds: 200));
    await e2.dispose();
  });

  test('inside the edge threshold clears timeshiftBehind and announces the edge', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr)),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    k2.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    k2.emitPosition(const Duration(seconds: 295));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.timeshiftBehind, isNull);
    expect(events.whereType<MovaLiveEdgeReach>(), isNotEmpty);
    await sub.cancel();
    await e2.dispose();
  });

  test('MovaTimeShiftChg fires only when the whole-second lag changes', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr)),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    // All three ticks quantise to the same whole-second lag (199s): the raw
    // lags are 199.8s / 199.4s / 199.1s, which truncate to 199 every time.
    //
    // 三次 tick 量化后落后量相同（均为 199 秒）：原始落后量分别是 199.8 /
    // 199.4 / 199.1 秒，截断后都是 199。
    k2.emitPosition(const Duration(milliseconds: 100200));
    k2.emitPosition(const Duration(milliseconds: 100600));
    k2.emitPosition(const Duration(milliseconds: 100900));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<MovaTimeShiftChg>().length, 1,
        reason: 'sub-second jitter must not spam the event stream');
    await sub.cancel();
    await e2.dispose();
  });

  test('an injected windowResolver overrides the kernel duration', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.dvr,
          windowResolver: (_) => const Duration(seconds: 120),
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.seekableWindow, const Duration(seconds: 120));
    await e2.dispose();
  });

  test('timeshift seek reopens the stream at the url the builder returns', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    await e2.seek(const Duration(seconds: 100));
    expect(k2.lastUri, 'https://host/l.m3u8?behind=500');
    expect(k2.calls, contains('open'));
    expect(k2.calls, isNot(contains('seek')));
    expect(e2.state.timeshiftBehind, const Duration(seconds: 500));
    await e2.dispose();
  });

  test('timeshift seek is a no-op when no urlBuilder is supplied', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: Duration(seconds: 600),
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.calls.clear();
    await e2.seek(const Duration(seconds: 100));
    expect(k2.calls, isEmpty);
    await e2.dispose();
  });

  test('a timeshift seek landing inside the edge threshold reports the edge', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.seek(const Duration(seconds: 595));
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.timeshiftBehind, isNull);
    expect(events.whereType<MovaLiveEdgeReach>(), isNotEmpty);
    await sub.cancel();
    await e2.dispose();
  });

  test('a live seek is clamped to the window even when duration is unknown', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.dvr,
          dvrWindow: Duration(seconds: 120),
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    await Future<void>.delayed(Duration.zero);
    await e2.seek(const Duration(seconds: 999));
    expect(k2.lastSeek, const Duration(seconds: 120));
    await e2.dispose();
  });

  test('beforeSeek still gates a timeshift seek', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      interceptors: [_CancelSeek()],
      options: MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.calls.clear();
    await e2.seek(const Duration(seconds: 100));
    expect(k2.calls, isEmpty);
    await e2.dispose();
  });

  test('backToLiveEdge in dvr mode seeks to the window end without reopening', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr)),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    k2.emitPosition(const Duration(seconds: 100));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    await e2.backToLiveEdge();
    expect(k2.calls, ['seek']);
    expect(k2.lastSeek, const Duration(seconds: 300));
    expect(e2.state.timeshiftBehind, isNull);
    await e2.dispose();
  });

  test('backToLiveEdge in timeshift mode reopens the original live url', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.timeshift,
          dvrWindow: const Duration(seconds: 600),
          urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    await e2.seek(const Duration(seconds: 100));
    expect(k2.lastUri, 'https://host/l.m3u8?behind=500');
    k2.calls.clear();
    await e2.backToLiveEdge();
    expect(k2.calls, ['open']);
    expect(k2.lastUri, 'https://host/l.m3u8',
        reason: 'must reopen the original url, not the time-shifted one');
    expect(e2.state.timeshiftBehind, isNull);
    await e2.dispose();
  });

  test('an explicit backToLive strategy overrides the mode-derived one', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.dvr,
          backToLive: MovaBackToLive.reopen,
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    await e2.backToLiveEdge();
    expect(k2.calls, ['open']);
    await e2.dispose();
  });

  test('backToLiveEdge is a no-op for a VOD source', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    k.calls.clear();
    await e.backToLiveEdge();
    expect(k.calls, isEmpty);
  });

  test('autoBackToLiveOnStall jumps back only while time-shifted and only when on', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(
      kernel: k2,
      options: const MovaOpts(
        live: MovaLiveConfig(
          seekMode: MovaLiveSeekMode.dvr,
          autoBackToLiveOnStall: true,
        ),
      ),
    );
    await e2.open(const MovaSource('https://host/l.m3u8', type: MovaStreamType.live));
    k2.emitDuration(const Duration(seconds: 300));
    await Future<void>.delayed(Duration.zero);

    // At the edge: a stall must not move the playhead.
    // 在边缘：卡顿不应移动播放头。
    k2.emitPosition(const Duration(seconds: 298));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    k2.emitBuffering(true);
    await Future<void>.delayed(Duration.zero);
    expect(k2.calls, isEmpty);

    // Time-shifted: a stall jumps back to the edge.
    // 时移中：卡顿会跳回边缘。
    k2.emitBuffering(false);
    k2.emitPosition(const Duration(seconds: 50));
    await Future<void>.delayed(Duration.zero);
    k2.calls.clear();
    k2.emitBuffering(true);
    await Future<void>.delayed(Duration.zero);
    expect(k2.calls, contains('seek'));
    await e2.dispose();
  });

  test('pipSupported starts false and flips once the port answers', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(kernel: k2, pip: _YesPip());
    expect(e2.pipSupported, isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(e2.pipSupported, isTrue);
    expect(e2.state.pipSupported, isTrue);
    await e2.dispose();
  });

  test('pipSupported stays false when the port throws', () async {
    final k2 = FakeKernel();
    final e2 = MovaEngine(kernel: k2, pip: _ThrowingPip());
    await Future<void>.delayed(Duration.zero);
    expect(e2.pipSupported, isFalse);
    await e2.dispose();
  });

  test('seek optimistically reports the target and suppresses stale pre-seek echoes', () async {
    await e.open(const MovaSource('https://host/a.mp4'));
    k.emitDuration(const Duration(minutes: 10));
    k.emitPosition(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);

    final seen = <Duration>[];
    final sub = e.progress.listen((p) => seen.add(p.position));
    await Future<void>.delayed(Duration.zero);

    await e.seek(const Duration(seconds: 120));
    await Future<void>.delayed(Duration.zero);
    expect(seen, contains(const Duration(seconds: 120)),
        reason: 'the target must be reported before the kernel round trip settles');

    // A stale echo of the pre-seek position must not regress what is
    // reported — this is exactly the "flashes back to the old spot" bug a
    // tap-to-seek/swipe/double-tap step all shared before this fix.
    //
    // seek 前旧位置的陈旧回声不能让上报的位置倒退——这正是修复前
    // 点击/横滑/双击 seek 都会"闪回旧位置"的那个 bug。
    k.emitPosition(const Duration(seconds: 6));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(seen.last, const Duration(seconds: 120));

    // Once the kernel actually lands near the target (within the settle
    // tolerance), normal reporting resumes.
    //
    // 一旦内核真的落到目标附近（在结算容差内），恢复正常上报。
    k.emitPosition(const Duration(milliseconds: 120200));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(seen.last, const Duration(milliseconds: 120200));

    await sub.cancel();
  });

  test('setVolume routes to the kernel when no volume port is wired', () async {
    await e.setVolume(30);
    expect(k.calls, contains('setVolume'));
    expect(e.state.volume, 30);
  });

  test('setVolume routes to the volume port, not the kernel, when wired', () async {
    final port = _RecordingVolumePort(current: 100);
    final k2 = FakeKernel();
    final e2 = MovaEngine(kernel: k2, volume: port);
    final events = <MovaEvent>[];
    final sub = e2.events.listen(events.add);
    await e2.setVolume(30);
    await Future<void>.delayed(Duration.zero); // let the event dispatch
    expect(port.lastSet, 30);
    // The kernel's own volume was left untouched (system/host owns volume now).
    // 内核自身音量未被触碰（音量现在归系统/宿主管）。
    expect(k2.calls, isNot(contains('setVolume')));
    expect(e2.state.volume, 30);
    expect(events.whereType<MovaVolumeChg>().map((e) => e.value), contains(30));
    await sub.cancel();
    await e2.dispose();
  });

  test('a wired volume port seeds the gesture baseline into state.volume', () async {
    final port = _RecordingVolumePort(current: 45);
    final e2 = MovaEngine(kernel: FakeKernel(), volume: port);
    // Seeding is async (like the pip probe); let it settle.
    // 播种是异步的（同 pip 探测），等它落定。
    await Future<void>.delayed(Duration.zero);
    expect(e2.state.volume, 45);
    await e2.dispose();
  });

  test('CallbackVolumePort forwards set to its callback and reports get', () async {
    double? seen;
    final port = CallbackVolumePort((p) => seen = p, onGet: () async => 70);
    await port.set(55);
    expect(seen, 55);
    expect(await port.get(), 70);
  });
}

/// A spy [MovaOrientPort] that records every `apply(...)` call's
/// width/height so tests can assert re-application behavior.
///
/// 记录每次 `apply(...)` 调用的宽高的 [MovaOrientPort] 间谍实现，供测试
/// 断言重新应用行为。
class _SpyOrientationPort implements MovaOrientPort {
  /// Every (width, height) pair passed to [apply], in call order.
  ///
  /// 每次 [apply] 调用传入的 (width, height)，按调用顺序记录。
  final List<(int, int)> calls = [];

  /// Every forced-orientation override passed to [apply], in call order.
  ///
  /// 每次 [apply] 调用传入的强制方向覆盖，按调用顺序记录。
  final List<MovaOrient> orientations = [];

  @override
  Future<void> apply({
    required bool fullscreen,
    required bool immersive,
    required int width,
    required int height,
    required MovaOrient orientation,
  }) async {
    calls.add((width, height));
    orientations.add(orientation);
  }

  @override
  Future<void> reset() async {}
}

class _CancelSeek extends MovaHook {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

class _DenyPlay extends MovaHook {
  @override
  Future<bool> beforePlay() async => false;
}

/// A pip port that reports support and always succeeds.
///
/// 报告支持画中画且总是成功的 pip 端口。
class _YesPip implements MovaPipPort {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> enter({int? width, int? height}) async => true;
}

/// A pip port whose capability probe fails, standing in for a platform whose
/// channel is missing.
///
/// 能力探测会失败的 pip 端口，用于模拟缺少平台通道的平台。
class _ThrowingPip implements MovaPipPort {
  @override
  Future<bool> isSupported() async => throw MissingPluginException('no pip');

  @override
  Future<bool> enter({int? width, int? height}) async => false;
}

/// A spy [MovaVolumePort] that records the last set value and reports a fixed
/// current level for baseline seeding.
///
/// 记录最近一次 set 值、并回报固定当前值供基线播种的 [MovaVolumePort] 探针。
class _RecordingVolumePort implements MovaVolumePort {
  _RecordingVolumePort({required this.current});

  /// The value returned by [get], used as the gesture baseline.
  ///
  /// [get] 返回的值，用作手势基线。
  final double current;

  /// The most recent value passed to [set].
  ///
  /// 最近一次传给 [set] 的值。
  double? lastSet;

  @override
  Future<double> get() async => current;

  @override
  Future<void> set(double percent) async => lastSet = percent;
}

/// A [MovaSttEngine] test double reporting `['zh', 'en']` that lets tests push
/// cues on demand and records start/stop/dispose calls.
///
/// [MovaSttEngine] 的测试替身，报告 `['zh', 'en']`，允许测试按需推送字幕，并
/// 记录启停/销毁调用。
class _FakeSttEngine implements MovaSttEngine {
  final _cues = StreamController<MovaSttCue>.broadcast();
  bool started = false;
  Duration? startedAt;
  bool stopped = false;
  bool disposed = false;

  @override
  List<String> get languages => const ['zh', 'en'];

  @override
  Stream<MovaSttCue> get cues => _cues.stream;

  @override
  Future<void> start(Duration atPosition) async {
    started = true;
    startedAt = atPosition;
  }

  @override
  void feed(Float32List samples, int sampleRateHz) {}

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _cues.close();
  }

  /// Pushes [cue] to [cues].
  ///
  /// 把 [cue] 推送到 [cues]。
  void emit(MovaSttCue cue) => _cues.add(cue);
}
