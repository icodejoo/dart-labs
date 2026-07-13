//#region src/ffuzzy-corpus.d.ts
/** Initialize the WASM engine. Await once before constructing any `FuzzyCorpus`. Idempotent. */
declare function ffuzzyInitialize(opts?: Record<string, unknown>): Promise<void>;
/** `true` once {@link ffuzzyInitialize} has completed successfully. */
declare function ffuzzyReady(): boolean;
type FuzzyCase = 0 | 1 | 2;
declare const FuzzyCase: Readonly<{
  readonly respect: 0;
  readonly ignore: 1;
  readonly smart: 2;
}>;
type FuzzyNorm = 0 | 1;
declare const FuzzyNorm: Readonly<{
  readonly never: 0;
  readonly smart: 1;
}>;
type FuzzyMode = 0 | 1 | 2 | 3 | 4;
declare const FuzzyMode: Readonly<{
  readonly fuzzy: 0;
  readonly substring: 1;
  readonly prefix: 2;
  readonly postfix: 3;
  readonly exact: 4;
}>;
type FuzzyScoring = 0 | 1 | 2;
declare const FuzzyScoring: Readonly<{
  readonly fast: 0;
  readonly off: 1;
  readonly nucleo: 2;
}>;
type FuzzyKeyKind = 0 | 1 | 2 | 3 | 100;
declare const FuzzyKeyKind: Readonly<{
  readonly original: 0;
  readonly pinyin: 1;
  readonly initials: 2;
  readonly romaji: 3;
  readonly custom: 100;
}>;
/** An alternate search key (e.g. pinyin / romaji / initials). */
declare class FuzzyKey {
  readonly text: string;
  readonly kind: number;
  constructor(text: string, kind?: number);
  static kind(text: string, kind: FuzzyKeyKind): FuzzyKey;
}
/** Search options — mirrors `FuzzyOptions` in `ffuzzy.dart`. */
declare class FuzzyOptions {
  readonly scoring: FuzzyScoring;
  readonly caseMatching: FuzzyCase;
  readonly normalization: FuzzyNorm;
  readonly parallel: boolean;
  readonly threads: number;
  readonly limit: number;
  /** When `true`, `FuzzyHit.indices` is populated (Pass 2 runs). Default `false`. */
  readonly highlight: boolean;
  constructor(init?: Partial<FuzzyOptions>);
}
/** One result from a corpus search. */
interface FuzzyHit<T = unknown> {
  raw: T;
  index: number;
  score: number;
  /** Which key kind matched (`FuzzyKeyKind.*`). */
  matchedKind: number;
  /** Raw integer kind code — same as `matchedKind`; mirrors `FuzzyHit.matchedKindCode` in Dart. */
  matchedKindCode: number;
  matchedKey: number;
  /** Matched codepoint positions. Populated only when `highlight: true`. */
  indices: number[];
}
/** Dot-notation field paths for `T` (up to two levels deep). */
type FieldPath<T extends Record<string, unknown>> = { [K in keyof T & string]: T[K] extends Record<string, unknown> ? K | `${K}.${keyof T[K] & string}` : K; }[keyof T & string];
type SearchStrategy = 'fuzzy' | 'approx' | 'fallback' | 'merge';
/**
 * Returns a sensible edit-distance threshold based on query length (mirrors
 * Elasticsearch's AUTO policy). Used as the default when `maxDistance` is omitted.
 * - length ≤ 2 → 0 (exact)
 * - length 3-5 → 1
 * - length 6+  → 2
 */
declare function autoMaxDistance(query: string): number;
interface FuzzyDualResult<T = unknown> {
  fuzzy: FuzzyHit<T>[];
  approx: FuzzyHit<T>[];
}
interface FuzzyCorpusInit<T> {
  stringOf?: (item: T) => string;
  options?: Partial<FuzzyOptions> | FuzzyOptions;
  matchPaths?: boolean;
  preferPrefix?: boolean;
}
/**
 * A resident corpus of `T` items. Build once, search many times.
 * Release WASM memory with `dispose()` or the `using` statement.
 *
 * @example
 * ```ts
 * const corpus = FuzzyCorpus.strings(['src/main.rs', 'README.md']);
 * corpus.fuzzy('src').forEach(h => console.log(h.raw, h.score));
 * corpus.dispose();
 * ```
 */
