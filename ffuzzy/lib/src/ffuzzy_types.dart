// Shared pure-Dart types for ffuzzy — no platform-specific imports.
// Imported by both ffuzzy_ffi.dart (native) and ffuzzy_web.dart (web).
library;

/// Case handling (mirrors `ffz_case_matching`).
enum FuzzyCase { respect, ignore, smart }

/// Unicode normalization (mirrors `ffz_normalization`).
enum FuzzyNorm { never, smart }

/// Scoring model for corpus queries (mirrors `ffz_scoring_mode`).
///
/// Set the corpus-wide default in [FuzzyOptions]; override per call via the
/// `scoring` named parameter on [FuzzyCorpus.fuzzy], [FuzzyCorpus.exact], etc.
enum FuzzyScoring {
  /// 2-row rolling DP with simplified bonuses (default). Faster than [nucleo]
  /// in single-threaded scenarios; good ranking quality for typical use.
  fast,

  /// No DP. Prefilter only; all matching items get [FuzzyHit.score] == 0 and
  /// are returned in corpus insertion order. Use for programmatic
  /// exact/ID matching where ranking is irrelevant.
  off,

  /// Full-matrix DP, nucleo 0.3.1 compatible. Highest ranking accuracy.
  nucleo,
}

/// Which key produced a hit. Custom host kinds use values >= 100.
enum FuzzyKeyKind { original, pinyin, initials, romaji, custom }

/// The raw C `ffz_key_kind` code for a kind (original=0..romaji=3, custom=100).
extension FuzzyKeyKindCode on FuzzyKeyKind {
  int get code => switch (this) {
        FuzzyKeyKind.original => 0,
        FuzzyKeyKind.pinyin => 1,
        FuzzyKeyKind.initials => 2,
        FuzzyKeyKind.romaji => 3,
        FuzzyKeyKind.custom => 100,
      };
}

FuzzyKeyKind kindOf(int v) => switch (v) {
      0 => FuzzyKeyKind.original,
      1 => FuzzyKeyKind.pinyin,
      2 => FuzzyKeyKind.initials,
      3 => FuzzyKeyKind.romaji,
      _ => FuzzyKeyKind.custom,
    };

/// Search options. Set the corpus-wide defaults on the [FuzzyCorpus]
/// constructor; the mode methods override individual fields per call.
class FuzzyOptions {
  final FuzzyScoring scoring;
  final FuzzyCase caseMatching;
  final FuzzyNorm normalization;
  final bool parallel;
  final int threads;
  final int limit;
  final bool highlight;

  const FuzzyOptions({
    this.scoring = FuzzyScoring.fast,
    this.caseMatching = FuzzyCase.smart,
    this.normalization = FuzzyNorm.smart,
    this.parallel = false,
    this.threads = 0,
    this.limit = 0,
    this.highlight = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FuzzyOptions &&
          scoring == other.scoring &&
          caseMatching == other.caseMatching &&
          normalization == other.normalization &&
          parallel == other.parallel &&
          threads == other.threads &&
          limit == other.limit &&
          highlight == other.highlight);

  @override
  int get hashCode => Object.hash(
      scoring, caseMatching, normalization, parallel, threads, limit, highlight);

  FuzzyOptions copyWith({
    FuzzyScoring? scoring,
    FuzzyCase? caseMatching,
    FuzzyNorm? normalization,
    bool? parallel,
    int? threads,
    int? limit,
    bool? highlight,
  }) =>
      FuzzyOptions(
        scoring: scoring ?? this.scoring,
        caseMatching: caseMatching ?? this.caseMatching,
        normalization: normalization ?? this.normalization,
        parallel: parallel ?? this.parallel,
        threads: threads ?? this.threads,
        limit: limit ?? this.limit,
        highlight: highlight ?? this.highlight,
      );
}

/// An alternate search key for an item (e.g. host-computed pinyin/romaji).
class FuzzyKey {
  final String text;

