// Web (WASM) platform — C bridge implementation via dart:js_interop.
// Loads assets/ffz-module.js (Emscripten host glue) + assets/ffz.wasm.
// Calls C exports directly — no JS corpus wrapper (ffuzzy-corpus.mjs not used here).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ffuzzy_types.dart';
import 'ffuzzy_corpus.dart';

export 'ffuzzy_types.dart';
export 'ffuzzy_corpus.dart' hide FuzzyCorpusProtected;

// 网页缓冲分配失败的信息。
const _allocationOom = 'ffuzzy: WASM allocation failed (OOM)';
// 新增条目失败的信息。
const _addOom =
    'ffuzzy: add failed (OOM or incompatible engine; rebuild engine)';
// 过滤结果分配失败的信息。
const _filterOom = 'ffz filter returned null (OOM)';
// 语料库分配失败的信息。
const _corpusOom = 'ffz_ffi_new_cfg2 returned null (OOM)';

// ── Enum → C value ────────────────────────────────────────────────────────────

extension on FuzzyScoring {
  // 转换为引擎使用的枚举编号。
  int get _c => switch (this) {
        FuzzyScoring.fast => 0,
        FuzzyScoring.off => 1,
        FuzzyScoring.nucleo => 2
      };
}

extension on FuzzyCase {
  // 转换为引擎使用的枚举编号。
  int get _c => switch (this) {
        FuzzyCase.respect => 0,
        FuzzyCase.ignore => 1,
        FuzzyCase.smart => 2
      };
}

extension on FuzzyNorm {
  // 转换为引擎使用的枚举编号。
  int get _c => switch (this) { FuzzyNorm.never => 0, FuzzyNorm.smart => 1 };
}

// ── WASM module (Emscripten instance) ─────────────────────────────────────────

// 声明网页引擎桥接接口。
extension type _Mod._(JSObject _) implements JSObject {
  // Linear memory — re-read before each access (shifts on memory growth)
  // 读取当前线性内存的字节视图。
  @JS('HEAPU8')
  external JSUint8Array get heapu8;
  // 读取当前线性内存的整数视图。
  @JS('HEAP32')
  external JSInt32Array get heap32;

  // 分配引擎内存，返回地址或零。
  @JS('_malloc')
  external int malloc(int n);
  // 释放引擎内存。
  @JS('_free')
  external void free(int ptr);

  // 按路径和评分选项创建语料库。
  @JS('_ffz_ffi_new_cfg2')
  external int newCfg2(int mp, int pp, int sc);
  // 新增条目，返回一表示提交成功。
  @JS('_ffz_ffi_add')
  external int add(int cp, int sp, int len);
  // 新增带显式附加键的条目，返回一表示提交成功。
  @JS('_ffz_ffi_add_keyed')
  external int addKeyed(int cp, int sp, int len, int tp, int lp, int kp, int n);
  // 清空引擎语料库。
  @JS('_ffz_ffi_clear')
  external void corpusClear(int cp);
  // 释放引擎语料库。
  @JS('_ffz_ffi_free')
  external void corpusFree(int cp);

  // 按模式过滤并返回完整结果句柄。
  @JS('_ffz_ffi_filter_ex2')
  external int filterEx2(int cp, int qp, int qlen, int mode, int cm, int nm,
      int par, int thr, int lim, int sc);
  // 按模式过滤并省略高亮。
  @JS('_ffz_ffi_filter_raws')
  external int filterRaws(int cp, int qp, int qlen, int mode, int cm, int nm,
      int par, int thr, int lim, int sc);
  // 执行近似子串过滤。
  @JS('_ffz_ffi_filter_edit')
  external int filterEdit(
      int cp, int qp, int qlen, int maxDist, int cm, int nm, int lim);
  // 执行合并过滤。
  @JS('_ffz_ffi_filter_merge')
  external int filterMerge(int cp, int qp, int qlen, int cm, int nm,
      int maxDist, int sc, int par, int thr, int lim);
  // 执行回退过滤。
  @JS('_ffz_ffi_filter_fallback')
  external int filterFallback(int cp, int qp, int qlen, int cm, int nm,
      int maxDist, int sc, int par, int thr, int lim);
  // 执行双路过滤。
  @JS('_ffz_ffi_filter_dual')
  external int filterDual(int cp, int qp, int qlen, int cm, int nm, int maxDist,
      int sc, int par, int thr, int lim);
  // 读取双路句柄中的子序列结果。
  @JS('_ffz_ffi_dual_seq')
  external int dualSeq(int d);
  // 读取双路句柄中的近似结果。
  @JS('_ffz_ffi_dual_edit')
  external int dualEdit(int d);
  // 释放双路结果句柄。
  @JS('_ffz_ffi_dual_free')
  external void dualFree(int d);

