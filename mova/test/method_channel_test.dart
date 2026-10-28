import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelMova platform = MethodChannelMova();
  const MethodChannel channel = MethodChannel('mova');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('setSystemVolume invokes the channel with the percent and reads result', () async {
    MethodCall? seen;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return true;
    });
    final ok = await platform.setSystemVolume(42);
    expect(ok, isTrue);
    expect(seen?.method, 'setSystemVolume');
    expect((seen?.arguments as Map)['percent'], 42);
  });

  test('getSystemVolume returns the channel value', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 55.0);
    expect(await platform.getSystemVolume(), 55.0);
  });

  test('system volume degrades to null/false without a native impl', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await platform.getSystemVolume(), isNull);
    expect(await platform.setSystemVolume(50), isFalse);
  });

  group('PiP over the channel', () {
    /// Installs [handler] as the native side of the `mova` channel.
    ///
    /// 把 [handler] 装成 `mova` 通道的原生一侧。
    void mockNative(Future<Object?> Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
    }

    /// Simulates the native side pushing [method] with [arguments] into Dart.
    ///
    /// 模拟原生一侧向 Dart 推送 [method] 及 [arguments]。
    Future<void> pushFromNative(String method, Object? arguments) {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(MethodCall(method, arguments)),
            (_) {},
          );
    }

    tearDown(() {
      // The channel handler is process-global; leave it clean for other tests.
      // 通道处理器是进程级全局的；清干净，免得影响别的用例。
      channel.setMethodCallHandler(null);
    });

    test('pipChanged pushes reach pipChanges as bools, in order', () async {
      final fresh = MethodChannelMova();
      final seen = <bool>[];
      final sub = fresh.pipChanges.listen(seen.add);
      await pushFromNative('pipChanged', true);
      await pushFromNative('pipChanged', false);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [true, false]);
      await sub.cancel();
    });

    test('a pipChanged with a non-bool argument is ignored', () async {
      final fresh = MethodChannelMova();
      final seen = <bool>[];
      final sub = fresh.pipChanges.listen(seen.add);
      await pushFromNative('pipChanged', 'yes');
      await pushFromNative('pipChanged', 1);
      await pushFromNative('pipChanged', null);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await sub.cancel();
    });

    test('other native method names are ignored', () async {
      final fresh = MethodChannelMova();
      final seen = <bool>[];
      final sub = fresh.pipChanges.listen(seen.add);
      await pushFromNative('somethingElse', true);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      await sub.cancel();
    });

    test('every listener of pipChanges receives the same push', () async {
      final fresh = MethodChannelMova();
      final a = <bool>[];
      final b = <bool>[];
      final subA = fresh.pipChanges.listen(a.add);
      final subB = fresh.pipChanges.listen(b.add);
      await pushFromNative('pipChanged', false);
      await Future<void>.delayed(Duration.zero);
      expect(a, [false]);
      expect(b, [false]);
      await subA.cancel();
      await subB.cancel();
    });

    test('isPipSupported returns the native answer', () async {
      mockNative((call) async => call.method == 'isPipSupported' ? true : null);
      expect(await platform.isPipSupported(), isTrue);
      mockNative((call) async => false);
      expect(await platform.isPipSupported(), isFalse);
    });

    test('isPipSupported degrades to false on null, PlatformException and MissingPluginException', () async {
      mockNative((call) async => null);
      expect(await platform.isPipSupported(), isFalse);
      mockNative((call) async => throw PlatformException(code: 'boom'));
      expect(await platform.isPipSupported(), isFalse);
      mockNative(null);
      expect(await platform.isPipSupported(), isFalse);
    });

    test('enterPip sends width/height and returns the native result', () async {
      MethodCall? seen;
      mockNative((call) async {
        seen = call;
        return true;
      });
      expect(await platform.enterPip(width: 16, height: 9), isTrue);
      expect(seen?.method, 'enterPip');
      expect(seen?.arguments, {'width': 16, 'height': 9});
    });

    test('enterPip without a ratio sends explicit nulls', () async {
      MethodCall? seen;
      mockNative((call) async {
        seen = call;
        return true;
      });
      await platform.enterPip();
      expect(seen?.arguments, {'width': null, 'height': null});
    });

    test('enterPip turns null, PlatformException and MissingPluginException into false', () async {
      mockNative((call) async => null);
      expect(await platform.enterPip(width: 16, height: 9), isFalse);
      mockNative((call) async => throw PlatformException(code: 'no-activity'));
      expect(await platform.enterPip(width: 16, height: 9), isFalse);
      mockNative(null);
      expect(await platform.enterPip(width: 16, height: 9), isFalse);
    });

    test('system volume turns PlatformException into null / false', () async {
      mockNative((call) async => throw PlatformException(code: 'boom'));
      expect(await platform.getSystemVolume(), isNull);
      expect(await platform.setSystemVolume(30), isFalse);
    });
  });
}
