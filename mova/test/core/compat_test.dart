import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';

void main() {
  test('MovaCtrl forwards to the engine it wraps', () async {
    final k = FakeKernel();
    // ignore: deprecated_member_use_from_same_package
    final c = MovaCtrl(engine: MovaEngine(kernel: k));
    await c.open(const MovaSource('https://host/a.mp4'));
    await c.play();
    expect(k.calls, ['open', 'play']);
    await c.dispose();
  });
}
