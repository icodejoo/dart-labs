import 'package:ffuzzy/ffuzzy.dart';
import 'demo_data.dart';

/// 同步搜索回调，返回命中、原始对象或双路结果。
typedef SearchCall = Object Function(FuzzyCorpus<String> corpus, String query);

/// 异步搜索回调，保留平台自身的执行语义。
typedef AsyncSearchCall = Future<Object> Function(
    FuzzyCorpus<String> corpus, String query);

/// 一个搜索方法及其原始对象、异步变体。
class SearchSpec {
  /// 创建完整的搜索演示配置。
  const SearchSpec(this.name, this.en, this.zh, this.query, this.hits,
      this.raws, this.asyncHits, this.asyncRaws, this.code);

  /// 公开方法或策略名。
  final String name;

  /// 英文说明。
  final String en;

  /// 中文说明。
  final String zh;

  /// 初始查询。
  final String query;

  /// 同步命中调用。
  final SearchCall hits;

  /// 同步原始对象调用；双路结果无此变体。
  final SearchCall? raws;

  /// 异步命中调用。
  final AsyncSearchCall asyncHits;

  /// 异步原始对象调用。
  final AsyncSearchCall? asyncRaws;

  /// 与实际调用一致的示例代码。
  final String code;
}

/// 可复用的子序列查询样本。
const _subsequenceQuery = 'scf';

/// 可复用的拼写错误查询样本。
const _typoQuery = 'scaffolx';

/// 可复用的文件扩展名查询样本。
const _extensionQuery = '.dart';

