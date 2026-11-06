import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:xvg/xvg.dart' show RustLib;
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animation_detector.dart';
import 'package:xvg/src/animation/css_animation_values.dart';
import 'package:xvg/src/animation/css_cascade.dart';
import 'package:xvg/src/animation/css_keyframes_compiler.dart';
import 'package:xvg/src/animation/css_stylesheet.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_dom.dart';
import 'package:xvg/src/animation/svg_gradient.dart';
import 'package:xvg/src/animation/svg_path_data.dart';
import 'package:xvg/src/animation/svg_style.dart';
import 'package:xvg/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

SvgDocument doc(String body) => parseAnimatedSvgDocument(
  '<svg xmlns:xlink="http://www.w3.org/1999/xlink">$body</svg>',
);
CssCompileResult compile(
  String frames, {
  String animation = 'a 1s linear',
  Map<String, String> properties = const {},
  bool hooks = false,
}) => compileCssAnimations(
  animations: parseCssAnimations(parseCssDeclarations('animation:$animation')),
  keyframes: parseCssStylesheet(frames).keyframes,
  cssProperties: properties,
  hooks: hooks ? cssCompileHooks : const CssCompileHooks(),
);

class Element implements CssElement {
  Element(this.parent);
  @override
  final Element? parent;
  @override
  String get localName => 'g';
  static int reads = 0;
  @override
  String? attribute(String name) {
    reads++;
    return null;
  }
}

int count(SvgNode n) =>
    1 + n.children.fold(0, (sum, child) => sum + count(child));
