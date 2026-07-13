// Shared corpus logic: state management, all public API, pure-Dart fallback search.
// Exported by platform files with `hide FuzzyCorpusProtected`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'ffuzzy_types.dart';

// ── Mode codes ────────────────────────────────────────────────────────────────

const int mFuzzy     = 0;
const int mSubstring = 1;
const int mPrefix    = 2;
const int mPostfix   = 3;
const int mExact     = 4;

// ── Helpers ───────────────────────────────────────────────────────────────────

Uint8List toUtf8(String s) {
  if (s.isEmpty) return Uint8List.fromList([0]);
  return Uint8List.fromList(utf8.encode(s));
}

bool _hasUpper(String s) => s != s.toLowerCase();

String _foldQuery(String q, FuzzyCase cm) {
  final up = _hasUpper(q);
  return switch (cm) {
    FuzzyCase.respect => q,
    FuzzyCase.ignore  => q.toLowerCase(),
    FuzzyCase.smart   => up ? q : q.toLowerCase(),
  };
}

String _foldText(String t, FuzzyCase cm, bool qUp) =>
    switch (cm) {
      FuzzyCase.respect => t,
      FuzzyCase.ignore  => t.toLowerCase(),
      FuzzyCase.smart   => qUp ? t : t.toLowerCase(),
    };

// ── Pure-Dart fallback for non-fuzzy modes ────────────────────────────────────

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
      mPrefix    => t.startsWith(fq),
      mPostfix   => t.endsWith(fq),
      mExact     => t == fq,
      _          => false,
    };
    if (match) {
      out.add(FuzzyHit<T>(items[i], i, 0, FuzzyKeyKind.original, 0, 0, const []));
    }
  }
  return out;
}

