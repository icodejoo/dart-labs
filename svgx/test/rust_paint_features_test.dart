// Pixel-level tests for the static path's newer paint features: `<clipPath>`,
// `<mask>`, `<pattern>` and the `feGaussianBlur` filter MVP. Each renders a
// scene through `RustSvgPictureCache` and reads back real pixels, so a
// silently-dropped clip/mask/pattern shows up as a failure rather than a
// "did not throw" pass.
//
// Best-effort: skips itself if the native library isn't loadable under plain
// `flutter test` (host VM, no Flutter build step), same convention as
// `rust_image_smoke_test.dart`.
//
// 静态路径较新绘制特性的像素级测试：`<clipPath>`、`<mask>`、`<pattern>` 以及
// `feGaussianBlur` 滤镜 MVP。每个用例都通过 `RustSvgPictureCache` 渲染并回读
// 真实像素，这样"裁剪/遮罩/图案被静默丢弃"会直接失败，而不是靠"没抛异常"
// 蒙混过关。
//
// 尽力而为：若在纯 `flutter test`（host VM，未走 Flutter 构建）下原生库无法
// 加载则自行跳过，约定同 `rust_image_smoke_test.dart`。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

/// Full-size blue square clipped to its left half.
/// 整幅蓝色方块，被裁剪到左半边。
const _clipSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <defs><clipPath id="c"><rect x="0" y="0" width="50" height="100"/></clipPath></defs>
  <rect x="0" y="0" width="100" height="100" fill="#0000FF" clip-path="url(#c)"/>
</svg>
''';

/// Full-size blue square masked by a white rect covering only its left half —
/// white luminance = fully visible, unpainted (transparent black) = hidden.
/// 整幅蓝色方块，被只覆盖左半边的白色矩形遮罩——白色亮度为完全可见，
/// 未绘制处（透明黑）为隐藏。
const _maskSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <defs>
    <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
      <rect x="0" y="0" width="50" height="100" fill="#FFFFFF"/>
    </mask>
  </defs>
  <rect x="0" y="0" width="100" height="100" fill="#0000FF" mask="url(#m)"/>
</svg>
''';

/// A 20x20 tile whose top-left quadrant is red; tiled across a 100x100 rect.
/// 20x20 的贴片，左上四分之一为红色；平铺覆盖 100x100 的矩形。
const _patternSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <defs>
    <pattern id="p" patternUnits="userSpaceOnUse" x="0" y="0" width="20" height="20">
      <rect x="0" y="0" width="10" height="10" fill="#FF0000"/>
    </pattern>
  </defs>
  <rect x="0" y="0" width="100" height="100" fill="url(#p)"/>
</svg>
''';

/// A hard-edged black square with a strong Gaussian blur: pixels just outside
/// the square's own bounds must pick up some coverage.
/// 一个硬边黑色方块 + 较强的高斯模糊：方块自身边界之外的像素必须被沾染上
/// 一定的覆盖度。
const _blurSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <defs>
    <filter id="b" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="6"/>
    </filter>
  </defs>
  <rect x="30" y="30" width="40" height="40" fill="#000000" filter="url(#b)"/>
</svg>
''';

/// Renders [source] and reads back its raw RGBA pixels at 100x100.
/// 渲染 [source] 并按 100x100 回读原始 RGBA 像素。
Future<ByteData> _renderPixels(String source) async {
  RustSvgPictureCache.instance.clear();
  final info = RustSvgPictureCache.instance.getOrRender(source);
  final image = await info.picture.toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

/// Alpha of the pixel at ([x], [y]) in a 100-wide RGBA buffer.
/// 100 像素宽 RGBA 缓冲中 ([x], [y]) 处像素的 alpha。
int _alphaAt(ByteData pixels, int x, int y) => pixels.getUint8((y * 100 + x) * 4 + 3);

/// Red channel of the pixel at ([x], [y]). / ([x], [y]) 处像素的红色通道。
int _redAt(ByteData pixels, int x, int y) => pixels.getUint8((y * 100 + x) * 4);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await RustLib.init();
    } catch (_) {
      // Already initialized in this isolate, or genuinely unavailable — the
      // per-test calls below surface any real failure.
      // 本 isolate 内已初始化，或确实不可用——真实失败会在下面各用例里暴露。
    }
  });

  test('parseSvg carries a clip-path onto the clipped path', () {
    final scene = parseSvg(data: _clipSvg, currentColor: null);
    expect(scene.paths, hasLength(1));
    expect(scene.paths.single.effects?.clips, hasLength(1));
  });

  test('a clip-path actually clips the recorded picture', () async {
    final pixels = await _renderPixels(_clipSvg);
    expect(_alphaAt(pixels, 25, 50), greaterThan(200), reason: 'inside the clip must stay painted');
    expect(_alphaAt(pixels, 75, 50), lessThan(16), reason: 'outside the clip must be cut away');
  });

  test('a luminance mask hides the region its content does not cover', () async {
    final pixels = await _renderPixels(_maskSvg);
    expect(_alphaAt(pixels, 25, 50), greaterThan(200), reason: 'white mask content keeps pixels visible');
    expect(_alphaAt(pixels, 75, 50), lessThan(16), reason: 'uncovered mask region must be masked out');
  });

  test('a pattern fill repeats its tile instead of painting a flat colour', () async {
    final scene = parseSvg(data: _patternSvg, currentColor: null);
    expect(scene.paths.single.effects?.fillPattern, isNotNull);

    final pixels = await _renderPixels(_patternSvg);
    // The tile is 20x20 with a red 10x10 top-left quadrant, so (5,5) and
    // (25,25) (the next tile over) are red while (15,15) is empty.
    // 贴片为 20x20、左上 10x10 为红色，因此 (5,5) 与下一块贴片的 (25,25) 为
    // 红色，而 (15,15) 为空。
    expect(_redAt(pixels, 5, 5), greaterThan(200));
    expect(_alphaAt(pixels, 5, 5), greaterThan(200));
    expect(_alphaAt(pixels, 15, 15), lessThan(16), reason: 'the tile\'s empty quadrant must stay empty');
    expect(_alphaAt(pixels, 25, 25), greaterThan(200), reason: 'the tile must repeat, not stop after one');
  });

  test('feGaussianBlur softens the shape beyond its own bounds', () async {
    final pixels = await _renderPixels(_blurSvg);
    final inside = _alphaAt(pixels, 50, 50);
    final justOutside = _alphaAt(pixels, 24, 50);
    final farOutside = _alphaAt(pixels, 5, 50);
    expect(inside, greaterThan(200), reason: 'the shape core stays opaque');
    expect(justOutside, greaterThan(8), reason: 'blur must bleed past the original edge');
    expect(justOutside, lessThan(inside), reason: 'the bleed must be softer than the core');
    expect(farOutside, lessThan(16), reason: 'blur must fall off, not flood the canvas');
  });
}
