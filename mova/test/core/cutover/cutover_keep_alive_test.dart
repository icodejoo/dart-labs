import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';

/// Yields a few microtasks so async chains inside [MovaCutoverEngine] settle.
///
/// 让出几个微任务，使 [MovaCutoverEngine] 内部的异步链结算完毕。
Future<void> settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _cue = MovaWarmCue(remaining: Duration(seconds: 1), total: Duration(seconds: 10));
const _ready = MovaProg(position: Duration(seconds: 5), buffer: Duration(seconds: 6));

/// Builds a cutover engine whose factory makes [FakeKeepAliveApi]s (or plain
/// [FakeMovaApi]s when [plain]), recording each into [made].
///
/// 构造一个切换引擎，工厂产出 [FakeKeepAliveApi]（[plain] 时为普通 [FakeMovaApi]），逐个记进 [made]。
MovaCutoverEngine _build(List<FakeMovaApi> made, {bool plain = false}) {
  const opts = MovaOpts(cutover: MovaCutoverConfig(enabled: true, muteWhileWarm: false));
  return MovaCutoverEngine(engineFactory: () {
    final f = plain ? FakeMovaApi(options: opts) : FakeKeepAliveApi(options: opts);
    made.add(f);
    return f;
  });
}

/// Warms a shadow to ready and returns it (the second engine made).
///
/// 把影子引擎预热到就绪并返回它（工厂造出的第二个引擎）。
Future<FakeMovaApi> _warm(MovaCutoverEngine api, List<FakeMovaApi> made) async {
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
  test('1. it is a keepAlive controller and forwards to the active engine, answering with its reply', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    expect(api, isA<MovaKeepAlive>());
    final phase = await api.setKeepAlive(true);
    expect(made.first.calls, contains('setKeepAlive:true'));
    expect(phase, MovaKeepAlivePhase.holding);
    expect(await api.setKeepAlive(false), MovaKeepAlivePhase.off);
    expect(made.first.calls, contains('setKeepAlive:false'));
  });

  test('2. the active engine keepAlive state and events show through the proxy', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    final events = <MovaEvent>[];
    final sub = api.events.listen(events.add);
    await settle();
    made.first.push(made.first.state.copyWith(keepAlivePhase: MovaKeepAlivePhase.holding));
    made.first.pushEvent(const MovaKeepAliveChange(
      phase: MovaKeepAlivePhase.holding,
      reason: MovaKeepAliveReason.requested,
      mode: MovaKeepAliveMode.muted,
    ));
    await settle();
    expect(api.state.keepAlivePhase, MovaKeepAlivePhase.holding);
    expect(events.whereType<MovaKeepAliveChange>(), hasLength(1));
    await sub.cancel();
  });

  test('3. a hold requested before commit puts the shadow into keepAlive before play without volume writes', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    await api.setKeepAlive(true);
    final shadow = await _warm(api, made);
    final old = made.first;
    final ok = await api.commit();
    expect(ok, isTrue);
    final calls = shadow.calls;
    expect(calls, containsAllInOrder(['setKeepAlive:true', 'play']));
    expect(calls, isNot(contains('setVolume')));
    expect(old.calls, contains('pause'));
  });

  test('4. without a request the commit sequence is unchanged', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made);
    final shadow = await _warm(api, made);
    expect(await api.commit(), isTrue);
    expect(shadow.calls.any((c) => c.startsWith('setKeepAlive')), isFalse);
    expect(shadow.calls, contains('play'));
    expect(shadow.calls, isNot(contains('setVolume')));
  });

  test('5. an engine without the capability just pauses and plays, and answers off', () async {
    final made = <FakeMovaApi>[];
    final api = _build(made, plain: true);
    expect(await api.setKeepAlive(true), MovaKeepAlivePhase.off);
    expect(made.first.calls, contains('pause'));
    expect(await api.setKeepAlive(false), MovaKeepAlivePhase.off);
    expect(made.first.calls, contains('play'));
  });
}