  /// The key kind code. Defaults to 1 (pinyin).
  final int kind;
  const FuzzyKey(this.text, {this.kind = 1 /* pinyin */});
  FuzzyKey.kind(this.text, FuzzyKeyKind kind) : kind = kind.code;
}

/// Strategy used by [FuzzyCorpus.search].
enum SearchStrategy {
  /// fzf-style subsequence match (default). Requires [FFZ_SUBSEQUENCE] build.
  fuzzy,

  /// Edit-distance (Levenshtein) approximate match. Requires [FFZ_EDIT_DISTANCE] build.
  approx,

  /// Run [fuzzy] first; fall back to [approx] when the subsequence result is empty.
  fallback,

  /// Run both algorithms; return subsequence hits first, then approx-only hits
  /// (items already found by subsequence are deduplicated).
  merge,
}

/// Dual-algorithm result returned by [FuzzyCorpus.dual].
class FuzzyDualResult<T> {
  /// Hits from the fzf-style subsequence algorithm, sorted by score descending.
  final List<FuzzyHit<T>> fuzzy;

  /// Hits from the edit-distance algorithm, sorted by distance ascending.
  final List<FuzzyHit<T>> approx;

  const FuzzyDualResult({required this.fuzzy, required this.approx});
}

/// Returns a sensible edit-distance threshold based on query length, mirroring
/// Elasticsearch's AUTO policy:
/// - length ≤ 2 → 0 (exact — too short to tolerate errors)
/// - length 3-5 → 1
/// - length 6+  → 2
///
/// Use this when you want adaptive tolerance without picking a fixed [maxDistance]:
/// ```dart
/// corpus.approx(q, maxDistance: autoMaxDistance(q));
/// ```
int autoMaxDistance(String query) {
  final n = query.length;
  if (n <= 2) return 0;
  if (n <= 5) return 1;
  return 2;
}

/// Thrown when the native library can't be loaded or a symbol is missing.
class FuzzyException implements Exception {
  final String message;
  const FuzzyException(this.message);
  @override
  String toString() => 'FuzzyException: $message';
}

/// One search result for a [FuzzyCorpus] of `T`.
///
/// [raw] is the original item that matched. [index] is its insertion order in
/// the corpus. [indices] contains matched codepoint positions only when the
/// search was called with `highlight: true`; otherwise it is empty.
class FuzzyHit<T> {
  final T raw;
  final int index;

  /// Non-negative integer; higher is a better match. Comparable only within
  /// results of the same query. Always 0 when [FuzzyScoring.off] is in effect.
  final int score;
  final FuzzyKeyKind matchedKind;

  /// The raw integer kind code of the matched key.
  final int matchedKindCode;

  final int matchedKey;

  /// Matched codepoint positions within the matched key. Populated only when
  /// the search was called with `highlight: true`; empty otherwise.
  final List<int> indices;

  const FuzzyHit(this.raw, this.index, this.score, this.matchedKind,
      this.matchedKindCode, this.matchedKey, this.indices);

  @override
  String toString() =>
      'FuzzyHit(index: $index, score: $score, kind: $matchedKind($matchedKindCode), raw: $raw)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FuzzyHit<T> &&
          index == other.index &&
          score == other.score &&
          matchedKind == other.matchedKind &&
          matchedKindCode == other.matchedKindCode &&
          matchedKey == other.matchedKey &&
          raw == other.raw &&
          indices.length == other.indices.length &&
          Iterable.generate(indices.length, (i) => indices[i] == other.indices[i])
              .every((v) => v));

  @override
  int get hashCode => Object.hash(index, score, matchedKind, matchedKindCode,
      matchedKey, raw, indices.fold<int>(0, (h, e) => h ^ e.hashCode));
}

/// Convert codepoint indices (as in [FuzzyHit.indices]) to UTF-16 code-unit
/// offsets into [text], suitable for Dart `String`/`TextSpan` highlighting.
List<int> fuzzyCodepointToUtf16(String text, List<int> codepointIndices) {
  if (codepointIndices.isEmpty) return const <int>[];
  final offsets = <int>[];
  var u16 = 0;
  for (final r in text.runes) {
    offsets.add(u16);
    u16 += r > 0xFFFF ? 2 : 1;
  }
  return [
    for (final c in codepointIndices)
      (c >= 0 && c < offsets.length) ? offsets[c] : u16
  ];
}
