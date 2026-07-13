// Card specs for the "Raws变体" tab — the 8 *Raws methods (matched items,
// no FuzzyHit wrapper, no highlight-index computation).
//
// "Raws变体" Tab 的卡片定义 —— 8 个 *Raws 方法（直接返回匹配项，不带
// FuzzyHit 包装，不计算高亮下标）。
import '../widgets/demo_card.dart';
import 'shared_query_tab.dart';

final List<QuerySpec> rawsSpecs = [
  QuerySpec('fuzzyRaws', "corpus.fuzzyRaws(query)",
      (c, q) => ResultList(c.fuzzyRaws(q, limit: 20))),
  QuerySpec('substringRaws', "corpus.substringRaws(query)",
      (c, q) => ResultList(c.substringRaws(q, limit: 20))),
  QuerySpec('prefixRaws', "corpus.prefixRaws(query)",
      (c, q) => ResultList(c.prefixRaws(q, limit: 20))),
  QuerySpec('postfixRaws', "corpus.postfixRaws(query)",
      (c, q) => ResultList(c.postfixRaws(q, limit: 20))),
  QuerySpec('suffixRaws', "corpus.suffixRaws(query)",
      (c, q) => ResultList(c.suffixRaws(q, limit: 20))),
  QuerySpec('exactRaws', "corpus.exactRaws(query)",
      (c, q) => ResultList(c.exactRaws(q, limit: 20))),
  QuerySpec('searchRaws', "corpus.searchRaws(query)",
      (c, q) => ResultList(c.searchRaws(q, limit: 20))),
  QuerySpec('approxRaws', "corpus.approxRaws(query)",
      (c, q) => ResultList(c.approxRaws(q, limit: 20))),
];
