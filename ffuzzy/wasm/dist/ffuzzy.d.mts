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
 * 按查询码点数选择默认编辑距离。
 * @param query 查询文本。
 * @returns 零至二码点返回零，三至五码点返回一，其余返回二。
 * @example autoMaxDistance("你好世界"); // 返回一
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
 * 可反复搜索的常驻语料库，用完后调用 dispose 释放资源。
 * @typeParam T 原始条目类型，默认字符串。
 * @example const c = FuzzyCorpus.strings(["你好"]); c.fuzzy("你"); c.dispose();
 */
declare class FuzzyCorpus<T = string> {
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
  /**
   * 创建可反复搜索的语料库。
   * @param items 初始条目，可省略。
   * @param init 文本提取函数及默认选项，可省略。
   * @returns 新语料库；引擎未就绪时同步搜索返回空结果。
   * @throws {Error} 资源不足或文本回调失败。
   * @example const c = new FuzzyCorpus(["你好"]); c.dispose();
   */
  constructor(items?: Iterable<T>, init?: FuzzyCorpusInit<T>);
  /** Resolves when the engine finishes loading (success or failure). Useful for
   *  re-triggering a search after a corpus created before `ffuzzyInitialize`:
   *  ```ts
   *  corpus.ready.then(() => { if (corpus.isReady) renderResults(corpus.fuzzy(q)); });
   *  ``` */
  get ready(): Promise<void>;
  /**
   * 读取当前语料库是否可搜索。
   *
   * @returns 引擎已就绪且语料库未销毁时为真。
   * @example corpus.isReady;
   */
  get isReady(): boolean;
  static strings(items?: Iterable<string>, opts?: Omit<FuzzyCorpusInit<string>, 'stringOf'>): FuzzyCorpus<string>;
  static byKey<T extends Record<string, unknown>>(maps?: Iterable<T>, field?: FieldPath<T> | (string & {}), opts?: Omit<FuzzyCorpusInit<T>, 'stringOf'>): FuzzyCorpus<T>;
  /**
   * 按首字段及其余字段建立原始键和附加键。
   * @param maps 初始条目，可省略。
   * @param fields 字段路径；不能为空。
   * @param opts 默认选项，可省略。
   * @returns 新语料库；字段缺失视为空文本。
   * @throws {Error} 资源不足或文本回调失败。
   * @throws {Error} fields 为空。
   * @example const c = FuzzyCorpus.byKeys([{name: "你好"}], ["name"]); c.dispose();
   */
  static byKeys<T extends Record<string, unknown>>(maps?: Iterable<T>, fields?: (FieldPath<T> | (string & {}))[], opts?: Omit<FuzzyCorpusInit<T>, 'stringOf'>): FuzzyCorpus<T>;
  get length(): number;
  /**
   * 新增条目，失败保留已有条目。
   * @param item 待加入条目。
   * @returns 空值。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @example corpus.add("你好");
   */
  add(item: T): void;
  /**
   * 依次新增条目，失败保留已加入的前缀。
   * @param items 待加入条目。
   * @returns 空值。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @example corpus.addAll(["你好"]);
   */
  addAll(items: Iterable<T>): void;
  /**
   * 新增条目和附加键，原始键自动保留。
   * @param item 待加入条目。
   * @param keys 附加键，允许为空。
   * @returns 空值。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @example corpus.addKey("你好", [new FuzzyKey("nihao")]);
   */
  addKey(item: T, keys: FuzzyKey[]): void;
  /**
   * 替换条目并清除其附加键；重建失败时条目截断为已写入的前缀。
   * @param index 从零开始的索引。
   * @param item 新条目。
   * @returns 空值。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @throws {RangeError} 索引不是有效整数或越界。
   * @example corpus.update(0, "你好");
   */
  update(index: number, item: T): void;
  /**
   * 删除指定条目；重建失败时条目截断为已写入的前缀。
   * @param index 从零开始的索引。
   * @returns 空值。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @throws {RangeError} 索引不是有效整数或越界。
   * @example corpus.removeAt(0);
   */
  removeAt(index: number): void;
  /**
   * 删除满足条件的条目；回调失败时不提交本次筛选。
   * @param test 删除条件，回调异常向上传递。
   * @returns 删除数量。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @example corpus.removeWhere(s => s === "");
   */
  removeWhere(test: (item: T) => boolean): number;
  /**
   * 刷新现有条目；提供来源时替换条目并清除附加键；重建失败时条目截断为已写入的前缀。
   * @param source 新来源，省略时保留现有条目及键。
   * @returns 空值。
   * @throws {Error} 语料库已销毁、资源不足或文本回调失败。
   * @example corpus.refresh(["你好"]);
   */
  refresh(source?: Iterable<T>): void;
  clear(): void;
  /**
   * 子序列搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.fuzzy("你好");
   */
  fuzzy(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 子串搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.substring("你好");
   */
  substring(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 前缀搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.prefix("你好");
   */
  prefix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 后缀搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.postfix("你好");
   */
  postfix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 后缀搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.suffix("你好");
   */
  suffix(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 完整文本搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.exact("你好");
   */
  exact(query: string, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 子序列搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.fuzzyRaws("你好");
   */
  fuzzyRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 子串搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.substringRaws("你好");
   */
  substringRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 前缀搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.prefixRaws("你好");
   */
  prefixRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 后缀搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.postfixRaws("你好");
   */
  postfixRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 后缀搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.suffixRaws("你好");
   */
  suffixRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 完整文本搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.exactRaws("你好");
   */
  exactRaws(query: string, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 统一搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   *   opts.strategy 选择算法，默认 `'fuzzy'`：`'fuzzy'` 为子序列匹配；`'approx'` 为编辑距离近似匹配；
   *   `'fallback'` 先做子序列匹配，无命中时再退到近似匹配；`'merge'` 同时运行两种算法，子序列命中排在前。
   *   opts.maxDistance 为最大编辑距离，须为 0–10 的整数，省略时按查询码点数自动选择。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {RangeError} 显式距离不是零至十的整数，或近似、回退、合并、双路查询超过六十四码点。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.searchRaws("你好");
   */
  searchRaws(query: string, opts?: Partial<FuzzyOptions> & {
    strategy?: SearchStrategy;
    maxDistance?: number;
  }): T[];
  /**
   * 近似子串搜索。
   * @param query 查询文本。
   * @param maxDistance 最大编辑距离，省略时按查询码点数自动选择。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {RangeError} 显式距离不是零至十的整数，或近似、回退、合并、双路查询超过六十四码点。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.approx("你好");
   */
  approx(query: string, maxDistance?: number, opts?: Partial<FuzzyOptions>): FuzzyHit<T>[];
  /**
   * 统一搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   *   opts.strategy 选择算法，默认 `'fuzzy'`：`'fuzzy'` 为子序列匹配；`'approx'` 为编辑距离近似匹配；
   *   `'fallback'` 先做子序列匹配，无命中时再退到近似匹配；`'merge'` 同时运行两种算法，子序列命中排在前。
   *   opts.maxDistance 为最大编辑距离，须为 0–10 的整数，省略时按查询码点数自动选择。
   * @returns 命中列表，highlight 为真时包含码点下标。引擎未就绪时返回空结果。
   * @throws {RangeError} 显式距离不是零至十的整数，或近似、回退、合并、双路查询超过六十四码点。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.search("你好");
   */
  search(query: string, opts?: Partial<FuzzyOptions> & {
    strategy?: SearchStrategy;
    maxDistance?: number;
  }): FuzzyHit<T>[];
  /**
   * 近似子串搜索。
   * @param query 查询文本。
   * @param maxDistance 最大编辑距离，省略时按查询码点数自动选择。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。
   * @returns 原始条目列表。引擎未就绪时返回空结果。
   * @throws {RangeError} 显式距离不是零至十的整数，或近似、回退、合并、双路查询超过六十四码点。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.approxRaws("你好");
   */
  approxRaws(query: string, maxDistance?: number, opts?: Partial<FuzzyOptions>): T[];
  /**
   * 双路搜索。
   * @param query 查询文本。
   * @param opts 搜索选项，省略的字段沿用语料库选项；limit 非正数表示不限。 maxDistance 默认按查询码点数自动选择。
   * @returns 独立的子序列和近似命中列表。引擎未就绪时返回空结果。
   * @throws {RangeError} 显式距离不是零至十的整数，或近似、回退、合并、双路查询超过六十四码点。
   * @throws {Error} 语料库已销毁或资源不足。
   * @example corpus.dual("你好");
   */
  dual(query: string, opts?: Partial<FuzzyOptions> & {
    maxDistance?: number;
  }): FuzzyDualResult<T>;
  private _readHits;
  private _readFlat;
  private _approxRaw;
  /**
   * 销毁语料库，可重复调用。
   *
   * @returns 空值；销毁后搜索和修改抛出 Error。
   * @example corpus.dispose();
   */
  dispose(): void;
  [Symbol.dispose](): void;
  /** Returns true if ready to search; false if still deferred (WASM not loaded). */
  private _ensureReady;
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
export { FieldPath, FuzzyCase, FuzzyCorpus, FuzzyCorpusInit, FuzzyDualResult, FuzzyHit, FuzzyKey, FuzzyKeyKind, FuzzyMode, FuzzyNorm, FuzzyOptions, FuzzyScoring, SearchStrategy, autoMaxDistance, ffuzzyInitialize, ffuzzyReady, fuzzyCodepointToUtf16, highlightHtml };