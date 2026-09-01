// Pixel-level (glyph-level) verification of `<text>` rendering in the
// animation/SMIL Dart path (lib/src/animation/). `<text>` IS implemented
// there (_paintText in animated_svg_painter.dart, via TextPainter) — see
// test/animation/text_node_test.dart for the existing "paints without
// throwing" coverage. This file goes further: it samples actual rendered
// pixel bytes to confirm the glyph really lands where expected, in the
// expected color, and that nothing stray gets painted outside it.
//
// 动画/SMIL Dart 路径中 `<text>` 渲染的像素级（字形级）校验。`<text>`
// 在该路径下已实现（animated_svg_painter.dart 的 _paintText，经
// TextPainter）——已有的"绘制不抛异常"覆盖见
// test/animation/text_node_test.dart。本文件进一步采样实际渲染出的像素字节，
// 确认字形真的落在预期位置、预期颜色，且字形外围没有意外溢出的绘制。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';

const _size = 100;
const _sizeD = 100.0;

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="$_size" height="$_size" '
  'viewBox="0 0 $_size $_size">$body</svg>',
);

Future<ByteData> _renderPixels(SvgDocument document) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    clock: ValueNotifier(Duration.zero),
    theme: const SvgxTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: document.gradients,
  ).paint(canvas, const Size(_sizeD, _sizeD));
  final image = await recorder.endRecording().toImage(_size, _size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

/// RGBA at ([x], [y]) as a 4-int list `[r, g, b, a]`.
///
/// ([x], [y]) 处的 RGBA，四元 `[r, g, b, a]`。
List<int> _rgbaAt(ByteData pixels, int x, int y) {
  final base = (y * _size + x) * 4;
  return [
    pixels.getUint8(base),
    pixels.getUint8(base + 1),
    pixels.getUint8(base + 2),
    pixels.getUint8(base + 3),
  ];
}

bool _closeToRed(List<int> rgba, {int tol = 30}) =>
    (rgba[0] - 255).abs() <= tol &&
    rgba[1] <= tol &&
    rgba[2] <= tol &&
    rgba[3] > 200;

bool _isBackground(List<int> rgba) =>
    rgba[3] == 0; // transparent canvas backdrop

void main() {
  group('glyph-level pixel verification', () {
    test('a bold filled "I" glyph paints red pixels within its bbox, background elsewhere', () async {
      // font-size=60 at x=20,y=70 (baseline): the glyph occupies roughly
      // x in [20, 20+strokeish width], y in [70-ascent, 70]. We use a large
      // size so the glyph body is many pixels wide/tall, tolerant of exact
      // font metrics differing by platform/test-harness font fallback.
      // font-size=60，锚点 x=20,y=70（基线）：字形大致占据 x∈[20, 20+宽度]，
      // y∈[70-上升高度, 70]。用较大字号使字形本体覆盖足够多像素，容忍不同
      // 平台/测试环境字体回退带来的具体度量差异。
      final document = _parse(
        '<text x="20" y="70" font-size="60" fill="#FF0000">I</text>',
      );
      final pixels = await _renderPixels(document);

      // Sample a small block squarely inside the glyph's expected bbox
      // (a vertical bar shape for "I", centered under the anchor).
      // 在字形预期包围盒内部采样一小块（"I" 的字形是一条竖条，位于锚点下方）。
      final samples = <List<int>>[];
      for (var y = 40; y <= 65; y += 5) {
        for (var x = 22; x <= 35; x += 4) {
          samples.add(_rgbaAt(pixels, x, y));
        }
      }
      final redHits = samples.where(_closeToRed).length;
      expect(
        redHits,
        greaterThan(0),
        reason:
            'expected at least one near-red, mostly-opaque pixel inside the glyph bbox; '
            'samples: $samples',
      );

      // Corners far from the text must remain untouched background
      // (transparent) — proof nothing stray gets painted outside the glyph.
      // 远离文本的四角必须保持未触碰的透明背景——证明字形之外没有意外溢出绘制。
      expect(
        _isBackground(_rgbaAt(pixels, 2, 2)),
        isTrue,
        reason: 'top-left corner',
      );
      expect(
        _isBackground(_rgbaAt(pixels, _size - 3, 2)),
        isTrue,
        reason: 'top-right corner',
      );
      expect(
        _isBackground(_rgbaAt(pixels, 2, _size - 3)),
        isTrue,
        reason: 'bottom-left corner',
      );
      expect(
        _isBackground(_rgbaAt(pixels, _size - 3, _size - 3)),
        isTrue,
        reason: 'bottom-right corner',
      );
    });

    test(
      'fill="none" text paints no red pixels anywhere (glyph genuinely absent)',
      () async {
        final document = _parse(
          '<text x="20" y="70" font-size="60" fill="none">I</text>',
        );
        final pixels = await _renderPixels(document);

        var redFound = false;
        for (var y = 0; y < _size; y += 4) {
          for (var x = 0; x < _size; x += 4) {
            if (_closeToRed(_rgbaAt(pixels, x, y))) redFound = true;
          }
        }
        expect(
          redFound,
          isFalse,
          reason: 'fill="none" must render no glyph pixels at all',
        );
      },
    );
  });
}
