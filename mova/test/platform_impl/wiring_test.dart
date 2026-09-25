import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/platform/ports.dart';
import 'package:mova/src/core/preview/extractor.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/platform_impl/brightness_impl.dart';
import 'package:mova/src/platform_impl/mpv_extractor_impl.dart';
import 'package:mova/src/platform_impl/orientation_impl.dart';
import 'package:mova/src/platform_impl/pip_impl.dart';
import 'package:mova/src/platform_impl/wiring.dart';

import '../support/fake_kernel.dart';

/// A fake [PathProviderPlatform] so `createMovaEngine()`'s real disk-cache
/// wiring (Task 12) can dispose cleanly in this plain-Dart test suite,
/// without a real platform channel behind `path_provider`.
///
/// 假的 [PathProviderPlatform]，让 `createMovaEngine()`（Task 12 起接入真实
/// 磁盘缓存）在本纯 Dart 测试套件里也能正常 dispose，而不需要 `path_provider`
/// 背后真正的平台通道。
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

/// A fake [MovaBrightPort] used only to prove that an explicit override
/// wins over `createMovaEngine`'s real-adapter default.
///
/// 仅用于证明显式覆盖会胜过 `createMovaEngine` 的真实适配器默认值的假
/// [MovaBrightPort]。
class _FakeBrightnessPort implements MovaBrightPort {
  @override
  Future<double> get() => Future.value(0.5);

  @override
  Future<void> set(double value) => Future.value();
}

/// A fake [MovaFramePuller] used only to prove that an explicitly injected
/// extractor still wins under `audioOnly: true`.
///
/// 仅用于证明显式注入的抽帧器在 `audioOnly: true` 下仍然胜出的假
/// [MovaFramePuller]。
/// A fake [MovaNetProbe] used only to prove that an explicit probe override
/// is wired into [MovaOpts.preview] by `createMovaEngine`.
///
/// 仅用于证明显式传入的探针会被 `createMovaEngine` 接入
/// [MovaOpts.preview] 的假 [MovaNetProbe]。
class _FakeNetProbe implements MovaNetProbe {
  @override
  Future<bool> allowHeavy() async => true;

