/**
 * ffuzzy — high-level corpus API over the ffuzzy WASM engine.
 * Naming and behaviour mirrors `ffuzzy.dart`.
 *
 * ```ts
 * import { ffuzzyInitialize, FuzzyCorpus } from '@codejoo/ffuzzy';
 * await ffuzzyInitialize();
 * const corpus = FuzzyCorpus.strings(['src/main.rs', 'README.md']);
 * const hits = corpus.fuzzy('src');  // FuzzyHit<string>[]
 * corpus.dispose();
 * ```
 */
// @ts-ignore — ffz.mjs is the Emscripten-compiled engine; we cast it ourselves below
import ffuzzyModule from './ffz.mjs';

// ── WASM module instance ──────────────────────────────────────────────────────

interface FfzMod {
  HEAPU8:  Uint8Array;
  HEAP32:  Int32Array;
  HEAPU32: Uint32Array;
  _malloc(n: number): number;
  _free(ptr: number): void;
  _ffz_ffi_new_cfg(mp: number, pp: number): number;
  _ffz_ffi_new_cfg2(mp: number, pp: number, sc: number): number;
  _ffz_ffi_add(cp: number, sp: number, len: number): void;
  _ffz_ffi_add_keyed(cp: number, sp: number, len: number, tp: number, lp: number, kp: number, n: number): void;
  _ffz_ffi_clear(cp: number): void;
  _ffz_ffi_free(cp: number): void;
  _ffz_ffi_filter_ex(cp: number, qp: number, qlen: number, mode: number, cm: number, nm: number, par: number, thr: number, lim: number): number;
  _ffz_ffi_filter_ex2(cp: number, qp: number, qlen: number, mode: number, cm: number, nm: number, par: number, thr: number, lim: number, sc: number): number;
  _ffz_ffi_filter_raws(cp: number, qp: number, qlen: number, mode: number, cm: number, nm: number, par: number, thr: number, lim: number, sc: number): number;
  _ffz_ffi_filter_edit(cp: number, qp: number, qlen: number, maxDist: number, cm: number, nm: number, lim: number): number;
  _ffz_ffi_filter_merge(cp: number, qp: number, qlen: number, cm: number, nm: number, maxDist: number, sc: number, par: number, thr: number, lim: number): number;
  _ffz_ffi_filter_fallback(cp: number, qp: number, qlen: number, cm: number, nm: number, maxDist: number, sc: number, par: number, thr: number, lim: number): number;
  _ffz_ffi_filter_dual(cp: number, qp: number, qlen: number, cm: number, nm: number, maxDist: number, sc: number, par: number, thr: number, lim: number): number;
  _ffz_ffi_dual_seq(d: number): number;
  _ffz_ffi_dual_edit(d: number): number;
  _ffz_ffi_dual_free(d: number): void;
  _ffz_ffi_results_len(r: number): number;
  _ffz_ffi_results_item(r: number, i: number): number;
  _ffz_ffi_results_score(r: number, i: number): number;
  _ffz_ffi_results_kind(r: number, i: number): number;
  _ffz_ffi_results_key(r: number, i: number): number;
  _ffz_ffi_results_nindices(r: number, i: number): number;
  _ffz_ffi_results_index(r: number, i: number, j: number): number;
  _ffz_ffi_results_free(r: number): void;
  _ffz_ffi_results_bulk(r: number, ip: number, sp: number, kp: number, keyp: number, n: number): void;
  _ffz_ffi_results_items_bulk(r: number, ip: number, n: number): void;
}

// ── singleton ─────────────────────────────────────────────────────────────────

let _M: FfzMod | null = null;
let _readyResolve: (() => void) | null = null;
// Resolves when ffuzzyInitialize finishes — success (_M set) or failure (_M null).
const _readyPromise = new Promise<void>(res => { _readyResolve = res; });

/** Initialize the WASM engine. Await once before constructing any `FuzzyCorpus`. Idempotent. */
export async function ffuzzyInitialize(opts?: Record<string, unknown>): Promise<void> {
  if (_M) return;
  try {
    _M = await (ffuzzyModule as unknown as (o?: Record<string, unknown>) => Promise<FfzMod>)(opts);
  } finally {
    _readyResolve?.();
  }
}

