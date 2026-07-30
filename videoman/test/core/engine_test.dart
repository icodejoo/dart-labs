import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/engine.dart';
import 'package:videoman/src/core/events/events.dart';
import 'package:videoman/src/core/interceptor/interceptor.dart';
import 'package:videoman/src/core/model/quality.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
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
}

class _CancelSeek extends VmInterceptor {
  @override
  Future<Duration?> beforeSeek(Duration t) async => null;
}

class _DenyPlay extends VmInterceptor {
  @override
  Future<bool> beforePlay() async => false;
}