  // 读取命中数量。
  @JS('_ffz_ffi_results_len')
  external int rLen(int r);
  // 读取命中的原始条目下标。
  @JS('_ffz_ffi_results_item')
  external int rItem(int r, int i);
  // 读取命中分数。
  @JS('_ffz_ffi_results_score')
  external int rScore(int r, int i);
  // 读取命中的键类型。
  @JS('_ffz_ffi_results_kind')
  external int rKind(int r, int i);
  // 读取命中的键下标。
  @JS('_ffz_ffi_results_key')
  external int rKey(int r, int i);
  // 读取高亮码点数。
  @JS('_ffz_ffi_results_nindices')
  external int rNIdx(int r, int i);
  // 读取指定高亮码点下标。
  @JS('_ffz_ffi_results_index')
  external int rIdx(int r, int i, int j);
  // 释放结果句柄。
  @JS('_ffz_ffi_results_free')
  external void rFree(int r);
}

@JS('_ffzModule')
external _Mod? get _module;

@JS('_ffzInitPromise')
external JSPromise<JSAny?>? get _initPromise;

// ── Init ──────────────────────────────────────────────────────────────────────

bool _ready = false;
// Completes when ffuzzyInit finishes — either successfully (_ready=true) or
// with failure (_ready stays false). Either way, deferred corpora can unblock.
final _readyCompleter = Completer<void>();

// 共享正在进行的网页初始化。
Future<void>? _initializing;

/// 初始化网页引擎；[webAssetsUrl] 为本地模块地址，[webUrl] 为远程模块地址，前者优先。
/// 返回初始化完成通知，并发调用共享初始化；成功后重复调用立即完成。
/// 两地址均省略时抛 ArgumentError；加载失败或超时抛 FuzzyException，可重试。
///
/// 示例：`await ffuzzyInit(webUrl: "/ffz.mjs");`。
Future<void> ffuzzyInit({String? webAssetsUrl, String? webUrl}) {
  if (_ready) return Future.value();
  return _initializing ??= _initialize(webAssetsUrl, webUrl).whenComplete(() {
    _initializing = null;
  });
}

// 加载模块并完成共享初始化状态。
Future<void> _initialize(String? webAssetsUrl, String? webUrl) async {
  if (_ready) return;
  if (webAssetsUrl == null && webUrl == null) {
    throw ArgumentError(
      'ffuzzyInit: on web, provide webAssetsUrl (local Flutter asset) '
      'or webUrl (CDN / remote URL).',
    );
  }
  final url = webAssetsUrl ?? webUrl!; // assets takes priority

  // Inject a module script that imports ffz.mjs (WASM inlined as base64)
  // and instantiates it. No separate fetch — WASM bytes are already embedded.
  final el = web.document.createElement('script') as web.HTMLScriptElement;
  el.type = 'module';
  el.textContent = '''
    {
      let _res, _rej;
      globalThis._ffzInitPromise =
          new Promise((res, rej) => { _res = res; _rej = rej; });
      (async () => {
        try {
          const { default: create } = await import(${jsonEncode(url)});
          globalThis._ffzModule = await create();
          _res();
        } catch (e) { _rej(e); }
      })();
    }
  ''';
  (web.document.head ?? web.document.body!).append(el);

  // Module scripts are deferred — poll for the Promise (set synchronously).
  JSPromise<JSAny?>? promise;
  for (var ms = 10; ms <= 1280 && promise == null; ms *= 2) {
    await Future.delayed(Duration(milliseconds: ms));
    promise = _initPromise;
  }
  if (promise == null) {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    throw FuzzyException('ffuzzy: WASM init timed out — check URL: $url');
  }
  try {
    await promise.toDart;
  } catch (e) {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    throw FuzzyException('ffuzzy: WASM init failed: $e');
  }
  _ready = true;
  if (!_readyCompleter.isCompleted) _readyCompleter.complete();
}