/** `true` once {@link ffuzzyInitialize} has completed successfully. */
export function ffuzzyReady(): boolean { return _M !== null; }

// ── enums ─────────────────────────────────────────────────────────────────────

export type FuzzyCase = 0 | 1 | 2;
export const FuzzyCase = Object.freeze({ respect: 0, ignore: 1, smart: 2 } as const);

export type FuzzyNorm = 0 | 1;
export const FuzzyNorm = Object.freeze({ never: 0, smart: 1 } as const);

export type FuzzyMode = 0 | 1 | 2 | 3 | 4;
export const FuzzyMode = Object.freeze({ fuzzy: 0, substring: 1, prefix: 2, postfix: 3, exact: 4 } as const);

export type FuzzyScoring = 0 | 1 | 2;
export const FuzzyScoring = Object.freeze({ fast: 0, off: 1, nucleo: 2 } as const);

export type FuzzyKeyKind = 0 | 1 | 2 | 3 | 100;
export const FuzzyKeyKind = Object.freeze({ original: 0, pinyin: 1, initials: 2, romaji: 3, custom: 100 } as const);

// ── supporting classes ────────────────────────────────────────────────────────

/** An alternate search key (e.g. pinyin / romaji / initials). */
export class FuzzyKey {
  readonly text: string;
  readonly kind: number;
  constructor(text: string, kind: number = FuzzyKeyKind.pinyin) { this.text = text; this.kind = kind; }
  static kind(text: string, kind: FuzzyKeyKind): FuzzyKey { return new FuzzyKey(text, kind); }
}

/** Search options — mirrors `FuzzyOptions` in `ffuzzy.dart`. */
export class FuzzyOptions {
  readonly scoring:       FuzzyScoring;
  readonly caseMatching:  FuzzyCase;
  readonly normalization: FuzzyNorm;
  readonly parallel:      boolean;
  readonly threads:       number;
  readonly limit:         number;
  /** When `true`, `FuzzyHit.indices` is populated (Pass 2 runs). Default `false`. */
  readonly highlight:     boolean;
  constructor(init: Partial<FuzzyOptions> = {}) {
    this.scoring       = init.scoring       ?? FuzzyScoring.fast;
    this.caseMatching  = init.caseMatching  ?? FuzzyCase.smart;
    this.normalization = init.normalization ?? FuzzyNorm.smart;
    this.parallel      = init.parallel      ?? false;
    this.threads       = init.threads       ?? 0;
    this.limit         = init.limit         ?? 0;
    this.highlight     = init.highlight     ?? false;
  }
}

/** One result from a corpus search. */
export interface FuzzyHit<T = unknown> {
  raw: T; index: number; score: number;
  /** Which key kind matched (`FuzzyKeyKind.*`). */
  matchedKind: number;
  /** Raw integer kind code — same as `matchedKind`; mirrors `FuzzyHit.matchedKindCode` in Dart. */
  matchedKindCode: number;
  matchedKey: number;
  /** Matched codepoint positions. Populated only when `highlight: true`. */
  indices: number[];
}

/** Dot-notation field paths for `T` (up to two levels deep). */
export type FieldPath<T extends Record<string, unknown>> = {
  [K in keyof T & string]: T[K] extends Record<string, unknown>
    ? K | `${K}.${keyof T[K] & string}` : K;
}[keyof T & string];

export type SearchStrategy = 'fuzzy' | 'approx' | 'fallback' | 'merge';

/**
 * Returns a sensible edit-distance threshold based on query length (mirrors
 * Elasticsearch's AUTO policy). Used as the default when `maxDistance` is omitted.
 * - length ≤ 2 → 0 (exact)
 * - length 3-5 → 1
 * - length 6+  → 2
 */
export function autoMaxDistance(query: string): number {
  if (query.length <= 2) return 0;
  if (query.length <= 5) return 1;
  return 2;
}