declare class FuzzyCorpus<T = string> {
  [x: number]: () => void;
  private _M;
  private _stringOf;
  private _opts;
  private _items;
  private _keys;
  private _disposed;
  private _deferred;
  private _matchPaths;
  private _preferPrefix;
  private _ptr;
  private _scratch;
  private _scratch4;
  private _scratchCap;
  constructor(items?: Iterable<T>, init?: FuzzyCorpusInit<T>);
  /** Resolves when the engine finishes loading (success or failure). Useful for
   *  re-triggering a search after a corpus created before `ffuzzyInitialize`:
   *  ```ts
   *  corpus.ready.then(() => { if (corpus.isReady) renderResults(corpus.fuzzy(q)); });
   *  ``` */
  get ready(): Promise<void>;
  /** `true` once the engine has loaded and this corpus is backed by WASM. */
  get isReady(): boolean;
  static strings(items?: Iterable<string>, opts?: Omit<FuzzyCorpusInit<string>, 'stringOf'>): FuzzyCorpus<string>;
  static byKey<T extends Record<string, unknown>>(maps?: Iterable<T>, field?: FieldPath<T> | (string & {}), opts?: Omit<FuzzyCorpusInit<T>, 'stringOf'>): FuzzyCorpus<T>;
  static byKeys<T extends Record<string, unknown>>(maps?: Iterable<T>, fields?: (FieldPath<T> | (string & {}))[], opts?: Omit<FuzzyCorpusInit<T>, 'stringOf'>): FuzzyCorpus<T>;
  get length(): number;
  add(item: T): void;
  addAll(items: Iterable<T>): void;
  addKey(item: T, keys: FuzzyKey[]): void;
  update(index: number, item: T): void;
  removeAt(index: number): void;
  removeWhere(test: (item: T) => boolean): number;
  refresh(source?: Iterable<T>): void;
  clear(): void;
  /** fzf-style subsequence search. Shorthand for `search(query, { strategy: 'fuzzy' })`. */
  fuzzy(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Contiguous-substring match. */
  substring(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Prefix match — item starts with query. */
  prefix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Postfix match — item ends with query. */
  postfix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Alias for {@link postfix}. */
  suffix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Exact whole-string match. */
  exact(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Fuzzy search — raw `T[]` only, no wrapper. Faster: skips highlight-index computation. */
  fuzzyRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /** Substring search — raw `T[]` only. */
  substringRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /** Prefix search — raw `T[]` only. */
  prefixRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /** Postfix search — raw `T[]` only. */
  postfixRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /** Alias for {@link postfixRaws}. */
  suffixRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /** Exact search — raw `T[]` only. */
  exactRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /** Edit-distance (typo-tolerant) search. Shorthand for `search(q, { strategy: 'approx' })`.
   *  Requires WASM built with FFZ_EDIT_DISTANCE. Returns [] if not available. */
  /** Raw-object shorthand for `search()`. Returns `T[]` instead of `FuzzyHit<T>[]`. */
  searchRaws(query: string, opts?: Partial<FuzzyOptions> & {
    strategy?: SearchStrategy;
    maxDistance?: number;
  }): T[];
  /** Edit-distance (typo-tolerant) search. Shorthand for `search(q, { strategy: 'approx' })`.
   *  `maxDistance` defaults to {@link autoMaxDistance}(query) when omitted. */
  approx(query: string, maxDistance?: number, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Unified search entry point.
   *
   * - `'fuzzy'`    — fzf subsequence (default, same as calling `fuzzy()`)
   * - `'approx'`   — edit-distance; `maxDistance` auto-scaled when omitted
   * - `'fallback'` — subsequence first; falls back to approx when empty
   * - `'merge'`    — both algorithms; subsequence hits first, then approx-only hits
   */
  search(query: string, opts?: Partial<FuzzyOptions> & {
    strategy?: SearchStrategy;
    maxDistance?: number;
  }): FuzzyHit<T>[];
  /** Raw-object shorthand for `approx()`. Returns `T[]` instead of `FuzzyHit<T>[]`. */
  approxRaws(query: string, maxDistance?: number, opts?: Partial<FuzzyOptions>): T[];
  /** Runs both algorithms independently and returns their results in separate buckets.
   *  `maxDistance` defaults to {@link autoMaxDistance}(query) when omitted. */
  dual(query: string, opts?: Partial<FuzzyOptions> & {
    maxDistance?: number;
  }): FuzzyDualResult<T>;
  private _approxRaw;
  dispose(): void;
  /** Returns true if ready to search; false if still deferred (WASM not loaded). */
  private _ensureReady;
  private _allocScratch;
  private _ensureScratch;
  private _nativeAdd;
  private _rebuild;
  private _filter;
  private _search;
  private _searchRaws;
  /** Non-WASM search for prefix/postfix/exact/substring modes using native JS string ops. */
  private _nativeSearch;
  private _alive;
  private _bounds;
}
/**
 * Convert codepoint indices to UTF-16 code-unit offsets. No-op for BMP-only text.
 * Needed for astral-plane characters (emoji, some CJK variants).
 */
declare function fuzzyCodepointToUtf16(text: string, codepointIndices: number[]): number[];
/**
 * Wrap matched characters in an HTML tag for highlighting.
 * Adjacent matched codepoints are merged. Non-matched text is HTML-escaped (XSS-safe).
 * Requires `highlight: true` on the search call that produced the hit.
 *
 * @example
 * ```ts
 * const [hit] = corpus.fuzzy('src', { highlight: true });
 * highlightHtml(hit.raw, hit.indices); // '<mark>src</mark>/main.dart'
 * ```
 */
declare function highlightHtml(text: string, indices: number[], opts?: {
  tag?: string;
}): string;
//#endregion
export { FieldPath, FuzzyCase, FuzzyCorpus, FuzzyCorpusInit, FuzzyDualResult, FuzzyHit, FuzzyKey, FuzzyKeyKind, FuzzyMode, FuzzyNorm, FuzzyOptions, FuzzyScoring, SearchStrategy, autoMaxDistance, ffuzzyInitialize, ffuzzyReady, fuzzyCodepointToUtf16, highlightHtml };