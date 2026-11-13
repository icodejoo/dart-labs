import 'package:flutter/foundation.dart';
import 'package:mova/testing.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mova/src/core/mova.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/platform/platform.dart';
import 'package:mova/src/core/preview/extractor.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/preview/service.dart';
import 'package:mova/src/platform_impl/brightness_impl.dart';
import 'package:mova/src/platform_impl/mpv_extractor_impl.dart';
import 'package:mova/src/platform_impl/orient_impl.dart';
import 'package:mova/src/platform_impl/pip_impl.dart';
import 'package:mova/src/platform_impl/wiring.dart';

import '../support/fake_kernel.dart';

/// A fake [PathProviderPlatform] so `createMova()`'s real disk-cache
/// wiring (Task 12) can dispose cleanly in this plain-Dart test suite,
/// without a real platform channel behind `path_provider`.
///
/// 假的 [PathProviderPlatform]，让 `createMova()`（Task 12 起接入真实
/// 磁盘缓存）在本纯 Dart 测试套件里也能正常 dispose，而不需要 `path_provider`
/// 背后真正的平台通道。
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

/// A fake [IMovaBrightness] used only to prove that an explicit override
/// wins over `createMova`'s real-adapter default.
///
/// 仅用于证明显式覆盖会胜过 `createMova` 的真实适配器默认值的假
/// [IMovaBrightness]。
class _FakeBrightness implements IMovaBrightness {
  @override
  Future<double> get() => Future.value(0.5);

  @override
  Future<void> set(double value) => Future.value();
}

/// A fake [IMovaFramePuller] used only to prove that an explicitly injected
/// extractor still wins under `audioOnly: true`.
///
/// 仅用于证明显式注入的抽帧器在 `audioOnly: true` 下仍然胜出的假
/// [IMovaFramePuller]。
/// A fake [IMovaNetProbe] used only to prove that an explicit probe override
/// is wired into [MovaOpts.preview] by `createMova`.
///
/// 仅用于证明显式传入的探针会被 `createMova` 接入
/// [MovaOpts.preview] 的假 [IMovaNetProbe]。
class _FakeNetProbe implements IMovaNetProbe {
  @override
  Future<bool> allowHeavy() async => true;

