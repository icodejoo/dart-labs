// Pixel-level verification of `filter="blur(...)"` (feGaussianBlur) in the
// animation/SMIL Dart path (lib/src/animation/) — NOT the Rust static path,
// which already has its own coverage in test/rust_paint_features_test.dart.
//
// Samples actual rendered pixel bytes (via toImage/toByteData) rather than
// merely asserting "no exception thrown": a shape with no blur must show a
// hard alpha transition at its edge; the same shape with blur must show a
// gradual alpha falloff that bleeds past the original geometric edge.
//
// 动画/SMIL Dart 路径（lib/src/animation/）中 `filter="blur(...)"`
// （feGaussianBlur）的像素级校验——非 Rust 静态路径（已在
// test/rust_paint_features_test.dart 覆盖）。
//
// 真正采样渲染出的像素字节（经 toImage/toByteData），而非仅断言"不抛异常"：
// 无模糊的形状边缘必须是硬跳变；同一形状加了模糊后，边缘必须呈现渐变式的
// alpha 衰减，并越过原始几何边缘产生渗出。

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
    clipPaths: document.clipPaths,
    masks: document.masks,
  ).paint(canvas, const Size(_sizeD, _sizeD));
  final image = await recorder.endRecording().toImage(_size, _size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

int _alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * _size + x) * 4 + 3);

/// Samples a horizontal line of alpha values straddling x=[centerX], from
/// [centerX] - [halfSpan] to [centerX] + [halfSpan] inclusive, at row [y].
///
/// 在第 [y] 行采样横跨 x=[centerX] 的一段水平线上的 alpha 值，范围是
/// [centerX] - [halfSpan] 到 [centerX] + [halfSpan]（含端点）。
List<int> _alphaLine(ByteData pixels, int centerX, int y, int halfSpan) => [
  for (var x = centerX - halfSpan; x <= centerX + halfSpan; x++)
    _alphaAt(pixels, x, y),
];

void main() {
  group('no blur: hard edge', () {
    test('alpha jumps 255->0 within 1-2 pixels at the shape edge, no falloff', () async {
      // A 50x100 solid rect: geometric right edge sits at x=50.
      // 一个 50x100 的实心矩形：几何右边缘在 x=50。
      final document = _parse(
        '<rect x="0" y="0" width="50" height="100" fill="#0000FF"/>',
      );
      final pixels = await _renderPixels(document);

      final line = _alphaLine(pixels, 50, 50, 9); // x = 41..59
      // Well inside the shape: fully opaque.
      expect(_alphaAt(pixels, 41, 50), 255, reason: 'well inside the rect');
      // Well outside the shape: fully transparent.
      expect(_alphaAt(pixels, 59, 50), 0, reason: 'well outside the rect');

      // The transition itself must be a hard step: at most one pixel of
      // partial alpha (antialiasing), never a multi-pixel gradual ramp.
      // 过渡本身必须是硬跳变：至多一个像素的部分 alpha（抗锯齿），绝不能是
      // 多像素的渐变斜坡。
      final partial = line.where((a) => a > 5 && a < 250).length;
      expect(
        partial,
        lessThanOrEqualTo(2),
        reason:
            'no-blur edge should not have a gradual alpha ramp; sampled line: $line',
      );
    });
  });

  group('with feGaussianBlur: gradual falloff + bleed', () {
    test('CSS shorthand filter="blur(Npx)" produces gradual falloff and edge bleed', () async {
      final document = _parse(
        '<rect x="0" y="0" width="50" height="100" fill="#0000FF" filter="blur(8px)"/>',
      );
      final pixels = await _renderPixels(document);
      final line = _alphaLine(pixels, 50, 50, 19); // x = 31..69

      // Proof of gradual falloff: several pixels with strictly-partial alpha,
      // not just antialiasing.
      // 渐变衰减的证据：多个像素处于严格意义上的部分 alpha，而非仅仅是抗锯齿。
      final partial = line.where((a) => a > 5 && a < 250).length;
      expect(
        partial,
        greaterThanOrEqualTo(6),
        reason:
            'blurred edge should ramp gradually over several pixels; sampled line: $line',
      );

      // Proof of bleed: nonzero alpha several px past the original geometric
      // edge (x=50), where the unblurred shape would be fully transparent.
      // 渗出的证据：原始几何边缘（x=50）之外数像素处仍有非零 alpha——未模糊的
      // 形状在这里应当是完全透明的。
      expect(
        _alphaAt(pixels, 58, 50),
        greaterThan(0),
        reason: 'blur bleeds past the geometric edge',
      );

      // The falloff must actually be monotonic-ish (decreasing as we move
      // away from the shape interior), confirming this is a real blur kernel
      // and not e.g. a second opaque shape or a fixed semi-transparent fill.
      // 衰减必须大致单调（离形状内部越远越低），确认这确实是真实的模糊核，
      // 而非例如第二个不透明形状或固定的半透明填充。
      expect(_alphaAt(pixels, 45, 50), greaterThan(_alphaAt(pixels, 55, 50)));
      expect(_alphaAt(pixels, 55, 50), greaterThan(_alphaAt(pixels, 65, 50)));
    });

    test('<filter><feGaussianBlur stdDeviation="..."/></filter> referenced via url(#id)', () async {
      final document = _parse(
        '<defs><filter id="b"><feGaussianBlur stdDeviation="8"/></filter></defs>'
        '<rect x="0" y="0" width="50" height="100" fill="#0000FF" filter="url(#b)"/>',
      );
      final pixels = await _renderPixels(document);
      final line = _alphaLine(pixels, 50, 50, 19);

      final partial = line.where((a) => a > 5 && a < 250).length;
      expect(
        partial,
        greaterThanOrEqualTo(6),
        reason:
            'url(#id) feGaussianBlur should ramp gradually too; sampled line: $line',
      );
      expect(
        _alphaAt(pixels, 58, 50),
        greaterThan(0),
        reason: 'blur bleeds past the geometric edge',
      );
    });
  });
}