export interface FuzzyDualResult<T = unknown> {
  fuzzy: FuzzyHit<T>[];
  approx: FuzzyHit<T>[];
}

export interface FuzzyCorpusInit<T> {
  stringOf?: (item: T) => string;
  options?: Partial<FuzzyOptions> | FuzzyOptions;
  matchPaths?: boolean;
  preferPrefix?: boolean;
}

// ── internal helpers ──────────────────────────────────────────────────────────

// ── case folding for native (non-WASM) modes — mirrors dartSearch in ffuzzy_corpus.dart ──

function foldPair(text: string, query: string, cm: FuzzyCase): [string, string] {
  const hasUpper = query !== query.toLowerCase();
  if (cm === FuzzyCase.ignore || (cm === FuzzyCase.smart && !hasUpper)) {
    return [text.toLowerCase(), query.toLowerCase()];
  }
  return [text, query];
}

function writeUtf8(M: FfzMod, s: string): [number, number] {
  const bytes = new TextEncoder().encode(s);
  const ptr = M._malloc(bytes.length || 1);
  M.HEAPU8.set(bytes, ptr);
  return [ptr, bytes.length];
}

function getField(obj: Record<string, unknown>, path: string): string {
  if (obj == null) return '';
  if (!path.includes('.')) { const v = obj[path]; return v == null ? '' : String(v); }
  let cur: unknown = obj;
  for (const part of path.split('.')) { if (cur == null) return ''; cur = (cur as Record<string, unknown>)[part]; }
  return cur == null ? '' : String(cur);
}

const SCRATCH_INIT = 256;

// ── FuzzyCorpus ───────────────────────────────────────────────────────────────

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
export class FuzzyCorpus<T = string> {
  private _M:           FfzMod | null        = null;
  private _stringOf:    (item: T) => string;
  private _opts:        FuzzyOptions;
  private _items:       T[]                   = [];
  private _keys:        (FuzzyKey[] | null)[] = [];
  private _disposed:    boolean               = false;
  private _deferred:    boolean               = false;
  private _matchPaths:  boolean               = false;
  private _preferPrefix: boolean              = false;
  private _ptr:         number                = 0;
  private _scratch:     number                = 0;
  private _scratch4:    number                = 0;
  private _scratchCap:  number                = 0;

  constructor(items?: Iterable<T>, init?: FuzzyCorpusInit<T>) {
    const o = init ?? {};
    this._stringOf    = o.stringOf ?? (String as unknown as (item: T) => string);
    this._opts        = new FuzzyOptions(o.options);
    this._matchPaths  = o.matchPaths ?? false;
    this._preferPrefix = o.preferPrefix ?? false;
    if (!_M) {
      this._deferred = true;
      if (items) for (const item of items) { this._items.push(item); this._keys.push(null); }
      return;
    }
    this._M = _M;
    const sc = this._opts.scoring;
    this._ptr = this._M._ffz_ffi_new_cfg2(this._matchPaths ? 1 : 0, this._preferPrefix ? 1 : 0, sc);
    if (!this._ptr) throw new Error('FuzzyCorpus: native allocation failed (OOM)');
    this._allocScratch(SCRATCH_INIT);
    if (items) this.addAll(items);
  }

  /** Resolves when the engine finishes loading (success or failure). Useful for
   *  re-triggering a search after a corpus created before `ffuzzyInitialize`:
   *  ```ts
   *  corpus.ready.then(() => { if (corpus.isReady) renderResults(corpus.fuzzy(q)); });
   *  ``` */
  get ready(): Promise<void> { return this._deferred ? _readyPromise : Promise.resolve(); }

  /** `true` once the engine has loaded and this corpus is backed by WASM. */
  get isReady(): boolean { return !this._deferred && this._M !== null; }

  // ── static factories ────────────────────────────────────────────────────────

  static strings(items?: Iterable<string>, opts?: Omit<FuzzyCorpusInit<string>, 'stringOf'>): FuzzyCorpus<string> {
    return new FuzzyCorpus(items ?? [], { ...opts, stringOf: String });
  }

