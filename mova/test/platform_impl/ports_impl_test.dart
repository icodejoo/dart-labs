import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova_platform_interface.dart';
import 'package:mova/src/core/model/orientation.dart';
import 'package:mova/src/platform_impl/orientation_impl.dart';
import 'package:mova/src/platform_impl/volume_impl.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A platform whose system-volume answers and writes the test controls.
///
/// 系统音量的读取结果与写入记录都由测试掌控的平台。
class _VolumePlatform extends MovaPlatform with MockPlatformInterfaceMixin {
  /// What `getSystemVolume` answers (null models "no native implementation").
  ///
  /// `getSystemVolume` 的回答（null 表示"没有原生实现"）。
  double? volume;

  /// Every percent handed to `setSystemVolume`, in order.
  ///
  /// 交给 `setSystemVolume` 的每个百分比，按顺序。
  final List<double> writes = <double>[];

  @override
  Future<double?> getSystemVolume() async => volume;

  @override
  Future<bool> setSystemVolume(double percent) async {
    writes.add(percent);
    return true;
  }
}

/// The method names and arguments `SystemChrome` sent over the platform channel.
///
/// `SystemChrome` 经平台通道发出的方法名与参数。
class _ChromeLog {
  final List<MethodCall> calls = <MethodCall>[];

  /// The arguments of every `setPreferredOrientations`, as string lists.
  ///
  /// 每次 `setPreferredOrientations` 的参数，转成字符串列表。
  List<List<String>> get preferred => calls
      .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
      .map((c) => (c.arguments as List<dynamic>).cast<String>())
      .toList();

  /// The arguments of every `setEnabledSystemUIMode`, stringified.
  ///
  /// 每次 `setEnabledSystemUIMode` 的参数，转成字符串。
  List<String> get uiModes => calls
      .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
      .map((c) => c.arguments.toString())
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MovaSystemChromeOrientationPort', () {
    late _ChromeLog log;
    final port = MovaSystemChromeOrientationPort();

    setUp(() {
      log = _ChromeLog();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          log.calls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('fullscreen + immersive on a landscape video asks for landscape and immersive-sticky', () async {
      await port.apply(
        fullscreen: true,
        immersive: true,
        width: 1920,
        height: 1080,
        orientation: MovaOrientation.auto,
      );
      expect(
        log.preferred.single,
        resolveOrientations(MovaOrientation.auto, fullscreen: true, width: 1920, height: 1080)
            .map((o) => o.toString())
            .toList(),
      );
      expect(log.preferred.single.every((s) => s.contains('landscape')), isTrue);
      expect(log.uiModes.single, contains('immersiveSticky'));
    });

    test('fullscreen on a portrait video asks for portrait', () async {
      await port.apply(
        fullscreen: true,
        immersive: true,
        width: 1080,
        height: 1920,
        orientation: MovaOrientation.auto,
      );
      expect(log.preferred.single.every((s) => s.contains('portrait')), isTrue);
    });

    test('a forced orientation wins over the video aspect, even windowed', () async {
      await port.apply(
        fullscreen: false,
        immersive: false,
        width: 1920,
        height: 1080,
        orientation: MovaOrientation.portrait,
      );
      expect(log.preferred.single.every((s) => s.contains('portrait')), isTrue);
      expect(log.uiModes.single, contains('edgeToEdge'));
    });

    test('windowed auto lets every orientation through and keeps the system bars', () async {
      await port.apply(
        fullscreen: false,
        immersive: false,
        width: 1920,
        height: 1080,
        orientation: MovaOrientation.auto,
      );
      expect(log.preferred.single, hasLength(DeviceOrientation.values.length));
      expect(log.uiModes.single, contains('edgeToEdge'));
    });

    test('reset restores every orientation and the edge-to-edge mode', () async {
      await port.reset();
      expect(
        log.preferred.single,
        DeviceOrientation.values.map((o) => o.toString()).toList(),
      );
      expect(log.uiModes.single, contains('edgeToEdge'));
    });

    test('apply sets the orientations before the system UI mode', () async {
      await port.apply(
        fullscreen: true,
        immersive: true,
        width: 1920,
        height: 1080,
        orientation: MovaOrientation.auto,
      );
      final order = log.calls.map((c) => c.method).toList();
      expect(order.indexOf('SystemChrome.setPreferredOrientations'), lessThan(order.indexOf('SystemChrome.setEnabledSystemUIMode')));
    });
  });

  group('MovaSystemVolumePort', () {
    late _VolumePlatform platform;
    late MovaPlatform original;

    setUp(() {
      original = MovaPlatform.instance;
      platform = _VolumePlatform();
      MovaPlatform.instance = platform;
    });

    tearDown(() => MovaPlatform.instance = original);

    test('get returns the system volume the platform reports', () async {
      platform.volume = 42.5;
      expect(await MovaSystemVolumePort().get(), 42.5);
    });

    test('get falls back to 100 when the platform has no native implementation', () async {
      platform.volume = null;
      expect(await MovaSystemVolumePort().get(), 100);
    });

    test('set forwards an in-range percent unchanged', () async {
      await MovaSystemVolumePort().set(30);
      expect(platform.writes, [30]);
    });

    test('set clamps above 100 and below 0 before it reaches the platform', () async {
      await MovaSystemVolumePort().set(150);
      await MovaSystemVolumePort().set(-20);
      expect(platform.writes, [100, 0]);
    });
  });
}
