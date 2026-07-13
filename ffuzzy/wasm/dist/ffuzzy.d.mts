//#region src/ffuzzy-corpus.d.ts
/** Initialize the WASM engine. Await once before constructing any `FuzzyCorpus`. Idempotent. */
declare function ffuzzyInitialize(opts?: Record<string, unknown>): Promise<void>;
/** `true` once {@link ffuzzyInitialize} has completed. */
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
  matchedKind: number;
  matchedKey: number;
  /** Matched codepoint positions. Populated only when `highlight: true`. */
  indices: number[];
}
/** Dot-notation field paths for `T` (up to two levels deep). */
type FieldPath<T extends Record<string, unknown>> = { [K in keyof T & string]: T[K] extends Record<string, unknown> ? K | `${K}.${keyof T[K] & string}` : K; }[keyof T & string];
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
  private _ptr;
  private _scratch;
  private _scratch4;
  private _scratchCap;
  constructor(items?: Iterable<T>, init?: FuzzyCorpusInit<T>);
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
  /** Fuzzy (subsequence) search. Supports fzf operators: `!term` `^term` `'term` `term$`. */
  fuzzy(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /** Fuzzy search — raw `T[]` only, no wrapper. Faster: skips highlight-index computation. */
  fuzzyRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  dispose(): void;
  private _allocScratch;
  private _ensureScratch;
  private _nativeAdd;
  private _rebuild;
  private _filter;
  private _search;
  private _searchRaws;
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
export { FieldPath, FuzzyCase, FuzzyCorpus, FuzzyCorpusInit, FuzzyHit, FuzzyKey, FuzzyKeyKind, FuzzyMode, FuzzyNorm, FuzzyOptions, FuzzyScoring, ffuzzyInitialize, ffuzzyReady, fuzzyCodepointToUtf16, highlightHtml };