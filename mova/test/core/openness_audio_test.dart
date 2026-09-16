import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mova/src/platform_impl/wiring.dart';

import '../support/fake_kernel.dart';

/// A fake [PathProviderPlatform] so `createMovaEngine()`'s real disk-cache
/// wiring can dispose cleanly in this plain-Dart test suite.
///
/// 假的 [PathProviderPlatform]，让 `createMovaEngine()` 的真实磁盘缓存接线在本
/// 纯 Dart 测试套件里也能正常 dispose。
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

/// The `MovaOpts` config sections, read straight from the source so the count
/// cannot silently drift.
///
/// 直接从源码读出的 `MovaOpts` 配置节，避免数量悄悄漂移。
List<String> _optsSections() {
  final src = File('lib/src/core/options/options.dart').readAsStringSync();
  final body = src.substring(src.indexOf('class MovaOpts'), src.indexOf('  const MovaOpts('));
  return RegExp(r'^  final \w+ (\w+);', multiLine: true)
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  group('audio-only openness contract — default + knob + injection per decision', () {
    test('whether a video pipeline is built: built by default', () {
      final engine = createMovaEngine(kernel: FakeKernel());
      addTearDown(engine.dispose);

      expect(engine.renderHandle, isNotNull);
      expect(
        engine.debugExtractor,
        isNotNull,
        reason: 'audioOnly defaults to false, so nothing about the video path '
            'changes / audioOnly 默认 false，视频路径一切照旧',
      );
    });

    test('the audioOnly knob turns both the render handle and the extractor off', () {
      final engine = createMovaEngine(kernel: FakeKernel.audioOnly(), audioOnly: true);
      addTearDown(engine.dispose);

      expect(engine.renderHandle, isNull);
      expect(engine.debugExtractor, isNull);
    });

    test('audioOnly deliberately did NOT become a MovaOpts section', () {
      expect(
        _optsSections(),
        const [
          'preview',
          'live',
          'gesture',
          'abr',
          'controls',
          'danmaku',
          'stt',
          'playlist',
          'ads',
          'strings',
          'theme',
          'swap',
        ],
        reason: 'audioOnly is a construction-time resource decision — the '
            "kernel's render handle is bound once and never re-bound, so a "
            'MovaOpts.copyWith(audioOnly: true) could never take effect. '
            'Putting it in MovaOpts would be a knob that lies. / '
            'audioOnly 是构造期的资源决策——内核的渲染句柄一次绑定、永不重绑，'
            'MovaOpts.copyWith(audioOnly: true) 根本无法生效。放进 MovaOpts '
            '等于造一个骗人的口子。',
      );
    });
  });
}
