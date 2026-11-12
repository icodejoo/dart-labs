import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/state/state.dart';
import '../support/fake_api.dart';

/// 意图与内核播放观测相互独立的替身契约。
void main() {
  test('open 使用 autoPlay，拒绝打开不修改意图', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    await api.open(const MovaSource('a'));
    expect(api.state.playbackIntent, isTrue);
    expect(api.state.playing, isFalse);
    await api.open(const MovaSource('b'), autoPlay: false);
    expect(api.state.playbackIntent, isFalse);
    api.acceptOpens = false;
    expect(await api.open(const MovaSource('c')), isFalse);
    expect(api.state.playbackIntent, isFalse);
  });
  test('play 维护意图，不推送 playing', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    await api.play();
    expect(api.state.playbackIntent, isTrue);
    expect(api.state.playing, isFalse);
  });
  test('pause 清除意图，不覆盖独立的 playing 观测', () async {
    final api = FakeMovaApi();
    addTearDown(api.dispose);
    api.push(const MovaState(playing: true, playbackIntent: true));
    await api.pause();
    expect(api.state.playbackIntent, isFalse);
    expect(api.state.playing, isTrue);
  });
}
