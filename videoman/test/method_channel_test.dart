import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/videoman_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelVideoman platform = MethodChannelVideoman();
  const MethodChannel channel = MethodChannel('videoman');

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
}
