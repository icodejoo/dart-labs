// 像素测试使用 xvg 的录制探针。
// ignore_for_file: implementation_imports

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bench_app/raster_233kb_bench.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// 录制正式静态路径，并回读绘制计数和直通 RGBA。
Future<(Map<String, int>, ByteData)> _renderClips(String source) async {
  final cache = RustXvgPictureCache.instance;
  late RasterRecordingCanvas canvas;
  RustXvgPictureCache.debugWrapRecordingCanvas = (inner) =>
      canvas = RasterRecordingCanvas(inner, 'xvg');
  try {
    final info = cache.getOrRender(source);
    final image = info.picture.toImageSync(16, 16);
    try {
      expect(canvas.restoreCount, canvas.saveCount + canvas.saveLayerCount);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      return (canvas.effects, pixels);
    } finally {
      image.dispose();
      info.picture.dispose();
    }
  } finally {
    cache.clear();
    RustXvgPictureCache.debugWrapRecordingCanvas = null;
  }
}

/// 在小画布上同时覆盖渐变、裁剪和带透明度的离屏层。
Future<(RasterRecordingCanvas, int, int)> _record(String mode) async {
  const red = ui.Color(0xffff0000);
  const blue = ui.Color(0xff0000ff);
  final recorder = ui.PictureRecorder();
  final canvas = RasterRecordingCanvas(ui.Canvas(recorder), mode);
  const bounds = ui.Rect.fromLTWH(0, 0, 16, 16);
  canvas
    ..save()
    ..clipPath(ui.Path()..addRect(const ui.Rect.fromLTWH(0, 0, 8, 16)))
    ..saveLayer(bounds, ui.Paint()..color = const ui.Color(0x80000000))
    ..drawPath(
      ui.Path()..addRect(bounds),
      ui.Paint()
        ..color = red
        ..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(16, 0), [
          blue,
          blue,
        ]),
    )
    ..restore()
    ..restore();
  expect(canvas.getSaveCount(), 1);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(16, 16);
  try {
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
    return (
      canvas,
      pixels.getUint32((4 * 16 + 4) * 4),
      pixels.getUint32((4 * 16 + 12) * 4),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retains the finite path prefix without modifying other attributes', () {
    const source =
        '<path id="M-nan" d="M0 0 L8 8 M-nan -nan L4 4"/>'
        "<path d='M2 3 Q5 6 7 8'/>";
    expect(
      retainFinitePathPrefixes(source),
      '<path id="M-nan" d="M0 0 L8 8"/>'
      "<path d='M2 3 Q5 6 7 8'/>",
    );
  });

  test('records one clip per group and restores unclipped siblings', () async {
    await RustLib.init();
    const opening =
        '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">'
        '<defs><clipPath id="c"><rect x="2" y="3" width="12" height="10"/>'
        '</clipPath></defs>';
    const first = '<rect width="8" height="16" fill="red"/>';
    const second = '<rect x="6" width="10" height="16" fill="blue"/>';
    const shared =
        '$opening<g clip-path="url(#c)" opacity=".5">$first$second</g></svg>';
    const mixed = '$opening<g clip-path="url(#c)">$first</g>$second</svg>';

    final (sharedCounts, sharedPixels) = await _renderClips(shared);
    expect(sharedCounts['clipPath'], 1);
    expect(sharedCounts['saveLayer'], 1);
    expect(sharedPixels.getUint32((5 * 16 + 4) * 4), 0xff000080);
    expect(sharedPixels.getUint32((14 * 16 + 10) * 4), 0);

    final (mixedCounts, mixedPixels) = await _renderClips(mixed);
    expect(mixedCounts['clipPath'], 1);
    expect(mixedCounts['saveLayer'], 0);
    expect(mixedPixels.getUint32((5 * 16 + 4) * 4), 0xff0000ff);
    expect(mixedPixels.getUint32((14 * 16 + 10) * 4), 0x0000ffff);
  });

  test(
    'records effects and each ablation changes only its expected pixels',
    () async {
      final baseline = await _record('xvg');
      final noClip = await _record('no_clip');
      final noLayer = await _record('no_layer');
      final noGradient = await _record('no_gradient');

      for (final result in [baseline, noClip, noLayer, noGradient]) {
        expect(result.$1.effects['clipPath'], 1);
        expect(result.$1.effects['saveLayer'], 1);
        expect(result.$1.effects['gradient'], 1);
        expect(result.$1.counts['drawPath'], 1);
      }
      expect((baseline.$2, baseline.$3), (0x0000ff80, 0));
      expect((noClip.$2, noClip.$3), (0x0000ff80, 0x0000ff80));
      expect((noLayer.$2, noLayer.$3), (0x0000ffff, 0));
      expect((noGradient.$2, noGradient.$3), (0xff000080, 0));
    },
  );
}
