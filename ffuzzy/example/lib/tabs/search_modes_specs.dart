// Card specs for the "Search modes" tab — the 12 synchronous search-mode
// methods, including all 4 SearchStrategy variants via the unified search().
//
// "Search modes" Tab 的卡片定义 —— 12 个同步搜索方法，包含统一入口
// search() 的全部 4 种 SearchStrategy。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../widgets/demo_card.dart';
import 'shared_query_tab.dart';

Widget _hits(List<FuzzyHit<String>> hits) =>
    ResultList([for (final h in hits) '${h.raw}  (score ${h.score})']);

// approx's score is -distance (see ffz_corpus.c); indices are the matched
// window's codepoint range (a contiguous run), not discrete positions.
//
// approx 的分数是 -distance（参见 ffz_corpus.c）；indices 是匹配窗口的码点
// 区间（一段连续范围），而不是离散的位置。
String _approxWindowLine(FuzzyHit<String> h) {
  if (h.indices.isEmpty) return '${h.raw}  (dist ${-h.score})';
  final u16 = fuzzyCodepointToUtf16(h.raw, [h.indices.first, h.indices.last]);
  final window = h.raw.substring(u16[0], u16[1] + 1);
  return '${h.raw}  [$window]  (dist ${-h.score})';
}

Widget _approxHits(List<FuzzyHit<String>> hits) =>
    ResultList([for (final h in hits) _approxWindowLine(h)]);

final List<QuerySpec> searchModeSpecs = [
  QuerySpec('fuzzy', "corpus.fuzzy(query)",
      (c, q) => _hits(c.fuzzy(q, limit: 20))),
  QuerySpec('substring', "corpus.substring(query)",
      (c, q) => _hits(c.substring(q, limit: 20))),
  QuerySpec('prefix', "corpus.prefix(query)",
      (c, q) => _hits(c.prefix(q, limit: 20))),
  QuerySpec('postfix', "corpus.postfix(query)",
      (c, q) => _hits(c.postfix(q, limit: 20))),
  QuerySpec('suffix', "corpus.suffix(query)  // alias of postfix",
      (c, q) => _hits(c.suffix(q, limit: 20))),
  QuerySpec('exact', "corpus.exact(query)",
      (c, q) => _hits(c.exact(q, limit: 20))),
  QuerySpec(
      'search (fuzzy)',
      "corpus.search(query,\n"
          "  strategy: SearchStrategy.fuzzy)  // default",
      (c, q) => _hits(c.search(q, strategy: SearchStrategy.fuzzy, limit: 20)),
      note: 'Unified entry point, same algorithm as fuzzy() above.'),
  QuerySpec(
      'search (approx)',
      "corpus.search(query,\n"
          "  strategy: SearchStrategy.approx, highlight: true)",
      (c, q) => _approxHits(c.search(q,
          strategy: SearchStrategy.approx, limit: 20, highlight: true)),
      note: 'Unified entry point, same algorithm as approx() below.'),
  QuerySpec(
      'search (fallback)',
      "corpus.search(query,\n"
          "  strategy: SearchStrategy.fallback)",
      (c, q) =>
          _hits(c.search(q, strategy: SearchStrategy.fallback, limit: 20)),
      note: 'Runs fuzzy first; only falls back to approx (edit-distance) '
          'when the fuzzy result is empty — so a clean subsequence match '
          'always wins over a typo-tolerant one.'),
  QuerySpec(
      'search (merge)',
      "corpus.search(query,\n"
          "  strategy: SearchStrategy.merge)",
      (c, q) => _hits(c.search(q, strategy: SearchStrategy.merge, limit: 20)),
      note: 'Runs both algorithms in one scan — subsequence hits first, '
          'then approx-only hits (already-found items are deduplicated).'),
  QuerySpec(
      'approx',
      "corpus.approx(query, highlight: true)\n"
          "// edit-distance, SUBSTRING search",
      (c, q) => _approxHits(c.approx(q, limit: 20, highlight: true)),
      note: 'Finds a window inside the item within edit distance of query — '
          "the window can start/end anywhere, so 'scaffolx' (a typo, not a "
          'fuzzy subsequence) still matches inside a long path. [brackets] '
          'show the matched window.'),
  QuerySpec('dual', "corpus.dual(query)  // fuzzy + approx, split", (c, q) {
    final r = c.dual(q, limit: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('fuzzy:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        _hits(r.fuzzy),
        const SizedBox(height: 4),
        const Text('approx:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        _hits(r.approx),
      ],
    );
  }),
];
