import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';

/// Yields a few microtasks so async chains inside [MovaSwapEngine] settle.
///
/// 让出几个微任务，使 [MovaSwapEngine] 内部的异步链结算完毕。
Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _cue = MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10));
const _ready = MovaProg(position: Duration(seconds: 5), buffer: Duration(seconds: 6));

/// Builds a swap engine whose factory makes [FakeStandbyApi]s (or plain
/// [FakeMovaApi]s when [plain]), recording each into [made].
///
/// 构造一个切换引擎，工厂产出 [FakeStandbyApi]（[plain] 时为普通 [FakeMovaApi]），逐个记进 [made]。
MovaSwapEngine _build(List<FakeMovaApi> made, {bool plain = false}) {
  const opts = MovaOpts(swap: MovaSwapConfig(enabled: true, muteWhileWarm: false));
  return MovaSwapEngine(engineFactory: () {
    final f = plain ? FakeMovaApi(options: opts) : FakeStandbyApi(options: opts);
    made.add(f);
    return f;
  });
}

/// Warms a shadow to ready and returns it (the second engine made).
///
/// 把影子引擎预热到就绪并返回它（工厂造出的第二个引擎）。
Future<FakeMovaApi> _warm(MovaSwapEngine api, List<FakeMovaApi> made) async {
  await api.prepare(const MovaSource('https://host/content.mp4'), at: const Duration(seconds: 5), cue: _cue);
  await settle();
  final shadow = made[1];
  shadow.pushProgress(_ready);
  await settle();
  shadow.pushProgress(_ready);
  await settle();
  return shadow;
}

void main() {
  test('1. it is a standby controller and forwards to the active engine, answering with its reply', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    expect(api, isA<MovaStandbyController>());
    final phase = await api.setStandby(true);
    expect(made.first.calls, contains('setStandby:true'));
    expect(phase, MovaStandbyPhase.holding);
    expect(await api.setStandby(false), MovaStandbyPhase.off);
    expect(made.first.calls, contains('setStandby:false'));
  });

  test('2. the active engine standby state and events show through the proxy', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    final events = <MovaEvent>[];
    final sub = api.events.listen(events.add);
    await settle();
    made.first.push(made.first.state.copyWith(standby: MovaStandbyPhase.holding));
    made.first.pushEvent(const MovaStandbyChange(
      phase: MovaStandbyPhase.holding,
      reason: MovaStandbyReason.requested,
      mode: MovaStandbyMode.muted,
    ));
    await settle();
    expect(api.state.standby, MovaStandbyPhase.holding);
    expect(events.whereType<MovaStandbyChange>(), hasLength(1));
    await sub.cancel();
  });

  test('3. a hold requested before the commit puts the shadow into standby before volume and play', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    await api.setStandby(true);
    final shadow = await _warm(api, made);
    final old = made.first;
    final ok = await api.commit();
    expect(ok, isTrue);
    final calls = shadow.calls;
    expect(calls, containsAllInOrder(['setStandby:true', 'setVolume', 'play']));
    expect(old.calls, contains('pause'));
  });

  test('4. without a request the commit sequence is unchanged', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    final shadow = await _warm(api, made);
    expect(await api.commit(), isTrue);
    expect(shadow.calls.any((c) => c.startsWith('setStandby')), isFalse);
    expect(shadow.calls, containsAllInOrder(['setVolume', 'play']));
  });

  test('5. an engine without the capability just pauses and plays, and answers off', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made, plain: true);
    expect(await api.setStandby(true), MovaStandbyPhase.off);
    expect(made.first.calls, contains('pause'));
    expect(await api.setStandby(false), MovaStandbyPhase.off);
    expect(made.first.calls, contains('play'));
  });
}
