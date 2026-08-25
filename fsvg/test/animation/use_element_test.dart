// `<use href="#id">` resolution: forward references, `<defs>`/`<symbol>`
// targets, x/y placement, dangling references, and reference cycles.
//
// Pure parse-time behaviour, no FFI in the x/y-only paths, so every case here
// really runs under plain `flutter test`.
//
// `<use href="#id">` 的解析：前向引用、`<defs>`/`<symbol>` 目标、x/y 摆放、
// 悬空引用与引用环。
//
// 全部是解析阶段行为，x/y 路径不涉及 FFI，因此这里每个用例在纯
// `flutter test` 下都会真正执行。

import 'package:flutter_test/flutter_test.dart';
import 'package:fsvg/src/animation/svg_document_parser.dart';
import 'package:fsvg/src/animation/svg_dom.dart';

int _countKind(SvgNode node, SvgNodeKind kind) {
  var n = node.kind == kind ? 1 : 0;
  for (final child in node.children) {
    n += _countKind(child, kind);
  }
  return n;
}

void main() {
  group('<use>', () {
    test('clones a target declared earlier in the document', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<defs><circle id="dot" cx="0" cy="0" r="2"/></defs>'
        '<use href="#dot" x="5" y="7"/>'
        '</svg>',
      );

      // <defs> itself never renders, so the only circle is the instance.
      expect(_countKind(document.root, SvgNodeKind.circle), 1);
      final wrapper = document.root.children.single;
      expect(wrapper.kind, SvgNodeKind.group);
      expect(wrapper.transform, [1, 0, 0, 1, 5, 7]);
      expect(wrapper.children.single.attributes['r'], '2');
    });

    test('resolves a forward reference (use before its target)', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<use href="#later" x="1" y="1"/>'
        '<defs><rect id="later" x="0" y="0" width="3" height="3"/></defs>'
        '</svg>',
      );

      expect(_countKind(document.root, SvgNodeKind.rect), 1);
      expect(document.root.children.single.transform, [1, 0, 0, 1, 1, 1]);
    });

    test('xlink:href is accepted as well as href', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        'width="24" height="24">'
        '<defs><circle id="dot" cx="0" cy="0" r="2"/></defs>'
        '<use xlink:href="#dot"/>'
        '</svg>',
      );

      expect(_countKind(document.root, SvgNodeKind.circle), 1);
    });

    test('a <g> target clones its whole subtree', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<defs><g id="pair"><circle cx="0" cy="0" r="1"/><circle cx="4" cy="0" r="1"/></g></defs>'
        '<use href="#pair"/><use href="#pair" x="10"/>'
        '</svg>',
      );

      expect(_countKind(document.root, SvgNodeKind.circle), 4);
      expect(document.root.children[0].transform, isNull);
      expect(document.root.children[1].transform, [1, 0, 0, 1, 10, 0]);
    });

    test('a <symbol> target is treated as a group', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<symbol id="s" viewBox="0 0 8 8"><circle cx="4" cy="4" r="3"/></symbol>'
        '<use href="#s"/>'
        '</svg>',
      );

      expect(_countKind(document.root, SvgNodeKind.circle), 1);
    });

    test('the instance carries the target\'s own animations (shadow-tree reading)', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<defs><circle id="dot" cx="0" cy="0" r="1">'
        '<animate attributeName="r" from="1" to="4" dur="1s" fill="freeze"/>'
        '</circle></defs>'
        '<use href="#dot"/>'
        '</svg>',
      );

      final circle = document.root.children.single.children.single;
      expect(circle.animations, hasLength(1));
      expect(circle.animations.single.sample(const Duration(seconds: 2)), 4);
    });

    test('the <use> element\'s presentation attributes land on the wrapper', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<defs><circle id="dot" cx="0" cy="0" r="1"/></defs>'
        '<use href="#dot" x="2" fill="none" stroke="currentColor"/>'
        '</svg>',
      );
      final wrapper = document.root.children.single;

      expect(wrapper.attributes['fill'], 'none');
      expect(wrapper.attributes['stroke'], 'currentColor');
      expect(wrapper.attributes.containsKey('x'), isFalse, reason: 'placement, not presentation');
      expect(wrapper.attributes.containsKey('href'), isFalse);
    });

    test('a dangling reference renders nothing, silently', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<use href="#missing"/><circle cx="1" cy="1" r="1"/>'
        '</svg>',
      );

      expect(document.root.children, hasLength(1));
      expect(document.root.children.single.kind, SvgNodeKind.circle);
    });

    test('a non-local href (external file) renders nothing', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<use href="other.svg#dot"/>'
        '</svg>',
      );

      expect(document.root.children, isEmpty);
    });

    test('a self-referencing <use> terminates instead of looping forever', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<g id="loop"><circle cx="0" cy="0" r="1"/><use href="#loop"/></g>'
        '</svg>',
      );

      // The outer <g> renders once; the nested <use> re-enters "loop", which
      // is already in progress, so it is skipped.
      expect(_countKind(document.root, SvgNodeKind.circle), 1);
    });

    test('a two-step reference cycle terminates', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<defs>'
        '<g id="a"><circle cx="0" cy="0" r="1"/><use href="#b"/></g>'
        '<g id="b"><circle cx="2" cy="0" r="1"/><use href="#a"/></g>'
        '</defs>'
        '<use href="#a"/>'
        '</svg>',
      );

      // a -> b -> (a already resolving, skipped): two circles, then it stops.
      expect(_countKind(document.root, SvgNodeKind.circle), 2);
    });
  });
}
