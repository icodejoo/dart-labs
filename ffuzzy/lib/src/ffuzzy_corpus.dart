// Shared corpus logic: state management, all public API, pure-Dart fallback search.
// Exported by platform files with `hide FuzzyCorpusProtected`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'ffuzzy_types.dart';

// 销毁后访问的错误信息。
const _disposedMessage = 'FuzzyCorpus used after dispose()';

// ── Mode codes ────────────────────────────────────────────────────────────────

/// 子序列搜索模式编号。
const int mFuzzy = 0;
/// 子串搜索模式编号。
const int mSubstring = 1;
/// 前缀搜索模式编号。
const int mPrefix = 2;
/// 后缀搜索模式编号。
const int mPostfix = 3;
/// 完整匹配模式编号。
const int mExact = 4;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// 将 [s] 编码为 UTF-8 字节，返回真实长度的字节串。
///
/// 示例：`toUtf8("你好")` 返回六个字节。
Uint8List toUtf8(String s) => Uint8List.fromList(utf8.encode(s));

bool _hasUpper(String s) => s != s.toLowerCase();

// 根据大小写规则转换查询文本。
String _foldQuery(String q, FuzzyCase cm) {
  final up = _hasUpper(q);
  return switch (cm) {
    FuzzyCase.respect => q,
    FuzzyCase.ignore => q.toLowerCase(),
    FuzzyCase.smart => up ? q : q.toLowerCase(),
  };
}

// 根据大小写规则及查询特征转换候选文本。
String _foldText(String t, FuzzyCase cm, bool qUp) => switch (cm) {
      FuzzyCase.respect => t,
      FuzzyCase.ignore => t.toLowerCase(),
      FuzzyCase.smart => qUp ? t : t.toLowerCase(),
    };

// ── Pure-Dart fallback for non-fuzzy modes ────────────────────────────────────

// 允许的最大编辑距离。
const _maxEditDistance = 10;
// 近似查询允许的最大码点数。
const _maxEditQuery = 64;

// 返回显式或自动距离；距离不在零至十时抛 RangeError，近似查询超六十四码点时抛 ArgumentError。
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

/// 按字面模式搜索 [items]；[stringOf] 提取文本，[mode] 为子串、前后缀或完整匹配编号。
/// [query] 为查询，[o] 控制大小写和数量；返回按原顺序排列、无高亮的命中，未知模式返回空列表。
///
/// 示例：`dartSearch(["你好"], (s) => s, mPrefix, "你", const FuzzyOptions())`。
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

/// 按 [mode] 和 [query] 搜索 [items]，通过 [stringOf] 提取文本，[o] 控制大小写和数量。
/// 返回命中的原始条目；未知模式返回空列表。
///
/// 示例：`dartSearchRaws(["你好"], (s) => s, mExact, "你好", const FuzzyOptions())`。
List<T> dartSearchRaws<T>(List<T> items, String Function(T) stringOf, int mode,
        String query, FuzzyOptions o) =>
    [for (final h in dartSearch(items, stringOf, mode, query, o)) h.raw];

// ── Abstract base (hidden from public API) ────────────────────────────────────

