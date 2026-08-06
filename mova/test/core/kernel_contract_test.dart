import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/kernel/kernel.dart';

import '../support/fake_kernel.dart';

void main() {
  test('FakeKernel records calls and replays pushed state', () async {
    final k = FakeKernel();
    final seen = <bool>[];
    final sub = k.playing.listen(seen.add);
    await k.open('https://host/a.mp4');
    await k.play();
    await k.seek(const Duration(seconds: 7));
    k.emitPlaying(true);
    await Future<void>.delayed(Duration.zero);
    expect(k.lastUri, 'https://host/a.mp4');
    expect(k.calls, ['open', 'play', 'seek']);
    expect(k.lastSeek, const Duration(seconds: 7));
    expect(seen.last, isTrue);
    await sub.cancel();
    await k.dispose();
  });

  test('MovaSize compares by value', () {
    expect(const MovaSize(width: 16, height: 9), const MovaSize(width: 16, height: 9));
  });
}