  @override
  Stream<bool> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _FakeFramePuller implements MovaFramePuller {
  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async =>
      null;

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  // This is the regression test for the "nothing ever constructs the real
  // adapters" bug: MovaEngine() alone silently falls back to noop ports, and a
  // missing `createMovaEngine()` call anywhere in app code is invisible to a
  // diff review. Asserting concrete runtime types here means a future
  // regression (e.g. someone reverting example/lib/main.dart back to a bare
  // `MovaEngine()`) is caught by this suite instead of only being caught by a
  // human staring at a brightness slider.
  //
  // 这是"没有任何地方真正构造过真实适配器"这一回归 bug 的对应测试：单独的
  // `MovaEngine()` 会静默回退到空端口，而 app 代码里漏调用 `createMovaEngine()`
  // 在 diff review 中是不可见的。这里断言具体运行时类型，意味着未来的回归
  // （例如有人把 example/lib/main.dart 改回裸 `MovaEngine()`）能被本测试套件
  // 捕获，而不是只能靠人盯着亮度滑块才能发现。
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  group('createMovaEngine', () {
    test('defaults every port to the real platform adapter', () {
      final engine = createMovaEngine(kernel: FakeKernel());
      addTearDown(engine.dispose);

      expect(engine.debugBrightnessPort, isA<MovaScreenBrightnessPort>());
      expect(engine.debugPipPort, isA<MovaChannelPipPort>());
      expect(engine.debugOrientationPort, isA<MovaSystemChromeOrientationPort>());
    });

    test('an explicitly injected port overrides the real-adapter default', () {
      final fakeBrightness = _FakeBrightnessPort();
      final engine = createMovaEngine(
        kernel: FakeKernel(),
        brightness: fakeBrightness,
      );
      addTearDown(engine.dispose);

      expect(engine.debugBrightnessPort, same(fakeBrightness));
      // Ports that weren't overridden still get the real adapter.
      //
      // 未被覆盖的端口仍然接入真实适配器。
      expect(engine.debugPipPort, isA<MovaChannelPipPort>());
      expect(engine.debugOrientationPort, isA<MovaSystemChromeOrientationPort>());
    });

    test('audioOnly leaves the frame-extraction fallback unwired', () {
      final engine = createMovaEngine(kernel: FakeKernel(), audioOnly: true);
      addTearDown(engine.dispose);

      expect(
        engine.debugExtractor,
        isNull,
        reason: 'MovaFrameExtractor would open a second Player with its own '
            'VideoController on first use — a whole extra video pipeline / '
            'MovaFrameExtractor 首次使用时会新开第二个 Player 并为其建 '
            'VideoController，那是一整条额外的视频管线',
      );
    });

    test('the frame extractor defaults to null even when audioOnly is off', () {
      // Changed 2026-09-25: MovaFrameExtractor pulls in media_kit_video as a
      // statically reachable dependency the moment createMovaEngine()
      // references it by default, defeating tree-shaking for hosts that
      // never use scrub preview. Hosts must now opt in explicitly.
      //
      // 2026-09-25 变更：MovaFrameExtractor 一旦被 createMovaEngine() 默认引用，
      // 就会把 media_kit_video 变成静态可达依赖，让从不使用拖动预览的宿主也摇
      // 不掉它。宿主现在必须显式 opt-in。
      final engine = createMovaEngine(kernel: FakeKernel());
      addTearDown(engine.dispose);

      expect(engine.debugExtractor, isNull);
    });

    test('an explicitly injected MovaFrameExtractor is wired when passed', () {
      final engine = createMovaEngine(kernel: FakeKernel(), extractor: MovaFrameExtractor());
      addTearDown(engine.dispose);

      expect(engine.debugExtractor, isA<MovaFrameExtractor>());
    });

    test('an explicitly injected extractor still wins under audioOnly', () {
      final puller = _FakeFramePuller();
      final engine = createMovaEngine(
        kernel: FakeKernel(),
        audioOnly: true,
        extractor: puller,
      );
      addTearDown(engine.dispose);

      expect(
        engine.debugExtractor,
        same(puller),
        reason: 'the host may wire its own extractor; audioOnly only changes '
            'the default / 宿主可以自己接抽帧器，audioOnly 只改默认值',
      );
    });

    test('preview.probe defaults to null (core falls back to MovaAlwaysAllowNetProbe)', () {
      // Changed 2026-09-25: MovaConnectivityNetProbe pulls in connectivity_plus as
      // a statically reachable dependency the moment createMovaEngine()
      // references it by default, defeating tree-shaking for hosts that never
      // enable wifiOnly preview policy. Hosts must now opt in explicitly.
      //
      // 2026-09-25 变更：MovaConnectivityNetProbe 一旦被 createMovaEngine() 默认
      // 引用，就会把 connectivity_plus 变成静态可达依赖，让从不启用 wifiOnly
      // 预览策略的宿主也摇不掉它。宿主现在必须显式 opt-in。
      final engine = createMovaEngine(kernel: FakeKernel());
      addTearDown(engine.dispose);

      expect(engine.options.preview.probe, isNull);
    });

    test('an explicitly injected probe is wired into MovaOpts.preview', () {
      final probe = _FakeNetProbe();
      final engine = createMovaEngine(kernel: FakeKernel(), probe: probe);
      addTearDown(engine.dispose);

      expect(engine.options.preview.probe, same(probe));
    });

    test('audioOnly does not disturb the other platform ports', () {
      final engine = createMovaEngine(kernel: FakeKernel(), audioOnly: true);
      addTearDown(engine.dispose);

      expect(engine.debugBrightnessPort, isA<MovaScreenBrightnessPort>());
      expect(engine.debugPipPort, isA<MovaChannelPipPort>());
      expect(engine.debugOrientationPort, isA<MovaSystemChromeOrientationPort>());
    });
  });

  test('MovaEngine() itself still defaults to the noop/fallback ports', () {
    // Guards the other half of the contract: core's own constructor must
    // stay platform-independent for pure-Dart unit tests.
    //
    // 保护契约的另一半：core 自身的构造函数必须对纯 Dart 单测保持平台无关。
    final engine = MovaEngine(kernel: FakeKernel());
    addTearDown(engine.dispose);

    expect(engine.debugBrightnessPort, isA<MovaFallbackBrightnessPort>());
    expect(engine.debugPipPort, isA<MovaNoopPipPort>());
    expect(engine.debugOrientationPort, isA<MovaNoopOrientationPort>());
  });
}
