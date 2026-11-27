import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// Artwork extent and raster scale reference. / 图稿范围及光栅缩放参考。
const _edge = 128;

/// Maximum channel delta allowed along antialiased edges. / 抗锯齿边缘允许的最大通道差。
const _maxEdgeChannelDelta = 1;

/// Identifies the diagonal fixture with scale-dependent Skia coverage. / 标记 Skia 覆盖率随缩放变化的斜边夹具。
const _diagonalPaths = 'diagonal paths';

/// Inserts a no-op clip scope to force two independent reference draws. / 插入无可见影响的裁剪作用域，让对照保留两次独立绘制。
String _mergeFixture(List<String> shapes, {required bool reference}) =>
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="$_edge" height="$_edge">
  <defs><clipPath id="c"><rect x="-40" y="-40" width="290" height="290"/></clipPath></defs>
  <path fill="#345678" d="${shapes[0]}"/>
  ${reference ? '<g clip-path="url(#c)">' : ''}
  <path fill="#345678" d="${shapes[1]}"/>
  ${reference ? '</g>' : ''}
  ${'<rect x="110" y="110" width="4" height="4"/> ' * (xvgRasterMinPaths - shapes.length)}
</svg>''';

/// Reads every channel of a rasterized picture and releases the image. / 读取图像全部通道并释放句柄。
Future<Uint8List> _pixels(RustSvgPictureInfo info, int edge) async {
  final image = await rasterizeSvgPicture(info, width: edge, height: edge);
  try {
    return (await image.toByteData())!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = RustXvgPictureCache.instance;
  setUpAll(RustLib.init);
  setUp(cache.clear);
  tearDown(cache.clear);

  const pairs = {
    'rectangles': ['M2 3H13V16H2Z', 'M18 3V16H29V3Z'],
    _diagonalPaths: ['M1 1L20 20L21 19L2 0Z', 'M1 7L20 26L21 25L2 6Z'],
    'concave cubic paths': [
      'M2 2H10V5H6C5 5 4 8 5 10H2Z',
      'M15 2H23V5H19C18 5 17 8 18 10H15Z',
    ],
  };
  for (final entry in pairs.entries) {
    test('merged ${entry.key} stay within one RGBA level', () async {
      final merged = _mergeFixture(entry.value, reference: false);
      final separate = _mergeFixture(entry.value, reference: true);
      expect(parseSvg(data: merged).paths, hasLength(xvgRasterMinPaths - 1));
      expect(parseSvg(data: separate).paths, hasLength(xvgRasterMinPaths));
      final mergedInfo = cache.getOrRender(merged);
      final separateInfo = cache.getOrRender(separate);
      addTearDown(mergedInfo.picture.dispose);
      addTearDown(separateInfo.picture.dispose);
      // Skia can differ by two levels for a half-covered diagonal at 3×. / Skia 在 3× 的半覆盖斜边上可能相差两个色阶。
      final scales = entry.key == _diagonalPaths ? [1, 2] : [1, 2, 3];
      for (final scale in scales) {
        final actual = await _pixels(mergedInfo, _edge * scale);
        final expected = await _pixels(separateInfo, _edge * scale);
        expect(actual, hasLength(expected.length));
        for (var channel = 0; channel < actual.length; channel++) {
          if ((actual[channel] - expected[channel]).abs() >
              _maxEdgeChannelDelta) {
            fail(
              'scale $scale, channel $channel: '
              '${actual[channel]} vs ${expected[channel]}',
            );
          }
        }
      }
    });
  }
}
