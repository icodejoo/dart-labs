// Syncbase `begin` resolution: `begin="other.end"` / `"other.begin+2s"` /
// negative offsets, chains, dangling references and reference cycles.
//
// Pure Dart (no FFI), so every case really runs under plain `flutter test`.
//
// 同步基准 `begin` 的解析：`begin="other.end"`/`"other.begin+2s"`/负偏移、
// 依赖链、悬空引用与引用环。
//
// 纯 Dart（不涉及 FFI），因此每个用例在纯 `flutter test` 下都会真正执行。

import 'package:flutter_test/flutter_test.dart';
import 'package:fsvg/src/animation/smil_animation.dart';
import 'package:fsvg/src/animation/svg_document_parser.dart';
import 'package:fsvg/src/animation/svg_dom.dart';

List<SmilAnimation> _animationsOf(SvgNode node) {
  final out = <SmilAnimation>[...node.animations];
  for (final child in node.children) {
    out.addAll(_animationsOf(child));
  }
  return out;
}

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">$body</svg>',
    );

void main() {
  group('parseSmilBeginSpec', () {
    test('reads a plain clock value', () {
      final spec = parseSmilBeginSpec('0.6s');
      expect(spec.syncbaseId, isNull);
      expect(spec.offset, const Duration(milliseconds: 600));
    });

    test('reads a bare syncbase reference', () {
      final spec = parseSmilBeginSpec('ring.end');
      expect(spec.syncbaseId, 'ring');
      expect(spec.onSyncbaseEnd, isTrue);
      expect(spec.offset, Duration.zero);
    });

    test('reads positive and negative offsets', () {
      expect(parseSmilBeginSpec('ring.begin+2s').offset, const Duration(seconds: 2));
      expect(parseSmilBeginSpec('ring.end - 500ms').offset, const Duration(milliseconds: -500));
      expect(parseSmilBeginSpec('ring.begin+2s').onSyncbaseEnd, isFalse);
    });

    test('an event value degrades to a zero offset (documented gap)', () {
      final spec = parseSmilBeginSpec('click');
      expect(spec.syncbaseId, isNull);
      expect(spec.offset, Duration.zero);
    });
  });

  group('resolution against a real document', () {
    test('begin="a.end" starts after the referenced animation finishes', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="500ms" begin="1s"/>'
        '<animate attributeName="opacity" from="0" to="1" dur="1s" begin="a.end"/>'
        '</circle>',
      );
      final animations = _animationsOf(document.root);

      expect(animations[1].begin, const Duration(milliseconds: 1500));
    });

    test('begin="a.begin+2s" offsets from the referenced begin', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="500ms" begin="1s"/>'
        '<animate attributeName="opacity" from="0" to="1" dur="1s" begin="a.begin+2s"/>'
        '</circle>',
      );

      expect(_animationsOf(document.root)[1].begin, const Duration(seconds: 3));
    });

    test('a negative offset pulls the start earlier', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="1s" begin="2s"/>'
        '<animate attributeName="opacity" from="0" to="1" dur="1s" begin="a.end-500ms"/>'
        '</circle>',
      );

      expect(_animationsOf(document.root)[1].begin, const Duration(milliseconds: 2500));
    });

    test('a chain A -> B -> C resolves transitively', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="c" attributeName="r" from="0" to="1" dur="1s" begin="1s"/>'
        '<animate id="b" attributeName="opacity" from="0" to="1" dur="2s" begin="c.end"/>'
        '<animate id="a" attributeName="cx" from="0" to="1" dur="1s" begin="b.end+500ms"/>'
        '</circle>',
      );
      final animations = _animationsOf(document.root);

      expect(animations[0].begin, const Duration(seconds: 1)); // c
      expect(animations[1].begin, const Duration(seconds: 2)); // b = c.end
      expect(animations[2].begin, const Duration(milliseconds: 4500)); // a = b.end + 0.5s
    });

    test('a forward reference (target declared later) still resolves', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate attributeName="opacity" from="0" to="1" dur="1s" begin="later.end"/>'
        '<animate id="later" attributeName="r" from="0" to="1" dur="1s" begin="1s"/>'
        '</circle>',
      );

      expect(_animationsOf(document.root)[0].begin, const Duration(seconds: 2));
    });

    test('a cycle disables the animations on it instead of hanging', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="1s" begin="b.end"/>'
        '<animate id="b" attributeName="opacity" from="0" to="1" dur="1s" begin="a.end"/>'
        '</circle>',
      );
      final animations = _animationsOf(document.root);

      expect(animations[0].begin, kSmilNeverBegins);
      expect(animations[1].begin, kSmilNeverBegins);
      // Disabled animations never produce a sampled value.
      expect(animations[0].sample(const Duration(seconds: 10)), isNull);
      // ...and they don't stretch the document's duration either.
      expect(document.totalDuration, Duration.zero);
    });

    test('a self-reference disables the animation', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="1s" begin="a.end"/>'
        '</circle>',
      );

      expect(_animationsOf(document.root).single.begin, kSmilNeverBegins);
    });

    test('syncing to the end of an indefinite animation disables it', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="spin" attributeName="r" from="0" to="1" dur="1s" repeatCount="indefinite"/>'
        '<animate attributeName="opacity" from="0" to="1" dur="1s" begin="spin.end"/>'
        '</circle>',
      );

      expect(_animationsOf(document.root)[1].begin, kSmilNeverBegins);
    });

    test('a dangling reference falls back to the plain offset', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate attributeName="r" from="0" to="1" dur="1s" begin="ghost.end+2s"/>'
        '</circle>',
      );

      expect(_animationsOf(document.root).single.begin, const Duration(seconds: 2));
    });

    test('<animateTransform> participates in the same resolution', () {
      final document = _parse(
        '<rect x="0" y="0" width="2" height="2">'
        '<animate id="a" attributeName="opacity" from="0" to="1" dur="1s" begin="1s"/>'
        '<animateTransform attributeName="transform" type="rotate" from="0" to="90" '
        'dur="1s" begin="a.end"/>'
        '</rect>',
      );
      final transform = document.root.children.single.transformAnimations.single;

      expect(transform.begin, const Duration(seconds: 2));
    });

    test('the document duration accounts for resolved syncbase begins', () {
      final document = _parse(
        '<circle cx="1" cy="1" r="1">'
        '<animate id="a" attributeName="r" from="0" to="1" dur="1s"/>'
        '<animate attributeName="opacity" from="0" to="1" dur="2s" begin="a.end"/>'
        '</circle>',
      );

      expect(document.totalDuration, const Duration(seconds: 3));
    });
  });
}
