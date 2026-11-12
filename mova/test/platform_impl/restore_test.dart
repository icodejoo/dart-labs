import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';

/// 可控制初值读取和写入完成时机的旧亮度端口。
class _Brightness implements MovaBrightPort {
  /// 用 [initial] 指定读取结果，可选 [writeGate] 延迟写入。
  _Brightness(this.initial, {this.writeGate});
  /// 亮度读取结果。
  final Future<double> initial;
  /// 写入完成闸门。
  final Future<void>? writeGate;
  /// 按调用顺序记录亮度写入。
  final List<double> writes = [];
  /// 返回预置初值。
  @override
  Future<double> get() => initial;
  /// 记录 [value]，等待闸门后完成。
  @override
  Future<void> set(double value) async {
    writes.add(value);
    await writeGate;
  }
}

/// 提供可选还原能力的端口，区分还原与普通写入。
class _Restorable extends _Brightness implements MovaBrightRestore {
  /// 用 [initial] 指定初始亮度。
  _Restorable(super.initial);
  /// 记录被还原的初值。
  final List<double> restored = [];
  /// 记录 [initialBrightness] 并完成还原。
  @override
  Future<void> restore(double initialBrightness) async => restored.add(initialBrightness);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(MovaTesting.useTestKernels);
  tearDown(MovaTesting.reset);

  test('异步播种真实亮度，销毁后迟到读取不再写状态', () async {
    final ready = Completer<double>();
    final api = createMovaEngine(brightness: _Brightness(ready.future));
    ready.complete(0.35);
    await Future<void>.delayed(Duration.zero);
    expect(api.state.brightness, 0.35);
    await api.dispose();
    final late = Completer<double>();
    final other = createMovaEngine(brightness: _Brightness(late.future));
    await other.dispose();
    late.complete(0.2);
    await Future<void>.delayed(Duration.zero);
    expect(other.state.brightness, 1);
  });

  test('先请求手势后返回初值不覆盖用户值，旧端口离场写回初值', () async {
    final ready = Completer<double>();
    final port = _Brightness(ready.future);
    final api = createMovaEngine(brightness: port);
    final change = api.setBrightness(0.8);
    ready.complete(0.3);
    await change;
    expect(api.state.brightness, 0.8);
    expect(port.writes, [0.8]);
    await api.dispose();
    await api.dispose();
    expect(port.writes, [0.8, 0.3]);
  });

  test('离场还原等待在途写入，避免迟到写入再次改变亮度', () async {
    final gate = Completer<void>();
    final port = _Brightness(Future.value(0.4), writeGate: gate.future);
    final api = createMovaEngine(brightness: port);
    final change = api.setBrightness(0.9);
    await Future<void>.delayed(Duration.zero);
    final dispose = api.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(port.writes, [0.9]);
    gate.complete();
    await change;
    await dispose;
    expect(port.writes, [0.9, 0.4]);
  });

  test('可选还原能力、opt-out、未修改及退役的控制权规则', () async {
    for (final mode in ['restore', 'optOut', 'untouched', 'retired']) {
      final port = _Restorable(Future.value(0.4));
      final api = createMovaEngine(brightness: port, restoreBrightness: mode != 'optOut');
      if (mode != 'untouched') await api.setBrightness(0.8);
      if (mode == 'retired') api.markRetired();
      await api.dispose();
      expect(port.restored, mode == 'restore' ? [0.4] : isEmpty);
    }
  });

