import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// 夹具和像素对照共用的正方形边长。
const _fixtureEdge = 128;

/// 用原生路径门槛构造两条可合并的填充轮廓。
String _mergeFixture({bool separate = false}) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="$_fixtureEdge" height="$_fixtureEdge">
  <defs><clipPath id="c"><rect x="-40" y="-40" width="290" height="290"/></clipPath></defs>
  <path d="M2.1 3.2H36.4V16.5H2.1Z"/>
  ${separate ? '<g clip-path="url(#c)">' : ''}
  <path d="M18.2 28.3V64.1H61.4V28.3Z"/>
  ${separate ? '</g>' : ''}
  ${'<rect x="110" y="110" width="4" height="4" fill="#8b4315"/> ' * (xvgRasterMinPaths - 2)}
</svg>''';

/// 读取预乘 RGBA 字节并释放图像句柄。
Future<Uint8List> _pixels(RustSvgPictureInfo info) async {
  final image = await rasterizeSvgPicture(
    info,
    width: _fixtureEdge,
    height: _fixtureEdge,
  );
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// 验证自动判定、强制开关和缓存一致性。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = RustXvgPictureCache.instance;
  final source = _mergeFixture();
  setUpAll(RustLib.init);
  tearDown(() {
    debugPathMergeOverride = null;
    debugStaticSvgAsyncParseThreshold = null;
    cache.clear();
  });

  test(
    'flutter_tester uses independent draws and skips GPU readback',
    () async {
      expect(ui.ImageFilter.isShaderFilterSupported, isFalse);
      final picture = cache.getOrRender(source);
      addTearDown(picture.picture.dispose);
      expect(picture.pathCount, xvgRasterMinPaths);
      final probe = await debugPathMergeProbeResult;
      expect(probe?.allowed, isFalse);
      expect(probe?.maxDelta, isNull);
    },
  );

  test(
    'the sync renderer preserves the cached picture across a pass',
    () async {
      debugPathMergeOverride = false;
      final first = cache.getOrRender(source);
      addTearDown(first.picture.dispose);
      expect(first.pathCount, xvgRasterMinPaths);

      debugPathMergeOverride = true;
      expect(cache.peek(source), same(first));
      expect(cache.getOrRender(source), same(first));
      expect(await cache.getOrRenderAsync(source), same(first));

      cache.clear();
      final merged = cache.getOrRender(source);
      addTearDown(merged.picture.dispose);
      expect(merged.pathCount, xvgRasterMinPaths - 1);
    },
  );

  test(
    'worker uses the requested policy and off pixels match byte for byte',
    () async {
      debugStaticSvgAsyncParseThreshold = 0;
      debugPathMergeOverride = false;
      final pending = cache.getOrRenderAsync(source);
      debugPathMergeOverride = true;
      expect(cache.getOrRenderAsync(source), same(pending));
      final separate = await pending;
      final reference = await cache.getOrRenderAsync(
        _mergeFixture(separate: true),
      );
      addTearDown(separate.picture.dispose);
      addTearDown(reference.picture.dispose);
      expect(separate.pathCount, xvgRasterMinPaths);
      expect(reference.pathCount, xvgRasterMinPaths);
      final pixels = await _pixels(reference);
      expect(pixels.any((value) => value != 0), isTrue);
      expect(await _pixels(separate), orderedEquals(pixels));

      cache.clear();
      final merged = await cache.getOrRenderAsync(source);
      addTearDown(merged.picture.dispose);
      expect(merged.pathCount, xvgRasterMinPaths - 1);
      expect(parseSvg(data: source).paths, hasLength(xvgRasterMinPaths));
    },
  );
}
