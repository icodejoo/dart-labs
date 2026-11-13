import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import '../support/fake_api.dart';
import '../support/gated.dart';

/// 验证交错脚手架的默认兼容性与门闩行为。
void main() {
  test('四个动词分别等待门闩且记录进入顺序', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    for (final verb in ['open', 'play', 'pause', 'seek']) {
      final gate = Completer<void>();
      late Future<void> pending;
      switch (verb) {
        case 'open':
          api.openGate = gate;
          pending = api.open(const MovaSource('a')).then((_) {});
        case 'play':
          api.playGate = gate;
          pending = api.play();
        case 'pause':
          api.pauseGate = gate;
          pending = api.pause();
        case 'seek':
          api.seekGate = gate;
          pending = api.seek(Duration.zero);
      }
      var finished = false;
      final observed = pending.then((_) => finished = true);
      await Future<void>.value();
      expect(finished, isFalse);
      expect(api.calls.last, verb);
      gate.complete();
      await observed;
    }
  });
  test('播放观测默认不推送，显式开启才跟随动词', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    await api.play();
    expect(api.state.playing, isFalse);
    api.pushPlayingOnVerbs = true;
    await api.play();
    expect(api.state.playing, isTrue);
    await api.pause();
    expect(api.state.playing, isFalse);
  });
  test('结束与错误事件可主动驱动', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    final events = <Object>[];
    final sub = api.events.listen(events.add);
    addTearDown(sub.cancel);
    api.emitDone();
    api.emitError('noise', fatal: false);
    expect(api.state.error, isNull);
    api.emitError('fatal');
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(3));
    expect(api.state.error, 'fatal');
  });
  test('工厂跨实例排序并统计每次释放调用', () async {
    final factory = GatedMovaFactory();
    final a = factory.create();
    final b = factory.create();
    await a.play();
    await b.pause();
    expect(factory.log.entries.map((e) => e.instance), [
      a.instanceId,
      b.instanceId,
    ]);
    expect(a.instanceId, isNot(b.instanceId));
    await a.dispose();
    await a.dispose();
    await b.dispose();
    expect(a.disposeCount, 2);
    expect(b.disposeCount, 1);
  });
  test('切换替身按源返回结果并等待预热与提交', () async {
    final cutover = FakeCutover();
    addTearDown(cutover.dispose);
    cutover.prepareGate = Completer<void>();
    final prepare = cutover.prepare(const MovaSource('a'));
    expect(cutover.preparedSource?.uri, 'a');
    cutover.prepareGate!.complete();
    await prepare;
    cutover.commitResultFor = (source) => source.uri == 'a';
    cutover.commitGate = Completer<void>();
    final commit = cutover.commit();
    cutover.commitGate!.complete();
    expect(await commit, isTrue);
    expect(cutover.preparedSources.map((s) => s.uri), ['a']);
  });
}