  test('连续换指后由最终引擎还原最初亮度，旧引擎不抢还原权', () async {
    final ports = <_Restorable>[];
    final api = MovaCutoverEngine(engineFactory: () {
      final port = _Restorable(Future.value(ports.isEmpty ? 0.3 : 0.8));
      ports.add(port);
      return createMovaEngine(brightness: port,
        options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
    });
    await api.setBrightness(0.8);
    for (var i = 0; i < 2; i++) {
      await api.prepare(MovaSource('https://test/video$i'), plan: MovaWarmPlan(
        trigger: const MovaEagerWarm(), policy: MovaBufferWarm(stableTicks: 1)));
      await api.setBrightness(0.9);
      MovaTesting.lastKernel!.emitBuffer(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await api.commit(), isTrue);
      expect(api.state.brightness, 0.9);
      await Future<void>.delayed(Duration.zero);
      expect(ports.expand((port) => port.restored), isEmpty);
    }
    await api.dispose();
    await api.dispose();
    expect(ports.first.restored, [0.3]);
    expect(ports.skip(1).expand((port) => port.restored), isEmpty);
  });

  test('初值失败或非有限时不写回猜测值，仍可调节及销毁', () async {
    for (final invalid in [double.nan, double.infinity, null]) {
      // 延迟生成错误 Future，确保引擎已安装错误处理。
      final ready = Completer<double>();
      final port = _Brightness(ready.future);
      final api = createMovaEngine(brightness: port);
      if (invalid == null) {
        ready.completeError(StateError('read failed'));
      } else {
        ready.complete(invalid);
      }
      await api.setBrightness(0.6);
      await api.dispose();
      expect(port.writes, [0.6]);
    }
  });

  test('真实亮度端口分别还原应用覆盖与系统控制，并隔离平台失败', () async {
    const channel = MethodChannel('github.com/aaassseee/screen_brightness');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    for (final hadOverride in [false, true]) {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'hasApplicationScreenBrightnessChanged') return hadOverride;
        if (call.method == 'getApplicationScreenBrightness') return 0.45;
        return null;
      });
      final port = MovaScreenBrightnessPort();
      expect(await port.get(), 0.45);
      await port.set(0.8);
      await port.restore(0.45);
      expect(calls.last.method, hadOverride ? 'setApplicationScreenBrightness' : 'resetApplicationScreenBrightness');
      if (hadOverride) expect(calls.last.arguments, {'brightness': 0.45});
      messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'failure'));
      await port.restore(0.45);
      await port.set(0.8);
      expect(await port.get(), 1);
    }
  });

  test('强制横屏退出全屏后保留方向，销毁时还原宿主方向和 manual 系统栏', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async { calls.add(call); return null; });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final api = createMovaEngine(kernel: MovaTestKernel(), brightness: _Brightness(Future.value(0.4)), orientationConfig: const MovaOrientationConfig(
      allowedOrientations: [DeviceOrientation.portraitUp], systemUiMode: SystemUiMode.manual, systemUiOverlays: [SystemUiOverlay.top],
    ));
    await api.setFullscreen(true);
    await api.setOrientation(MovaOrientation.landscape);
    calls.clear();
    await api.setFullscreen(false);
    expect(api.state.orientation, MovaOrientation.landscape);
    expect(calls.first.method, 'SystemChrome.setPreferredOrientations');
    expect(calls.first.arguments, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.last.arguments, ['SystemUiOverlay.top']);
    await api.setFullscreen(true);
    calls.clear();
    await api.dispose();
    expect(calls.first.arguments, ['DeviceOrientation.portraitUp']);
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.last.arguments, ['SystemUiOverlay.top']);
  });

  test('auto 方向退出全屏及销毁时还原宿主方向和 manual 系统栏', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final api = createMovaEngine(
      kernel: MovaTestKernel(),
      brightness: _Brightness(Future.value(0.4)),
      orientationConfig: const MovaOrientationConfig(
        allowedOrientations: [DeviceOrientation.portraitUp],
        systemUiMode: SystemUiMode.manual,
        systemUiOverlays: [SystemUiOverlay.top],
      ),
    );
    expect(api.state.orientation, MovaOrientation.auto);
    await api.setFullscreen(true);
    calls.clear();
    await api.setFullscreen(false);
    expect(calls.first.method, 'SystemChrome.setPreferredOrientations');
    expect(calls.first.arguments, ['DeviceOrientation.portraitUp']);
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.last.arguments, ['SystemUiOverlay.top']);
    await api.setFullscreen(true);
    calls.clear();
    await api.dispose();
    expect(calls.first.method, 'SystemChrome.setPreferredOrientations');
    expect(calls.first.arguments, ['DeviceOrientation.portraitUp']);
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
    expect(calls.last.arguments, ['SystemUiOverlay.top']);
  });

  test('方向默认仍允许全部方向，退役引擎离场不复位系统栏', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async { calls.add(call); return null; });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final api = createMovaEngine(orientation: const MovaSystemChromeOrientationPort());
    await api.setFullscreen(true);
    calls.clear();
    await api.setFullscreen(false);
    expect(calls.first.arguments, DeviceOrientation.values.map((o) => o.toString()).toList());
    expect(calls.last.arguments, SystemUiMode.edgeToEdge.toString());
    await api.setFullscreen(true);
    calls.clear();
    api.markRetired();
    await api.dispose();
    expect(calls, isEmpty);
  });
}
