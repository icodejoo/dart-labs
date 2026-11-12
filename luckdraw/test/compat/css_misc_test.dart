import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/luckdraw.dart';
import 'package:luckdraw/src/compat/css_misc.dart'
    show imageProviderFromSrc, parseCssFontFamily;

/// 验证上游 padding 特殊顺序和字体、图片适配。
void main() {
  const options = LuckyCanvasCompatOptions();
  group('compat misc parsers', () {
    test(
        'parseCssPadding uses the upstream top-bottom-left-right order for four values',
        () {
      final warnings = <String>[];
      expect(parseCssPadding('1 2 3 4', options, warnings.add),
          const LuckyEdgeInsets.only(top: 1, bottom: 2, left: 3, right: 4));
      expect(parseCssPadding('1', options, warnings.add),
          const LuckyEdgeInsets.all(1));
      expect(parseCssPadding('1 2', options, warnings.add),
          const LuckyEdgeInsets.symmetric(vertical: 1, horizontal: 2));
      expect(parseCssPadding('1 2 3', options, warnings.add),
          const LuckyEdgeInsets.only(top: 1, bottom: 3, left: 2, right: 2));
      expect(parseCssPadding('1  2 3', options, warnings.add),
          const LuckyEdgeInsets.only(top: 1, bottom: 0, left: 2, right: 3));
      expect(parseCssPadding('1 2 3 4 5', options, warnings.add),
          const LuckyEdgeInsets.only(top: 1, bottom: 2, left: 3, right: 4));
      expect(parseCssPadding('50%', options, warnings.add),
          const LuckyEdgeInsets.all(.5));
      expect(parseCssPadding('', options, warnings.add), LuckyEdgeInsets.zero);
      expect(
          parseCssPadding(null, options, warnings.add), LuckyEdgeInsets.zero);
      expect(warnings, isEmpty);
      expect(
          parseCssPadding('bad!', options, warnings.add), LuckyEdgeInsets.zero);
      expect(warnings, hasLength(1));
      expect(parseCssPadding(1, options, warnings.add), LuckyEdgeInsets.zero);
      expect(warnings, hasLength(2));
    });
    test(
        'parseCssPadding ignores individual padding fields with a warning (U-01)',
        () {
      final warnings = <String>[];
      expect(
          parseCssPadding({
            'padding': '1 2',
            'paddingTop': 9,
            'paddingBottom': 8,
            'paddingLeft': 7,
            'paddingRight': 6,
          }, options, warnings.add),
          const LuckyEdgeInsets.symmetric(vertical: 1, horizontal: 2));
      expect(warnings, hasLength(4));
      expect(warnings.every((warning) => warning.contains('(U-01)')), isTrue);
      expect(parseCssPadding({'paddingTop': 5}, options, warnings.add),
          LuckyEdgeInsets.zero);
      expect(warnings, hasLength(5));
      expect(parseCssPadding({'padding': '3'}, options, warnings.add),
          const LuckyEdgeInsets.all(3));
      expect(warnings, hasLength(5));
    });
    test('parseCssFontWeight maps keywords and numbers', () {
      expect(parseCssFontWeight('normal'), FontWeight.w400);
      expect(parseCssFontWeight(' BOLD '), FontWeight.w700);
      expect(parseCssFontWeight('bolder'), FontWeight.w700);
      expect(parseCssFontWeight('lighter'), FontWeight.w300);
      expect(parseCssFontWeight(100), FontWeight.w100);
      expect(parseCssFontWeight('900'), FontWeight.w900);
      expect(parseCssFontWeight(550), FontWeight.w600);
      expect(parseCssFontWeight(-100), FontWeight.w100);
      expect(parseCssFontWeight(1000), FontWeight.w900);
      expect(parseCssFontWeight(null), isNull);
      expect(parseCssFontWeight('unknown'), isNull);
      expect(parseCssFontWeight(double.infinity), isNull);
    });
    test('fontStyle splits into family and fallback with sans-serif as null',
        () {
      _expectFamily('"Roboto", Arial, sans-serif', 'Roboto', ['Arial']);
      _expectFamily("'Times New Roman', serif", 'Times New Roman', ['serif']);
      _expectFamily('"A,B", Arial', 'A,B', ['Arial']);
      expect(parseCssFontFamily('sans-serif'), (family: null, fallback: null));
      _expectFamily(' SANS-SERIF, Arial ', null, ['Arial']);
      expect(parseCssFontFamily('Arial'), (family: 'Arial', fallback: null));
      expect(parseCssFontFamily(' , "" , '), (family: null, fallback: null));
      expect(parseCssFontFamily(null), (family: null, fallback: null));
      expect(parseCssFontFamily(' '), (family: null, fallback: null));
    });
    test('image src maps to Network Memory or Asset providers', () {
      final warnings = <String>[];
      final http = imageProviderFromSrc(
          'http://example.com/a.png', options, warnings.add) as NetworkImage;
      final https = imageProviderFromSrc(
          'https://example.com/a.png', options, warnings.add) as NetworkImage;
      expect(http.url, 'http://example.com/a.png');
      expect(https.url, 'https://example.com/a.png');
      final memory = imageProviderFromSrc(
          'data:image/png;base64,AQID', options, warnings.add) as MemoryImage;
      expect(memory.bytes, [1, 2, 3]);
      final asset = imageProviderFromSrc('images/a.png', options, warnings.add)
          as AssetImage;
      expect(asset.assetName, 'images/a.png');
      final resolved = <String>[];
      const custom = AssetImage('custom.png');
      final configured = LuckyCanvasCompatOptions(assetResolver: (src) {
        resolved.add(src);
        return custom;
      });
      expect(imageProviderFromSrc('a.png', configured, warnings.add),
          same(custom));
      expect(resolved, ['a.png']);
      expect(warnings, isEmpty);
      for (final source in <Object?>[
        null,
        '',
        true,
        'data:broken',
        'data:image/png;base64,%%%'
      ]) {
        final before = warnings.length;
        expect(imageProviderFromSrc(source, options, warnings.add), isNull);
        expect(warnings.length, before + 1);
      }
    });
  });
}

/// 分别比较字体族与回退列表内容，避免 record 中的 List 按身份比较。
void _expectFamily(String value, String? family, List<String> fallback) {
  final parsed = parseCssFontFamily(value);
  expect(parsed.family, family);
  expect(parsed.fallback, fallback);
}
