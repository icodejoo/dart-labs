import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/platform/ports.dart';

void main() {
  test('fallback brightness port reports full brightness and ignores writes', () async {
    final p = FallbackBrightnessPort();
    expect(await p.get(), 1.0);
    await p.set(0.2);
    expect(await p.get(), 1.0);
  });

  test('noop pip port is unsupported', () async {
    final p = NoopPipPort();
    expect(await p.isSupported(), isFalse);
    expect(await p.enter(width: 16, height: 9), isFalse);
  });
}
