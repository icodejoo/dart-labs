// On-device smoke test for the shipped native library: it must load, and the
// Dart decoder must agree with the binary's wire format. Both have failed for
// real (a stale Android .so mis-decoded the new `commands` field; a CI-built
// Android .so crashed inside frb init), so CI runs this on the macOS desktop
// and the iOS simulator.
// 已发布原生库的真机冒烟测试：库必须能加载，Dart 解码器必须与二进制的线格式一致。
// 两者都真实出过问题（旧 Android .so 解错新 `commands` 字段；CI 编的 Android .so
// 在 frb 初始化时崩溃），因此 CI 在 macOS 桌面和 iOS 模拟器上运行本测试。

// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:svgx/src/rust/api/svg.dart';
import 'package:svgx/svgx.dart';

/// Two shapes, one masked: exercises paths, effects and the mask wire layout.
/// 两个图形，其中一个带 mask：覆盖路径、效果和 mask 的线格式布局。
const _maskedSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <mask id="m"><rect x="0" y="0" width="12" height="24" fill="#fff"/></mask>
  <rect x="2" y="2" width="20" height="20" fill="#2A6DF4" mask="url(#m)"/>
  <circle cx="12" cy="12" r="4" fill="#FF7A00"/>
</svg>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await Svgx.ensureInitialized());

  test('Native backend initializes without throwing', () async {
    await Svgx.ensureInitialized();
  });

  test('parseSvg decodes a masked scene from the native library', () {
    final scene = parseSvg(data: _maskedSvg, currentColor: null);
    expect(scene.paths, hasLength(2));
    expect(
      scene.paths.where((p) => p.effects?.mask != null),
      hasLength(1),
      reason: 'exactly the masked <rect> should carry a mask effect',
    );
  });
}
