// `<text>` nodes in the animation path: parsing text content/x/y/font
// attributes, and rendering (no throw, honors fill/opacity via the existing
// generic per-frame animation mechanism). No `<tspan>`/textPath, and the text
// content itself cannot be animated — documented scope limits.
//
// 动画路径中的 `<text>` 节点：解析文本内容/x/y/字体属性，以及绘制（不抛错，
// 通过既有的通用逐帧动画机制支持 fill/opacity）。不支持 `<tspan>`/textPath，
// 也不支持对文本内容本身做动画——明确的范围限制。

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';
import 'package:svgx/src/animation/svg_theme.dart';

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="40" viewBox="0 0 100 40">$body</svg>',
    );

void main() {
  group('parsing', () {
    test('a <text> node carries its content, x/y and font attributes', () {
      final document = _parse(
        '<text x="5" y="20" font-size="14" font-family="monospace" text-anchor="middle">Hi</text>',
      );
      final node = document.root.children.single;

      expect(node.kind, SvgNodeKind.text);
      expect(node.textContent, 'Hi');
      expect(node.attributes['x'], '5');
      expect(node.attributes['y'], '20');
      expect(node.attributes['font-size'], '14');
      expect(node.attributes['font-family'], 'monospace');
      expect(node.attributes['text-anchor'], 'middle');
    });

    test('whitespace around the text content is trimmed', () {
      final document = _parse('<text x="0" y="0">\n  Hello  \n</text>');

      expect(document.root.children.single.textContent, 'Hello');
    });

    test('an empty <text> element parses to empty content, not null', () {
      final document = _parse('<text x="0" y="0"></text>');

      expect(document.root.children.single.textContent, '');
    });

    test('a non-text node never carries textContent', () {
      final document = _parse('<rect x="0" y="0" width="1" height="1"/>');

      expect(document.root.children.single.textContent, isNull);
    });
  });

  group('painting', () {
    Future<void> paint(SvgDocument document, {Duration time = Duration.zero}) async {
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
      ).paint(canvas, const Size(100, 40));
      // Painting text touches the font/text-layout engine; the assertion here
      // is simply that it never throws — pixel-exact glyph verification is
      // out of scope (this engine doesn't reimplement text shaping).
      // 绘制文本会触及字体/排版引擎；此处的断言仅是不抛出异常——像素级字形校验
      // 不在范围内（本引擎不重新实现文本排版）。
      recorder.endRecording();
    }

    test('a plain <text> node paints without throwing', () async {
      await paint(_parse('<text x="10" y="20" font-size="12">Hello</text>'));
    });

    test('fill="none" text paints nothing, without throwing', () async {
      await paint(_parse('<text x="10" y="20" fill="none">Hello</text>'));
    });

    test('empty text content paints nothing, without throwing', () async {
      await paint(_parse('<text x="10" y="20"></text>'));
    });

    test('an <animate> on opacity is sampled for text via the generic mechanism', () async {
      final document = _parse(
        '<text x="10" y="20">Hi'
        '<animate attributeName="opacity" from="0" to="1" dur="1s" fill="freeze"/>'
        '</text>',
      );
      await paint(document, time: Duration.zero);
      await paint(document, time: const Duration(seconds: 2));

      final node = document.root.children.single;
      expect(node.animations.single.attributeName, 'opacity');
      expect(node.animations.single.sample(Duration.zero), 0);
      expect(node.animations.single.sample(const Duration(seconds: 2)), 1);
    });
  });
}
