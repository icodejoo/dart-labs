// Card specs for the 17 async search-mode mirrors in the "Async镜像" tab.
// (asyncBuild / asyncAddAll / asyncDispose are lifecycle methods, not search
// mirrors — see async_lifecycle_cards.dart.)
//
// "Async镜像" Tab 里 17 个异步搜索镜像方法的卡片定义。
// （asyncBuild / asyncAddAll / asyncDispose 是生命周期方法，不是搜索镜像，
// 见 async_lifecycle_cards.dart。）
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../widgets/demo_card.dart';
import 'shared_query_tab.dart';

Widget _futureHits(Future<List<FuzzyHit<String>>> f) => FutureBuilder(
      future: f,
      builder: (context, snap) => snap.connectionState != ConnectionState.done
          ? const SizedBox(
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : ResultList([for (final h in snap.data!) '${h.raw}  (score ${h.score})']),
    );

Widget _futureRaws(Future<List<String>> f) => FutureBuilder(
      future: f,
      builder: (context, snap) => snap.connectionState != ConnectionState.done
          ? const SizedBox(
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : ResultList(snap.data!),
    );

final List<QuerySpec> asyncSearchSpecs = [
  QuerySpec('asyncFuzzy', "await corpus.asyncFuzzy(query)",
      (c, q) => _futureHits(c.asyncFuzzy(q, limit: 20))),
  QuerySpec('asyncFuzzyRaws', "await corpus.asyncFuzzyRaws(query)",
      (c, q) => _futureRaws(c.asyncFuzzyRaws(q, limit: 20))),
  QuerySpec('asyncPrefix', "await corpus.asyncPrefix(query)",
      (c, q) => _futureHits(c.asyncPrefix(q, limit: 20))),
  QuerySpec('asyncPrefixRaws', "await corpus.asyncPrefixRaws(query)",
      (c, q) => _futureRaws(c.asyncPrefixRaws(q, limit: 20))),
  QuerySpec('asyncPostfix', "await corpus.asyncPostfix(query)",
      (c, q) => _futureHits(c.asyncPostfix(q, limit: 20))),
  QuerySpec('asyncPostfixRaws', "await corpus.asyncPostfixRaws(query)",
      (c, q) => _futureRaws(c.asyncPostfixRaws(q, limit: 20))),
  QuerySpec('asyncSuffix', "await corpus.asyncSuffix(query)",
      (c, q) => _futureHits(c.asyncSuffix(q, limit: 20))),
  QuerySpec('asyncSuffixRaws', "await corpus.asyncSuffixRaws(query)",
      (c, q) => _futureRaws(c.asyncSuffixRaws(q, limit: 20))),
  QuerySpec('asyncExact', "await corpus.asyncExact(query)",
      (c, q) => _futureHits(c.asyncExact(q, limit: 20))),
  QuerySpec('asyncExactRaws', "await corpus.asyncExactRaws(query)",
      (c, q) => _futureRaws(c.asyncExactRaws(q, limit: 20))),
  QuerySpec('asyncSubstring', "await corpus.asyncSubstring(query)",
      (c, q) => _futureHits(c.asyncSubstring(q, limit: 20))),
  QuerySpec('asyncSubstringRaws', "await corpus.asyncSubstringRaws(query)",
      (c, q) => _futureRaws(c.asyncSubstringRaws(q, limit: 20))),
  QuerySpec('asyncSearch', "await corpus.asyncSearch(query)",
      (c, q) => _futureHits(c.asyncSearch(q, limit: 20))),
  QuerySpec('asyncSearchRaws', "await corpus.asyncSearchRaws(query)",
      (c, q) => _futureRaws(c.asyncSearchRaws(q, limit: 20))),
  QuerySpec('asyncApprox', "await corpus.asyncApprox(query)",
      (c, q) => _futureHits(c.asyncApprox(q, limit: 20))),
  QuerySpec('asyncApproxRaws', "await corpus.asyncApproxRaws(query)",
      (c, q) => _futureRaws(c.asyncApproxRaws(q, limit: 20))),
  QuerySpec('asyncDual', "await corpus.asyncDual(query)", (c, q) {
    return FutureBuilder(
      future: c.asyncDual(q, limit: 10),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2));
        }
        final r = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('fuzzy:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ResultList([for (final h in r.fuzzy) h.raw]),
            const SizedBox(height: 4),
            const Text('approx:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ResultList([for (final h in r.approx) h.raw]),
          ],
        );
      },
    );
  }),
];