/// 当前公开 API 的搜索目录，合并重复的 Raws 与异步页面。
final searchSpecs = <SearchSpec>[
  SearchSpec(
      'fuzzy',
      'Subsequence matching with fzf operators.',
      '子序列匹配，支持 fzf 查询操作符。',
      _subsequenceQuery,
      (c, q) => c.fuzzy(q, limit: resultLimit, highlight: true),
      (c, q) => c.fuzzyRaws(q, limit: resultLimit),
      (c, q) => c.asyncFuzzy(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncFuzzyRaws(q, limit: resultLimit),
      '''corpus.fuzzy(query, limit: resultLimit, highlight: true);
corpus.fuzzyRaws(query, limit: resultLimit);
await corpus.asyncFuzzy(query, limit: resultLimit, highlight: true);
await corpus.asyncFuzzyRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'substring',
      'Literal substring, including spaces.',
      '字面子串匹配，保留空格。',
      'src',
      (c, q) => c.substring(q, limit: resultLimit, highlight: true),
      (c, q) => c.substringRaws(q, limit: resultLimit),
      (c, q) => c.asyncSubstring(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncSubstringRaws(q, limit: resultLimit),
      '''corpus.substring(query, limit: resultLimit, highlight: true);
corpus.substringRaws(query, limit: resultLimit);
await corpus.asyncSubstring(query, limit: resultLimit, highlight: true);
await corpus.asyncSubstringRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'prefix',
      'Matches the start of a key.',
      '匹配键的开头。',
      'lib',
      (c, q) => c.prefix(q, limit: resultLimit, highlight: true),
      (c, q) => c.prefixRaws(q, limit: resultLimit),
      (c, q) => c.asyncPrefix(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncPrefixRaws(q, limit: resultLimit),
      '''corpus.prefix(query, limit: resultLimit, highlight: true);
corpus.prefixRaws(query, limit: resultLimit);
await corpus.asyncPrefix(query, limit: resultLimit, highlight: true);
await corpus.asyncPrefixRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'postfix',
      'Matches the end of a key.',
      '匹配键的末尾。',
      _extensionQuery,
      (c, q) => c.postfix(q, limit: resultLimit, highlight: true),
      (c, q) => c.postfixRaws(q, limit: resultLimit),
      (c, q) => c.asyncPostfix(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncPostfixRaws(q, limit: resultLimit),
      '''corpus.postfix(query, limit: resultLimit, highlight: true);
corpus.postfixRaws(query, limit: resultLimit);
await corpus.asyncPostfix(query, limit: resultLimit, highlight: true);
await corpus.asyncPostfixRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'suffix',
      'Alias of postfix; identical behavior.',
      'postfix 的有效别名，行为相同。',
      _extensionQuery,
      (c, q) => c.suffix(q, limit: resultLimit, highlight: true),
      (c, q) => c.suffixRaws(q, limit: resultLimit),
      (c, q) => c.asyncSuffix(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncSuffixRaws(q, limit: resultLimit),
      '''corpus.suffix(query, limit: resultLimit, highlight: true);
corpus.suffixRaws(query, limit: resultLimit);
await corpus.asyncSuffix(query, limit: resultLimit, highlight: true);
await corpus.asyncSuffixRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'exact',
      'Matches the complete key.',
      '完整键匹配。',
      readmeItem,
      (c, q) => c.exact(q, limit: resultLimit, highlight: true),
      (c, q) => c.exactRaws(q, limit: resultLimit),
      (c, q) => c.asyncExact(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncExactRaws(q, limit: resultLimit),
      '''corpus.exact(query, limit: resultLimit, highlight: true);
corpus.exactRaws(query, limit: resultLimit);
await corpus.asyncExact(query, limit: resultLimit, highlight: true);
await corpus.asyncExactRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'search (fuzzy)',
      'Unified entry: subsequence strategy.',
      '统一入口：子序列策略。',
      _subsequenceQuery,
      (c, q) => c.search(q,
          strategy: SearchStrategy.fuzzy, limit: resultLimit, highlight: true),
      (c, q) =>
          c.searchRaws(q, strategy: SearchStrategy.fuzzy, limit: resultLimit),
      (c, q) => c.asyncSearch(q,
          strategy: SearchStrategy.fuzzy, limit: resultLimit, highlight: true),
      (c, q) => c.asyncSearchRaws(q,
          strategy: SearchStrategy.fuzzy, limit: resultLimit),
      '''corpus.search(query, strategy: SearchStrategy.fuzzy, limit: resultLimit, highlight: true);
corpus.searchRaws(query, strategy: SearchStrategy.fuzzy, limit: resultLimit);
await corpus.asyncSearch(query, strategy: SearchStrategy.fuzzy, limit: resultLimit, highlight: true);
await corpus.asyncSearchRaws(query, strategy: SearchStrategy.fuzzy, limit: resultLimit);'''),
  SearchSpec(
      'search (approx)',
      'Unified entry: edit-distance windows.',
      '统一入口：编辑距离窗口匹配。',
      _typoQuery,
      (c, q) => c.search(q,
          strategy: SearchStrategy.approx, limit: resultLimit, highlight: true),
      (c, q) =>
          c.searchRaws(q, strategy: SearchStrategy.approx, limit: resultLimit),
      (c, q) => c.asyncSearch(q,
          strategy: SearchStrategy.approx, limit: resultLimit, highlight: true),
      (c, q) => c.asyncSearchRaws(q,
          strategy: SearchStrategy.approx, limit: resultLimit),
      '''corpus.search(query, strategy: SearchStrategy.approx, limit: resultLimit, highlight: true);
corpus.searchRaws(query, strategy: SearchStrategy.approx, limit: resultLimit);
await corpus.asyncSearch(query, strategy: SearchStrategy.approx, limit: resultLimit, highlight: true);
await corpus.asyncSearchRaws(query, strategy: SearchStrategy.approx, limit: resultLimit);'''),
  SearchSpec(
      'search (fallback)',
      'Falls back only when fuzzy finds nothing.',
      '仅在子序列无命中时回退近似搜索。',
      _typoQuery,
      (c, q) => c.search(q,
          strategy: SearchStrategy.fallback,
          limit: resultLimit,
          highlight: true),
      (c, q) => c.searchRaws(q,
          strategy: SearchStrategy.fallback, limit: resultLimit),
      (c, q) => c.asyncSearch(q,
          strategy: SearchStrategy.fallback,
          limit: resultLimit,
          highlight: true),
      (c, q) => c.asyncSearchRaws(q,
          strategy: SearchStrategy.fallback, limit: resultLimit),
      '''corpus.search(query, strategy: SearchStrategy.fallback, limit: resultLimit, highlight: true);
corpus.searchRaws(query, strategy: SearchStrategy.fallback, limit: resultLimit);
await corpus.asyncSearch(query, strategy: SearchStrategy.fallback, limit: resultLimit, highlight: true);
await corpus.asyncSearchRaws(query, strategy: SearchStrategy.fallback, limit: resultLimit);'''),
  SearchSpec(
      'search (merge)',
      'Fuzzy hits first, then deduplicated approx hits.',
      '子序列命中优先，再追加去重的近似命中。',
      _typoQuery,
      (c, q) => c.search(q,
          strategy: SearchStrategy.merge, limit: resultLimit, highlight: true),
      (c, q) =>
          c.searchRaws(q, strategy: SearchStrategy.merge, limit: resultLimit),
      (c, q) => c.asyncSearch(q,
          strategy: SearchStrategy.merge, limit: resultLimit, highlight: true),
      (c, q) => c.asyncSearchRaws(q,
          strategy: SearchStrategy.merge, limit: resultLimit),
      '''corpus.search(query, strategy: SearchStrategy.merge, limit: resultLimit, highlight: true);
corpus.searchRaws(query, strategy: SearchStrategy.merge, limit: resultLimit);
await corpus.asyncSearch(query, strategy: SearchStrategy.merge, limit: resultLimit, highlight: true);
await corpus.asyncSearchRaws(query, strategy: SearchStrategy.merge, limit: resultLimit);'''),
  SearchSpec(
      'approx',
      'Typo-tolerant substring; up to 64 codepoints.',
      '容错子串搜索；查询最多 64 个码点。',
      _typoQuery,
      (c, q) => c.approx(q, limit: resultLimit, highlight: true),
      (c, q) => c.approxRaws(q, limit: resultLimit),
      (c, q) => c.asyncApprox(q, limit: resultLimit, highlight: true),
      (c, q) => c.asyncApproxRaws(q, limit: resultLimit),
      '''corpus.approx(query, limit: resultLimit, highlight: true);
corpus.approxRaws(query, limit: resultLimit);
await corpus.asyncApprox(query, limit: resultLimit, highlight: true);
await corpus.asyncApproxRaws(query, limit: resultLimit);'''),
  SearchSpec(
      'dual',
      'Returns separate fuzzy and approx groups.',
      '分别返回子序列与近似结果组。',
      _typoQuery,
      (c, q) => c.dual(q, limit: resultLimit, highlight: true),
      null,
      (c, q) => c.asyncDual(q, limit: resultLimit, highlight: true),
      null, '''corpus.dual(query, limit: resultLimit, highlight: true);
await corpus.asyncDual(query, limit: resultLimit, highlight: true);'''),
];
