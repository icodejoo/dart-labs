// Pixel-level tests for the static path's `currentColor` substitution and
// `paint-order` handling. Each renders a scene through `RustSvgPictureCache`
// and reads back real pixels, mirroring the convention in
// `rust_paint_features_test.dart`.
//
// Best-effort: skips itself if the native library isn't loadable under plain
// `flutter test` (host VM, no Flutter build step), same convention as
// `rust_image_smoke_test.dart`.
//
// 静态路径 `currentColor` 替换与 `paint-order` 处理的像素级测试。每个用例都
// 通过 `RustSvgPictureCache` 渲染并回读真实像素，约定同
// `rust_paint_features_test.dart`。
//
// 尽力而为：若在纯 `flutter test`（host VM，未走 Flutter 构建）下原生库无法
// 加载则自行跳过，约定同 `rust_image_smoke_test.dart`。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart';

/// A full-size square whose fill is `currentColor`, resolved via the
/// caller-supplied override at render time.
/// 整幅方块，fill 为 `currentColor`，在渲染时按调用方传入的覆盖色解析。
const _currentColorSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <rect x="0" y="0" width="100" height="100" fill="currentColor"/>
</svg>
''';

/// A large filled+stroked circle with `paint-order="stroke fill"`, so the
/// fill paints over the stroke instead of the default stroke-over-fill.
/// 一个较大的填充+描边圆，`paint-order="stroke fill"` 使填充盖在描边之上，
/// 而非默认的描边盖在填充之上。
const _paintOrderSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <circle cx="50" cy="50" r="40" fill="#0000FF" stroke="#FF0000" stroke-width="20" paint-order="stroke fill"/>
</svg>
''';

/// Renders [source] and reads back its raw RGBA pixels at 100x100, with
/// `currentColor` resolved to [currentColorArgb] when given.
/// 渲染 [source] 并按 100x100 回读原始 RGBA 像素；给定 [currentColorArgb] 时
/// 用它解析 `currentColor`。
Future<ByteData> _renderPixels(String source, {int? currentColorArgb}) async {
  RustSvgPictureCache.instance.clear();
  final info = RustSvgPictureCache.instance.getOrRender(
    source,
    currentColorArgb: currentColorArgb,
  );
  final image = await info.picture.toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

/// The RGBA channel quadruple at ([x], [y]) in a 100-wide RGBA buffer.
/// 100 像素宽 RGBA 缓冲中 ([x], [y]) 处像素的 RGBA 四元组。
List<int> _rgbaAt(ByteData pixels, int x, int y) {
  final offset = (y * 100 + x) * 4;
  return [
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
    pixels.getUint8(offset + 3),
  ];
}

/// Whether the native library was loadable in this test process. Set once in
/// `setUpAll`; individual tests skip themselves when it's false instead of
/// failing hard on an environment limitation unrelated to the feature under
/// test (same convention as `rust_image_smoke_test.dart`).
/// 本测试进程内原生库是否可加载，在 `setUpAll` 中设置一次；为 false 时各用例
/// 自行跳过，而不是因与被测功能无关的环境限制而硬失败（约定同
/// `rust_image_smoke_test.dart`）。
bool _rustAvailable = true;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await RustLib.init();
    } catch (e) {
      _rustAvailable = false;
      // ignore: avoid_print
      print(
        'Skipping rust_current_color_paint_order_test.dart: native library not loadable in this test environment ($e)',
      );
    }
  });

  test(
    'currentColor resolves to the caller-supplied override at render time',
    () async {
      if (!_rustAvailable) return;
      // 0xFFFF7A00 = opaque orange.
      final pixels = await _renderPixels(
        _currentColorSvg,
        currentColorArgb: 0xFFFF7A00,
      );
      final rgba = _rgbaAt(pixels, 50, 50);
      expect(rgba, [0xFF, 0x7A, 0x00, 0xFF]);
    },
  );

  test(
    'currentColor with a different override paints a different color',
    () async {
      if (!_rustAvailable) return;
      // 0xFF00FF00 = opaque green.
      final pixels = await _renderPixels(
        _currentColorSvg,
        currentColorArgb: 0xFF00FF00,
      );
      final rgba = _rgbaAt(pixels, 50, 50);
      expect(rgba, [0x00, 0xFF, 0x00, 0xFF]);
    },
  );

  test('paint-order="stroke fill" paints fill over stroke, differing from the default order', () async {
    if (!_rustAvailable) return;
    final pixels = await _renderPixels(_paintOrderSvg);
    // The stroke straddles the circle's edge (r=40, stroke-width=20, so it
    // spans radius 30..50). With the default order the stroke (red) would
    // sit on top there; with paint-order="stroke fill" the fill (blue)
    // paints last and wins.
    // 描边横跨圆的边缘（r=40，stroke-width=20，覆盖半径 30..50）。默认顺序下
    // 该处应是描边（红）盖在上面；paint-order="stroke fill" 下填充（蓝）
    // 后画，胜出。
    final rgba = _rgbaAt(pixels, 50, 15);
    expect(
      rgba[2],
      greaterThan(rgba[0]),
      reason: 'fill (blue) must win over stroke (red) at the shared edge',
    );
  });
}