List<T> dartSearchRaws<T>(List<T> items, String Function(T) stringOf,
    int mode, String query, FuzzyOptions o) =>
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

  // ── Bridge (C / WASM) — implemented by platform subclass ─────────────────

  void cAdd_(Uint8List bytes);
  void cAddKeyed_(Uint8List primary, List<FuzzyKey> keys);
  void cClear_();
  void cFree_();

  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o);
  List<T> searchRaws_(int mode, String q, FuzzyOptions o);
  Future<List<FuzzyHit<T>>> searchAsync_(int mode, String q, FuzzyOptions o);
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o);
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o);

  // C-side bridges — always implemented by platform subclass.
  List<FuzzyHit<T>> searchMerge_(String q, int maxDist, FuzzyOptions o);
  List<FuzzyHit<T>> searchFallback_(String q, int maxDist, FuzzyOptions o);
  FuzzyDualResult<T> searchDualC_(String q, int maxDist, FuzzyOptions o);

  // ── Shared internals ──────────────────────────────────────────────────────

  void check_() {
    if (disposed_) throw StateError('FuzzyCorpus used after dispose()');
    if (building_) throw StateError('FuzzyCorpus used while build in progress');
  }

  void checkMutate_() {
    check_();
    if (inFlight_ > 0) {
      throw StateError('FuzzyCorpus mutated while $inFlight_ search(es) in flight');
    }
  }

  void signalIfIdle_() {
    if (inFlight_ == 0 && !building_ && idle_ != null) {
      idle_!.complete();
      idle_ = null;
    }
  }

  FuzzyOptions eff_(FuzzyCase? cm, FuzzyNorm? nm, bool? par, int? th,
      int? lim, bool? hl, FuzzyScoring? sc) =>
      options.copyWith(
          caseMatching: cm, normalization: nm, parallel: par,
          threads: th, limit: lim, highlight: hl, scoring: sc);

  void nAdd_(T item, List<FuzzyKey>? keys) {
    final bytes = toUtf8(stringOf_(item));
    if (keys == null || keys.isEmpty) {
      cAdd_(bytes);
    } else {
      cAddKeyed_(bytes, keys);
    }
  }

  void rebuild_() {
    cClear_();
    for (var i = 0; i < items_.length; i++) {
      nAdd_(items_[i], keys_[i]);
    }
  }

  // ── Public mutation API ───────────────────────────────────────────────────

  int get length { check_(); return items_.length; }

  void add(T item) {
    checkMutate_();
    nAdd_(item, null);
    items_.add(item);
    keys_.add(null);
  }

  void addAll(Iterable<T> items) {
    checkMutate_();
    for (final item in items) {
      nAdd_(item, null);
      items_.add(item);
      keys_.add(null);
    }
  }

  void addKey(T item, List<FuzzyKey> keys) {
    checkMutate_();
    final ks = keys.isEmpty ? null : keys;
    nAdd_(item, ks);
    items_.add(item);
    keys_.add(ks);
  }

  void update(int index, T item) {
    checkMutate_();
    if (keys_[index] != null) {
      debugPrint('[ffuzzy] update() discards alternate keys at $index; '
          'use removeAt() + addKey() instead.');
    }
    items_[index] = item;
    keys_[index] = null;
    rebuild_();
  }

  void removeAt(int index) {
    checkMutate_();
    items_.removeAt(index);
    keys_.removeAt(index);
    rebuild_();
  }

  int removeWhere(bool Function(T item) test) {
    checkMutate_();
    var removed = 0;
    for (var i = items_.length - 1; i >= 0; i--) {
      if (test(items_[i])) {
        items_.removeAt(i);
        keys_.removeAt(i);
        removed++;
      }
    }
    if (removed > 0) rebuild_();
    return removed;
  }

  void refresh([Iterable<T>? source]) {
    checkMutate_();
    if (source != null) {
      items_..clear()..addAll(source);
      keys_..clear()..addAll(List<List<FuzzyKey>?>.filled(items_.length, null));
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
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      search(q, strategy: SearchStrategy.fuzzy,
          caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit,
          highlight: highlight, scoring: scoring);

  List<FuzzyHit<T>> substring(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      search_(mSubstring, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  List<FuzzyHit<T>> prefix(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      search_(mPrefix, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  List<FuzzyHit<T>> postfix(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      search_(mPostfix, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  List<FuzzyHit<T>> suffix(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      postfix(q, caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit, highlight: highlight, scoring: scoring);

  List<FuzzyHit<T>> exact(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      search_(mExact, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  List<T> fuzzyRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRaws_(mFuzzy, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  List<T> substringRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRaws_(mSubstring, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  List<T> prefixRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRaws_(mPrefix, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  List<T> postfixRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRaws_(mPostfix, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  List<T> suffixRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      postfixRaws(q, caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit, scoring: scoring);

  List<T> exactRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRaws_(mExact, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  /// Edit-distance search. Shorthand for `search(q, strategy: SearchStrategy.approx)`.
  ///
  /// [maxDistance] defaults to [autoMaxDistance] when omitted (auto-scaled by query length).
  List<FuzzyHit<T>> approx(String q,
          {int? maxDistance, FuzzyCase? caseMatching,
          FuzzyNorm? normalization, int? limit}) =>
      searchEdit_(q, maxDistance ?? autoMaxDistance(q),
          eff_(caseMatching, normalization, null, null, limit, false, null));

  /// Unified search entry point. Defaults to fzf-style subsequence (`strategy: SearchStrategy.fuzzy`).
  ///
  /// - [SearchStrategy.fuzzy]    — subsequence match (same as [fuzzy])
  /// - [SearchStrategy.approx]   — edit-distance; [maxDistance] auto-scaled when omitted
  /// - [SearchStrategy.fallback] — subsequence first; falls back to edit-distance if empty
  /// - [SearchStrategy.merge]    — both algorithms; subsequence hits first, then approx-only hits
  List<FuzzyHit<T>> search(String q, {
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
    final o = eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring);
    final dist = maxDistance ?? autoMaxDistance(q);
    return switch (strategy) {
      SearchStrategy.fuzzy     => search_(mFuzzy, q, o),
      SearchStrategy.approx    => searchEdit_(q, dist, o),
      SearchStrategy.fallback  => _fallback(q, dist, o),
      SearchStrategy.merge     => _merge(q, dist, o),
    };
  }

  /// Runs both algorithms independently and returns their results in separate buckets.
  ///
  /// [maxDistance] defaults to [autoMaxDistance] when omitted.
  FuzzyDualResult<T> dual(String q, {
    int? maxDistance,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    FuzzyScoring? scoring,
  }) {
    check_();
    final dist = maxDistance ?? autoMaxDistance(q);
    final o = eff_(caseMatching, normalization, parallel, threads, limit, false, scoring);
    return searchDualC_(q, dist, o);
  }

  List<FuzzyHit<T>> _fallback(String q, int maxDist, FuzzyOptions o) =>
      searchFallback_(q, maxDist, o);

  List<FuzzyHit<T>> _merge(String q, int maxDist, FuzzyOptions o) =>
      searchMerge_(q, maxDist, o);

  Future<List<FuzzyHit<T>>> asyncFuzzy(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      searchAsync_(mFuzzy, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  Future<List<FuzzyHit<T>>> asyncSubstring(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      searchAsync_(mSubstring, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  Future<List<FuzzyHit<T>>> asyncPrefix(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      searchAsync_(mPrefix, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  Future<List<FuzzyHit<T>>> asyncPostfix(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      searchAsync_(mPostfix, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  Future<List<FuzzyHit<T>>> asyncSuffix(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      asyncPostfix(q, caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit, highlight: highlight, scoring: scoring);

  Future<List<FuzzyHit<T>>> asyncExact(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, bool? highlight, FuzzyScoring? scoring}) =>
      searchAsync_(mExact, q, eff_(caseMatching, normalization, parallel, threads, limit, highlight, scoring));

  Future<List<T>> asyncFuzzyRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRawsAsync_(mFuzzy, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  Future<List<T>> asyncSubstringRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRawsAsync_(mSubstring, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  Future<List<T>> asyncPrefixRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRawsAsync_(mPrefix, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  Future<List<T>> asyncPostfixRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRawsAsync_(mPostfix, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  Future<List<T>> asyncSuffixRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      asyncPostfixRaws(q, caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit, scoring: scoring);

  Future<List<T>> asyncExactRaws(String q,
          {FuzzyCase? caseMatching, FuzzyNorm? normalization, bool? parallel,
          int? threads, int? limit, FuzzyScoring? scoring}) =>
      searchRawsAsync_(mExact, q, eff_(caseMatching, normalization, parallel, threads, limit, false, scoring));

  // ── search / approx / dual variants ──────────────────────────────────────

  List<T> searchRaws(String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance, FuzzyCase? caseMatching, FuzzyNorm? normalization,
    bool? parallel, int? threads, int? limit, FuzzyScoring? scoring,
  }) => [for (final h in search(q, strategy: strategy, maxDistance: maxDistance,
      caseMatching: caseMatching, normalization: normalization,
      parallel: parallel, threads: threads, limit: limit, scoring: scoring)) h.raw];

  Future<List<FuzzyHit<T>>> asyncSearch(String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance, FuzzyCase? caseMatching, FuzzyNorm? normalization,
    bool? parallel, int? threads, int? limit, bool? highlight, FuzzyScoring? scoring,
  }) async {
    check_(); inFlight_++;
    try {
      return search(q, strategy: strategy, maxDistance: maxDistance,
          caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit,
          highlight: highlight, scoring: scoring);
    } finally { inFlight_--; signalIfIdle_(); }
  }

  Future<List<T>> asyncSearchRaws(String q, {
    SearchStrategy strategy = SearchStrategy.fuzzy,
    int? maxDistance, FuzzyCase? caseMatching, FuzzyNorm? normalization,
    bool? parallel, int? threads, int? limit, FuzzyScoring? scoring,
  }) async {
    check_(); inFlight_++;
    try {
      return searchRaws(q, strategy: strategy, maxDistance: maxDistance,
          caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit, scoring: scoring);
    } finally { inFlight_--; signalIfIdle_(); }
  }

  List<T> approxRaws(String q,
          {int? maxDistance, FuzzyCase? caseMatching,
          FuzzyNorm? normalization, int? limit}) =>
      [for (final h in approx(q, maxDistance: maxDistance,
          caseMatching: caseMatching, normalization: normalization,
          limit: limit)) h.raw];

  Future<List<FuzzyHit<T>>> asyncApprox(String q, {
    int? maxDistance, FuzzyCase? caseMatching,
    FuzzyNorm? normalization, int? limit,
  }) async {
    check_(); inFlight_++;
    try {
      return approx(q, maxDistance: maxDistance,
          caseMatching: caseMatching, normalization: normalization, limit: limit);
    } finally { inFlight_--; signalIfIdle_(); }
  }

  Future<List<T>> asyncApproxRaws(String q, {
    int? maxDistance, FuzzyCase? caseMatching,
    FuzzyNorm? normalization, int? limit,
  }) async {
    check_(); inFlight_++;
    try {
      return approxRaws(q, maxDistance: maxDistance,
          caseMatching: caseMatching, normalization: normalization, limit: limit);
    } finally { inFlight_--; signalIfIdle_(); }
  }

  Future<FuzzyDualResult<T>> asyncDual(String q, {
    int? maxDistance, FuzzyCase? caseMatching, FuzzyNorm? normalization,
    bool? parallel, int? threads, int? limit, FuzzyScoring? scoring,
  }) async {
    check_(); inFlight_++;
    try {
      return dual(q, maxDistance: maxDistance,
          caseMatching: caseMatching, normalization: normalization,
          parallel: parallel, threads: threads, limit: limit, scoring: scoring);
    } finally { inFlight_--; signalIfIdle_(); }
  }
}
