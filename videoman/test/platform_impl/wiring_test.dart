import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/engine.dart';
import 'package:videoman/src/core/platform/ports.dart';
import 'package:videoman/src/platform_impl/brightness_impl.dart';
import 'package:videoman/src/platform_impl/orientation_impl.dart';
import 'package:videoman/src/platform_impl/pip_impl.dart';
import 'package:videoman/src/platform_impl/wiring.dart';

import '../support/fake_kernel.dart';

/// A fake [VmBrightnessPort] used only to prove that an explicit override
/// wins over `createVmEngine`'s real-adapter default.
///
/// 仅用于证明显式覆盖会胜过 `createVmEngine` 的真实适配器默认值的假
/// [VmBrightnessPort]。
class _FakeBrightnessPort implements VmBrightnessPort {
  @override
  Future<double> get() => Future.value(0.5);

  @override
  Future<void> set(double value) => Future.value();
}

void main() {
  // This is the regression test for the "nothing ever constructs the real
  // adapters" bug: VmEngine() alone silently falls back to noop ports, and a
  // missing `createVmEngine()` call anywhere in app code is invisible to a
  // diff review. Asserting concrete runtime types here means a future
  // regression (e.g. someone reverting example/lib/main.dart back to a bare
  // `VmEngine()`) is caught by this suite instead of only being caught by a
  // human staring at a brightness slider.
  //
  // 这是"没有任何地方真正构造过真实适配器"这一回归 bug 的对应测试：单独的
  // `VmEngine()` 会静默回退到空端口，而 app 代码里漏调用 `createVmEngine()`
  // 在 diff review 中是不可见的。这里断言具体运行时类型，意味着未来的回归
  // （例如有人把 example/lib/main.dart 改回裸 `VmEngine()`）能被本测试套件
  // 捕获，而不是只能靠人盯着亮度滑块才能发现。
  group('createVmEngine', () {
    test('defaults every port to the real platform adapter', () {
      final engine = createVmEngine(kernel: FakeKernel());
      addTearDown(engine.dispose);

      expect(engine.debugBrightnessPort, isA<ScreenBrightnessPort>());
      expect(engine.debugPipPort, isA<ChannelPipPort>());
      expect(engine.debugOrientationPort, isA<SystemChromeOrientationPort>());
    });

    test('an explicitly injected port overrides the real-adapter default', () {
      final fakeBrightness = _FakeBrightnessPort();
      final engine = createVmEngine(
        kernel: FakeKernel(),
        brightness: fakeBrightness,
      );
      addTearDown(engine.dispose);

      expect(engine.debugBrightnessPort, same(fakeBrightness));
      // Ports that weren't overridden still get the real adapter.
      //
      // 未被覆盖的端口仍然接入真实适配器。
      expect(engine.debugPipPort, isA<ChannelPipPort>());
      expect(engine.debugOrientationPort, isA<SystemChromeOrientationPort>());
    });
  });

  test('VmEngine() itself still defaults to the noop/fallback ports', () {
    // Guards the other half of the contract: core's own constructor must
    // stay platform-independent for pure-Dart unit tests.
    //
    // 保护契约的另一半：core 自身的构造函数必须对纯 Dart 单测保持平台无关。
    final engine = VmEngine(kernel: FakeKernel());
    addTearDown(engine.dispose);

    expect(engine.debugBrightnessPort, isA<FallbackBrightnessPort>());
    expect(engine.debugPipPort, isA<NoopPipPort>());
    expect(engine.debugOrientationPort, isA<NoopOrientationPort>());
  });
}
