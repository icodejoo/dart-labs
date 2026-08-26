// `<clipPath>`/`<mask>` in the animation path: id resolution onto SvgNode,
// document-level registration, pixel-level clip/mask correctness, and
// correct per-frame sampling when the referenced content is itself animated.
//
// 动画路径中的 `<clipPath>`/`<mask>`：id 解析到 SvgNode 上、文档级注册、
// 像素级裁剪/遮罩正确性，以及被引用内容自身带动画时逐帧采样正确。

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';
import 'package:svgx/src/animation/svg_theme.dart';

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">$body</svg>',
);

Future<ByteData> _renderPixels(
  SvgDocument document, {
  Duration time = Duration.zero,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    time: time,
    theme: const SvgTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: document.gradients,
    clipPaths: document.clipPaths,
    masks: document.masks,
  ).paint(canvas, const Size(100, 100));
  final image = await recorder.endRecording().toImage(100, 100);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!;
}

int _alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * 100 + x) * 4 + 3);

void main() {
  group('parsing', () {
    test('clip-path/mask url(#id) references are recorded on the node', () {
      final document = _parse(
        '<rect x="0" y="0" width="10" height="10" clip-path="url(#c)" mask="url(#m)"/>',
      );
      final node = document.root.children.single;

      expect(node.clipPathId, 'c');
      expect(node.maskId, 'm');
    });

    test('a clipPath/mask definition is registered on the document by id', () {
      final document = _parse(
        '<defs>'
        '<clipPath id="c"><rect x="0" y="0" width="1" height="1"/></clipPath>'
        '<mask id="m"><rect x="0" y="0" width="1" height="1" fill="#fff"/></mask>'
        '</defs>',
      );

      expect(document.clipPaths.containsKey('c'), isTrue);
      expect(document.masks.containsKey('m'), isTrue);
    });

    test('no reference means no id and rendering never looks anything up', () {
      final document = _parse('<rect x="0" y="0" width="10" height="10"/>');
      final node = document.root.children.single;

      expect(node.clipPathId, isNull);
      expect(node.maskId, isNull);
    });
  });

  group('pixel-level clip-path', () {
    test('clips a full-size fill down to the clip content', () async {
      final document = _parse(
        '<defs><clipPath id="c"><rect x="0" y="0" width="50" height="100"/></clipPath></defs>'
        '<rect x="0" y="0" width="100" height="100" fill="#0000FF" clip-path="url(#c)"/>',
      );
      final pixels = await _renderPixels(document);

      expect(_alphaAt(pixels, 10, 50), 255, reason: 'inside the clip region');
      expect(_alphaAt(pixels, 90, 50), 0, reason: 'outside the clip region');
    });

    test(
      'an animated clip path is sampled at the current frame, not just at rest',
      () async {
        final document = _parse(
          '<defs><clipPath id="c"><rect x="0" y="0" width="10" height="100">'
          '<animate attributeName="width" from="10" to="90" dur="1s" fill="freeze"/>'
          '</rect></clipPath></defs>'
          '<rect x="0" y="0" width="100" height="100" fill="#0000FF" clip-path="url(#c)"/>',
        );

        final atStart = await _renderPixels(document, time: Duration.zero);
        expect(
          _alphaAt(atStart, 50, 50),
          0,
          reason: 'clip is still narrow at t=0',
        );

        final atEnd = await _renderPixels(
          document,
          time: const Duration(seconds: 2),
        );
        expect(
          _alphaAt(atEnd, 50, 50),
          255,
          reason: 'clip has widened past x=50 by the end',
        );
      },
    );

    // Regression test for a bug found 2026-08-26 while caching geometry paths:
    // `_resolveClipPath` called `geometry.transform(matrix)` as a bare
    // statement, but `Path.transform` *returns* a transformed copy rather than
    // mutating the receiver — so the result was dropped and any transform on a
    // `<clipPath>`'s content was silently ignored. Here the clip rect covers
    // the left half and is translated 50 units right, so the *right* half must
    // survive; before the fix the left half did.
    //
    // 2026-08-26 在做几何路径缓存时发现的 bug 的回归测试：`_resolveClipPath`
    // 把 `geometry.transform(matrix)` 当成裸语句调用，但 `Path.transform` 是
    // **返回**变换后的副本而非原地修改接收者——于是返回值被丢弃，`<clipPath>`
    // 内容上的任何变换都被静默忽略。这里裁剪矩形覆盖左半边并向右平移 50 单位，
    // 因此存活的必须是**右**半边；修复前存活的是左半边。
    //
    // The tree is assembled by hand rather than parsed from markup because
    // `SvgNode.transform` is filled in by the Rust `parse_transform` bridge
    // (`native_svg_values.dart`), which degrades to null under plain
    // `flutter test` where no build step produced `svgx.dll` — a parsed
    // `transform="translate(50,0)"` would therefore be silently absent and the
    // test would pass for the wrong reason.
    //
    // 这里手工搭树而不是从标记文本解析，因为 `SvgNode.transform` 是由 Rust
    // `parse_transform` 桥（`native_svg_values.dart`）填入的，而在没有构建步骤
    // 产出 `svgx.dll` 的纯 `flutter test` 环境下它会退化为 null——解析
    // `transform="translate(50,0)"` 得到的会是"静默缺失"，测试就会因为错误的
    // 原因通过。
    test('a transform inside a clipPath is applied to its geometry', () async {
      final clipDef = SvgNode(
        kind: SvgNodeKind.root,
        attributes: const {},
        children: [
          SvgNode(
            kind: SvgNodeKind.rect,
            attributes: const {
              'x': '0',
              'y': '0',
              'width': '50',
              'height': '100',
            },
            transform: const [1, 0, 0, 1, 50, 0], // translate(50, 0)
          ),
        ],
      );
      final root = SvgNode(
        kind: SvgNodeKind.root,
        attributes: const {},
        children: [
          SvgNode(
            kind: SvgNodeKind.rect,
            attributes: const {
              'x': '0',
              'y': '0',
              'width': '100',
              'height': '100',
              'fill': '#0000FF',
            },
            clipPathId: 'c',
          ),
        ],
      );

      final recorder = ui.PictureRecorder();
      AnimatedSvgPainter(
        root: root,
        intrinsicSize: const Size(100, 100),
        time: Duration.zero,
        theme: const SvgTheme(),
        fit: BoxFit.fill,
        alignment: Alignment.center,
        clipPaths: {'c': clipDef},
      ).paint(Canvas(recorder), const Size(100, 100));
      final image = await recorder.endRecording().toImage(100, 100);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;

      expect(
        _alphaAt(pixels, 75, 50),
        255,
        reason: 'the translated clip rect covers the right half',
      );
      expect(
        _alphaAt(pixels, 25, 50),
        0,
        reason: 'the untranslated left half must not survive the clip',
      );
    });
  });

  group('pixel-level mask', () {
    test('masks a full-size fill down to the mask content luminance', () async {
      final document = _parse(
        '<defs><mask id="m"><rect x="0" y="0" width="50" height="100" fill="#FFFFFF"/></mask></defs>'
        '<rect x="0" y="0" width="100" height="100" fill="#0000FF" mask="url(#m)"/>',
      );
      final pixels = await _renderPixels(document);

      expect(
        _alphaAt(pixels, 10, 50),
        255,
        reason: 'covered by white mask content',
      );
      expect(
        _alphaAt(pixels, 90, 50),
        0,
        reason: 'not covered by any mask content',
      );
    });

    test('black mask content hides its area (near-zero luminance)', () async {
      final document = _parse(
        '<defs><mask id="m"><rect x="0" y="0" width="100" height="100" fill="#000000"/></mask></defs>'
        '<rect x="0" y="0" width="100" height="100" fill="#0000FF" mask="url(#m)"/>',
      );
      final pixels = await _renderPixels(document);

      expect(_alphaAt(pixels, 50, 50), lessThan(10));
    });

    test('an animated mask is sampled at the current frame', () async {
      final document = _parse(
        '<defs><mask id="m"><rect x="0" y="0" width="0" height="100" fill="#FFFFFF">'
        '<animate attributeName="width" from="0" to="100" dur="1s" fill="freeze"/>'
        '</rect></mask></defs>'
        '<rect x="0" y="0" width="100" height="100" fill="#0000FF" mask="url(#m)"/>',
      );

      final atStart = await _renderPixels(document, time: Duration.zero);
      expect(
        _alphaAt(atStart, 50, 50),
        0,
        reason: 'mask content has zero width at t=0',
      );

      final atEnd = await _renderPixels(
        document,
        time: const Duration(seconds: 2),
      );
      expect(
        _alphaAt(atEnd, 50, 50),
        255,
        reason: 'mask content has frozen full-width by the end',
      );
    });
  });
}
