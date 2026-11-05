import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/svgx.dart';

const _plain = '<svg width="24" height="24"><path d="M0 0H24V24H0Z"/></svg>';
const _clip = '''<svg width="24" height="24"><defs><clipPath id="c">
<rect width="12" height="24"/></clipPath></defs>
<path d="M0 0H24V24H0Z" clip-path="url(#c)"/></svg>''';
const _mask = '''<svg width="24" height="24"><defs><mask id="m">
<rect width="12" height="24" fill="white"/></mask></defs>
<path d="M0 0H24V24H0Z" mask="url(#m)"/></svg>''';
const _unused = '''<svg width="24" height="24"><defs><mask id="m">
<rect width="12" height="24" fill="white"/></mask></defs>
<path d="M0 0H24V24H0Z"/></svg>''';
const _comment = '<!-- <mask/><clipPath/> -->';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const _image =
    '<image width="1" height="1" href="data:image/png;base64,$_png"/>';
const _end = '</svg>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);
  tearDown(RustSvgxPictureCache.instance.clear);

  test('document risk reads parsed mask and clip registries', () {
    for (final source in [_plain, _clip, _mask, _unused]) {
      final document = parseAnimatedSvgDocument(source);
      expect(document.hasPixelSnapRisk, source != _plain);
    }
    expect(
      parseAnimatedSvgDocument(_plain.replaceFirst(_end, '$_comment$_end'))
          .hasPixelSnapRisk,
      isFalse,
    );
  });

  for (final source in [_plain, _clip, _mask, _unused]) {
    for (final withImage in [false, true]) {
      test(
        'static parsed effects sync/async/cache risk ${source == _plain
            ? 'plain'
            : source == _mask
            ? 'mask'
            : source == _clip
            ? 'clip'
            : 'unused'} image=$withImage',
        () async {
          final markup = withImage
              ? source.replaceFirst(_end, '$_image$_end')
              : source;
          final risk = source == _mask || source == _clip;
          final cache = RustSvgxPictureCache.instance;
          var misses = 0;
          cache.onParseMiss = (_) => misses++;
          addTearDown(() => cache.onParseMiss = null);
          final sync = cache.getOrRender(markup);
          expect(sync.hasPixelSnapRisk, risk);
          expect(cache.getOrRender(markup), same(sync));
          expect(await cache.getOrRenderAsync(markup), same(sync));
          expect(misses, 1);
          cache.clear();
          final async = await cache.getOrRenderAsync(markup);
          expect(async.hasPixelSnapRisk, risk);
          expect(cache.getOrRender(markup), same(async));
          expect(await cache.getOrRenderAsync(markup), same(async));
          expect(misses, 2);
        },
      );
    }
  }

  test('comments and long text do not become static mask risk', () {
    final source = _plain.replaceFirst(_end, '${_comment * 12000}$_end');
    expect(
      RustSvgxPictureCache.instance.getOrRender(source).hasPixelSnapRisk,
      isFalse,
    );
  });
}
