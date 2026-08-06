import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/state/state.dart';

import '../support/fake_api.dart';

void main() {
  test('FakeMovaApi replays the current state to late subscribers', () async {
    final api = FakeMovaApi();
    api.push(const MovaState(playing: true));
    final seen = <bool>[];
    final sub = api.states.listen((s) => seen.add(s.playing));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true]);
    await sub.cancel();
    await api.dispose();
  });

  test('FakeMovaApi records capability calls', () async {
    final api = FakeMovaApi();
    await api.play();
    await api.seek(const Duration(seconds: 3));
    expect(api.calls, ['play', 'seek']);
    expect(api.lastSeek, const Duration(seconds: 3));
    await api.dispose();
  });
}