// 管理共享语料状态，由平台子类提供引擎桥接。
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
  // 网页引擎就绪前仅缓存宿主条目。
  // ignore: non_constant_identifier_names
  bool cDeferred_ =
      false; // true when constructed before C backend is ready (web only)

  // ── Bridge (C / WASM) — implemented by platform subclass ─────────────────

  // 新增原始键，失败时抛错并阻止宿主提交条目。
  void cAdd_(Uint8List bytes);
  // 写入原始文本和附加键，失败抛错。
  void cAddKeyed_(Uint8List primary, List<FuzzyKey> keys);
  // 清空平台索引。
  void cClear_();
  // 释放平台语料库。
  void cFree_();

  // 执行指定模式的同步搜索。
  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o);
  // 读取指定模式的原始条目。
  List<T> searchRaws_(int mode, String q, FuzzyOptions o);
  // 执行异步搜索并跟踪在途调用。
  Future<List<FuzzyHit<T>>> searchAsync_(int mode, String q, FuzzyOptions o);
  // 异步读取指定模式的原始条目。
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o);
  // 执行编辑距离搜索并按需读取高亮。
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o);

  // C-side bridges — always implemented by platform subclass.
  // 执行子序列与近似结果合并搜索。
  List<FuzzyHit<T>> searchMerge_(String q, int maxDist, FuzzyOptions o);
  // 无子序列命中时执行近似搜索。
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
  // 同步检查并补建延迟索引。
  // ignore: non_constant_identifier_names
  void syncEnsureReady_() {}
  // 等待平台引擎就绪并检查语料库生命周期。
  // ignore: non_constant_identifier_names
  Future<void> asyncEnsureReady_() async {}

  // ── Shared internals ──────────────────────────────────────────────────────

  // 拒绝已销毁或正在构建的语料库操作。
  void check_() {
    if (disposed_) throw StateError(_disposedMessage);
    if (building_) throw StateError('FuzzyCorpus used while build in progress');
  }

  // 检查修改权限，拒绝在途搜索期间修改。
  void checkMutate_() {
    check_();
    if (inFlight_ > 0) {
      throw StateError(
          'FuzzyCorpus mutated while $inFlight_ search(es) in flight');
    }
  }

  // 空闲时通知等待资源释放的调用方。
  void signalIfIdle_() {
    if (inFlight_ == 0 && !building_ && idle_ != null) {
      idle_!.complete();
      idle_ = null;
    }
  }

  // 合并本次覆盖项与语料库默认选项。
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

  /// 返回当前条目数；销毁后或构建中访问抛 StateError。
  /// 无参数。
  ///
  /// 示例：`corpus.length`。
  int get length {
    check_();
    return items_.length;
  }

  /// 新增 [item]；写入失败保留已有条目。
  /// [item] 为待加入条目。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.add("你好")`。
  void add(T item) {
    checkMutate_();
    nAdd_(item, null);
    items_.add(item);
    keys_.add(null);
  }

  /// 依次新增条目；失败时保留已成功加入的前缀。
  /// [items] 为待加入条目。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.addAll(["你好"])`。
  void addAll(Iterable<T> items) {
    checkMutate_();
    for (final item in items) {
      nAdd_(item, null);
      items_.add(item);
      keys_.add(null);
    }
  }

  /// 新增带附加搜索键的条目。
  /// [item] 为条目，[keys] 为附加键；原始键自动保留。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.addKey("你好", [FuzzyKey("nihao")])`。
  void addKey(T item, List<FuzzyKey> keys) {
    checkMutate_();
    final ks = keys.isEmpty ? null : List<FuzzyKey>.of(keys);
    nAdd_(item, ks);
    items_.add(item);
    keys_.add(ks);
  }

  /// 替换条目并清除其附加键；索引越界抛 RangeError。
  /// [index] 为从零开始的索引，[item] 为新条目；调试模式下替换附加键条目会触发断言。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.update(0, "你好")`。
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

  /// 删除条目；索引越界抛 RangeError。
  /// [index] 为从零开始的索引。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.removeAt(0)`。
  void removeAt(int index) {
    checkMutate_();
    items_.removeAt(index);
    keys_.removeAt(index);
    rebuild_();
  }

  /// 删除满足条件的条目并返回删除数量；回调失败时不提交本次筛选。
  /// [test] 为删除条件，回调异常向上传递。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.removeWhere((s) => s.isEmpty)`。
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

  /// 更新语料并清除新来源的附加键；省略来源时保留现有键，重建失败时条目截断为已写入的前缀。
  /// [source] 为新条目，可省略以刷新当前条目。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.refresh(["你好"])`。
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

  /// 清空语料库。
  /// 无参数。
  /// 销毁后、构建中或搜索未完成时修改抛 StateError。
  ///
  /// 示例：`corpus.clear()`。
  void clear() {
    checkMutate_();
    items_.clear();
    keys_.clear();
    cClear_();
  }

  // ── Public search API (all 24 methods, shared) ────────────────────────────

  /// 子序列搜索；[q] 为查询，返回命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.fuzzy("你好")`。
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

  /// 子串搜索；[q] 为查询，返回命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.substring("你好")`。
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

  /// 前缀搜索；[q] 为查询，返回命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.prefix("你好")`。
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

  /// 后缀搜索；[q] 为查询，返回命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.postfix("你好")`。
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

  /// 后缀搜索，[postfix] 的别名；[q] 为查询，返回命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.suffix("你好")`。
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

  /// 完整文本搜索；[q] 为查询，返回命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.exact("你好")`。
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

  /// 子序列搜索；[q] 为查询，返回原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.fuzzyRaws("你好")`。
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

  /// 子串搜索；[q] 为查询，返回原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.substringRaws("你好")`。
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

  /// 前缀搜索；[q] 为查询，返回原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.prefixRaws("你好")`。
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

  /// 后缀搜索；[q] 为查询，返回原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.postfixRaws("你好")`。
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

  /// 后缀搜索，[postfix] 的别名；[q] 为查询，返回原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.suffixRaws("你好")`。
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

  /// 完整文本搜索；[q] 为查询，返回原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.exactRaws("你好")`。
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

  /// 近似子串搜索；[q] 为查询，返回命中列表。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.approx("你好")`。
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

  /// 统一搜索；[q] 为查询，返回命中列表。
  /// [strategy] 选择子序列、近似、无子序列命中时回退或合并，默认子序列。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.search("你好")`。
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

  /// 双路搜索；[q] 为查询，返回两组独立命中。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.dual("你好")`。
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

  /// 子序列搜索；[q] 为查询，返回异步完成的命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncFuzzy("你好")`。
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

  /// 子串搜索；[q] 为查询，返回异步完成的命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncSubstring("你好")`。
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

  /// 前缀搜索；[q] 为查询，返回异步完成的命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncPrefix("你好")`。
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

  /// 后缀搜索；[q] 为查询，返回异步完成的命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncPostfix("你好")`。
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

  /// 后缀搜索，[postfix] 的别名；[q] 为查询，返回异步完成的命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncSuffix("你好")`。
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

  /// 完整文本搜索；[q] 为查询，返回异步完成的命中列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncExact("你好")`。
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

  /// 子序列搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncFuzzyRaws("你好")`。
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

  /// 子串搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncSubstringRaws("你好")`。
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

  /// 前缀搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncPrefixRaws("你好")`。
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

  /// 后缀搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncPostfixRaws("你好")`。
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

  /// 后缀搜索，[postfix] 的别名；[q] 为查询，返回异步完成的原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncSuffixRaws("你好")`。
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

  /// 完整文本搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncExactRaws("你好")`。
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

  /// 统一搜索；[q] 为查询，返回原始条目列表。
  /// [strategy] 选择子序列、近似、无子序列命中时回退或合并，默认子序列。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.searchRaws("你好")`。
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

  /// 统一搜索；[q] 为查询，返回异步完成的命中列表。
  /// [strategy] 选择子序列、近似、无子序列命中时回退或合并，默认子序列。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncSearch("你好")`。
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

  /// 统一搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [strategy] 选择子序列、近似、无子序列命中时回退或合并，默认子序列。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncSearchRaws("你好")`。
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

  /// 近似子串搜索；[q] 为查询，返回原始条目列表。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[limit] 为结果上限，非正数表示不限，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`corpus.approxRaws("你好")`。
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

  /// 近似子串搜索；[q] 为查询，返回异步完成的命中列表。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncApprox("你好")`。
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

  /// 近似子串搜索；[q] 为查询，返回异步完成的原始条目列表。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[limit] 为结果上限，非正数表示不限，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncApproxRaws("你好")`。
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

  /// 双路搜索；[q] 为查询，返回异步完成的两组独立命中。
  /// [maxDistance] 省略时按查询码点数自动选择；不在零至十时抛 RangeError。
  /// 近似、回退、合并和双路查询超过六十四码点时抛 ArgumentError。
  /// [caseMatching] 为大小写规则；[normalization] 为归一化规则；[parallel] 为并行开关；[threads] 为线程数，零表示自动；[limit] 为结果上限，非正数表示不限；[highlight] 为是否返回高亮码点下标；[scoring] 为评分方式，省略时沿用语料库选项。
  /// 销毁后、构建中或结果分配失败时抛 StateError；Web 端查询缓冲分配失败抛 FuzzyException，原生端抛 ArgumentError。
  ///
  /// 示例：`await corpus.asyncDual("你好")`。
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
