import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_style.dart';
import 'package:svgx/src/animation/svg_theme.dart';
import 'package:svgx/src/rust_static_svg.dart';
import 'package:svgx/svgx.dart' show RustLib;

import 'pixel_test_utils.dart';
import 'rule_pixel_utils.dart';

const _white = 'fill="#fff"';
const _partialFill = 'fill-opacity=".3"';
const _partialStroke = 'stroke-opacity=".3"';
const _partialOpacity = 'opacity=".3"';
const _bodyPath = 'd="M10 35H90V90H10Z"';
const _hole = '<path d="M40 35H60V55H40Z"/>';
const _fill = '<path $_white $_bodyPath/>';
const _stroke =
    '<path fill="none" stroke="#fff" stroke-width="30" d="M10 70H90"';
const _tolerance = 2;
const _channelMax = 255;
const _size = Size(100, 100);
const _fillOpacity = 'fill-opacity';
const _strokeOpacity = 'stroke-opacity';
const _opacity = 'opacity';
const _fillAttribute = 'fill';
const _strokeAttribute = 'stroke';
const _animationTiming = 'dur="2s" fill="freeze"';
const _animation = 'from=".2" to=".6" $_animationTiming';
const _colorAnimation = 'from="#ffffff33" to="#ffffff99" $_animationTiming';
const _samples = [(0, .2), (1, .4), (2, .6), (61, .6)];

