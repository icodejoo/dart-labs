import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
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

  test('FakeKernel reports a non-null render handle with a stable identity', () {
    final k = FakeKernel();
    expect(k.renderHandle, isNotNull);
    expect(
      identical(k.renderHandle, k.renderHandle),
      isTrue,
      reason: '_RenderSurface keys itself by handle identity, so a kernel must '
          'report the same instance every read / _RenderSurface 按句柄身份做 key，'
          '内核每次读取必须返回同一个实例',
    );
  });

  test('FakeKernel accepts an explicit null render handle (audio-only shape)', () {
    late final FakeKernel k;
    expect(() => k = FakeKernel(renderHandle: null), returnsNormally);
    expect(k.renderHandle, isNull);
  });

  test('MovaEngine wires up around a null render handle without throwing', () {
    late final MovaEngine engine;
    expect(
      () => engine = MovaEngine(kernel: FakeKernel(renderHandle: null)),
      returnsNormally,
      reason: "engine.dart's late final wiring must not depend on a non-null "
          'render handle / engine.dart 的 late final 接线不得依赖非空渲染句柄',
    );
    expect(engine.renderHandle, isNull);
  });

  test('MovaEngine forwards the kernel render handle unchanged when present', () {
    final kernel = FakeKernel();
    final engine = MovaEngine(kernel: kernel);
    expect(
      identical(engine.renderHandle, kernel.renderHandle),
      isTrue,
      reason: 'the handle is passed through as-is, never wrapped or replaced / '
          '句柄原样透传，不得被包装或替换',
    );
  });
}