// ignore: non_constant_identifier_names
_Mod get _M {
  final m = _module;
  if (m == null) throw const FuzzyException('ffuzzy: WASM not initialized');
  return m;
}

// ── WASM memory helpers ───────────────────────────────────────────────────────

// 分配并写入字节，内存增长后重新读取视图。
int _wAlloc(Uint8List bytes) {
  // 读取已加载模块，缺失时抛平台异常。
  final M = _M;
  final len = bytes.isEmpty ? 1 : bytes.length;
  final ptr = M.malloc(len);
  if (ptr == 0) {
    throw const FuzzyException(_allocationOom);
  }
  final heap = M.heapu8.toDart;
  if (bytes.isEmpty) {
    heap[ptr] = 0;
  } else {
    heap.setAll(ptr, bytes);
  }
  return ptr;
}

// 释放临时查询或键缓冲。
void _wFree(int ptr) => _M.free(ptr);

// ── FuzzyCorpus (web) ─────────────────────────────────────────────────────────

/// 可反复搜索的语料库；用完后调用 dispose 释放资源。
/// 引擎未就绪时同步搜索返回空结果，异步搜索等待初始化完成。
/// 类型参数 T 为原始条目类型。
///
/// 示例：`final c = FuzzyCorpus.strings(["你好"]); c.dispose();`。
final class FuzzyCorpus<T> extends FuzzyCorpusProtected<T> {
  /// 创建语料库；[items] 为初始条目，[stringOf] 提取搜索文本，[options] 为默认选项。
  /// [matchPaths] 启用路径匹配，[preferPrefix] 优先前缀。
  /// 返回新实例；文本提取异常向上传递，资源不足抛 FuzzyException。
  ///
  /// 示例：`final c = FuzzyCorpus(["你好"], stringOf: (s) => s); c.dispose();`。
  FuzzyCorpus(
    Iterable<T> items, {
    required String Function(T) stringOf,
    FuzzyOptions options = const FuzzyOptions(),
    bool matchPaths = false,
    bool preferPrefix = false,
    String? libraryPath, // ignored on web
  }) : super(options: options, stringOf_: stringOf) {
    _matchPaths = matchPaths;
    _preferPrefix = preferPrefix;
    if (!_ready) {
      cDeferred_ = true;
      for (final item in items) {
        items_.add(item);
        keys_.add(null);
      }
      return;
    }
    _cp = _M.newCfg2(
        matchPaths ? 1 : 0, preferPrefix ? 1 : 0, options.scoring._c);
    if (_cp == 0) {
      throw const FuzzyException(_corpusOom);
    }
    try {
      addAll(items);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  // ── Static constructors ───────────────────────────────────────────────────

  /// 创建字符串语料库；[items] 为条目，[options] 为搜索选项。
  /// [matchPaths] 启用路径匹配，[preferPrefix] 优先前缀。
  /// 返回新语料库；资源不足抛 FuzzyException。
  ///
  /// 示例：`final c = FuzzyCorpus.strings(["你好"]); c.dispose();`。
  static FuzzyCorpus<String> strings(Iterable<String> items,
          {FuzzyOptions options = const FuzzyOptions(),
          bool matchPaths = false,
          bool preferPrefix = false,
          String? libraryPath}) =>
      FuzzyCorpus<String>(items,
          stringOf: (s) => s,
          options: options,
          matchPaths: matchPaths,
          preferPrefix: preferPrefix);

  /// 以 [items] 中的 [field] 字段建立语料库，缺失字段视为空文本。
  /// [options] 为搜索选项，[matchPaths] 启用路径匹配，[preferPrefix] 优先前缀。
  /// 返回新语料库；资源不足抛 FuzzyException。
  ///
  /// 示例：`final c = FuzzyCorpus.byKey([{"name": "你好"}], "name"); c.dispose();`。
  static FuzzyCorpus<Map<String, dynamic>> byKey(
          Iterable<Map<String, dynamic>> items, String field,
          {FuzzyOptions options = const FuzzyOptions(),
          bool matchPaths = false,
          bool preferPrefix = false,
          String? libraryPath}) =>
      FuzzyCorpus<Map<String, dynamic>>(items,
          stringOf: (m) => (m[field] ?? '').toString(),
          options: options,
          matchPaths: matchPaths,
          preferPrefix: preferPrefix);

  /// 以 [items] 中 [fields] 的首字段为原始文本，其余为附加键；缺失字段视为空文本。
  /// [fields] 为空时抛 ArgumentError；[options] 为选项，[matchPaths] 启用路径匹配，[preferPrefix] 优先前缀。
  /// 返回新语料库；资源不足抛 FuzzyException。
  ///
  /// 示例：`final c = FuzzyCorpus.byKeys([{"name": "你好"}], ["name"]); c.dispose();`。
  static FuzzyCorpus<Map<String, dynamic>> byKeys(
      Iterable<Map<String, dynamic>> items, List<String> fields,
      {FuzzyOptions options = const FuzzyOptions(),
      bool matchPaths = false,
      bool preferPrefix = false,
      String? libraryPath}) {
    if (fields.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'must not be empty');
    }
    final c = FuzzyCorpus<Map<String, dynamic>>([],
        stringOf: (m) => (m[fields.first] ?? '').toString(),
        options: options,
        matchPaths: matchPaths,
        preferPrefix: preferPrefix);
    for (final item in items) {
      if (fields.length == 1) {
        c.add(item);
      } else {
        c.addKey(item, [
          for (var i = 1; i < fields.length; i++)
            FuzzyKey((item[fields[i]] ?? '').toString(),
                kind: FuzzyKeyKind.custom.code)
        ]);
      }
    }
    return c;
  }

  /// 异步创建语料库；[items] 为条目，[stringOf] 提取文本，[options] 为选项。
  /// [matchPaths] 启用路径匹配，[preferPrefix] 优先前缀。
  /// 返回完成构建的新语料库；提取文本的异常向上传递，资源不足抛 FuzzyException。
  ///
  /// 示例：`final c = await FuzzyCorpus.asyncBuild(["你好"], stringOf: (s) => s); c.dispose();`。
  static Future<FuzzyCorpus<T>> asyncBuild<T>(Iterable<T> items,
      {required String Function(T) stringOf,
      FuzzyOptions options = const FuzzyOptions(),
      bool matchPaths = false,
      bool preferPrefix = false,
      String? libraryPath}) async {
    final c = FuzzyCorpus<T>([],
        stringOf: stringOf,
        options: options,
        matchPaths: matchPaths,
        preferPrefix: preferPrefix);
    await c.asyncAddAll(items);
    return c;
  }

  // ── WASM-specific state ───────────────────────────────────────────────────

  int _cp = 0; // WASM corpus pointer
  bool _matchPaths = false;
  bool _preferPrefix = false;

  /// Completes when [ffuzzyInit] finishes (success or failure).
  /// On failure [isReady] stays `false` and searches return `[]`.
  Future<void> get ready => _ready ? Future.value() : _readyCompleter.future;

  /// `true` once the WASM engine has loaded successfully.
  bool get isReady => _ready;

  // Called at search time. If WASM has since loaded, do the one-time C alloc
  // + rebuild; otherwise stays deferred and searches return [].
  // 引擎就绪后一次性补建延迟语料库。
  void _ensureReady() {
    if (disposed_ || !cDeferred_ || !_ready) return;
    _cp = _M.newCfg2(
        _matchPaths ? 1 : 0, _preferPrefix ? 1 : 0, options.scoring._c);
    if (_cp == 0) {
      throw const FuzzyException(_corpusOom);
    }
    cDeferred_ = false;
    try {
      rebuild_();
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  // ── Bridge (WASM) ─────────────────────────────────────────────────────────

  // 新增原始键，失败时抛错并阻止宿主提交条目。
  @override
  void cAdd_(Uint8List bytes) {
    if (cDeferred_) {
      return; // 延迟条目由首次就绪时统一写入。
    }
    final sp = _wAlloc(bytes);
    try {
      if (_M.add(_cp, sp, bytes.length) != 1) {
        throw const FuzzyException(_addOom);
      }
    } finally {
      _wFree(sp);
    }
  }

  // 新增原始键及附加键，失败时阻止宿主提交条目。
  @override
  void cAddKeyed_(Uint8List primary, List<FuzzyKey> keys) {
    if (cDeferred_) return;
    final M = _M;
    final sp = _wAlloc(primary);
    final n = keys.length;
    final ta = M.malloc(n * 4);
    final la = M.malloc(n * 4);
    final ka = M.malloc(n * 4);
    final kPtrs = <int>[];
    try {
      if (ta == 0 || la == 0 || ka == 0) {
        throw const FuzzyException(_allocationOom);
      }
      for (var i = 0; i < n; i++) {
        final kb = toUtf8(keys[i].text);
        // _wAlloc below can trigger WebAssembly.Memory.grow(), which detaches
        // any typed-array view taken over the old buffer — so M.heap32 must
        // be re-read AFTER each allocation, never cached across one. (This is
        // the same discipline _wAlloc itself already follows internally.)
        final kp = _wAlloc(kb);
        kPtrs.add(kp);
        final h32 = M.heap32.toDart;
        h32[(ta >> 2) + i] = kp;
        h32[(la >> 2) + i] = kb.length;
        h32[(ka >> 2) + i] = keys[i].kind;
      }
      if (M.addKeyed(_cp, sp, primary.length, ta, la, ka, n) != 1) {
        throw const FuzzyException(_addOom);
      }
    } finally {
      for (final p in kPtrs) {
        _wFree(p);
      }
      _wFree(ta);
      _wFree(la);
      _wFree(ka);
      _wFree(sp);
    }
  }

  // 清空平台索引并释放键存储。
  @override
  void cClear_() {
    if (!cDeferred_) _M.corpusClear(_cp);
  }

  // 释放平台语料库。
  @override
  void cFree_() {
    if (!cDeferred_) _M.corpusFree(_cp);
  }

  // ── Search bridge ─────────────────────────────────────────────────────────

  // Returns true when the corpus is still deferred (caller should return empty).
  // 检查生命周期并判断同步搜索是否仍须等待引擎。
  bool _guardSync() {
    check_();
    _ensureReady();
    return cDeferred_;
  }

  // 同步检查并补建延迟索引。
  @override
  void syncEnsureReady_() => _ensureReady();

  // 等待引擎后复查生命周期并补建延迟索引。
  Future<void> _awaitReady() async {
    if (!cDeferred_) return;
    await _readyCompleter.future;
    check_();
    _ensureReady();
  }

  // 等待平台引擎就绪并检查语料库生命周期。
  @override
  Future<void> asyncEnsureReady_() async {
    await _awaitReady();
  }

  // 执行指定模式的同步搜索。
  @override
  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o) {
    if (_guardSync()) return [];
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = o.highlight
          ? M.filterEx2(
              _cp,
              qp,
              qb.length,
              mode,
              o.caseMatching._c,
              o.normalization._c,
              o.parallel ? 1 : 0,
              o.threads,
              o.limit,
              o.scoring._c)
          : M.filterRaws(
              _cp,
              qp,
              qb.length,
              mode,
              o.caseMatching._c,
              o.normalization._c,
              o.parallel ? 1 : 0,
              o.threads,
              o.limit,
              o.scoring._c);
      if (r == 0) throw StateError(_filterOom);
      return _readHits(M, r, o.highlight);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

  // 仅返回指定模式搜索的原始条目。
  @override
  List<T> searchRaws_(int mode, String q, FuzzyOptions o) {
    if (_guardSync()) return [];
    return [
      for (final h in search_(mode, q, o.copyWith(highlight: false))) h.raw
    ];
  }

  // 网页引擎同步执行；异步入口先等待加载，再返回实际搜索结果。
  // 执行异步搜索并跟踪在途调用。
  @override
  Future<List<FuzzyHit<T>>> searchAsync_(
      int mode, String q, FuzzyOptions o) async {
    check_();
    await _awaitReady();
    inFlight_++;
    try {
      return search_(mode, q, o);
    } finally {
      inFlight_--;
      signalIfIdle_();
    }
  }

  // 异步返回原始条目并维护生命周期。
  @override
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o) async {
    check_();
    await _awaitReady();
    inFlight_++;
    try {
      return searchRaws_(mode, q, o);
    } finally {
      inFlight_--;
      signalIfIdle_();
    }
  }

  // 复用查询缓冲及结果释放逻辑调用组合搜索。
  List<FuzzyHit<T>> _callWasmFilter(
      int Function(int cp, int qp, int qlen, int cm, int nm, int maxDist,
              int sc, int par, int thr, int lim)
          fn,
      String q,
      int maxDist,
      FuzzyOptions o) {
    if (_guardSync()) return [];
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = fn(_cp, qp, qb.length, o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (r == 0) throw StateError('ffuzzy: filter returned null (OOM)');
      return _readHits(M, r, o.highlight);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

  // 先执行子序列搜索，无命中时回退到近似搜索。
  @override
  List<FuzzyHit<T>> searchFallback_(String q, int maxDist, FuzzyOptions o) =>
      _callWasmFilter(
          (cp, qp, qlen, cm, nm, md, sc, par, thr, lim) =>
              _M.filterFallback(cp, qp, qlen, cm, nm, md, sc, par, thr, lim),
          q,
          maxDist,
          o);

  // 分别读取子序列与近似搜索结果。
  @override
  FuzzyDualResult<T> searchDualC_(String q, int maxDist, FuzzyOptions o) {
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int d = 0;
    try {
      d = M.filterDual(
          _cp,
          qp,
          qb.length,
          o.caseMatching._c,
          o.normalization._c,
          maxDist,
          o.scoring._c,
          o.parallel ? 1 : 0,
          o.threads,
          o.limit);
      if (d == 0) throw StateError('ffz_ffi_filter_dual returned null (OOM)');
      final sr = M.dualSeq(d);
      final er = M.dualEdit(d);
      final seqHits = sr != 0 ? _readHits(M, sr, o.highlight) : <FuzzyHit<T>>[];
      final editHits =
          er != 0 ? _readHits(M, er, o.highlight) : <FuzzyHit<T>>[];
      return FuzzyDualResult(fuzzy: seqHits, approx: editHits);
    } finally {
      _wFree(qp);
      if (d != 0) M.dualFree(d);
    }
  }

  // 执行子序列与近似结果合并搜索。
  @override
  List<FuzzyHit<T>> searchMerge_(String q, int maxDist, FuzzyOptions o) =>
      _callWasmFilter(
          (cp, qp, qlen, cm, nm, md, sc, par, thr, lim) =>
              _M.filterMerge(cp, qp, qlen, cm, nm, md, sc, par, thr, lim),
          q,
          maxDist,
          o);

  // 执行编辑距离搜索并按需读取高亮。
  @override
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o) {
    if (_guardSync()) return [];
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = M.filterEdit(_cp, qp, qb.length, maxDist, o.caseMatching._c,
          o.normalization._c, o.limit);
      if (r == 0) throw StateError(_filterOom);
      return _readHits(M, r, o.highlight);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

  // Web: WASM is synchronous, so — like searchAsync_ above — these just wait
  // for engine readiness (if deferred) before calling the sync path; there is
  // no worker-isolate offload to do on this platform.
  // 异步执行编辑距离搜索。
  @override
  Future<List<FuzzyHit<T>>> searchEditAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    await _awaitReady();
    inFlight_++;
    try {
      return searchEdit_(q, maxDist, o);
    } finally {
      inFlight_--;
      signalIfIdle_();
    }
  }

  // 异步执行合并搜索。
  @override
  Future<List<FuzzyHit<T>>> searchMergeAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    await _awaitReady();
    inFlight_++;
    try {
      return searchMerge_(q, maxDist, o);
    } finally {
      inFlight_--;
      signalIfIdle_();
    }
  }

  // 异步执行回退搜索。
  @override
  Future<List<FuzzyHit<T>>> searchFallbackAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    await _awaitReady();
    inFlight_++;
    try {
      return searchFallback_(q, maxDist, o);
    } finally {
      inFlight_--;
      signalIfIdle_();
    }
  }

  // 异步执行双路搜索。
  @override
  Future<FuzzyDualResult<T>> searchDualAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    await _awaitReady();
    inFlight_++;
    try {
      return searchDualC_(q, maxDist, o);
    } finally {
      inFlight_--;
      signalIfIdle_();
    }
  }

