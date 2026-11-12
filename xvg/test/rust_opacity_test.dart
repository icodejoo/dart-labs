// 静态 opacity 的显示列表与像素回归。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/xvg.dart';

/// 包装固定 viewport，方便检查非抗锯齿边界内的像素。
String _svg(String content, {String attributes = ''}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" $attributes>$content</svg>';

/// 经过真实 FFI 和 Picture 录制后回读像素，并释放临时图片。
Future<ByteData> _pixels(String source, {bool async = false}) async {
  final cache = RustXvgPictureCache.instance;
  final info = async
      ? await cache.getOrRenderAsync(source)
      : cache.getOrRender(source);
  final image = await info.picture.toImage(40, 40);
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    ))!;
  } finally {
    image.dispose();
  }
}

/// 读取指定像素的 alpha。
int _alpha(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * 40 + x) * 4 + 3);

/// 生成不透明红色 PNG，验证图片也包含在 opacity 组内。
Future<String> _redPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return base64Encode(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// 原生库不可加载时跳过用例。
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
        'Skipping rust_opacity_test.dart: native library not loadable in this test environment ($e)',
      );
    }
  });
  tearDown(() => RustXvgPictureCache.instance.clear());

  test(
    'group opacity composites overlapping children once and restores siblings',
    () async {
      if (!_rustAvailable) return;
      final source = _svg(
        '<g opacity=".5"><rect width="30" height="30" fill="red"/><rect x="10" width="30" height="30" fill="blue"/></g><rect y="35" width="40" height="5"/>',
      );
      final scene = parseSvg(data: source);
      expect(scene.commands.map((c) => c.kind), [2, 0, 0, 3, 0]);
      expect(scene.paths.map((p) => p.fillArgb >> 24), everyElement(255));
      final pixels = await _pixels(source);
      expect(_alpha(pixels, 5, 15), closeTo(128, 1));
      expect(_alpha(pixels, 20, 15), closeTo(128, 1));
      expect(_alpha(pixels, 35, 15), closeTo(128, 1));
      expect(_alpha(pixels, 20, 37), 255);
      expect(pixels.getUint8((15 * 40 + 20) * 4 + 2), 255);
    },
  );

  test('element opacity composites fill and stroke together', () async {
    if (!_rustAvailable) return;
    final pixels = await _pixels(
      _svg(
        '<rect x="5" y="5" width="30" height="30" fill="red" stroke="blue" stroke-width="10" opacity=".5"/>',
      ),
    );
    expect(_alpha(pixels, 20, 20), closeTo(128, 1));
    expect(_alpha(pixels, 7, 20), closeTo(128, 1));
    expect(_alpha(pixels, 2, 20), closeTo(128, 1));
  });

  test('nested group and element opacity multiply after compositing', () async {
    if (!_rustAvailable) return;
    final pixels = await _pixels(
      _svg(
        '<g opacity=".5"><g opacity=".5"><rect width="30" height="40"/><rect x="10" width="30" height="40"/></g></g>',
      ),
    );
    expect(_alpha(pixels, 5, 20), closeTo(64, 1));
    expect(_alpha(pixels, 20, 20), closeTo(64, 1));
    expect(_alpha(pixels, 35, 20), closeTo(64, 1));
  });

  test('opacity and fill-opacity remain separate for solid and gradient fills', () async {
    if (!_rustAvailable) return;
    for (final fill in ['red', 'url(#p)']) {
      final source = _svg(
        '<defs><linearGradient id="p"><stop stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient></defs><g opacity=".5"><rect width="40" height="40" fill="$fill" fill-opacity=".5"/></g>',
      );
      final pixels = await _pixels(source);
      expect(_alpha(pixels, 20, 20), closeTo(64, 1), reason: fill);
    }
  });

  test(
    'element opacity combines with fill-opacity and ancestor opacity',
    () async {
      if (!_rustAvailable) return;
      final pixels = await _pixels(
        _svg(
          '<g opacity=".5"><rect width="40" height="40" opacity=".5" fill-opacity=".5"/></g>',
        ),
      );
      expect(_alpha(pixels, 20, 20), closeTo(32, 1));
    },
  );

  test('root opacity wraps nested content', () async {
    if (!_rustAvailable) return;
    final pixels = await _pixels(
      _svg(
        '<rect width="40" height="40" opacity=".5"/>',
        attributes: 'opacity=".5"',
      ),
    );
    expect(_alpha(pixels, 20, 20), closeTo(64, 1));
  });

  test('opacity is clamped and an opaque scene needs no commands', () async {
    if (!_rustAvailable) return;
    for (final (value, alpha) in [
      ('-1', 0),
      ('0', 0),
      ('1', 255),
      ('2', 255),
    ]) {
      final source = _svg(
        '<g opacity="$value"><rect width="40" height="40"/></g>',
      );
      expect(_alpha(await _pixels(source), 20, 20), alpha);
      if (alpha == 255) expect(parseSvg(data: source).commands, isEmpty);
    }
  });

  test('mask and pattern subroots preserve group opacity', () async {
    if (!_rustAvailable) return;
    final source = _svg(
      '<defs><mask id="m" mask-type="alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="40" height="40"><g opacity=".5"><rect width="40" height="40" fill="white"/><rect width="30" height="40" fill="white"/></g></mask><pattern id="p" patternUnits="userSpaceOnUse" width="40" height="40"><g opacity=".5"><rect width="40" height="40" fill="red"/><rect width="30" height="40" fill="red"/></g></pattern></defs><rect width="40" height="40" fill="url(#p)" mask="url(#m)"/>',
    );
    final pixels = await _pixels(source);
    expect(_alpha(pixels, 20, 20), closeTo(64, 1));
    expect(_alpha(pixels, 35, 20), closeTo(64, 1));
  });

  test('luminance masks include group and fill alpha in every pixel', () async {
    if (!_rustAvailable) return;
    for (final content in [
      '<g opacity=".5"><rect width="40" height="40" fill="white"/><rect width="30" height="40" fill="white"/></g>',
      '<rect width="40" height="40" fill="white" fill-opacity=".5"/>',
    ]) {
      final pixels = await _pixels(
        _svg(
          '<defs><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="40" height="40">$content</mask></defs><rect width="40" height="40" fill="red" mask="url(#m)"/>',
        ),
      );
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          expect(
            _alpha(pixels, x, y),
            closeTo(128, 1),
            reason: '$content at ($x, $y)',
          );
        }
      }
    }
  });

  test('zero opacity omits main, mask and pattern subtrees', () async {
    if (!_rustAvailable) return;
    final scene = parseSvg(
      data: _svg(
        '<defs><mask id="m" mask-type="alpha"><g opacity="0"><rect width="40" height="40"/></g><rect width="40" height="40" fill="white"/></mask><pattern id="p" patternUnits="userSpaceOnUse" width="40" height="40"><g opacity="0"><rect width="40" height="40"/></g><rect width="40" height="40" fill="red"/></pattern></defs><g opacity="0"><rect width="40" height="40"/></g><rect width="40" height="40" fill="url(#p)" mask="url(#m)"/>',
      ),
    );
    expect(scene.paths, hasLength(1));
    expect(scene.commands, isEmpty);
    expect(scene.paths.single.effects!.mask!.paths, hasLength(1));
    expect(scene.paths.single.effects!.mask!.commands, isEmpty);
    expect(scene.paths.single.effects!.fillPattern!.paths, hasLength(1));
    expect(scene.paths.single.effects!.fillPattern!.commands, isEmpty);
    final pixels = await _pixels(
      _svg('<g opacity="0"><rect width="40" height="40"/></g>'),
    );
    expect(_alpha(pixels, 20, 20), 0);
  });

  test('opacity encloses images and paths in document order', () async {
    if (!_rustAvailable) return;
    final png = await _redPng();
    final source = _svg(
      '<g opacity=".5"><rect width="40" height="40" fill="blue"/><image width="30" height="40" preserveAspectRatio="none" href="data:image/png;base64,$png"/></g>',
    );
    expect(parseSvg(data: source).commands.map((c) => c.kind), [2, 0, 1, 3]);
    final pixels = await _pixels(source, async: true);
    expect(_alpha(pixels, 20, 20), closeTo(128, 1));
    expect(_alpha(pixels, 35, 20), closeTo(128, 1));
    expect(pixels.getUint8((20 * 40 + 20) * 4), 255);
    expect(pixels.getUint8((20 * 40 + 35) * 4 + 2), 255);
  });

  test('opaque scene retains the existing flat replay', () async {
    if (!_rustAvailable) return;
    final source = _svg('<rect width="40" height="40" fill="red"/>');
    expect(parseSvg(data: source).commands, isEmpty);
    expect(_alpha(await _pixels(source), 20, 20), 255);
  });
}