  @override
  Stream<bool> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _FakeFramePuller implements IMovaFramePuller {
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
  // adapters" bug: Mova() alone silently falls back to noop ports, and a
  // missing `createMova()` call anywhere in app code is invisible to a
  // diff review. Asserting concrete runtime types here means a future
  // regression (e.g. someone reverting example/lib/main.dart back to a bare
  // `Mova()`) is caught by this suite instead of only being caught by a
  // human staring at a brightness slider.
  //
  // 这是"没有任何地方真正构造过真实适配器"这一回归 bug 的对应测试：单独的
  // `Mova()` 会静默回退到空端口，而 app 代码里漏调用 `createMova()`
  // 在 diff review 中是不可见的。这里断言具体运行时类型，意味着未来的回归
  // （例如有人把 example/lib/main.dart 改回裸 `Mova()`）能被本测试套件
  // 捕获，而不是只能靠人盯着亮度滑块才能发现。
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  test('C11 injected kernel reports ignored audio and restart resource flags', () async {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) { if (message != null) messages.add(message); };
    try {
      final kernel = FakeKernel();
      final mova = createMova(kernel: kernel, audioOnly: true, preciseFirstFrame: true);
      await mova.dispose();
      expect(messages.join(), contains('audioOnly'));
      expect(messages.join(), contains('preciseFirstFrame'));
    } finally { debugPrint = previous; }
  });
  test('C11 Android strict TLS requires a CA before constructing a kernel', () async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    MovaTesting.useTestKernels();
    Mova? created;
    try {
      expect(() { created = createMova(tlsVerify: true); }, throwsAssertionError);
      expect(MovaTesting.kernels, isEmpty);
    } finally {
      await created?.dispose();
      MovaTesting.reset();
      debugDefaultTargetPlatformOverride = previous;
    }
  });
  test('C11 injected kernel reports ignored TLS without demanding a CA', () async {
    final messages = <String>[];
    final previous = debugPrint;
    final platform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    debugPrint = (message, {wrapWidth}) { if (message != null) messages.add(message); };
    try {
      final mova = createMova(kernel: FakeKernel(), tlsVerify: true, tlsCaFile: '/host/ca.pem');
      await mova.dispose();
      expect(messages.join(), contains('tlsVerify'));
      expect(messages.join(), contains('tlsCaFile'));
    } finally {
      debugPrint = previous;
      debugDefaultTargetPlatformOverride = platform;
    }
  });

  group('createMova', () {
    test('defaults every port to the real platform adapter', () {
      final mova = createMova(kernel: FakeKernel());
      addTearDown(mova.dispose);

      expect(mova.debugBrightness, isA<MovaBrightness>());
      expect(mova.debugPip, isA<MovaPip>());
      expect(mova.debugOrient, isA<MovaOrient>());
    });

    test('an explicitly injected port overrides the real-adapter default', () {
      final fakeBrightness = _FakeBrightness();
      final mova = createMova(
        kernel: FakeKernel(),
        brightness: fakeBrightness,
      );
      addTearDown(mova.dispose);

      expect(mova.debugBrightness, same(fakeBrightness));
      // Ports that weren't overridden still get the real adapter.
      //
      // 未被覆盖的端口仍然接入真实适配器。
      expect(mova.debugPip, isA<MovaPip>());
      expect(mova.debugOrient, isA<MovaOrient>());
    });

    test('audioOnly leaves the frame-extraction fallback unwired', () {
      final mova = createMova(kernel: FakeKernel(), audioOnly: true);
      addTearDown(mova.dispose);

      expect(
        mova.debugExtractor,
        isNull,
        reason: 'MovaFrameExtractor would open a second Player with its own '
            'VideoController on first use — a whole extra video pipeline / '
            'MovaFrameExtractor 首次使用时会新开第二个 Player 并为其建 '
            'VideoController，那是一整条额外的视频管线',
      );
    });

    test('the frame extractor defaults to null even when audioOnly is off', () {
      // 抽帧器仍需宿主显式 opt-in，不自动创建第二条视频管线。
      final mova = createMova(kernel: FakeKernel());
      addTearDown(mova.dispose);

      expect(mova.debugExtractor, isNull);
    });

    test('an explicitly injected MovaFrameExtractor is wired when passed', () {
      final mova = createMova(kernel: FakeKernel(), extractor: MovaFrameExtractor());
      addTearDown(mova.dispose);

      expect(mova.debugExtractor, isA<MovaFrameExtractor>());
    });

    test('an explicitly injected extractor still wins under audioOnly', () {
      final puller = _FakeFramePuller();
      final mova = createMova(
        kernel: FakeKernel(),
        audioOnly: true,
        extractor: puller,
      );
      addTearDown(mova.dispose);

      expect(
        mova.debugExtractor,
        same(puller),
        reason: 'the host may wire its own extractor; audioOnly only changes '
            'the default / 宿主可以自己接抽帧器，audioOnly 只改默认值',
      );
    });

    test('preview probe is lazy without mutating the options snapshot', () {
      // 默认真实探针延迟到远程请求才创建；仅检查 options.probe 为空不足以证明接线。
      final mova = createMova(kernel: FakeKernel());
      addTearDown(mova.dispose);

      expect(mova.options.preview.probe, isNull);
      expect((mova.preview as MovaPreviewService).probe, isA<MovaLazyNetProbe>());
    });

    test('an explicitly injected probe is wired into MovaOpts.preview', () {
      final probe = _FakeNetProbe();
      final mova = createMova(kernel: FakeKernel(), probe: probe);
      addTearDown(mova.dispose);

      expect(mova.options.preview.probe, same(probe));
    });

    test('audioOnly does not disturb the other platform ports', () {
      final mova = createMova(kernel: FakeKernel(), audioOnly: true);
      addTearDown(mova.dispose);

      expect(mova.debugBrightness, isA<MovaBrightness>());
      expect(mova.debugPip, isA<MovaPip>());
      expect(mova.debugOrient, isA<MovaOrient>());
    });
  });

  test('movaObserveFlags truth table: native follows reporter OR preciseFirstFrame, qoe follows reporter only', () {
    expect(movaObserveFlags(hasReporter: false, preciseFirstFrame: false), (qoe: false, native: false, restart: false));
    expect(movaObserveFlags(hasReporter: false, preciseFirstFrame: true), (qoe: false, native: true, restart: true));
    expect(movaObserveFlags(hasReporter: true, preciseFirstFrame: false), (qoe: true, native: true, restart: true));
    expect(movaObserveFlags(hasReporter: true, preciseFirstFrame: true), (qoe: true, native: true, restart: true));
  });

  test('movaObserveFlags: recovery alone opens the native pump for END_FILE only (restart/qoe stay off)', () {
    expect(
      movaObserveFlags(hasReporter: false, preciseFirstFrame: false, recovery: true),
      (qoe: false, native: true, restart: false),
    );
    expect(
      movaObserveFlags(hasReporter: false, preciseFirstFrame: true, recovery: true),
      (qoe: false, native: true, restart: true),
    );
    expect(
      movaObserveFlags(hasReporter: true, preciseFirstFrame: false, recovery: true),
      (qoe: true, native: true, restart: true),
    );
  });

  test('createMova forwards fit to the player', () {
    final mova = createMova(kernel: FakeKernel(), fit: MovaFit.cover);
    addTearDown(mova.dispose);
    expect(mova.state.fit, MovaFit.cover);
  });

  test('Mova() itself still defaults to the noop/fallback ports', () {
    // Guards the other half of the contract: core's own constructor must
    // stay platform-independent for pure-Dart unit tests.
    //
    // 保护契约的另一半：core 自身的构造函数必须对纯 Dart 单测保持平台无关。
    final mova = Mova(kernel: FakeKernel());
    addTearDown(mova.dispose);

    expect(mova.debugBrightness, isA<MovaFallbackBrightness>());
    expect(mova.debugPip, isA<MovaNoopPip>());
    expect(mova.debugOrient, isA<MovaNoopOrient>());
  });
}