  // 将原生结果转换为宿主命中对象，按需读取高亮。
  List<FuzzyHit<T>> _readHits(_Mod M, int r, bool highlight) {
    final n = M.rLen(r);
    final out = <FuzzyHit<T>>[];
    for (var i = 0; i < n; i++) {
      final idx = M.rItem(r, i);
      if (idx >= items_.length) continue;
      List<int> indices = const [];
      if (highlight) {
        final ni = M.rNIdx(r, i);
        indices = List<int>.generate(ni, (j) => M.rIdx(r, i, j));
      }
      final kind = M.rKind(r, i);
      out.add(FuzzyHit<T>(items_[idx], idx, M.rScore(r, i), kindOf(kind), kind,
          M.rKey(r, i), indices));
    }
    return out;
  }

  // ── Async build ───────────────────────────────────────────────────────────

  /// 异步追加 [items]，返回完成通知；文本提取异常向上传递。
  /// 销毁后、构建中或搜索未完成时调用抛 StateError；资源不足抛 FuzzyException。
  /// 失败时保留已提交的前缀。
  ///
  /// 示例：`await corpus.asyncAddAll(["你好"]);`。
  Future<void> asyncAddAll(Iterable<T> items) async {
    checkMutate_();
    building_ = true;
    try {
      // Can't call the public addAll() here: it re-runs checkMutate_(), which
      // throws StateError('...build in progress') because building_ is
      // already true at this point — 100% reproducible, not a race. Do the
      // same per-item work addAll() does, directly.
      await Future.microtask(() {
        for (final item in items) {
          nAdd_(item, null);
          items_.add(item);
          keys_.add(null);
        }
      });
    } finally {
      building_ = false;
      signalIfIdle_();
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// 释放语料库；无参数，无返回值，可重复调用。
  /// 调用后禁止搜索和修改；未结束的操作完成后释放资源。
  ///
  /// 示例：`corpus.dispose();`。
  void dispose() {
    if (disposed_) return;
    disposed_ = true;
    if (inFlight_ > 0 || building_) {
      unawaited(asyncDispose());
      return;
    }
    if (!freed_) {
      freed_ = true;
      cFree_();
    }
  }

  /// 销毁语料库并等待在途操作完成；无参数，返回资源释放完成通知。
  /// 可重复调用；调用后禁止搜索和修改。
  ///
  /// 示例：`await corpus.asyncDispose();`。
  Future<void> asyncDispose() async {
    disposed_ = true;
    if (inFlight_ > 0 || building_) {
      await (idle_ ??= Completer<void>()).future;
    }
    if (freed_) return;
    freed_ = true;
    cFree_();
  }
}

// ── FuzzyCrash (stub on web) ──────────────────────────────────────────────────

class FuzzyCrash {
  FuzzyCrash._();
  static bool install({String? breadcrumbPath, String? libraryPath}) => false;
  static String? lastReport({String? breadcrumbPath}) => null;
}
