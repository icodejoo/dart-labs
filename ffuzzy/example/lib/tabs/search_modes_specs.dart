// Card specs for the "搜索模式" tab — the 9 synchronous search-mode methods.
//
// "搜索模式" Tab 的卡片定义 —— 9 个同步搜索方法。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../widgets/demo_card.dart';
import 'shared_query_tab.dart';

Widget _hits(List<FuzzyHit<String>> hits) =>
    ResultList([for (final h in hits) '${h.raw}  (score ${h.score})']);

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
      'search (merge)',
      "corpus.search(query,\n"
          "  strategy: SearchStrategy.merge)",
      (c, q) => _hits(c.search(q, strategy: SearchStrategy.merge, limit: 20))),
  QuerySpec('approx', "corpus.approx(query)  // edit-distance",
      (c, q) => _hits(c.approx(q, limit: 20)),
      note: 'Whole-string Levenshtein distance vs the FULL item text — best '
          'for short, single-token candidates near the query\'s length '
          "(app names, usernames: 'instgram'→Instagram). Long paths need a "
          "near-complete typo instead, e.g. 'REDME.md'."),
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