void main() {
  var nativeReady = false;
  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (_) {}
  });
  test('05 color fallback hook works without native library', () {
    final r = compileCssAnimations(
      animations: parseCssAnimations(parseCssDeclarations('animation:a 1s')),
      keyframes: parseCssStylesheet(
        '@keyframes a{from{fill:red}to{fill:#0000ff}}',
      ).keyframes,
      hooks: CssCompileHooks(
        resolveColorToHex: (s) => s == 'red' ? '#ff0000ff' : null,
      ),
    );
    expect(r.color.single.values, [0xffff0000, 0xff0000ff]);
  });
  test('07 pixel origin rotates geometry around authored point', () async {
    final d = parsePixelDoc(
      '<style>rect{animation:a 1s linear forwards;transform-origin:50px 50px}@keyframes a{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}</style><rect x="60" y="40" width="10" height="10" fill="#ff0000"/>',
    );
    final pixels = await renderAt(d, const Duration(seconds: 1));
    expect(redAt(pixels, 55, 65), 255);
    expect(alphaAt(pixels, 65, 45), 0);
  });
  test('07 pixel origin wraps the transform list', () {
    final r = compile(
      '@keyframes a{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}',
      properties: {'transform-origin': '10px 20px'},
    );
    expect(r.skipped, isEmpty);
    expect(r.transforms, hasLength(3));
    expect(r.transforms.first.values.first, [10, 20, 0]);
    expect(r.transforms.last.values.first, [-10, -20, 0]);
  });
  for (final bad in [
    '01:60:00',
    '01:02:60',
    '1:2',
    'NaN',
    'Infinity',
    'abc',
    '0;a.end',
  ]) {
    test(
      '13 invalid clock keeps zero fallback $bad',
      () => expect(parseSmilDuration(bad), Duration.zero),
    );
  }

  test('01 duplicate IDs choose first for use gradient clip mask', () {
    final d = doc(
      '<defs><rect id="x" width="3"/><rect id="x" width="9"/><linearGradient id="g"><stop stop-color="#ff0000"/></linearGradient><linearGradient id="g"><stop stop-color="#0000ff"/></linearGradient><clipPath id="c"><rect width="3"/></clipPath><clipPath id="c"><rect width="9"/></clipPath><mask id="m"><rect width="3"/></mask><mask id="m"><rect width="9"/></mask></defs><use href="#x"/>',
    );
    expect(d.root.children.single.children.single.attributes['width'], '3');
    expect(d.gradients['g']!.stops.single.color, const Color(0xffff0000));
    expect(d.clipPaths['c']!.children.single.attributes['width'], '3');
    expect(d.masks['m']!.children.single.attributes['width'], '3');
  });
  test('01 xlink gradient full inheritance chain', () {
    final g = doc(
      '<defs><linearGradient id="a" x2=".25"><stop stop-color="#ff0000"/></linearGradient><linearGradient id="b" xlink:href="#a"/><linearGradient id="c" xlink:href="#b"/></defs>',
    ).gradients['c']!;
    expect(g.x2, .25);
    expect(g.stops, hasLength(1));
  });
  test('02 paint keywords case insensitive and theme stays dynamic', () {
    final attrs = doc('<rect fill=" CuRrEnTcOlOr " stroke="NONE"/>')
        .root
        .children
        .single
        .attributes;
    for (final color in [const Color(0xffff0000), const Color(0xff0000ff)]) {
      final s = ResolvedStyle.initial.inherit(
        attrs,
        XvgTheme(currentColor: color),
      );
      expect(s.fill, color);
      expect(s.stroke, isNull);
    }
  });
  for (final raw in ['5px 3px', '5PX,3px']) {
    test(
      '03 dash tokens $raw',
      () => expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': raw,
        }, const XvgTheme()).strokeDasharray,
        [5, 3],
      ),
    );
  }
  for (final raw in ['5 -3', '5% 3', '5px bad', 'NaN 2']) {
    test(
      '03 invalid dash is none $raw',
      () => expect(
        ResolvedStyle.initial.inherit({
          'stroke-dasharray': raw,
        }, const XvgTheme()).strokeDasharray,
        isEmpty,
      ),
    );
  }
  test('03 px presentation attributes', () {
    final s = ResolvedStyle.initial.inherit({
      'stroke-width': ' 2px ',
      'stroke-dashoffset': '5px',
    }, const XvgTheme());
    expect(s.strokeWidth, 2);
    expect(s.strokeDashoffset, 5);
  });
  test('04 pathological dash falls back to original solid path', () {
    final p = ui.Path()..lineTo(10, 0);
    expect(identical(dashPath(p, dashArray: [.001, .001]), p), isTrue);
    expect(identical(dashPath(p, dashArray: [0, 0]), p), isTrue);
  });
  for (final color in ['red', 'hsl(120,100%,50%)']) {
    test('05 CSS color hook resolves $color', () {
      if (!nativeReady) {
        markTestSkipped('Native color parser unavailable');
        return;
      }
      final r = compile(
        '@keyframes a{from{fill:$color}to{fill:#0000ff}}',
        hooks: true,
      );
      expect(r.color, hasLength(1));
      expect(r.skipped, isEmpty);
      expect(r.color.single.values, hasLength(2));
    });
  }
  test('05 currentColor gives explicit diagnostic', () {
    final r = compile(
      '@keyframes a{from{fill:currentColor}to{fill:#0000ff}}',
      hooks: true,
    );
    expect(r.color, isEmpty);
    expect(r.skipped.single.reason.name, 'currentColorRuntimeUnsupported');
  });
  for (final mode in ['both', 'backwards']) {
    test('06 delayed $mode reports approximation', () {
      final r = compile(
        '@keyframes a{from{opacity:0}to{opacity:1}}',
        animation: 'a 1s 2s $mode',
      );
      expect(r.numeric, hasLength(1));
      expect(r.approximations.single.reason.name, 'backwardsFillUnsupported');
    });
  }
  test('06 paused later transform suppresses earlier with real frames', () {
    final r = compile(
      '@keyframes a{from{transform:translate(0px)}to{transform:translate(10px)}} @keyframes b{from{transform:scale(1)}to{transform:scale(2)}}',
      animation: 'a 1s,b 1s paused',
    );
    expect(r.transforms, isEmpty);
    expect(r.skipped.map((s) => s.reason), [
      CssCompileSkipReason.overriddenByLaterAnimation,
      CssCompileSkipReason.paused,
    ]);
  });
  for (final property in ['transform-origin', 'transform-box']) {
    test('07 explicit $property diagnosed', () {
      final r = compile(
        '@keyframes a{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}',
        properties: {
          property: property == 'transform-origin' ? '50% 50%' : 'fill-box',
        },
      );
      expect(r.skipped.any((s) => s.property == 'transform'), isTrue);
    });
  }
  test('07 SVG presentation origin also affects CSS transforms', () {
    final n = doc(
      '<style>rect{animation:a 1s}@keyframes a{from{transform:rotate(0deg)}to{transform:rotate(90deg)}}</style><rect transform-origin="10px 20px"/>',
    ).root.children.single;
    expect(n.transformAnimations, hasLength(3));
  });
  test('07 animated origin cannot silently use the default pivot', () {
    final r = compile(
      '@keyframes a{from{transform-origin:50% 50%;transform:rotate(0deg)}to{transform:rotate(90deg)}}',
    );
    expect(r.transforms, isEmpty);
    expect(
      r.skipped.any((s) => s.reason.name == 'transformOriginUnsupported'),
      isTrue,
    );
  });
  for (final value in [
    'var(--x)',
    'calc(1 + 2)',
    'env(x)',
    'inherit',
    'unset',
  ]) {
    test('08 unsupported winner uses declared degradation semantics $value', () {
      final sheet = parseCssStylesheet(
        'g{fill:#ff0000;transform:rotate(1deg)}g{fill:$value;transform:$value}',
      );
      final c = computeCssStyle(CssRuleIndex(sheet), Element(null), []);
      expect(
        c.attributes['fill'],
        value.startsWith('calc(') ? '#ff0000' : isNull,
      );
      expect(
        c.properties['transform'],
        value.startsWith('calc(') ? 'rotate(1deg)' : isNull,
      );
    });
  }
  for (final malformed in ['"bad\n', 'rgb(1,2,3']) {
    test('08 malformed value bounded $malformed', () {
      final sheet = parseCssStylesheet('g{fill:$malformed;} rect{opacity:.5}');
      expect(
        sheet.rules.any(
          (r) => r.selectors.single.compounds.single.tag == 'rect',
        ),
        isTrue,
      );
    });
  }
  test('08 descendant matching bounded work', () {
    Element? e;
    for (var i = 0; i < 24; i++) {
      e = Element(e);
    }
    final s = parseCssStylesheet('#missing g g g g g g g g{opacity:1}')
        .rules
        .single
        .selectors
        .single;
    Element.reads = 0;
    expect(cssSelectorMatches(s, e!), isFalse);
    expect(Element.reads, lessThan(1000));
  });
  for (final r in [0, -1]) {
    test('09 degenerate radial uses final color $r', () async {
      final def = SvgGradientDef(
        radial: true,
        r: r.toDouble(),
        stops: const [
          SvgGradientStop(0, Color(0xffff0000)),
          SvgGradientStop(1, Color(0xff0000ff)),
        ],
        objectBoundingBox: false,
        tileMode: TileMode.clamp,
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 10, 10),
        Paint()
          ..shader = buildGradientShader(
            def,
            const Rect.fromLTWH(0, 0, 10, 10),
            1,
          ),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(10, 10);
      final bytes = (await image.toByteData())!;
      expect(bytes.getUint8(0), 0);
      expect(bytes.getUint8(2), 255);
      image.dispose();
      picture.dispose();
    });
  }
  for (final body in [
    '<feOffset/><feGaussianBlur stdDeviation="2"/><feMerge/>',
    '<feGaussianBlur in="other" stdDeviation="2"/>',
    '<feGaussianBlur stdDeviation="2"/><feGaussianBlur stdDeviation="3"/>',
  ]) {
    test(
      '10 unsupported filter chain $body',
      () => expect(
        doc(
          '<defs><filter id="f">$body</filter></defs><rect filter="url(#f)"/>',
        ).root.children.single.blurSigma,
        isNull,
      ),
    );
  }
  test(
    '10 single source graphic blur accepted',
    () => expect(
      doc(
        '<defs><filter id="f"><feGaussianBlur in="SourceGraphic" stdDeviation="2"/></filter></defs><rect filter="url(#f)"/>',
      ).root.children.single.blurSigma,
      2,
    ),
  );
  for (final flood in [
    'flood-opacity="0"',
    'flood-color="#ff000000"',
    'flood-color="transparent"',
  ]) {
    for (final input in ['', 'in="blend"']) {
      test('10 Figma body blur $flood $input', () {
        final d = doc(
          '<defs><filter id="f"><feFlood $flood result="bg"/><feBlend mode="normal" in="SourceGraphic" in2="bg" result="blend"/><feGaussianBlur $input stdDeviation="3"/></filter></defs><rect filter="url(#f)"/>',
        );
        expect(d.root.children.single.blurSigma, 3);
      });
    }
  }
  for (final prefix in [
    '<feFlood flood-opacity="1"/><feBlend mode="normal" in="SourceGraphic"/>',
    '<feFlood flood-opacity="0"/><feBlend mode="multiply" in="SourceGraphic"/>',
    '<feFlood flood-opacity="0"/><feBlend mode="normal" in="SourceAlpha"/>',
    '<feOffset/><feBlend mode="normal" in="SourceGraphic"/>',
  ]) {
    test('10 shadow prefix remains rejected $prefix', () {
      expect(
        doc(
          '<defs><filter id="f">$prefix<feGaussianBlur stdDeviation="3"/></filter></defs><rect filter="url(#f)"/>',
        ).root.children.single.blurSigma,
        isNull,
      );
    });
  }
  test('11 stops and animated nodes retain clamped document order', () {
    final g = doc(
      '<linearGradient id="g"><stop offset=".8" stop-color="#ff0000"/><stop stop-color="invalid"/><stop offset=".2" stop-color="#0000ff"><animate attributeName="stop-opacity" values="0;1" dur="1s"/></stop></linearGradient>',
    ).gradients['g']!;
    expect(g.stops.map((s) => s.offset), [.8, .8]);
    expect(g.stops.first.color, const Color(0xffff0000));
    expect(g.stopNodes, hasLength(2));
    expect(g.stopNodes.last.animations, hasLength(1));
  });
  test('12 use expansion has a global budget and finishes within two seconds', () {
    final defs = StringBuffer('<defs><g id="g0"><rect/></g>');
    for (var i = 1; i <= 10; i++) {
      defs.write(
        '<g id="g$i">${List.filled(10, '<use href="#g${i - 1}"/>').join()}</g>',
      );
    }
    defs.write('</defs><use href="#g10"/>');
    final watch = Stopwatch()..start();
    final d = doc(defs.toString());
    watch.stop();
    expect(count(d.root), lessThanOrEqualTo(100001));
    expect(d.root.children, isEmpty);
    expect(d.useExpansionTruncated, isTrue);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });
  test('12 use instances expand wholly and budget stays available for smaller instances', () {
    final d = doc(
      '<defs><symbol id="large">${List.filled(400, '<rect/>').join()}</symbol><rect id="small"/></defs>${List.filled(249, '<use href="#large"/>').join()}<use href="#small"/><circle/>',
    );
    // 248 * (wrapper + symbol + 400 rects) = 99,696; the 249th is skipped wholly.
    expect(d.root.children, hasLength(250));
    for (final instance in d.root.children.take(248)) {
      expect(instance.children.single.children, hasLength(400));
    }
    expect(d.root.children[248].children.single.attributes['id'], 'small');
    expect(d.root.children.last.kind, SvgNodeKind.circle);
    expect(count(d.root), 99700);
    expect(d.useExpansionTruncated, isTrue);
    expect(
      doc('<defs><rect id="r"/></defs><use href="#r"/>').useExpansionTruncated,
      isFalse,
    );
  });
  for (final pair in <String, int>{
    '01:02:03.125': 3723125,
    '02:03': 123000,
    '2h': 7200000,
    '2min': 120000,
    '2s': 2000,
    '2ms': 2,
    '2': 2000,
  }.entries) {
    test(
      '13 SMIL clock ${pair.key}',
      () => expect(
        parseSmilDuration(pair.key),
        Duration(milliseconds: pair.value),
      ),
    );
  }
  test('14 oversized syncbase begin remains disabled after resolution', () {
    final a = doc(
      '<rect><animate id="a" attributeName="x" values="0;1" dur="1s"/><animate attributeName="y" values="0;1" dur="1s" begin="a.end+20000000s"/></rect>',
    ).root.children.single.animations.last;
    expect(a.begin, kSmilNeverBegins);
  });
  test('14 oversized begin never starts and duration saturates', () {
    expect(parseSmilBeginSpec('20000000s').offset, kSmilNeverBegins);
    expect(parseSmilDuration('20000000s'), const Duration(seconds: 10000000));
  });
  for (final tag in [
    'set',
    'animate',
    'animateTransform',
    'animateMotion',
    'svg:set',
    'svg:animate',
  ]) {
    test(
      '15 self closing namespaced detection $tag',
      () =>
          expect(AnimationDetector.hasAnimations('<svg><$tag/></svg>'), isTrue),
    );
  }
}
