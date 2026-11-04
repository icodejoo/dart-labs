import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_style.dart';
import 'package:svgx/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

const _rect = '<rect width="60" height="100"/>';
const _overlap = '$_rect<rect x="40" width="60" height="100"/>';
const _gradient =
    '<defs><linearGradient id="gradient">'
    '<stop stop-color="#3487c4" stop-opacity=".6"/>'
    '<stop offset="1" stop-color="#f03"/></linearGradient></defs>';
Matcher _alpha(int value) => inInclusiveRange(value - 2, value + 2);

void main() {
  test('optimized opacity is pixel equivalent to forced isolation', () async {
    for (final opacity in ['.25', '.5', '.73']) {
      for (final leaf in [
        '<rect x="20.3" y="20.3" width="60" height="60" opacity=".6"/>',
        '<rect x="20.3" y="20.3" width="60" height="60" fill="#5a87c480" '
            'fill-opacity=".7" opacity=".6"/>',
        '<rect x="20.3" y="20.3" width="60" height="60" fill="url(#gradient)" '
            'fill-opacity=".7" opacity=".6"><animateTransform '
            'attributeName="transform" type="rotate" from="10 50 50" '
            'to="10 50 50" dur="1s"/></rect>',
        '<circle cx="50" cy="50" r="25" fill="none" stroke="#000" '
            'stroke-width="5" opacity=".6"/>',
      ]) {
        final actual = await renderAt(
          parsePixelDoc('$_gradient<g opacity="$opacity">$leaf</g>'),
          Duration.zero,
        );
        final reference = await renderAt(
          parsePixelDoc(
            '$_gradient<g opacity="$opacity">$leaf<rect width="0" height="0"/></g>',
          ),
          Duration.zero,
        );
        for (var i = 0; i < actual.lengthInBytes; i++) {
          expect(
            (actual.getUint8(i) - reference.getUint8(i)).abs(),
            lessThanOrEqualTo(1),
            reason: 'wrapper $opacity byte $i',
          );
        }
      }
      final actual = await renderAt(
        parsePixelDoc('<g filter="blur(3px)" opacity="$opacity">$_overlap</g>'),
        Duration.zero,
      );
      final reference = await renderAt(
        parsePixelDoc(
          '<g opacity="$opacity"><g filter="blur(3px)">$_overlap</g>'
          '<rect width="0" height="0"/></g>',
        ),
        Duration.zero,
      );
      for (var i = 0; i < actual.lengthInBytes; i++) {
        expect(
          (actual.getUint8(i) - reference.getUint8(i)).abs(),
          lessThanOrEqualTo(1),
          reason: 'blur $opacity byte $i',
        );
      }
    }
  });

  test(
    'blur opacity folding with transformed fill/stroke and clip is equivalent',
    () async {
      for (final clip in ['', 'clip-path="url(#c)"']) {
        const shape =
            '<rect x="20.3" y="20.3" width="60" height="60" '
            'fill="#3487c4" fill-opacity=".7" stroke="#f00" stroke-width="5"/>';
        const transform =
            '<animateTransform attributeName="transform" '
            'type="scale" from=".9" to=".9" dur="1s"/>';
        const defs =
            '<defs><clipPath id="c"><circle cx="50" cy="50" r="30.3"/>'
            '</clipPath></defs>';
        final actual = await renderAt(
          parsePixelDoc(
            '$defs<g opacity=".63" '
            'filter="blur(3px)" $clip>$transform$shape</g>',
          ),
          Duration.zero,
        );
        final reference = await renderAt(
          parsePixelDoc(
            '$defs<g opacity=".63">'
            '<g filter="blur(3px)" $clip>$transform$shape</g>'
            '<rect width="0" height="0"/></g>',
          ),
          Duration.zero,
        );
        for (var i = 0; i < actual.lengthInBytes; i++) {
          expect(
            (actual.getUint8(i) - reference.getUint8(i)).abs(),
            lessThanOrEqualTo(1),
            reason: 'clip=$clip byte=$i',
          );
        }
      }
    },
  );

  test('use leaf multiplies its own opacity with wrapper opacity', () async {
    final pixels = await renderAt(
      parsePixelDoc(
        '<defs><rect id="s" width="100" height="100" opacity=".5"/></defs>'
        '<use href="#s" opacity=".5"/>',
      ),
      Duration.zero,
    );
    expect(alphaAt(pixels, 50, 50), _alpha(64));
  });

  test('knownLimitation luminance mask ignores leaf and group alpha', () async {
    for (final content in [
      '<rect width="100" height="100" fill="#fff" opacity=".5"/>',
      '<g opacity=".5"><rect width="100" height="100" fill="#fff"/></g>',
      '<rect width="100" height="100" fill="#fff" fill-opacity=".5"/>',
    ]) {
      final pixels = await renderAt(
        parsePixelDoc(
          '<defs><mask id="m">$content</mask></defs>'
          '<rect width="100" height="100" mask="url(#m)"/>',
        ),
        Duration.zero,
      );
      expect(
        alphaAt(pixels, 50, 50),
        255,
        reason: 'knownLimitation: browser should be 128; update this test when fixed',
      );
    }
  });

  test('own scale scales blur sigma in the test renderer', () async {
    final scaled = await renderAt(
      parsePixelDoc(
        '<rect x="15" y="15" width="20" height="20" filter="blur(2px)">'
        '<animateTransform attributeName="transform" type="scale" '
        'from="2" to="2" dur="1s"/></rect>',
      ),
      Duration.zero,
    );
    final reference = await renderAt(
      parsePixelDoc(
        '<rect x="30" y="30" width="40" height="40" filter="blur(4px)"/>',
      ),
      Duration.zero,
    );
    expect(scaled.buffer.asUint8List(), reference.buffer.asUint8List());
  });

  test('Skia probe: clip outside blur trims the filtered result', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.clipRect(const Rect.fromLTWH(40, 0, 20, 100));
    canvas.saveLayer(
      null,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
    );
    canvas.drawRect(const Rect.fromLTWH(20, 20, 60, 60), Paint());
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 100);
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    expect(alphaAt(pixels, 39, 50), 0);
    expect(
      alphaAt(pixels, 40, 50),
      greaterThan(250),
      reason: 'pre-filter clipping would blur this edge to about half alpha',
    );
    image.dispose();
    picture.dispose();
  });

  test(
    'zero opacity skips all drawing and layers, then resumes next frame',
    () {
      for (final body in [
        '<rect width="100" height="100" stroke="#000" opacity="0"/>',
        '<g opacity="0">$_overlap</g>',
        '<rect width="100" height="100"><animate attributeName="opacity" '
            'values="0;1" dur="1s" fill="freeze"/></rect>',
        '<path d="M10 10H90V90Z" fill="#000" stroke="#000">'
            '<set attributeName="opacity" to="0"/></path>',
        '<g><animate attributeName="opacity" values="0;1" dur="1s" '
            'fill="freeze"/>$_overlap</g>',
      ]) {
        final doc = parsePixelDoc(body);
        final clock = ValueNotifier(Duration.zero);
        final painter = AnimatedSvgPainter(
          root: doc.root,
          intrinsicSize: const Size(100, 100),
          clock: clock,
          theme: const SvgxTheme(),
          fit: BoxFit.fill,
          alignment: Alignment.center,
        );
        final canvas = _CountingCanvas();
        painter.paint(canvas, const Size(100, 100));
        expect(
          canvas.calls.where((s) => s.toString().contains('draw')),
          isEmpty,
          reason: body,
        );
        expect(
          canvas.calls.where((s) => s == #saveLayer),
          isEmpty,
          reason: body,
        );
        expect(
          canvas.calls.where((s) => s == #save).length,
          canvas.calls.where((s) => s == #restore).length,
        );
        if (body.contains('<animate ')) {
          clock.value = const Duration(seconds: 2);
          final resumed = _CountingCanvas();
          painter.paint(resumed, const Size(100, 100));
          expect(
            resumed.calls.where((s) => s == #drawPath).length,
            body.startsWith('<rect') ? 1 : 2,
          );
        }
        clock.dispose();
      }
    },
  );

  test('opacity 0 group hides child <set> opacity=1', () async {
    // 组 opacity=0 时整棵子树在组一级就被跳过，子元素自身 opacity 变成 1 也不可见。
    int maxAlpha(ByteData pixels) {
      var max = 0;
      for (var y = 0; y < kPixelSize; y++) {
        for (var x = 0; x < kPixelSize; x++) {
          final a = alphaAt(pixels, x, y);
          if (a > max) max = a;
        }
      }
      return max;
    }

    const rect =
        '<rect width="100" height="100">'
        '<set attributeName="opacity" to="1" begin="0s" fill="freeze"/>'
        '</rect>';
    // 对照：不包组时同一个 <set> 确实把元素画出来，排除 <set> 未生效的假阳性。
    final control = parsePixelDoc(rect);
    final lit = await renderAt(control, const Duration(milliseconds: 500));
    expect(alphaAt(lit, 50, 50), 255);
    final doc = parsePixelDoc('<g opacity="0">$rect</g>');
    for (final ms in [0, 500]) {
      final pixels = await renderAt(doc, Duration(milliseconds: ms));
      expect(maxAlpha(pixels), 0, reason: 'at ${ms}ms');
    }
  });

  test('blur opacity shares one layer when there is no mask', () {
    final doc = parsePixelDoc(
      '<g filter="blur(3px)" opacity=".5">$_overlap</g>',
    );
    final clock = ValueNotifier(Duration.zero);
    final canvas = _CountingCanvas();
    AnimatedSvgPainter(
      root: doc.root,
      intrinsicSize: const Size(100, 100),
      clock: clock,
      theme: const SvgxTheme(),
      fit: BoxFit.fill,
      alignment: Alignment.center,
    ).paint(canvas, const Size(100, 100));
    expect(canvas.calls.where((s) => s == #saveLayer).length, 1);
    clock.dispose();
  });

  test('single paint wrapper pushes opacity into the leaf', () {
    final doc = parsePixelDoc('<g opacity=".5">$_rect</g>');
    final clock = ValueNotifier(Duration.zero);
    final canvas = _CountingCanvas();
    AnimatedSvgPainter(
      root: doc.root,
      intrinsicSize: const Size(100, 100),
      clock: clock,
      theme: const SvgxTheme(),
      fit: BoxFit.fill,
      alignment: Alignment.center,
    ).paint(canvas, const Size(100, 100));
    expect(canvas.calls.where((s) => s == #saveLayer), isEmpty);
    clock.dispose();
  });

  test('opacity is local; fill/stroke opacity still inherit', () {
    final parent = ResolvedStyle.initial.inherit({
      'opacity': '.5',
      'fill-opacity': '.4',
      'stroke-opacity': '.3',
    }, const SvgxTheme());
    final child = parent.inherit({}, const SvgxTheme());
    expect(child.opacity, 1);
    expect(child.fillOpacity, .4);
    expect(child.strokeOpacity, .3);
  });

  test(
    'nested groups multiply to .25, including explicit child opacity=1',
    () async {
      final pixels = await renderAt(
        parsePixelDoc(
          '<g opacity=".5"><g opacity=".5">'
          '<rect width="100" height="100" opacity="1"/></g></g>',
        ),
        Duration.zero,
      );
      expect(alphaAt(pixels, 50, 50), _alpha(64));
    },
  );

  test('nested groups multiply to .25 with an implicit leaf opacity', () async {
    final pixels = await renderAt(
      parsePixelDoc('<g opacity=".5"><g opacity=".5">$_rect</g></g>'),
      Duration.zero,
    );
    expect(alphaAt(pixels, 20, 50), _alpha(64));
  });

  for (final transformed in [false, true]) {
    test('filter then clip then mask then opacity (transform=$transformed)', () async {
      final pixels = await renderAt(
        parsePixelDoc(
          '<defs><filter id="b"><feGaussianBlur stdDeviation="3"/></filter>'
          '<clipPath id="c"><rect x="40" width="20" height="100"/></clipPath>'
          '<mask id="m" mask-type="alpha"><rect width="100" height="100" '
          'fill="#fff" opacity=".5"/></mask></defs>'
          '<g opacity=".5" filter="url(#b)" clip-path="url(#c)" '
          'mask="url(#m)">'
          '${transformed ? '<animateTransform attributeName="transform" type="translate" from="10 0" to="10 0" dur="1s"/>' : ''}'
          '<rect x="20" y="20" width="60" height="60"/>'
          '<rect x="20" y="20" width="60" height="60"/></g>',
        ),
        Duration.zero,
      );
      final dx = transformed ? 10 : 0;
      expect(alphaAt(pixels, 39 + dx, 50), 0);
      expect(
        alphaAt(pixels, 41 + dx, 50),
        _alpha(64),
        reason: 'clip must trim the already blurred result',
      );
      expect(alphaAt(pixels, 50 + dx, 50), _alpha(64));
      expect(alphaAt(pixels, 61 + dx, 50), 0);
    });
  }

  test('leaf opacity animation retains the alpha fast path', () async {
    final doc = parsePixelDoc(
      '<rect width="100" height="100" fill-opacity=".5">'
      '<animate attributeName="opacity" values="0;1" dur="1s" '
      'fill="freeze"/></rect>',
    );
    for (final (ms, alpha) in [(0, 0), (500, 64), (1500, 128)]) {
      expect(
        alphaAt(await renderAt(doc, Duration(milliseconds: ms)), 50, 50),
        _alpha(alpha),
      );
    }
  });

  test('group opacity also composites text and decoded images', () async {
    final text = await renderAt(
      parsePixelDoc(
        '<g opacity=".5"><text x="20" y="70" font-size="60" '
        'opacity=".5">I</text></g>',
      ),
      Duration.zero,
    );
    var maxAlpha = 0;
    for (var y = 0; y < kPixelSize; y++) {
      for (var x = 0; x < kPixelSize; x++) {
        final a = alphaAt(text, x, y);
        if (a > maxAlpha) maxAlpha = a;
      }
    }
    expect(maxAlpha, _alpha(64));
    final doc = parsePixelDoc(
      '<g opacity=".5"><image width="100" height="100" opacity=".5" '
      'href="data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="/></g>',
    );
    await resolveImageNodes(doc);
    // The PNG itself has alpha 127: 127 * .5 * .5 = 31.75.
    expect(alphaAt(await renderAt(doc, Duration.zero), 50, 50), _alpha(32));
    doc.root.children.single.children.single.resolvedImage!.dispose();
  });

  test('animated opacity inside a mask multiplies group opacity', () async {
    final doc = parsePixelDoc(
      '<defs><mask id="m" mask-type="alpha"><g>'
      '<animate attributeName="opacity" values="0;1" dur="1s" fill="freeze"/>'
      '$_overlap</g></mask></defs><g opacity=".5" mask="url(#m)">'
      '$_overlap</g>',
    );
    for (final (ms, alpha) in [(0, 0), (500, 64), (1500, 128)]) {
      final pixels = await renderAt(doc, Duration(milliseconds: ms));
      expect(alphaAt(pixels, 20, 50), _alpha(alpha));
      expect(alphaAt(pixels, 50, 50), _alpha(alpha));
    }
  });

  for (final wrapper in ['g', 'svg']) {
    test('$wrapper opacity composites overlapping children once', () async {
      final pixels = await renderAt(
        wrapper == 'svg'
            ? parseAnimatedSvgDocument(
                '<svg width="100" height="100" opacity=".5">$_overlap</svg>',
              )
            : parsePixelDoc('<g opacity=".5">$_overlap</g>'),
        Duration.zero,
      );
      expect(alphaAt(pixels, 20, 50), _alpha(128));
      expect(alphaAt(pixels, 50, 50), alphaAt(pixels, 20, 50));
    });
  }

  test(
    'use wrapper and referenced group each apply their own opacity',
    () async {
      final pixels = await renderAt(
        parsePixelDoc(
          '<defs><g id="s" opacity=".5">$_overlap</g></defs>'
          '<use href="#s" opacity=".5"/>',
        ),
        Duration.zero,
      );
      expect(alphaAt(pixels, 20, 50), _alpha(64));
      expect(alphaAt(pixels, 50, 50), _alpha(64));
    },
  );

  for (final paint in ['#000', 'url(#gradient)']) {
    test('fill and stroke composite before opacity: $paint', () async {
      final pixels = await renderAt(
        parsePixelDoc(
          '<defs><linearGradient id="gradient"><stop stop-color="#000"/>'
          '<stop offset="1" stop-color="#000"/></linearGradient></defs>'
          '<rect x="20" y="20" width="60" height="60" fill="$paint" '
          'stroke="#000" stroke-width="20" fill-opacity=".5" '
          'stroke-opacity=".5" opacity=".5"/>',
        ),
        Duration.zero,
      );
      expect(alphaAt(pixels, 50, 50), _alpha(64));
      expect(alphaAt(pixels, 15, 50), _alpha(64));
      // (.5 + .5 * (1 - .5)) * .5 = .375, rather than .4375.
      expect(alphaAt(pixels, 25, 50), _alpha(96));
    });
  }

  for (final css in [false, true]) {
    test('${css ? 'CSS' : 'SMIL'} group opacity changes over time', () async {
      final doc = parsePixelDoc(
        css
            ? '<style>@keyframes fade {from {opacity:0} to {opacity:1}}'
                  '#s {animation:fade 1s linear forwards}</style>'
                  '<g opacity=".5"><g id="s">$_overlap</g></g>'
            : '<g opacity=".5"><g><animate attributeName="opacity" '
                  'values="0;1" dur="1s" fill="freeze"/>$_overlap</g></g>',
      );
      for (final (ms, alpha) in [(0, 0), (500, 64), (1500, 128)]) {
        final pixels = await renderAt(doc, Duration(milliseconds: ms));
        expect(alphaAt(pixels, 20, 50), _alpha(alpha));
        expect(alphaAt(pixels, 50, 50), _alpha(alpha));
      }
    });
  }

  test('canvas calls: opacity-free drawing and single-paint fast paths', () {
    for (final (body, layers) in [
      ('<g>$_overlap</g>', 0),
      ('<g opacity="1">$_overlap</g>', 0),
      ('<rect width="100" height="100" opacity=".5"/>', 0),
      (
        '<rect width="100" height="100" fill="none" stroke="#000" opacity=".5"/>',
        0,
      ),
      ('<g opacity=".5">$_overlap</g>', 1),
      ('<g opacity=".5"><rect width="60" height="100" stroke="#000"/></g>', 1),
      (
        '<g opacity=".5"><rect width="60" height="100" filter="blur(3px)"/></g>',
        2,
      ),
      (
        '<g opacity=".5"><rect width="60" height="100" clip-path="url(#c)"/></g>',
        1,
      ),
      ('<g opacity=".5"><rect width="60" height="100" mask="url(#m)"/></g>', 1),
      (
        '<defs><mask id="m" mask-type="alpha">$_rect</mask></defs>'
            '<g opacity=".5"><rect width="60" height="100" mask="url(#m)"/></g>',
        3,
      ),
      ('<g opacity=".5"><g opacity=".5">$_overlap</g></g>', 2),
      ('<rect width="100" height="100" stroke="#000" opacity=".5"/>', 1),
    ]) {
      final doc = parsePixelDoc(body);
      final clock = ValueNotifier(Duration.zero);
      final canvas = _CountingCanvas();
      AnimatedSvgPainter(
        root: doc.root,
        intrinsicSize: const Size(100, 100),
        clock: clock,
        theme: const SvgxTheme(),
        fit: BoxFit.fill,
        alignment: Alignment.center,
        masks: doc.masks,
        clipPaths: doc.clipPaths,
      ).paint(canvas, const Size(100, 100));
      expect(
        canvas.calls.where((s) => s == #saveLayer).length,
        layers,
        reason: body,
      );
      if (body == '<g>$_overlap</g>') {
        expect(canvas.calls, [
          #save,
          #translate,
          #scale,
          #clipRect,
          #drawPath,
          #drawPath,
          #restore,
        ]);
      }
      clock.dispose();
    }
  });
}

/// 统计 saveLayer 次数的录制画布：记录每条画布指令，不做光栅化。
/// Counts every canvas command without rasterization.
class _CountingCanvas implements ui.Canvas {
  final calls = <Symbol>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return null;
  }
}