String _source(String content, {bool alpha = false}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
    'viewBox="0 0 100 100"><defs>'
    '<mask id="m" ${alpha ? 'mask-type="alpha"' : ''}>'
    '$content</mask></defs>'
    '<path fill="currentColor" d="M0 0H100V100H0Z" mask="url(#m)"/>'
    '</svg>';

Future<ByteData> _staticPixels(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(kPixelSize, kPixelSize);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _maxChannelDelta(ByteData pixels, ByteData reference) {
  expect(pixels.lengthInBytes, reference.lengthInBytes);
  var maxDelta = 0;
  for (var i = 0; i < pixels.lengthInBytes; i++) {
    final delta = (pixels.getUint8(i) - reference.getUint8(i)).abs();
    if (delta > maxDelta) maxDelta = delta;
  }
  return maxDelta;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());
  tearDownAll(() => RustSvgxPictureCache.instance.clear());

  test('leading-dot opacity values parse without falling back to one', () {
    final style = ResolvedStyle.initial.inherit(const {
      _fillOpacity: '.3',
      _strokeOpacity: '.3',
      _opacity: '.3',
    }, const SvgxTheme());
    expect(style.fillOpacity, closeTo(.3, .000001));
    expect(style.strokeOpacity, closeTo(.3, .000001));
    expect(style.opacity, closeTo(.3, .000001));
  });

  // Force AnimatedSvgPainter through renderDoc; no playback routing is involved.
  // renderDoc 直接使用 AnimatedSvgPainter，明确强制动画路径。
  for (final (name, content, coverage) in [
    (_fillOpacity, '<path $_white $_partialFill $_bodyPath/>', .3),
    (_strokeOpacity, '$_stroke $_partialStroke/>', .3),
    ('element opacity', '<path $_white $_partialOpacity $_bodyPath/>', .3),
    ('group opacity with overlap', '<g $_partialOpacity>$_fill$_fill</g>', .3),
    ('inherited fill-opacity', '<g $_partialFill>$_fill</g>', .3),
    (
      'combined opacity',
      '<g opacity=".5"><path $_white '
          'fill-opacity=".6" $_bodyPath/></g>',
      .3,
    ),
    ('color alpha', '<path fill="#ffffff4d" $_bodyPath/>', 77 / _channelMax),
    (
      'gray times alpha',
      '<path fill="#808080" opacity=".5" $_bodyPath/>',
      64 / _channelMax,
    ),
    (
      'translucent black over white',
      '$_fill<path $_partialOpacity '
          '$_bodyPath/>',
      .7,
    ),
  ]) {
    testWidgets('luminance mask $name matches SvgxStatic', (tester) async {
      final source = _source('$content$_hole');
      await tester.pumpWidget(Center(child: SvgxStatic(source)));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .singleWhere((widget) => widget.painter != null)
          .painter!;
      await tester.runAsync(() async {
        final reference = await _staticPixels(painter);
        final expected = coverage * _channelMax;
        expect(alphaAt(reference, 50, 70), closeTo(expected, _tolerance));
        expect(alphaAt(reference, 50, 45), 0);
        for (final approximate in [false, true]) {
          final doc = parseAnimatedSvgDocument(source);
          final pixels = await renderDoc(doc, approximate: approximate);
          expect(
            alphaAt(pixels, 50, 70),
            closeTo(expected, _tolerance),
            reason: 'approximate=$approximate',
          );
          expect(alphaAt(pixels, 50, 45), 0);
          expect(alphaAt(pixels, 5, 70), 0);
          if (approximate) {
            expect(doc.masks.values.single.maskClipEligible, isFalse);
          }
          expect(
            _maxChannelDelta(pixels, reference),
            lessThanOrEqualTo(_tolerance),
            reason: 'all RGBA channels, approximate=$approximate',
          );
        }
      });
    });
  }

  testWidgets('opaque mask retains antialiased alpha and matches SvgxStatic', (
    tester,
  ) async {
    // Raster coverage contributes alpha even without an opacity attribute.
    // 即使没有 opacity 属性，抗锯齿的光栅覆盖率仍贡献 alpha。
    const content = '<path $_white d="M10 35H90V90L10 80Z"/>';
    final source = _source(content);
    await tester.pumpWidget(Center(child: SvgxStatic(source)));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .singleWhere((widget) => widget.painter != null)
        .painter!;
    await tester.runAsync(() async {
      final reference = await _staticPixels(painter);
      final pixels = await renderDoc(parseAnimatedSvgDocument(source));
      final alphaPixels = await renderDoc(
        parseAnimatedSvgDocument(_source(content, alpha: true)),
      );
      expect(
        _maxChannelDelta(pixels, reference),
        lessThanOrEqualTo(_tolerance),
      );
      expect(
        _maxChannelDelta(pixels, alphaPixels),
        lessThanOrEqualTo(_tolerance),
      );
      var edgePixels = 0;
      for (var i = 3; i < pixels.lengthInBytes; i += 4) {
        final alpha = pixels.getUint8(i);
        if (alpha > 0 && alpha < _channelMax) edgePixels++;
      }
      expect(edgePixels, greaterThan(0));
    });
  });

  for (final attribute in [_fillOpacity, _strokeOpacity, _opacity]) {
    for (final alpha in [false, true]) {
      test('mask $attribute animation samples alpha (alpha mask=$alpha)', () async {
        final content = attribute == _strokeOpacity
            ? '$_stroke><animate attributeName="$attribute" $_animation/></path>'
            : '<path $_white $_bodyPath>'
                  '<animate attributeName="$attribute" $_animation/></path>';
        final doc = parseAnimatedSvgDocument(_source(content, alpha: alpha));
        for (final approximate in [false, true]) {
          for (final (seconds, coverage) in _samples) {
            final pixels = await renderDoc(
              doc,
              time: Duration(seconds: seconds),
              approximate: approximate,
            );
            expect(
              alphaAt(pixels, 50, 70),
              closeTo(coverage * _channelMax, _tolerance),
              reason: 'seconds=$seconds, approximate=$approximate',
            );
            expect(alphaAt(pixels, 5, 70), 0);
          }
          if (approximate) {
            expect(doc.masks.values.single.maskClipEligible, isFalse);
          }
        }
      });
    }
  }

  for (final attribute in [_fillAttribute, _strokeAttribute]) {
    for (final alpha in [false, true]) {
      test(
        'mask $attribute color animation samples alpha (alpha mask=$alpha)',
        () async {
          final content = attribute == _strokeAttribute
              ? '$_stroke><animate attributeName="$attribute" '
                    '$_colorAnimation/></path>'
              : '<path $_white $_bodyPath><animate attributeName="$attribute" '
                    '$_colorAnimation/></path>';
          final doc = parseAnimatedSvgDocument(_source(content, alpha: alpha));
          for (final approximate in [false, true]) {
            for (final (seconds, coverage) in _samples) {
              final pixels = await renderDoc(
                doc,
                time: Duration(seconds: seconds),
                approximate: approximate,
              );
              expect(
                alphaAt(pixels, 50, 70),
                closeTo(coverage * _channelMax, _tolerance),
                reason: 'seconds=$seconds, approximate=$approximate',
              );
              expect(alphaAt(pixels, 5, 70), 0);
            }
            if (approximate) {
              expect(doc.masks.values.single.maskClipEligible, isFalse);
            }
          }
        },
      );
    }
  }
}
