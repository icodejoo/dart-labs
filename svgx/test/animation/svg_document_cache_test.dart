// Tests for the animated-document cache added 2026-08-26 as a performance
// optimization: re-mounting an animated icon (which a scrolling list does
// constantly) must reuse the parsed document instead of re-parsing, while
// documents carrying <image> nodes must deliberately stay out of the cache —
// their decoded bitmap lives on the shared node, so sharing them between
// widgets would mean writing to shared mutable state.
//
// Eviction became random rather than LRU on 2026-08-27; see the
// "no LRU thrash" test below for the measured reason.
//
// 2026-08-26 作为性能优化加入的动画文档缓存的测试：动画图标重新挂载
// （滚动列表会不停这么做）必须复用已解析的文档而不是重新解析；而含 `<image>`
// 节点的文档必须刻意不入缓存——它解码出的位图存在共享节点上，跨控件共享就等于
// 写共享可变状态。
//
// 2026-08-27 起淘汰策略由 LRU 改为随机；实测理由见下方的 "no LRU thrash"
// 测试。

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

/// A distinct-but-equivalent source string, so a test can build a working set
/// of any size without hand-writing each SVG.
///
/// 一个互不相同但等价的源串，让测试可以构造任意大小的工作集，而不必手写每份
/// SVG。
String _variant(int i) => _staticIsh.replaceFirst('r="10"', 'r="${i + 1}"');

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

    test('never holds more than maximumSize entries', () {
      final previousMax = SvgDocumentCache.instance.maximumSize;
      addTearDown(() => SvgDocumentCache.instance.maximumSize = previousMax);
      SvgDocumentCache.instance.maximumSize = 2;

      for (var i = 0; i < 10; i++) {
        SvgDocumentCache.instance.getOrParse(_variant(i));
        expect(SvgDocumentCache.instance.length, lessThanOrEqualTo(2));
      }
    });

    // The regression guard for the real 2026-08-27 fix. Strict LRU has a
    // pathological interaction with the access pattern a scrolling icon grid
    // produces: cycling through a working set larger than the cache in a fixed
    // order evicts each entry exactly one step before it is requested again,
    // so the hit rate is not merely poor, it is exactly ZERO. Random eviction
    // has no such adversarial relationship with the access order and keeps
    // roughly capacity/working-set of the entries resident.
    //
    // Asserting "> 0 hits" rather than a specific rate is deliberate: the
    // point of the fix is that the cliff is gone, and a bound that depends on
    // the RNG draw would be a flaky test. Measured effect of this failure mode
    // on a real device is recorded on `SvgDocumentCache.maximumSize`.
    //
    // 2026-08-27 那次真实修复的回归防线。严格 LRU 与滚动图标网格产生的访问模式
    // 有病态的相互作用：按固定顺序循环访问一个比缓存更大的工作集时，每个条目
    // 都恰好在再次被请求的前一步被淘汰，于是命中率不是"偏低"，而是恰好为
    // **零**。随机淘汰与访问顺序之间不存在这种对抗关系，能留住大约
    // 容量/工作集 比例的条目。
    //
    // 刻意断言"命中数 > 0"而不是某个具体命中率：本次修复的要点是那个悬崖消失
    // 了，而依赖具体随机抽样结果的界会让测试变得不稳定。这个失效模式在真机上的
    // 实测影响记录在 `SvgDocumentCache.maximumSize` 上。
    test('a cyclic scan larger than the cache still hits (no LRU thrash)', () {
      final previousMax = SvgDocumentCache.instance.maximumSize;
      addTearDown(() => SvgDocumentCache.instance.maximumSize = previousMax);
      const workingSet = 20;
      SvgDocumentCache.instance.maximumSize = 10;

      final sources = List<String>.generate(workingSet, _variant);
      // First pass fills the cache; later passes are the ones that can hit.
      // 第一趟负责填满缓存，能命中的是后面几趟。
      for (final source in sources) {
        SvgDocumentCache.instance.getOrParse(source);
      }

      final seen = <String, Object>{};
      var hits = 0;
      for (var pass = 0; pass < 4; pass++) {
        for (final source in sources) {
          final document = SvgDocumentCache.instance.getOrParse(source).document;
          if (identical(seen[source], document)) hits++;
          seen[source] = document;
        }
      }

      expect(
        hits,
        greaterThan(0),
        reason: 'strict LRU would score exactly 0 hits on this access pattern',
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
