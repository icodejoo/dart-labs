// Shared corpus logic: state management, all public API, pure-Dart fallback search.
// Exported by platform files with `hide FuzzyCorpusProtected`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'ffuzzy_types.dart';

const _disposedMessage = 'FuzzyCorpus used after dispose()';

// ── Mode codes ────────────────────────────────────────────────────────────────

const int mFuzzy = 0;
const int mSubstring = 1;
const int mPrefix = 2;
const int mPostfix = 3;
const int mExact = 4;

// ── Helpers ───────────────────────────────────────────────────────────────────

// 编码为真实长度的字节串，空串保持零长度以匹配全部条目。
Uint8List toUtf8(String s) => Uint8List.fromList(utf8.encode(s));

bool _hasUpper(String s) => s != s.toLowerCase();

String _foldQuery(String q, FuzzyCase cm) {
  final up = _hasUpper(q);
  return switch (cm) {
    FuzzyCase.respect => q,
    FuzzyCase.ignore => q.toLowerCase(),
    FuzzyCase.smart => up ? q : q.toLowerCase(),
  };
}

String _foldText(String t, FuzzyCase cm, bool qUp) => switch (cm) {
      FuzzyCase.respect => t,
      FuzzyCase.ignore => t.toLowerCase(),
      FuzzyCase.smart => qUp ? t : t.toLowerCase(),
    };

// ── Pure-Dart fallback for non-fuzzy modes ────────────────────────────────────

const _maxEditDistance = 10;
const _maxEditQuery = 64;

// 统一校验编辑距离范围及单字算法的查询长度。
int _editDistance(String q, int? distance, {bool approximate = true}) {
  final dist = distance ?? autoMaxDistance(q);
  if (dist < 0 || dist > _maxEditDistance) {
    throw RangeError.range(dist, 0, _maxEditDistance, 'maxDistance');
  }
  if (approximate && q.runes.length > _maxEditQuery) {
    throw ArgumentError.value(q, 'query',
        'approximate search supports at most $_maxEditQuery codepoints');
  }
  return dist;
}

// 保留公开的纯 Dart 字面量搜索兼容入口。
List<FuzzyHit<T>> dartSearch<T>(List<T> items, String Function(T) stringOf,
    int mode, String query, FuzzyOptions o) {
  final up = _hasUpper(query);
  final fq = _foldQuery(query, o.caseMatching);
  final lim = o.limit > 0 ? o.limit : items.length;
  final out = <FuzzyHit<T>>[];
  for (var i = 0; i < items.length && out.length < lim; i++) {
    final t = _foldText(stringOf(items[i]), o.caseMatching, up);
    final match = switch (mode) {
      mSubstring => t.contains(fq),
      mPrefix => t.startsWith(fq),
      mPostfix => t.endsWith(fq),
      mExact => t == fq,
      _ => false,
    };
    if (match) {
      out.add(
          FuzzyHit<T>(items[i], i, 0, FuzzyKeyKind.original, 0, 0, const []));
    }
  }
  return out;
}

// 返回公开纯 Dart 搜索的原始条目。
List<T> dartSearchRaws<T>(List<T> items, String Function(T) stringOf, int mode,
        String query, FuzzyOptions o) =>
    [for (final h in dartSearch(items, stringOf, mode, query, o)) h.raw];

// ── Abstract base (hidden from public API) ────────────────────────────────────