  static byKey<T extends Record<string, unknown>>(
    maps?: Iterable<T>, field?: FieldPath<T> | (string & {}), opts?: Omit<FuzzyCorpusInit<T>, 'stringOf'>,
  ): FuzzyCorpus<T> {
    const f = field ?? '';
    return new FuzzyCorpus(maps ?? [], { ...opts, stringOf: (m) => getField(m as Record<string, unknown>, f) });
  }

  static byKeys<T extends Record<string, unknown>>(
    maps?: Iterable<T>, fields?: (FieldPath<T> | (string & {}))[], opts?: Omit<FuzzyCorpusInit<T>, 'stringOf'>,
  ): FuzzyCorpus<T> {
    if (!fields?.length) throw new Error('byKeys: fields must not be empty');
    const corpus = new FuzzyCorpus<T>([], { ...opts, stringOf: (m) => getField(m as Record<string, unknown>, fields[0]) });
    for (const item of maps ?? []) {
      if (fields.length === 1) { corpus.add(item); }
      else { corpus.addKey(item, fields.slice(1).map((f) => new FuzzyKey(getField(item as Record<string, unknown>, f), FuzzyKeyKind.custom))); }
    }
    return corpus;
  }

  // ── mutation API ─────────────────────────────────────────────────────────────

  get length(): number { this._alive(); return this._items.length; }

  add(item: T): void { this._alive(); this._nativeAdd(item, null); this._items.push(item); this._keys.push(null); }
  addAll(items: Iterable<T>): void { for (const item of items) this.add(item); }

  addKey(item: T, keys: FuzzyKey[]): void {
    this._alive();
    const ks = keys.length ? keys : null;
    this._nativeAdd(item, ks); this._items.push(item); this._keys.push(ks);
  }

  update(index: number, item: T): void {
    this._alive(); this._bounds(index);
    this._items[index] = item; this._keys[index] = null; this._rebuild();
  }

  removeAt(index: number): void {
    this._alive(); this._bounds(index);
    this._items.splice(index, 1); this._keys.splice(index, 1); this._rebuild();
  }

  removeWhere(test: (item: T) => boolean): number {
    this._alive();
    let removed = 0;
    for (let i = this._items.length - 1; i >= 0; i--) {
      if (test(this._items[i])) { this._items.splice(i, 1); this._keys.splice(i, 1); removed++; }
    }
    if (removed) this._rebuild();
    return removed;
  }

  refresh(source?: Iterable<T>): void {
    this._alive();
    if (source) { this._items = Array.from(source); this._keys = this._items.map(() => null); }
    this._rebuild();
  }

  clear(): void { this._alive(); this._M?._ffz_ffi_clear(this._ptr); this._items.length = 0; this._keys.length = 0; }

  // ── search API ───────────────────────────────────────────────────────────────

