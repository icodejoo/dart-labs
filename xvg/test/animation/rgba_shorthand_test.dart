import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/xvg.dart' show RustLib;
import 'package:xvg/src/animation/svg_style.dart';
import 'package:xvg/src/animation/css_values.dart';

import 'pixel_test_utils.dart';

/// 把秒数（可为小数）转为 [Duration]，与 begin_value_list_test.dart 中的同名定义一致。
/// Converts seconds (fractions allowed) to a [Duration]; same as the helper in begin_value_list_test.dart.
Duration sec(num t) => Duration(microseconds: (t * 1000000).round());

void main() {
  setUpAll(() async {
    await RustLib.init();
  });
  for (final property in ['fill', 'stroke', 'stop-color']) {
    test('plain element $property interpolates concrete ARGB endpoints', () {
      final doc = parsePixelDoc(
        '<rect><animate attributeName="$property" '
        'values="#ff0000;#0000ff" dur="1s" fill="freeze"/></rect>',
      );
      final a = doc.root.children.single.colorAnimations.single;
      expect(a.sample(sec(0)), 0xffff0000);
      expect(a.sample(sec(.5)), 0xff800080);
      expect(a.sample(sec(1)), 0xff0000ff);
    });
  }
  test('plain fill values multisegment and discrete interpolation', () {
    for (final mode in ['linear', 'discrete']) {
      final doc = parsePixelDoc(
        '<rect><animate attributeName="fill" '
        'values="#ff0000;#00ff00;#0000ff" dur="1s" calcMode="$mode" fill="freeze"/></rect>',
      );
      final a = doc.root.children.single.colorAnimations.single;
      expect(a.sample(sec(0)), 0xffff0000);
      expect(a.sample(sec(.25)), mode == 'linear' ? 0xff808000 : 0xffff0000);
      expect(a.sample(sec(.5)), 0xff00ff00);
      expect(a.sample(sec(.75)), mode == 'linear' ? 0xff008080 : 0xff0000ff);
      expect(a.sample(sec(1)), 0xff0000ff);
    }
  });
  test('animated group fill is inherited by plain child pixels', () async {
    final doc = parsePixelDoc(
      '<g><animate attributeName="fill" '
      'values="#ff0000;#0000ff" dur="1s" fill="freeze"/>'
      '<rect width="100" height="100"/></g>',
    );
    for (final (t, r, b) in [(0, 255, 0), (.5, 128, 128), (1, 0, 255)]) {
      final px = await renderAt(doc, sec(t));
      final index = (50 * 100 + 50) * 4;
      expect(px.getUint8(index), r);
      expect(px.getUint8(index + 1), 0);
      expect(px.getUint8(index + 2), b);
    }
  });
  test('RGBA shorthand matches long hex in both color parsers', () {
    expect(parseSvgHexColor('#36c8')?.toARGB32(), 0x883366cc);
    expect(parseCssColor('#36c8'), 0x883366cc);
    expect(parseSvgHexColor('#36xz'), isNull);
  });
  for (final entry in <String, String>{
    'attribute': '<rect width="100" height="100" fill="#36c8"/>',
    'inline': '<rect width="100" height="100" style="fill:#36c8"/>',
    'CSS': '<style>rect{fill:#36c8}</style><rect width="100" height="100"/>',
    'keyframe': '<style>@keyframes c{from{fill:#36c8}to{fill:#36c8}}rect{animation:c 1s infinite}</style><rect width="100" height="100"/>',
    'gradient': '<defs><linearGradient id="g"><stop stop-color="#36c8"/><stop offset="1" stop-color="#36c8"/></linearGradient></defs><rect width="100" height="100" fill="url(#g)"/>',
    'SMIL': '<rect width="100" height="100"><animate attributeName="fill" values="#36c8;#36c8" dur="1s"/></rect>',
    'stop SMIL': '<defs><linearGradient id="g"><stop stop-color="#36c8"><animate attributeName="stop-color" values="#36c8;#36c8" dur="1s"/></stop></linearGradient></defs><rect width="100" height="100" fill="url(#g)"/>',
  }.entries) {
    test('RGBA ${entry.key} renders alpha 136', () async {
      final pixels = await renderAt(
        parsePixelDoc(entry.value),
        const Duration(milliseconds: 500),
      );
      expect(alphaAt(pixels, 50, 50), closeTo(136, 1));
    });
  }
}
