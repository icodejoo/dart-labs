// Parse-time coverage for the Rust-backed value parsers wired into the
// animation engine: CSS named colours (`fill="red"`), static `<g transform>`
// matrices, and `<animateTransform type="skewX"/"skewY">`.
//
// The colour/transform cases depend on the native library (`svgx.dll`/`.so`),
// which plain `flutter test` on the host VM has no build step to produce. They
// self-skip in that case — same convention as `test/rust_image_smoke_test.dart`
// — and print why, so a skipped run is never mistaken for a passing one.
//
// 动画引擎中接入的 Rust 取值解析器的解析阶段覆盖：CSS 具名颜色
// （`fill="red"`）、静态 `<g transform>` 矩阵，以及
// `<animateTransform type="skewX"/"skewY">`。
//
// 颜色/变换用例依赖原生库（`svgx.dll`/`.so`），而纯 `flutter test` 的 host VM
// 没有产出它的构建步骤，此时用例自行跳过（与
// `test/rust_image_smoke_test.dart` 同一约定）并打印原因，避免把"跳过"误当成
// "通过"。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart' show RustLib;
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';

// One shared init attempt for the whole file: flutter_rust_bridge throws on a
// second RustLib.init(), so re-initializing per test would look like "native
// unavailable" even when it loaded fine.
//
// 整份文件共用一次初始化尝试：flutter_rust_bridge 第二次 RustLib.init() 会抛错，
// 若每个用例都初始化一遍，即便原生库加载正常也会被误判成"不可用"。
Future<bool>? _initAttempt;

Future<bool> _nativeReady() {
  return _initAttempt ??= RustLib.init().then((_) => true).catchError((
    Object e,
  ) {
    // ignore: avoid_print
    print(
      'Skipping: native library not loadable in this test environment ($e)',
    );
    return false;
  });
}

void main() {
  group('named colours (Rust parse_color, resolved once at parse time)', () {
    test('fill="red" / stroke="blue" normalize to hex on the node', () async {
      if (!await _nativeReady()) return;

      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<circle cx="12" cy="12" r="10" fill="red" stroke="blue"/>'
        '</svg>',
      );
      final circle = document.root.children.single;

      expect(circle.attributes['fill'], '#FF0000FF');
      expect(circle.attributes['stroke'], '#0000FFFF');
    });

    test('a name no hand-rolled table would carry still resolves', () async {
      if (!await _nativeReady()) return;

      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<rect x="0" y="0" width="4" height="4" fill="cornflowerblue"/>'
        '</svg>',
      );

      expect(document.root.children.single.attributes['fill'], '#6495EDFF');
    });

    test('none / currentColor / hex / url() are left untouched', () async {
      if (!await _nativeReady()) return;

      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<path d="M0 0 L4 4" fill="none" stroke="currentColor"/>'
        '<path d="M0 0 L4 4" fill="#abc" stroke="url(#grad)"/>'
        '</svg>',
      );
      final first = document.root.children[0];
      final second = document.root.children[1];

      expect(first.attributes['fill'], 'none');
      expect(first.attributes['stroke'], 'currentColor');
      expect(second.attributes['fill'], '#abc');
      expect(second.attributes['stroke'], 'url(#grad)');
    });
  });

  group('static <g transform> (Rust parse_transform, resolved once)', () {
    test(
      'a transform list composes into one affine matrix on the node',
      () async {
        if (!await _nativeReady()) return;

        final document = parseAnimatedSvgDocument(
          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
          '<g transform="translate(10,20)"><circle cx="0" cy="0" r="1"/></g>'
          '</svg>',
        );
        final group = document.root.children.single;

        expect(group.transform, isNotNull);
        expect(group.transform, hasLength(6));
        expect(group.transform![4], closeTo(10, 1e-6));
        expect(group.transform![5], closeTo(20, 1e-6));
      },
    );

    test('rotate about a pivot keeps the pivot fixed', () async {
      if (!await _nativeReady()) return;

      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<g transform="rotate(90 12 12)"><circle cx="0" cy="0" r="1"/></g>'
        '</svg>',
      );
      final m = document.root.children.single.transform!;
      final x = m[0] * 12 + m[2] * 12 + m[4];
      final y = m[1] * 12 + m[3] * 12 + m[5];

      expect(x, closeTo(12, 1e-4));
      expect(y, closeTo(12, 1e-4));
    });

    test(
      'a malformed transform leaves the node untransformed, no throw',
      () async {
        if (!await _nativeReady()) return;

        final document = parseAnimatedSvgDocument(
          '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
          '<g transform="not-a-transform"><circle cx="0" cy="0" r="1"/></g>'
          '</svg>',
        );

        expect(document.root.children.single.transform, isNull);
      },
    );
  });

  group('<animateTransform type="skewX"/"skewY">', () {
    // Pure-Dart parse + sample path: no FFI involved, so this runs everywhere.
    // 纯 Dart 的解析 + 采样路径，不涉及 FFI，因此在任何环境都会真正运行。
    test('skewX parses and samples its angle', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<rect x="0" y="0" width="4" height="4">'
        '<animateTransform attributeName="transform" type="skewX" '
        'from="0" to="45" dur="1s" fill="freeze"/>'
        '</rect></svg>',
      );
      final rect = document.root.children.single;

      expect(rect.transformAnimations, hasLength(1));
      final anim = rect.transformAnimations.single;
      expect(anim.type, SmilTransformType.skewX);
      expect(
        anim.sample(const Duration(milliseconds: 500))![0],
        closeTo(22.5, 1e-6),
      );
      expect(anim.sample(const Duration(seconds: 2))![0], closeTo(45, 1e-6));
    });

    test('skewY parses with the same timing semantics', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<rect x="0" y="0" width="4" height="4">'
        '<animateTransform attributeName="transform" type="skewY" '
        'values="0;30" dur="2s"/>'
        '</rect></svg>',
      );
      final anim = document.root.children.single.transformAnimations.single;

      expect(anim.type, SmilTransformType.skewY);
      expect(anim.sample(const Duration(seconds: 1))![0], closeTo(15, 1e-6));
    });

    test('an unknown animateTransform type is skipped, not crashed on', () {
      final document = parseAnimatedSvgDocument(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<rect x="0" y="0" width="4" height="4">'
        '<animateTransform attributeName="transform" type="wobble" '
        'from="0" to="1" dur="1s"/>'
        '</rect></svg>',
      );

      expect(document.root.children.single.transformAnimations, isEmpty);
    });
  });

  test('SvgNode without a transform attribute has a null matrix', () {
    final document = parseAnimatedSvgDocument(
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
      '<g><circle cx="1" cy="1" r="1"/></g>'
      '</svg>',
    );
    final group = document.root.children.single;

    expect(group.kind, SvgNodeKind.group);
    expect(group.transform, isNull);
  });
}
