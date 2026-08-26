// Static `<linearGradient>`/`<radialGradient>` support: stop parsing,
// `href` inheritance, gradientUnits, spreadMethod, `fill="url(#id)"` wiring,
// and shader construction (including the degenerate-bbox guard).
//
// Animated gradients are explicitly out of scope — see svgx CLAUDE.md.
//
// 静态 `<linearGradient>`/`<radialGradient>` 支持：色标解析、`href` 继承、
// gradientUnits、spreadMethod、`fill="url(#id)"` 的接线，以及 shader 构建
// （含包围盒退化的保护）。
//
// 动画渐变明确不在范围内——见 svgx CLAUDE.md。

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_gradient.dart';
import 'package:svgx/src/animation/svg_style.dart';
import 'package:svgx/src/animation/svg_theme.dart';

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">$body</svg>',
);

void main() {
  group('gradient definitions', () {
    test('a linear gradient and its stops are parsed', () {
      final document = _parse(
        '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#FF0000"/>'
        '<stop offset="100%" stop-color="#0000FF" stop-opacity="0.5"/>'
        '</linearGradient></defs>'
        '<rect x="0" y="0" width="10" height="10" fill="url(#g)"/>',
      );
      final def = document.gradients['g']!;

      expect(def.radial, isFalse);
      expect(def.stops, hasLength(2));
      expect(def.stops.first.color, const Color(0xFFFF0000));
      expect(def.stops.last.offset, 1);
      expect(def.stops.last.color.a, closeTo(0.5, 0.01));
      expect(def.x2, 1);
      expect(def.y2, 1);
      expect(
        def.objectBoundingBox,
        isTrue,
        reason: 'SVG default gradientUnits',
      );
      expect(def.tileMode, TileMode.clamp);
    });

    test('a radial gradient keeps its centre, radius and focal point', () {
      final document = _parse(
        '<defs><radialGradient id="g" cx="0.3" cy="0.4" r="0.6" fx="0.1" fy="0.2" '
        'gradientUnits="userSpaceOnUse" spreadMethod="reflect">'
        '<stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#000000"/>'
        '</radialGradient></defs>',
      );
      final def = document.gradients['g']!;

      expect(def.radial, isTrue);
      expect(def.cx, 0.3);
      expect(def.r, 0.6);
      expect(def.fx, 0.1);
      expect(def.objectBoundingBox, isFalse);
      expect(def.tileMode, TileMode.mirror);
    });

    test('stops are inherited through an href chain', () {
      final document = _parse(
        '<defs>'
        '<linearGradient id="base"><stop offset="0" stop-color="#FF0000"/>'
        '<stop offset="1" stop-color="#00FF00"/></linearGradient>'
        '<linearGradient id="derived" href="#base" x1="0" y1="0" x2="0" y2="1"/>'
        '</defs>',
      );
      final def = document.gradients['derived']!;

      expect(def.stops, hasLength(2));
      expect(def.stops.first.color, const Color(0xFFFF0000));
      expect(def.y2, 1);
    });

    test('a cyclic href chain terminates instead of recursing forever', () {
      final document = _parse(
        '<defs>'
        '<linearGradient id="a" href="#b"/>'
        '<linearGradient id="b" href="#a"><stop offset="0" stop-color="#FF0000"/>'
        '<stop offset="1" stop-color="#00FF00"/></linearGradient>'
        '</defs>',
      );

      expect(document.gradients['b']!.stops, hasLength(2));
      // "a" inherits from "b", which points back at "a" — resolution stops
      // there rather than hanging; "a" ends up with b's stops.
      expect(document.gradients['a']?.stops, hasLength(2));
    });

    test('a gradient with no stops is dropped', () {
      final document = _parse('<defs><linearGradient id="empty"/></defs>');

      expect(document.gradients.containsKey('empty'), isFalse);
    });

    // Hex on purpose: a named stop-color goes through the same parse-time
    // normalization as fill/stroke, which needs the native library — covered
    // in transform_and_color_test.dart instead of here.
    //
    // 刻意用十六进制：具名 stop-color 走的是与 fill/stroke 相同的解析阶段
    // 归一化，需要原生库——该场景在 transform_and_color_test.dart 中覆盖。
    test('hex stop colours parse into exact ARGB', () {
      final document = _parse(
        '<defs><linearGradient id="g">'
        '<stop offset="0" stop-color="#123456"/><stop offset="1" stop-color="#654321"/>'
        '</linearGradient></defs>',
      );

      expect(
        document.gradients['g']!.stops.first.color,
        const Color(0xFF123456),
      );
    });
  });

  group('animated gradients', () {
    test(
      'an <animate> on a gradient attribute resamples geometry per frame',
      () {
        final document = _parse(
          '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="0">'
          '<animate attributeName="x2" from="0" to="1" dur="1s" fill="freeze"/>'
          '<stop offset="0" stop-color="#FF0000"/><stop offset="1" stop-color="#0000FF"/>'
          '</linearGradient></defs>',
        );
        final def = document.gradients['g']!;

        final atStart = resampleGradientAtTime(def, Duration.zero);
        expect(atStart.x2, 0);

        final atEnd = resampleGradientAtTime(def, const Duration(seconds: 2));
        expect(atEnd.x2, 1);
      },
    );

    test('an <animate attributeName="stop-color"> on a <stop> resamples its colour', () {
      final document = _parse(
        '<defs><linearGradient id="g">'
        '<stop offset="0" stop-color="#000000">'
        '<animate attributeName="stop-color" values="#000000;#FFFFFF" dur="1s" fill="freeze"/>'
        '</stop>'
        '<stop offset="1" stop-color="#0000FF"/>'
        '</linearGradient></defs>',
      );
      final def = document.gradients['g']!;

      final atStart = resampleGradientAtTime(def, Duration.zero);
      expect(atStart.stops.first.color, const Color(0xFF000000));

      final atEnd = resampleGradientAtTime(def, const Duration(seconds: 2));
      expect(atEnd.stops.first.color, const Color(0xFFFFFFFF));
    });

    test(
      'an <animate attributeName="stop-opacity"> resamples the stop\'s alpha',
      () {
        final document = _parse(
          '<defs><linearGradient id="g">'
          '<stop offset="0" stop-color="#FF0000">'
          '<animate attributeName="stop-opacity" from="0" to="1" dur="1s" fill="freeze"/>'
          '</stop>'
          '<stop offset="1" stop-color="#0000FF"/>'
          '</linearGradient></defs>',
        );
        final def = document.gradients['g']!;

        final atStart = resampleGradientAtTime(def, Duration.zero);
        expect(atStart.stops.first.color.a, closeTo(0, 0.01));

        final atEnd = resampleGradientAtTime(def, const Duration(seconds: 2));
        expect(atEnd.stops.first.color.a, closeTo(1, 0.01));
      },
    );

    test(
      'calcMode="discrete" on stop-color holds each keyframe, no blending',
      () {
        final document = _parse(
          '<defs><linearGradient id="g">'
          '<stop offset="0" stop-color="#000000">'
          '<animate attributeName="stop-color" values="#000000;#FFFFFF" calcMode="discrete" '
          'dur="1s" fill="freeze"/>'
          '</stop>'
          '<stop offset="1" stop-color="#0000FF"/>'
          '</linearGradient></defs>',
        );
        final def = document.gradients['g']!;

        final midway = resampleGradientAtTime(
          def,
          const Duration(milliseconds: 400),
        );
        expect(midway.stops.first.color, const Color(0xFF000000));
      },
    );

    test(
      'a gradient with no animations resamples to an unchanged def (fast path)',
      () {
        final document = _parse(
          '<defs><linearGradient id="g">'
          '<stop offset="0" stop-color="#FF0000"/><stop offset="1" stop-color="#0000FF"/>'
          '</linearGradient></defs>',
        );
        final def = document.gradients['g']!;

        expect(
          identical(
            resampleGradientAtTime(def, const Duration(seconds: 1)),
            def,
          ),
          isTrue,
        );
      },
    );

    test(
      'a def built without animatedNode (e.g. directly in a test) is untouched',
      () {
        const def = SvgGradientDef(
          radial: false,
          objectBoundingBox: true,
          tileMode: TileMode.clamp,
          stops: [
            SvgGradientStop(0, Color(0xFFFF0000)),
            SvgGradientStop(1, Color(0xFF0000FF)),
          ],
        );

        expect(
          identical(
            resampleGradientAtTime(def, const Duration(seconds: 1)),
            def,
          ),
          isTrue,
        );
      },
    );
  });

  group('paint wiring', () {
    test(
      'fill="url(#id)" resolves to a gradient id on the style, not a colour',
      () {
        final style = ResolvedStyle.initial.inherit({
          'fill': 'url(#g)',
          'stroke': 'url("#s")',
        }, const SvgTheme());

        expect(style.fillGradientId, 'g');
        expect(style.strokeGradientId, 's');
        expect(style.fill, isNull);
      },
    );

    test('a plain colour clears any inherited gradient reference', () {
      final withGradient = ResolvedStyle.initial.inherit({
        'fill': 'url(#g)',
      }, const SvgTheme());
      final overridden = withGradient.inherit({
        'fill': '#00FF00',
      }, const SvgTheme());

      expect(overridden.fillGradientId, isNull);
      expect(overridden.fill, const Color(0xFF00FF00));
    });
  });

  group('buildGradientShader', () {
    const def = SvgGradientDef(
      radial: false,
      objectBoundingBox: true,
      tileMode: TileMode.clamp,
      stops: [
        SvgGradientStop(0, Color(0xFFFF0000)),
        SvgGradientStop(1, Color(0xFF0000FF)),
      ],
    );

    test('builds a shader over a real bounding box', () {
      expect(
        buildGradientShader(def, const Rect.fromLTWH(0, 0, 10, 10), 1),
        isNotNull,
      );
    });

    test('returns null for a degenerate bounding box', () {
      expect(
        buildGradientShader(def, const Rect.fromLTWH(0, 0, 0, 10), 1),
        isNull,
      );
    });

    test('tolerates duplicate/non-increasing stop offsets', () {
      const hardEdge = SvgGradientDef(
        radial: false,
        objectBoundingBox: true,
        tileMode: TileMode.clamp,
        stops: [
          SvgGradientStop(0, Color(0xFFFF0000)),
          SvgGradientStop(0.5, Color(0xFFFF0000)),
          SvgGradientStop(0.5, Color(0xFF0000FF)),
          SvgGradientStop(1, Color(0xFF0000FF)),
        ],
      );

      expect(
        buildGradientShader(hardEdge, const Rect.fromLTWH(0, 0, 10, 10), 1),
        isNotNull,
      );
    });

    test('a single-stop gradient still builds', () {
      const single = SvgGradientDef(
        radial: true,
        objectBoundingBox: false,
        tileMode: TileMode.clamp,
        stops: [SvgGradientStop(0, Color(0xFFFF0000))],
      );

      expect(
        buildGradientShader(single, const Rect.fromLTWH(0, 0, 10, 10), 1),
        isNotNull,
      );
    });
  });
}
