import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/testing/hooks.dart';
import '../../support/fake_api.dart';
import '../../support/fake_kernel.dart';
import 'cutover_operation_test.dart' show settleOperations;

/// 模拟 state 比 events 多一层投递的实际引擎组合，不能依赖两条流的偶然先后。
class DelayedStatesApi extends FakeMovaApi {
  DelayedStatesApi({super.options});
  @override
  Stream<MovaState> get states => super.states.asyncMap((s) async {
    await Future<void>.delayed(Duration.zero);
    return s;
  });
}

void main() {
  test('H77 代理缓冲事件接收时 state 与载荷一致', () async {
    final api = MovaCutoverEngine(engineFactory: () => DelayedStatesApi());
    addTearDown(api.dispose);
    final active = api.active as FakeMovaApi;
    active.push(active.state.copyWith(buffering: true));
    await settleOperations();
    expect(api.state.buffering, isTrue);
    final seen = <(bool, bool, int)>[];
    api.events.listen((e) {
      if (e is MovaBufferChange) {
        seen.add((e.buffering, api.state.buffering, api.state.renderEpoch));
      }
    });
    active.push(active.state.copyWith(buffering: false));
    active.pushEvent(const MovaBufferChange(false));
    await settleOperations();
    expect(seen, [(false, false, 0)]);
  });
  test('H77 换指后事件使用新 epoch 与同一状态，重入通知顺序稳定', () async {
    final engines = <DelayedStatesApi>[];
    final api = MovaCutoverEngine(
      engineFactory: () {
        final e = DelayedStatesApi(
          options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)),
        );
        engines.add(e);
        return e;
      },
    );
    addTearDown(api.dispose);
    await api.prepare(
      const MovaSource('https://host/new.mp4'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    final shadow = engines.last;
    const tick = MovaProg(
      position: Duration(seconds: 1),
      buffer: Duration(seconds: 10),
    );
    shadow.pushProgress(tick);
    await settleOperations();
    shadow.pushProgress(tick);
    await settleOperations();
    expect(await api.commit(), isTrue);
    shadow.push(shadow.state.copyWith(buffering: true));
    await settleOperations();
    await api.prepare(
      const MovaSource('https://host/spare.mp4'),
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    final seen = <(bool, bool, int)>[];
    api.events.listen((e) {
      if (e is MovaBufferChange) {
        seen.add((e.buffering, api.state.buffering, api.state.renderEpoch));
        unawaited(api.abandon()); // 同步产生 cutover 通知也不重入事件控制器。
      }
    });
    shadow.push(shadow.state.copyWith(buffering: false));
    shadow.pushEvent(const MovaBufferChange(false));
    await settleOperations();
    expect(seen, [(false, false, 1)]);
  });
  test('普通 MovaEngine 缓冲事件接收时 state 与载荷一致', () async {
    final kernel = FakeKernel();
    final engine = MovaEngine(
      kernel: kernel,
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://host/ordinary.mp4'));
    final seen = <(bool, bool)>[];
    engine.events.listen((e) {
      if (e is MovaBufferChange) {
        seen.add((e.buffering, engine.state.buffering));
      }
    });
    kernel.emitBuffering(true);
    await settleOperations();
    kernel.emitBuffering(false);
    await settleOperations();
    expect(seen, [(true, true), (false, false)]);
    expect(engine.state.renderEpoch, 0);
  });
  test('普通 MovaEngine 时长与播放事件接收时 state 一致', () async {
    final kernel = FakeKernel();
    final engine = MovaEngine(
      kernel: kernel,
      fetcher: const MovaTestHttpFetch(),
    );
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('https://host/ordinary.mp4'));
    final durations = <(Duration, Duration)>[];
    final playing = <bool>[];
    engine.events.listen((e) {
      if (e is MovaDurationChange) {
        durations.add((e.duration, engine.state.duration));
      }
      if (e is MovaPlay) playing.add(engine.state.playing);
    });
    kernel.emitDuration(const Duration(seconds: 30));
    await settleOperations();
    kernel.emitPlaying(true);
    await settleOperations();
    expect(durations, [
      (const Duration(seconds: 30), const Duration(seconds: 30)),
    ]);
    expect(playing, [true]);
  });
}
