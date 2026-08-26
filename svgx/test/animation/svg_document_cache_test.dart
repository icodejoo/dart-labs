// Tests for the animated-document LRU cache added 2026-08-26 as a
// performance optimization: re-mounting an animated icon (which a scrolling
// list does constantly) must reuse the parsed document instead of re-parsing,
// while documents carrying <image> nodes must deliberately stay out of the
// cache — their decoded bitmap lives on the shared node, so sharing them
// between widgets would mean writing to shared mutable state.
//
// 2026-08-26 作为性能优化加入的动画文档 LRU 缓存的测试：动画图标重新挂载
// （滚动列表会不停这么做）必须复用已解析的文档而不是重新解析；而含 `<image>`
// 节点的文档必须刻意不入缓存——它解码出的位图存在共享节点上，跨控件共享就等于
// 写共享可变状态。

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_cache.dart';

const _staticIsh =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
    '<circle cx="12" cy="12" r="10">'
    '<animate attributeName="r" values="0;10" dur="1s"/>'
    '</circle></svg>';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const _withImage =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
    '<image x="0" y="0" width="24" height="24" '
    'href="data:image/png;base64,$_pngBase64"/>'
    '<circle cx="12" cy="12" r="10">'
    '<animate attributeName="r" values="0;10" dur="1s"/>'
    '</circle></svg>';

void main() {
  setUp(SvgDocumentCache.instance.clear);
  tearDown(SvgDocumentCache.instance.clear);

  group('SvgDocumentCache', () {
    test('returns the identical document instance on a repeat parse', () {
      final first = SvgDocumentCache.instance.getOrParse(_staticIsh);
      final second = SvgDocumentCache.instance.getOrParse(_staticIsh);

      expect(first.hasImages, isFalse);
      expect(
        second.document,
        same(first.document),
        reason: 'a warm cache must not re-parse',
      );
    });

    test('parses distinct sources into distinct documents', () {
      final a = SvgDocumentCache.instance.getOrParse(_staticIsh);
      final b = SvgDocumentCache.instance.getOrParse(
        _staticIsh.replaceFirst('r="10"', 'r="8"'),
      );

      expect(b.document, isNot(same(a.document)));
    });

    test('never caches a document containing <image> nodes', () {
      final first = SvgDocumentCache.instance.getOrParse(_withImage);
      final second = SvgDocumentCache.instance.getOrParse(_withImage);

      expect(first.hasImages, isTrue);
      expect(second.hasImages, isTrue);
      expect(
        second.document,
        isNot(same(first.document)),
        reason:
            'image documents hold per-widget decoded bitmaps and must stay '
            'unshared',
      );
    });

    test('evicts the least-recently-used entry past maximumSize', () {
      final previousMax = SvgDocumentCache.instance.maximumSize;
      addTearDown(() => SvgDocumentCache.instance.maximumSize = previousMax);
      SvgDocumentCache.instance.maximumSize = 2;

      final a = SvgDocumentCache.instance.getOrParse(_staticIsh);
      final srcB = _staticIsh.replaceFirst('r="10"', 'r="8"');
      final srcC = _staticIsh.replaceFirst('r="10"', 'r="6"');
      SvgDocumentCache.instance.getOrParse(srcB);
      SvgDocumentCache.instance.getOrParse(srcC); // evicts the oldest (a)

      expect(
        SvgDocumentCache.instance.getOrParse(_staticIsh).document,
        isNot(same(a.document)),
      );
      // srcC was the most recent insert, so it is still cached.
      expect(
        SvgDocumentCache.instance.getOrParse(srcC).document,
        same(SvgDocumentCache.instance.getOrParse(srcC).document),
      );
    });

    test('clear() drops cached documents', () {
      final first = SvgDocumentCache.instance.getOrParse(_staticIsh);
      SvgDocumentCache.instance.clear();

      expect(
        SvgDocumentCache.instance.getOrParse(_staticIsh).document,
        isNot(same(first.document)),
      );
    });
  });
}
