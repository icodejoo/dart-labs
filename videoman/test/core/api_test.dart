import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/state/state.dart';

import '../support/fake_api.dart';

void main() {
  test('FakeVmApi replays the current state to late subscribers', () async {
    final api = FakeVmApi();
    api.push(const VmState(playing: true));
    final seen = <bool>[];
    final sub = api.states.listen((s) => seen.add(s.playing));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true]);
    await sub.cancel();
    await api.dispose();
  });

  test('FakeVmApi records capability calls', () async {
    final api = FakeVmApi();
    await api.play();
    await api.seek(const Duration(seconds: 3));
    expect(api.calls, ['play', 'seek']);
    expect(api.lastSeek, const Duration(seconds: 3));
    await api.dispose();
  });
}
