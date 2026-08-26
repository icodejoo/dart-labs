// Smoke test for embedded base64 <image> support, covering both the
// animation-engine parse/decode pipeline and (best-effort) the Rust static
// path's FFI call. Pixel-level rendering is out of scope — see task notes.
//
// 内嵌 base64 <image> 支持的冒烟测试，覆盖动画引擎解析/解码流水线，以及
// （尽力而为）Rust 静态路径的 FFI 调用。像素级渲染验证不在范围内——见任务说明。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';

// Same 1x1 opaque red PNG fixture used by the Rust-side test in
// rust/src/api/svg.rs (parses_embedded_base64_png_into_svg_image), so the two
// tests exercise the same real bytes end to end.
//
// 与 rust/src/api/svg.rs 里 Rust 侧测试
// （parses_embedded_base64_png_into_svg_image）相同的 1x1 不透明红色 PNG
// fixture，确保两侧测试用的是同一份真实字节。
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const _imageSvg =
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <image x="2" y="3" width="10" height="12" href="data:image/png;base64,$_pngBase64"/>
</svg>
''';

void main() {
  group('animation path: <image> node', () {
    test(
      'parseAnimatedSvgDocument produces an image node with the raw href',
      () {
        final document = parseAnimatedSvgDocument(_imageSvg);
        final imageNodes = _collectImageNodes(document.root);

        expect(imageNodes, hasLength(1));
        final node = imageNodes.single;
        expect(node.attributes['href'], contains('base64,$_pngBase64'));
        expect(
          node.resolvedImage,
          isNull,
          reason: 'not decoded until resolveImageNodes runs',
        );
      },
    );

    test('documentHasImages detects the node without triggering decode', () {
      final document = parseAnimatedSvgDocument(_imageSvg);
      expect(documentHasImages(document), isTrue);

      final noImageDocument = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="10"/></svg>',
      );
      expect(documentHasImages(noImageDocument), isFalse);
    });

    test('resolveImageNodes decodes the base64 payload into a ui.Image without throwing', () async {
      final document = parseAnimatedSvgDocument(_imageSvg);

      await resolveImageNodes(document);

      final node = _collectImageNodes(document.root).single;
      expect(node.resolvedImage, isNotNull);
      expect(node.resolvedImage!.width, 1);
      expect(node.resolvedImage!.height, 1);
    });

    test('a malformed href resolves to null instead of throwing', () async {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<image x="0" y="0" width="10" height="10" href="not-a-data-uri"/>'
        '</svg>',
      );

      await resolveImageNodes(document);

      final node = _collectImageNodes(document.root).single;
      expect(node.resolvedImage, isNull);
    });
  });
}

List<SvgNode> _collectImageNodes(SvgNode node) {
  final out = <SvgNode>[];
  void walk(SvgNode n) {
    if (n.kind == SvgNodeKind.image) out.add(n);
    for (final child in n.children) {
      walk(child);
    }
  }

  walk(node);
  return out;
}