  /** fzf-style subsequence search. Shorthand for `search(query, { strategy: 'fuzzy' })`. */
  fuzzy(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] { return this.search(query, { ...opts, strategy: 'fuzzy' }); }
  /** Contiguous-substring match. */
  substring(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] { return this._nativeSearch(1, query, opts ?? {}); }
  /** Prefix match — item starts with query. */
  prefix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] { return this._nativeSearch(2, query, opts ?? {}); }
  /** Postfix match — item ends with query. */
  postfix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] { return this._nativeSearch(3, query, opts ?? {}); }
  /** Alias for {@link postfix}. */
  suffix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] { return this.postfix(query, opts); }
  /** Exact whole-string match. */
  exact(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] { return this._nativeSearch(4, query, opts ?? {}); }

  /** Fuzzy search — raw `T[]` only, no wrapper. Faster: skips highlight-index computation. */
  fuzzyRaws(query: string, opts?: Partial<FuzzyOptions>): T[] { return this._searchRaws(0, query, opts ?? {}); }
  /** Substring search — raw `T[]` only. */
  substringRaws(query: string, opts?: Partial<FuzzyOptions>): T[] { return this.substring(query, opts).map(h => h.raw); }
  /** Prefix search — raw `T[]` only. */
  prefixRaws(query: string, opts?: Partial<FuzzyOptions>): T[] { return this.prefix(query, opts).map(h => h.raw); }
  /** Postfix search — raw `T[]` only. */
  postfixRaws(query: string, opts?: Partial<FuzzyOptions>): T[] { return this.postfix(query, opts).map(h => h.raw); }
  /** Alias for {@link postfixRaws}. */
  suffixRaws(query: string, opts?: Partial<FuzzyOptions>): T[] { return this.postfixRaws(query, opts); }
  /** Exact search — raw `T[]` only. */
  exactRaws(query: string, opts?: Partial<FuzzyOptions>): T[] { return this.exact(query, opts).map(h => h.raw); }

  /** Edit-distance (typo-tolerant) search. Shorthand for `search(q, { strategy: 'approx' })`.
   *  Requires WASM built with FFZ_EDIT_DISTANCE. Returns [] if not available. */
  /** Raw-object shorthand for `search()`. Returns `T[]` instead of `FuzzyHit<T>[]`. */
  searchRaws(query: string, opts?: Partial<FuzzyOptions> & { strategy?: SearchStrategy; maxDistance?: number }): T[] {
    return this.search(query, opts).map(h => h.raw);
  }

  /** Edit-distance (typo-tolerant) search. Shorthand for `search(q, { strategy: 'approx' })`.
   *  `maxDistance` defaults to {@link autoMaxDistance}(query) when omitted. */
  approx(query: string, maxDistance?: number, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[] {
    const dist = maxDistance ?? autoMaxDistance(query);
    return this._approxRaw(query, dist, new FuzzyOptions({ ...this._opts, ...opts }));
  }

  /** Unified search entry point.
   *
   * - `'fuzzy'`    — fzf subsequence (default, same as calling `fuzzy()`)
   * - `'approx'`   — edit-distance; `maxDistance` auto-scaled when omitted
   * - `'fallback'` — subsequence first; falls back to approx when empty
   * - `'merge'`    — both algorithms; subsequence hits first, then approx-only hits
   */
  search(query: string, opts?: Partial<FuzzyOptions> & { strategy?: SearchStrategy; maxDistance?: number }): FuzzyHit<T>[] {
    this._alive();
    if (!this._ensureReady()) return [];
    const M = this._M!;
    const { strategy = 'fuzzy', maxDistance, ...rest } = opts ?? {};
    const dist = maxDistance ?? autoMaxDistance(query);
    const o = new FuzzyOptions({ ...this._opts, ...rest });
    switch (strategy) {
      case 'fuzzy':    return this._search(0, query, rest);
      case 'approx':   return this._approxRaw(query, dist, o);
      case 'fallback': {
        const [qp, qn] = writeUtf8(M, query);
        let res = 0;
        try { res = M._ffz_ffi_filter_fallback(this._ptr, qp, qn, o.caseMatching, o.normalization, dist, o.scoring, 0, 0, o.limit); }
        finally { M._free(qp); }
        return this._readFlat(M, res);
      }
      case 'merge': {
        const [qp, qn] = writeUtf8(M, query);
        let res = 0;
        try {
          res = M._ffz_ffi_filter_merge(this._ptr, qp, qn,
              o.caseMatching, o.normalization, dist, o.scoring, 0, 0, o.limit);
        } finally { M._free(qp); }
        return this._readFlat(M, res);
      }
    }
  }

  /** Raw-object shorthand for `approx()`. Returns `T[]` instead of `FuzzyHit<T>[]`. */
  approxRaws(query: string, maxDistance?: number, opts?: Partial<FuzzyOptions>): T[] {
    return this.approx(query, maxDistance, opts).map(h => h.raw);
  }

  /** Runs both algorithms independently and returns their results in separate buckets.
   *  `maxDistance` defaults to {@link autoMaxDistance}(query) when omitted. */
  dual(query: string, opts?: Partial<FuzzyOptions> & { maxDistance?: number }): FuzzyDualResult<T> {
    this._alive();
    if (!this._ensureReady()) return { fuzzy: [], approx: [] };
    const { maxDistance, ...rest } = opts ?? {};
    const dist = maxDistance ?? autoMaxDistance(query);
    const o = new FuzzyOptions({ ...this._opts, ...rest });
    const M = this._M!;
    const [qp, qn] = writeUtf8(M, query);
    let d = 0;
    try { d = M._ffz_ffi_filter_dual(this._ptr, qp, qn, o.caseMatching, o.normalization, dist, o.scoring, 0, 0, o.limit); }
    finally { M._free(qp); }
    const sr = M._ffz_ffi_dual_seq(d);
    const er = M._ffz_ffi_dual_edit(d);
    const readSet = (r: number): FuzzyHit<T>[] => {
      const len = M._ffz_ffi_results_len(r);
      const hits = new Array<FuzzyHit<T>>(len);
      for (let i = 0; i < len; i++) {
        const idx = M._ffz_ffi_results_item(r, i);
        const kind = M._ffz_ffi_results_kind(r, i);
        hits[i] = { raw: this._items[idx], index: idx, score: M._ffz_ffi_results_score(r, i),
                    matchedKind: kind, matchedKindCode: kind,
                    matchedKey: M._ffz_ffi_results_key(r, i), indices: [] };
      }
      return hits;
    };
    const result: FuzzyDualResult<T> = { fuzzy: readSet(sr), approx: readSet(er) };
    M._ffz_ffi_dual_free(d);
    return result;
  }

  private _readFlat(M: FfzMod, res: number): FuzzyHit<T>[] {
    const len = M._ffz_ffi_results_len(res);
    const hits = new Array<FuzzyHit<T>>(len);
    for (let i = 0; i < len; i++) {
      const idx = M._ffz_ffi_results_item(res, i);
      const kind = M._ffz_ffi_results_kind(res, i);
      hits[i] = { raw: this._items[idx], index: idx, score: M._ffz_ffi_results_score(res, i),
                  matchedKind: kind, matchedKindCode: kind,
                  matchedKey: M._ffz_ffi_results_key(res, i), indices: [] };
    }
    M._ffz_ffi_results_free(res);
    return hits;
  }

  private _approxRaw(query: string, maxDistance: number, o: FuzzyOptions): FuzzyHit<T>[] {
    if (!this._ensureReady()) return [];
    const M = this._M!;
    const [qp, qn] = writeUtf8(M, query);
    const res = M._ffz_ffi_filter_edit(this._ptr, qp, qn, maxDistance,
        o.caseMatching, o.normalization, o.limit);
    M._free(qp);
    return this._readFlat(M, res);
  }

  // ── lifecycle ────────────────────────────────────────────────────────────────

  dispose(): void {
    if (this._disposed) return;
    this._disposed = true;
    const M = this._M;
    if (!M) return; // deferred — no WASM memory allocated
    M._ffz_ffi_free(this._ptr);
    if (this._scratchCap) { M._free(this._scratch); M._free(this._scratch4); }
  }

  [Symbol.dispose](): void { this.dispose(); }

  // ── internals ─────────────────────────────────────────────────────────────────

  /** Returns true if ready to search; false if still deferred (WASM not loaded). */
  private _ensureReady(): boolean {
    if (!this._deferred) return true;
    if (!_M) return false;
    this._deferred = false;
    this._M = _M;
    const sc = this._opts.scoring;
    this._ptr = this._M._ffz_ffi_new_cfg2(this._matchPaths ? 1 : 0, this._preferPrefix ? 1 : 0, sc);
    if (!this._ptr) throw new Error('FuzzyCorpus: native allocation failed (OOM)');
    this._allocScratch(SCRATCH_INIT);
    this._rebuild();
    return true;
  }

  private _allocScratch(cap: number): void {
    const M = this._M;
    if (this._scratchCap) { M._free(this._scratch); M._free(this._scratch4); }
    this._scratch = M._malloc(cap * 4); this._scratch4 = M._malloc(cap * 4 * 4); this._scratchCap = cap;
  }

  private _ensureScratch(n: number): void {
    if (n > this._scratchCap) this._allocScratch(Math.max(n, this._scratchCap * 2));
  }

  private _nativeAdd(item: T, keys: FuzzyKey[] | null): void {
    const M = this._M;
    if (!M) return; // deferred — caller already buffered item in _items
    if (!keys) {
      const [p, n] = writeUtf8(M, this._stringOf(item));
      M._ffz_ffi_add(this._ptr, p, n); M._free(p); return;
    }
    const nk = keys.length;
    const [ip, ilen] = writeUtf8(M, this._stringOf(item));
    const tP = M._malloc(4 * nk), lP = M._malloc(4 * nk), kP = M._malloc(4 * nk);
    const kPtrs: number[] = [];
    try {
      for (let i = 0; i < nk; i++) {
        const [kp, klen] = writeUtf8(M, keys[i].text);
        kPtrs.push(kp);
        M.HEAPU32[(tP >> 2) + i] = kp;
        M.HEAPU32[(lP >> 2) + i] = klen;
        M.HEAP32 [(kP >> 2) + i] = keys[i].kind;
      }
      M._ffz_ffi_add_keyed(this._ptr, ip, ilen, tP, lP, kP, nk);
    } finally {
      for (const p of kPtrs) M._free(p);
      M._free(tP); M._free(lP); M._free(kP); M._free(ip);
    }
  }

  private _rebuild(): void {
    if (!this._M) return;
    this._M._ffz_ffi_clear(this._ptr);
    for (let i = 0; i < this._items.length; i++) this._nativeAdd(this._items[i], this._keys[i]);
  }

  private _filter(mode: number, query: string, o: FuzzyOptions): number {
    const M = this._M!;
    const [qp, qn] = writeUtf8(M, query);
    let res: number;
    try {
      res = o.highlight
        ? M._ffz_ffi_filter_ex2(this._ptr, qp, qn, mode, o.caseMatching, o.normalization, o.parallel ? 1 : 0, o.threads, o.limit, o.scoring)
        : M._ffz_ffi_filter_raws(this._ptr, qp, qn, mode, o.caseMatching, o.normalization, o.parallel ? 1 : 0, o.threads, o.limit, o.scoring);
    } finally {
      M._free(qp);
    }
    if (!res!) throw new Error('FuzzyCorpus: filter failed (OOM)');
    return res!;
  }

  private _search(mode: number, query: string, overrides: Partial<FuzzyOptions>): FuzzyHit<T>[] {
    this._alive();
    if (!this._ensureReady()) return [];
    const M = this._M!, o = new FuzzyOptions({ ...this._opts, ...overrides });
    const res = this._filter(mode, query, o);
    const len = M._ffz_ffi_results_len(res);
    if (len === 0) { M._ffz_ffi_results_free(res); return []; }

    const hits = new Array<FuzzyHit<T>>(len);
    if (!o.highlight) {
      this._ensureScratch(len);
      const sp = this._scratch4 >> 2;
      M._ffz_ffi_results_bulk(res, this._scratch4, this._scratch4 + len * 4, this._scratch4 + len * 8, this._scratch4 + len * 12, len);
      const H = M.HEAPU32, I = M.HEAP32;
      for (let i = 0; i < len; i++) {
        const idx = H[sp + i];
        const mk = I[sp + len * 2 + i];
        hits[i] = { raw: this._items[idx], index: idx, score: I[sp + len + i], matchedKind: mk, matchedKindCode: mk, matchedKey: H[sp + len * 3 + i], indices: [] };
      }
    } else {
      const canIdx = o.highlight;
      for (let i = 0; i < len; i++) {
        const idx = M._ffz_ffi_results_item(res, i);
        let indices: number[] = [];
        if (canIdx) {
          const ni = M._ffz_ffi_results_nindices(res, i);
          indices = new Array(ni);
          for (let j = 0; j < ni; j++) indices[j] = M._ffz_ffi_results_index(res, i, j);
        }
        const kind = M._ffz_ffi_results_kind(res, i);
        hits[i] = {
          raw: this._items[idx], index: idx,
          score: M._ffz_ffi_results_score(res, i),
          matchedKind: kind, matchedKindCode: kind,
          matchedKey: M._ffz_ffi_results_key(res, i),
          indices,
        };
      }
    }
    M._ffz_ffi_results_free(res);
    return hits;
  }

  private _searchRaws(mode: number, query: string, overrides: Partial<FuzzyOptions>): T[] {
    this._alive();
    if (!this._ensureReady()) return [];
    const M = this._M!, o = new FuzzyOptions({ ...this._opts, ...overrides });
    const [qp, qn] = writeUtf8(M, query);
    const res = M._ffz_ffi_filter_raws(this._ptr, qp, qn, mode, o.caseMatching, o.normalization, o.parallel ? 1 : 0, o.threads, o.limit, o.scoring);
    M._free(qp);
    if (!res) throw new Error('FuzzyCorpus: filter_raws failed (OOM)');
    const len = M._ffz_ffi_results_len(res);
    if (len === 0) { M._ffz_ffi_results_free(res); return []; }
    this._ensureScratch(len);
    M._ffz_ffi_results_items_bulk(res, this._scratch, len);
    const H = M.HEAPU32, base = this._scratch >> 2;
    const out = new Array<T>(len);
    for (let i = 0; i < len; i++) out[i] = this._items[H[base + i]];
    M._ffz_ffi_results_free(res);
    return out;
  }

  /** Non-WASM search for prefix/postfix/exact/substring modes using native JS string ops. */
  private _nativeSearch(mode: number, query: string, overrides: Partial<FuzzyOptions>): FuzzyHit<T>[] {
    this._alive();
    if (!this._ensureReady()) return [];
    const o = new FuzzyOptions({ ...this._opts, ...overrides });
    const lim = o.limit > 0 ? o.limit : this._items.length;
    const out: FuzzyHit<T>[] = [];
    for (let i = 0; i < this._items.length && out.length < lim; i++) {
      const [t, q] = foldPair(this._stringOf(this._items[i]), query, o.caseMatching);
      const match = mode === 1 ? t.includes(q)
                  : mode === 2 ? t.startsWith(q)
                  : mode === 3 ? t.endsWith(q)
                  : mode === 4 ? t === q
                  : false;
      if (match) out.push({ raw: this._items[i], index: i, score: 0, matchedKind: 0, matchedKindCode: 0, matchedKey: 0, indices: [] });
    }
    return out;
  }

  private _alive(): void { if (this._disposed) throw new Error('FuzzyCorpus used after dispose()'); }
  private _bounds(i: number): void {
    if (i < 0 || i >= this._items.length)
      throw new RangeError(`index ${i} out of range [0, ${this._items.length})`);
  }
}

// ── highlight utilities ───────────────────────────────────────────────────────

/**
 * Convert codepoint indices to UTF-16 code-unit offsets. No-op for BMP-only text.
 * Needed for astral-plane characters (emoji, some CJK variants).
 */
export function fuzzyCodepointToUtf16(text: string, codepointIndices: number[]): number[] {
  if (!codepointIndices.length) return [];
  const offsets: number[] = [];
  let u16 = 0;
  for (const ch of text) { offsets.push(u16); u16 += (ch.codePointAt(0) ?? 0) > 0xffff ? 2 : 1; }
  return codepointIndices.map((c) => (c >= 0 && c < offsets.length ? offsets[c] : u16));
}

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
export function highlightHtml(text: string, indices: number[], opts?: { tag?: string }): string {
  const tag = opts?.tag ?? 'mark';
  if (!indices?.length) return esc(text);
  const set = new Set(indices), cps = Array.from(text);
  let out = '', open = false;
  for (let i = 0; i < cps.length; i++) {
    const m = set.has(i);
    if (m && !open)  { out += `<${tag}>`; open = true; }
    if (!m && open)  { out += `</${tag}>`; open = false; }
    out += esc(cps[i]);
  }
  if (open) out += `</${tag}>`;
  return out;
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