/// Shared corpus implementation. Platform files (`ffuzzy_ffi.dart`,
/// `ffuzzy_web.dart`) extend this and implement the `c*_` bridge methods.
///
/// Fields with a trailing `_` are implementation-internal — not public API —
/// but must be non-private so platform subclasses in separate libraries can
/// access them via inheritance.
abstract base class FuzzyCorpusProtected<T> {
  FuzzyCorpusProtected({
    required this.options,
    required this.stringOf_,
  });

  final FuzzyOptions options;

  // ignore: non_constant_identifier_names
  final String Function(T) stringOf_;

  // ── Protected state ───────────────────────────────────────────────────────

  // ignore: non_constant_identifier_names
  final List<T> items_ = [];
  // ignore: non_constant_identifier_names
  final List<List<FuzzyKey>?> keys_ = [];
  // ignore: non_constant_identifier_names
  bool disposed_ = false;
  // ignore: non_constant_identifier_names
  bool freed_ = false;
  // ignore: non_constant_identifier_names
  int inFlight_ = 0;
  // ignore: non_constant_identifier_names
  bool building_ = false;
  // ignore: non_constant_identifier_names
  Completer<void>? idle_;
  // ignore: non_constant_identifier_names
  bool cDeferred_ =
      false; // true when constructed before C backend is ready (web only)

  // ── Bridge (C / WASM) — implemented by platform subclass ─────────────────

  // 新增原始键，失败时抛错并阻止宿主提交条目。
  void cAdd_(Uint8List bytes);
  void cAddKeyed_(Uint8List primary, List<FuzzyKey> keys);
  void cClear_();
  // 释放平台语料库。
  void cFree_();

  // 执行指定模式的同步搜索。
  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o);
  List<T> searchRaws_(int mode, String q, FuzzyOptions o);
  // 执行异步搜索并跟踪在途调用。
  Future<List<FuzzyHit<T>>> searchAsync_(int mode, String q, FuzzyOptions o);
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o);
  // 执行编辑距离搜索并按需读取高亮。
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o);

  // C-side bridges — always implemented by platform subclass.
  // 执行子序列与近似结果合并搜索。
  List<FuzzyHit<T>> searchMerge_(String q, int maxDist, FuzzyOptions o);
  List<FuzzyHit<T>> searchFallback_(String q, int maxDist, FuzzyOptions o);
  // 分别读取子序列与近似搜索结果。
  FuzzyDualResult<T> searchDualC_(String q, int maxDist, FuzzyOptions o);

  // Async counterparts of searchEdit_/searchMerge_/searchFallback_/searchDualC_
  // above. On native these genuinely offload to a worker isolate (like
  // searchAsync_); on web, WASM calls are inherently synchronous, so these
  // just await engine readiness before calling the sync path.
  // 异步执行编辑距离搜索。
  Future<List<FuzzyHit<T>>> searchEditAsync_(
      String q, int maxDist, FuzzyOptions o);
  // 异步执行合并搜索。
  Future<List<FuzzyHit<T>>> searchMergeAsync_(
      String q, int maxDist, FuzzyOptions o);
  // 异步执行回退搜索。
  Future<List<FuzzyHit<T>>> searchFallbackAsync_(
      String q, int maxDist, FuzzyOptions o);
  // 异步执行双路搜索。
  Future<FuzzyDualResult<T>> searchDualAsync_(
      String q, int maxDist, FuzzyOptions o);

  // Lazy-init hooks — web overrides to trigger _ensureReady(); FFI is always ready (no-op).
  // ignore: non_constant_identifier_names
  // 同步检查并补建延迟索引。
  void syncEnsureReady_() {}
  // ignore: non_constant_identifier_names
  // 等待平台引擎就绪并检查语料库生命周期。
  Future<void> asyncEnsureReady_() async {}

  // ── Shared internals ──────────────────────────────────────────────────────

  // 拒绝已销毁或正在构建的语料库操作。
  void check_() {
    if (disposed_) throw StateError(_disposedMessage);
    if (building_) throw StateError('FuzzyCorpus used while build in progress');
  }

  void checkMutate_() {
    check_();
    if (inFlight_ > 0) {
      throw StateError(
          'FuzzyCorpus mutated while $inFlight_ search(es) in flight');
    }
  }

  void signalIfIdle_() {
    if (inFlight_ == 0 && !building_ && idle_ != null) {
      idle_!.complete();
      idle_ = null;
    }
  }

  FuzzyOptions eff_(FuzzyCase? cm, FuzzyNorm? nm, bool? par, int? th, int? lim,
          bool? hl, FuzzyScoring? sc) =>
      options.copyWith(
          caseMatching: cm,
          normalization: nm,
          parallel: par,
          threads: th,
          limit: lim,
          highlight: hl,
          scoring: sc);

  // 提取文本后复查生命周期，再写入平台索引。
  void nAdd_(T item, List<FuzzyKey>? keys) {
    final bytes = toUtf8(stringOf_(item));
    if (disposed_) throw StateError(_disposedMessage);
    if (keys == null || keys.isEmpty) {
      cAdd_(bytes);
    } else {
      cAddKeyed_(bytes, keys);
    }
  }

  // 重建平台索引，失败时将宿主截断到已提交条目。
  void rebuild_() {
    cClear_();
    for (var i = 0; i < items_.length; i++) {
      try {
        nAdd_(items_[i], keys_[i]);
      } catch (_) {
        items_.length = i;
        keys_.length = i;
        rethrow;
      }
    }
  }

  // ── Public mutation API ───────────────────────────────────────────────────

  int get length {
    check_();
    return items_.length;
  }

  // 写入平台成功后追加宿主条目。
  void add(T item) {
    checkMutate_();
    nAdd_(item, null);
    items_.add(item);
    keys_.add(null);
  }

  // 逐条新增并保留已成功提交的前缀。
  void addAll(Iterable<T> items) {
    checkMutate_();
    for (final item in items) {
      nAdd_(item, null);
      items_.add(item);
      keys_.add(null);
    }
  }

  // 复制附加键并在平台写入成功后提交宿主记录。
  void addKey(T item, List<FuzzyKey> keys) {
    checkMutate_();
    final ks = keys.isEmpty ? null : List<FuzzyKey>.of(keys);
    nAdd_(item, ks);
    items_.add(item);
    keys_.add(ks);
  }

  // 替换条目后重建索引。
  void update(int index, T item) {
    checkMutate_();
    final hadKeys = keys_[index] != null;
    items_[index] = item;
    keys_[index] = null;
    rebuild_();
    if (hadKeys) {
      // Mutation above already ran identically in debug and release — the
      // assert below is a loud after-the-fact warning, not a gate, so this
      // method's effect never forks by build mode.
      final msg = '[ffuzzy] update() discarded alternate keys at $index; '
          'use removeAt() + addKey() instead.';
      assert(false, msg);
      debugPrint(msg);
    }
  }

  // 删除指定条目后重建索引。
  void removeAt(int index) {
    checkMutate_();
    items_.removeAt(index);
    keys_.removeAt(index);
    rebuild_();
  }

  // 先完成筛选再删除，避免回调失败留下半次修改。
  int removeWhere(bool Function(T item) test) {
    checkMutate_();
    final indices = <int>[];
    for (var i = items_.length - 1; i >= 0; i--) {
      if (test(items_[i])) indices.add(i);
    }
    checkMutate_();
    for (final i in indices) {
      items_.removeAt(i);
      keys_.removeAt(i);
    }
    if (indices.isNotEmpty) rebuild_();
    return indices.length;
  }

  // 先收集新条目再替换宿主数据并重建索引。
  void refresh([Iterable<T>? source]) {
    checkMutate_();
    if (source != null) {
      final items = List<T>.of(source);
      checkMutate_();
      items_
        ..clear()
        ..addAll(items);
      keys_
        ..clear()
        ..addAll(List<List<FuzzyKey>?>.filled(items.length, null));
    }
    rebuild_();
  }

  void clear() {
    checkMutate_();
    items_.clear();
    keys_.clear();
    cClear_();
  }

  // ── Public search API (all 24 methods, shared) ────────────────────────────

  /// fzf-style subsequence search. Shorthand for `search(q, strategy: SearchStrategy.fuzzy)`.
  List<FuzzyHit<T>> fuzzy(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      search(q,
          strategy: SearchStrategy.fuzzy,
          caseMatching: caseMatching,
          normalization: normalization,
          parallel: parallel,
          threads: threads,
          limit: limit,
          highlight: highlight,
          scoring: scoring);

  List<FuzzyHit<T>> substring(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      search_(
          mSubstring,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  List<FuzzyHit<T>> prefix(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      search_(
          mPrefix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  List<FuzzyHit<T>> postfix(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      search_(
          mPostfix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  List<FuzzyHit<T>> suffix(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      postfix(q,
          caseMatching: caseMatching,
          normalization: normalization,
          parallel: parallel,
          threads: threads,
          limit: limit,
          highlight: highlight,
          scoring: scoring);

  List<FuzzyHit<T>> exact(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      search_(
          mExact,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  List<T> fuzzyRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRaws_(
          mFuzzy,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  List<T> substringRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRaws_(
          mSubstring,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  List<T> prefixRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRaws_(
          mPrefix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  List<T> postfixRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRaws_(
          mPostfix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  List<T> suffixRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      postfixRaws(q,
          caseMatching: caseMatching,
          normalization: normalization,
          parallel: parallel,
          threads: threads,
          limit: limit,
          scoring: scoring);

  List<T> exactRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRaws_(
          mExact,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  /// Approximate SUBSTRING search: finds items containing a window whose
  /// edit distance to [q] is within [maxDistance] — the window may start/end
  /// anywhere in the item's text, it is NOT anchored to the whole string (so
  /// a short typo'd [q] can match inside a much longer item). Shorthand for
  /// `search(q, strategy: SearchStrategy.approx)`.
  ///
  /// 近似子串搜索：查找包含某个窗口的条目，该窗口与 [q] 的编辑距离不超过
  /// [maxDistance] —— 该窗口可以从条目文本中的任意位置开始/结束，并不锚定到
  /// 整个字符串（因此一个较短的、带有拼写错误的 [q] 也能匹配到一个长得多的
  /// 条目内部）。是 `search(q, strategy: SearchStrategy.approx)` 的简写。
  ///
  /// [maxDistance] defaults to [autoMaxDistance] when omitted (auto-scaled by
  /// query length — note this scales with the QUERY's length, not the
  /// window's, so it stays meaningful regardless of how long the item is).
  ///
  /// 省略 [maxDistance] 时默认使用 [autoMaxDistance]（根据查询长度自动缩放
  /// ——注意这里是按“查询”的长度缩放，而不是窗口的长度，因此无论条目本身
  /// 有多长，该值都始终有意义）。
  ///
  /// When [highlight] is true, [FuzzyHit.indices] is populated with every
  /// codepoint position in the matched window (a contiguous range) rather
  /// than the discrete positions [fuzzy] reports.
  ///
  /// 当 [highlight] 为 true 时，[FuzzyHit.indices] 会被填充为匹配窗口内的
  /// 每一个码点位置（一个连续区间），而不是 [fuzzy] 所报告的离散位置。
  /// 编辑距离须在零到十之间；涉及近似匹配的查询最多六十四个码点，超限抛参数异常。
  List<FuzzyHit<T>> approx(String q,
          {int? maxDistance,
          FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          int? limit,
          bool? highlight}) =>
      searchEdit_(
          q,
          _editDistance(q, maxDistance),
          eff_(
              caseMatching, normalization, null, null, limit, highlight, null));

  /// Unified search entry point. Defaults to fzf-style subsequence (`strategy: SearchStrategy.fuzzy`).
  ///
  /// 统一的搜索入口。默认使用 fzf 风格的子序列匹配（`strategy: SearchStrategy.fuzzy`）。
  ///
  /// - [SearchStrategy.fuzzy]    — subsequence match (same as [fuzzy])
  /// - [SearchStrategy.approx]   — edit-distance; [maxDistance] auto-scaled when omitted
  /// - [SearchStrategy.fallback] — subsequence first; falls back to edit-distance if empty
  /// - [SearchStrategy.merge]    — both algorithms; subsequence hits first, then approx-only hits
  ///
  /// - [SearchStrategy.fuzzy]    —— 子序列匹配（等同于 [fuzzy]）
  /// - [SearchStrategy.approx]   —— 编辑距离匹配；省略 [maxDistance] 时自动缩放
  /// - [SearchStrategy.fallback] —— 优先子序列匹配；结果为空时回退到编辑距离匹配
  /// - [SearchStrategy.merge]    —— 同时使用两种算法；子序列命中在前，仅编辑距离命中的结果在后
  /// 编辑距离须在零到十之间；涉及近似匹配的查询最多六十四个码点，超限抛参数异常。
  List<FuzzyHit<T>> search(
    String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    bool? highlight,
    FuzzyScoring? scoring,
  }) {
    final o = eff_(caseMatching, normalization, parallel, threads, limit,
        highlight, scoring);
    final dist = _editDistance(q, maxDistance,
        approximate: strategy != SearchStrategy.fuzzy);
    return switch (strategy) {
      SearchStrategy.fuzzy => search_(mFuzzy, q, o),
      SearchStrategy.approx => searchEdit_(q, dist, o),
      SearchStrategy.fallback => _fallback(q, dist, o),
      SearchStrategy.merge => _merge(q, dist, o),
    };
  }

  /// Runs both algorithms independently and returns their results in separate buckets.
  ///
  /// 独立运行两种算法，并将各自的结果分别放入不同的结果桶中返回。
  ///
  /// [maxDistance] defaults to [autoMaxDistance] when omitted.
  ///
  /// 省略 [maxDistance] 时默认使用 [autoMaxDistance]。
  /// 编辑距离须在零到十之间；涉及近似匹配的查询最多六十四个码点，超限抛参数异常。
  FuzzyDualResult<T> dual(
    String q, {
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    bool? highlight,
    FuzzyScoring? scoring,
  }) {
    final dist = _editDistance(q, maxDistance);
    check_();
    syncEnsureReady_();
    final o = eff_(caseMatching, normalization, parallel, threads, limit,
        highlight, scoring);
    if (cDeferred_) return FuzzyDualResult(fuzzy: const [], approx: const []);
    return searchDualC_(q, dist, o);
  }

  // 子序列无命中时回退到编辑距离搜索。
  List<FuzzyHit<T>> _fallback(String q, int maxDist, FuzzyOptions o) {
    check_();
    syncEnsureReady_();
    if (cDeferred_) return const [];
    return searchFallback_(q, maxDist, o);
  }

  // 合并子序列命中与近似命中。
  List<FuzzyHit<T>> _merge(String q, int maxDist, FuzzyOptions o) {
    check_();
    syncEnsureReady_();
    if (cDeferred_) return const [];
    return searchMerge_(q, maxDist, o);
  }

  Future<List<FuzzyHit<T>>> asyncFuzzy(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      searchAsync_(
          mFuzzy,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  Future<List<FuzzyHit<T>>> asyncSubstring(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      searchAsync_(
          mSubstring,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  Future<List<FuzzyHit<T>>> asyncPrefix(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      searchAsync_(
          mPrefix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  Future<List<FuzzyHit<T>>> asyncPostfix(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      searchAsync_(
          mPostfix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  Future<List<FuzzyHit<T>>> asyncSuffix(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      asyncPostfix(q,
          caseMatching: caseMatching,
          normalization: normalization,
          parallel: parallel,
          threads: threads,
          limit: limit,
          highlight: highlight,
          scoring: scoring);

  Future<List<FuzzyHit<T>>> asyncExact(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          bool? highlight,
          FuzzyScoring? scoring}) =>
      searchAsync_(
          mExact,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, highlight,
              scoring));

  Future<List<T>> asyncFuzzyRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRawsAsync_(
          mFuzzy,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  Future<List<T>> asyncSubstringRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRawsAsync_(
          mSubstring,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  Future<List<T>> asyncPrefixRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRawsAsync_(
          mPrefix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  Future<List<T>> asyncPostfixRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRawsAsync_(
          mPostfix,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  Future<List<T>> asyncSuffixRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      asyncPostfixRaws(q,
          caseMatching: caseMatching,
          normalization: normalization,
          parallel: parallel,
          threads: threads,
          limit: limit,
          scoring: scoring);

  Future<List<T>> asyncExactRaws(String q,
          {FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          bool? parallel,
          int? threads,
          int? limit,
          FuzzyScoring? scoring}) =>
      searchRawsAsync_(
          mExact,
          q,
          eff_(caseMatching, normalization, parallel, threads, limit, false,
              scoring));

  // ── search / approx / dual variants ──────────────────────────────────────

  List<T> searchRaws(
    String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    FuzzyScoring? scoring,
  }) =>
      [
        for (final h in search(q,
            strategy: strategy,
            maxDistance: maxDistance,
            caseMatching: caseMatching,
            normalization: normalization,
            parallel: parallel,
            threads: threads,
            limit: limit,
            scoring: scoring))
          h.raw
      ];

  // Dispatches to the per-strategy *Async_ bridge method (searchAsync_ /
  // searchEditAsync_ / searchFallbackAsync_ / searchMergeAsync_), each of
  // which genuinely offloads to a worker isolate on native and awaits engine
  // readiness on web — unlike simply calling the synchronous `search()`
  // inside an async function, which still blocks the calling isolate/thread
  // for the whole native call.
  /// 编辑距离须在零到十之间；涉及近似匹配的查询最多六十四个码点，超限抛参数异常。
  Future<List<FuzzyHit<T>>> asyncSearch(
    String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    bool? highlight,
    FuzzyScoring? scoring,
  }) async {
    final dist = _editDistance(q, maxDistance,
        approximate: strategy != SearchStrategy.fuzzy);
    await asyncEnsureReady_();
    check_();
    final o = eff_(caseMatching, normalization, parallel, threads, limit,
        highlight, scoring);
    return switch (strategy) {
      SearchStrategy.fuzzy => searchAsync_(mFuzzy, q, o),
      SearchStrategy.approx => searchEditAsync_(q, dist, o),
      SearchStrategy.fallback => searchFallbackAsync_(q, dist, o),
      SearchStrategy.merge => searchMergeAsync_(q, dist, o),
    };
  }

  Future<List<T>> asyncSearchRaws(
    String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    FuzzyScoring? scoring,
  }) async {
    final hits = await asyncSearch(q,
        strategy: strategy,
        maxDistance: maxDistance,
        caseMatching: caseMatching,
        normalization: normalization,
        parallel: parallel,
        threads: threads,
        limit: limit,
        highlight: false,
        scoring: scoring);
    return [for (final h in hits) h.raw];
  }

  List<T> approxRaws(String q,
          {int? maxDistance,
          FuzzyCase? caseMatching,
          FuzzyNorm? normalization,
          int? limit}) =>
      [
        for (final h in approx(q,
            maxDistance: maxDistance,
            caseMatching: caseMatching,
            normalization: normalization,
            limit: limit))
          h.raw
      ];

  /// 编辑距离须在零到十之间；涉及近似匹配的查询最多六十四个码点，超限抛参数异常。
  Future<List<FuzzyHit<T>>> asyncApprox(
    String q, {
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    int? limit,
    bool? highlight,
  }) {
    check_();
    final dist = _editDistance(q, maxDistance);
    final o =
        eff_(caseMatching, normalization, null, null, limit, highlight, null);
    return searchEditAsync_(q, dist, o);
  }

  Future<List<T>> asyncApproxRaws(
    String q, {
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    int? limit,
  }) async {
    final hits = await asyncApprox(q,
        maxDistance: maxDistance,
        caseMatching: caseMatching,
        normalization: normalization,
        limit: limit,
        highlight: false);
    return [for (final h in hits) h.raw];
  }

  /// 编辑距离须在零到十之间；涉及近似匹配的查询最多六十四个码点，超限抛参数异常。
  Future<FuzzyDualResult<T>> asyncDual(
    String q, {
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    bool? highlight,
    FuzzyScoring? scoring,
  }) async {
    final dist = _editDistance(q, maxDistance);
    await asyncEnsureReady_();
    check_();
    final o = eff_(caseMatching, normalization, parallel, threads, limit,
        highlight, scoring);
    if (cDeferred_) return FuzzyDualResult(fuzzy: const [], approx: const []);
    return searchDualAsync_(q, dist, o);
  }
}
