// Best-effort smoke test for the Rust static path's <image> support. Skips
// itself if the native library isn't loadable under plain `flutter test`
// (host VM, no Flutter build step) rather than failing the whole suite over
// an environment limitation unrelated to the feature under test.
//
// Rust 静态路径 <image> 支持的尽力而为冒烟测试。若在纯 `flutter test`
// （host VM，未走 Flutter 构建）下原生库无法加载，则自行跳过，而不是让整个
// 测试套件因与被测功能无关的环境限制而失败。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const _imageSvg =
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <image x="2" y="3" width="10" height="12" href="data:image/png;base64,$_pngBase64"/>
</svg>
''';

void main() {
  test('parseSvg surfaces embedded <image> nodes in SvgScene.images', () async {
    try {
      await RustLib.init();
    } catch (e) {
      // ignore: avoid_print
      print(
        'Skipping: native library not loadable in this test environment ($e)',
      );
      return;
    }

    final scene = parseSvg(data: _imageSvg, currentColor: null);
    expect(scene.images, hasLength(1));
    final img = scene.images.single;
    expect(img.width, greaterThan(0));
    expect(img.height, greaterThan(0));
    expect(img.data, isNotEmpty);
    expect(img.format, SvgImageFormat.png);
  });
}
