// Web (WASM) platform — C bridge implementation via dart:js_interop.
// Loads assets/ffz-module.js (Emscripten host glue) + assets/ffz.wasm.
// Calls C exports directly — no JS corpus wrapper (ffuzzy-corpus.mjs not used here).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ffuzzy_types.dart';
import 'ffuzzy_corpus.dart';

export 'ffuzzy_types.dart';
export 'ffuzzy_corpus.dart' hide FuzzyCorpusProtected;

// ── Enum → C value ────────────────────────────────────────────────────────────

extension on FuzzyScoring {
  int get _c => switch (this) { FuzzyScoring.fast=>0, FuzzyScoring.off=>1, FuzzyScoring.nucleo=>2 };
}
extension on FuzzyCase {
  int get _c => switch (this) { FuzzyCase.respect=>0, FuzzyCase.ignore=>1, FuzzyCase.smart=>2 };
}
extension on FuzzyNorm {
  int get _c => switch (this) { FuzzyNorm.never=>0, FuzzyNorm.smart=>1 };
}

// ── WASM module (Emscripten instance) ─────────────────────────────────────────

extension type _Mod._(JSObject _) implements JSObject {
  // Linear memory — re-read before each access (shifts on memory growth)
  @JS('HEAPU8')  external JSUint8Array  get heapu8;
  @JS('HEAP32')  external JSInt32Array  get heap32;

  @JS('_malloc') external int    malloc(int n);
  @JS('_free')   external void   free(int ptr);

  @JS('_ffz_ffi_new_cfg2') external int newCfg2(int mp, int pp, int sc);
  @JS('_ffz_ffi_add')      external void add(int cp, int sp, int len);
  @JS('_ffz_ffi_add_keyed') external void addKeyed(int cp, int sp, int len,
      int tp, int lp, int kp, int n);
  @JS('_ffz_ffi_clear')    external void corpusClear(int cp);
  @JS('_ffz_ffi_free')     external void corpusFree(int cp);

  @JS('_ffz_ffi_filter_ex2')
  external int filterEx2(int cp, int qp, int qlen,
      int mode, int cm, int nm, int par, int thr, int lim, int sc);
  @JS('_ffz_ffi_filter_raws')
  external int filterRaws(int cp, int qp, int qlen,
      int mode, int cm, int nm, int par, int thr, int lim, int sc);
  @JS('_ffz_ffi_filter_edit')
  external int filterEdit(int cp, int qp, int qlen,
      int maxDist, int cm, int nm, int lim);
  @JS('_ffz_ffi_filter_merge')
  external int filterMerge(int cp, int qp, int qlen,
      int cm, int nm, int maxDist, int sc, int par, int thr, int lim);
  @JS('_ffz_ffi_filter_fallback')
  external int filterFallback(int cp, int qp, int qlen,
      int cm, int nm, int maxDist, int sc, int par, int thr, int lim);
  @JS('_ffz_ffi_filter_dual')
  external int filterDual(int cp, int qp, int qlen,
      int cm, int nm, int maxDist, int sc, int par, int thr, int lim);
  @JS('_ffz_ffi_dual_seq')  external int dualSeq(int d);
  @JS('_ffz_ffi_dual_edit') external int dualEdit(int d);
  @JS('_ffz_ffi_dual_free') external void dualFree(int d);

  @JS('_ffz_ffi_results_len')      external int rLen(int r);
  @JS('_ffz_ffi_results_item')     external int rItem(int r, int i);
  @JS('_ffz_ffi_results_score')    external int rScore(int r, int i);
  @JS('_ffz_ffi_results_kind')     external int rKind(int r, int i);
  @JS('_ffz_ffi_results_key')      external int rKey(int r, int i);
  @JS('_ffz_ffi_results_nindices') external int rNIdx(int r, int i);
  @JS('_ffz_ffi_results_index')    external int rIdx(int r, int i, int j);
  @JS('_ffz_ffi_results_free')     external void rFree(int r);
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

/// Initialize the ffuzzy WASM engine. Await once at app startup before
/// constructing any [FuzzyCorpus]. On native this is a no-op.
///
/// On web, exactly one of [webAssetsUrl] or [webUrl] must be provided:
/// - [webAssetsUrl] — local Flutter asset path (declared in pubspec `assets:`),
///   e.g. `'/assets/ffz.mjs'`. Takes priority when both are given.
/// - [webUrl] — remote URL (CDN or self-hosted),
///   e.g. `'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.7.0/dist/ffz.mjs'`.
///
/// If both are provided, [webAssetsUrl] is used and [webUrl] is ignored.
/// Throws [ArgumentError] on web if neither is provided.
Future<void> ffuzzyInit({String? webAssetsUrl, String? webUrl}) async {
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
          const { default: create } = await import("$url");
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
    _readyCompleter.complete();
    throw FuzzyException('ffuzzy: WASM init timed out — check URL: $url');
  }
  try {
    await promise.toDart;
  } catch (e) {
    _readyCompleter.complete();
    throw FuzzyException('ffuzzy: WASM init failed: $e');
  }
  _ready = true;
  _readyCompleter.complete();
}


_Mod get _M {
  final m = _module;
  if (m == null) throw const FuzzyException('ffuzzy: WASM not initialized');
  return m;
}

// ── WASM memory helpers ───────────────────────────────────────────────────────

int _wAlloc(Uint8List bytes) {
  final M = _M;
  final len = bytes.isEmpty ? 1 : bytes.length;
  final ptr = M.malloc(len);
  final heap = M.heapu8.toDart;
  if (bytes.isEmpty) { heap[ptr] = 0; } else { heap.setAll(ptr, bytes); }
  return ptr;
}
void _wFree(int ptr) => _M.free(ptr);

// ── FuzzyCorpus (web) ─────────────────────────────────────────────────────────

final class FuzzyCorpus<T> extends FuzzyCorpusProtected<T> {
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
      _deferred = true;
      for (final item in items) { items_.add(item); keys_.add(null); }
      return;
    }
    _cp = _M.newCfg2(matchPaths ? 1 : 0, preferPrefix ? 1 : 0, options.scoring._c);
    if (_cp == 0) throw const FuzzyException('ffz_ffi_new_cfg2 returned null (OOM)');
    addAll(items);
  }

  // ── Static constructors ───────────────────────────────────────────────────

  static FuzzyCorpus<String> strings(Iterable<String> items,
          {FuzzyOptions options = const FuzzyOptions(), bool matchPaths = false,
          bool preferPrefix = false, String? libraryPath}) =>
      FuzzyCorpus<String>(items, stringOf: (s) => s, options: options,
          matchPaths: matchPaths, preferPrefix: preferPrefix);

  static FuzzyCorpus<Map<String, dynamic>> byKey(
      Iterable<Map<String, dynamic>> items, String field,
      {FuzzyOptions options = const FuzzyOptions(), bool matchPaths = false,
      bool preferPrefix = false, String? libraryPath}) =>
      FuzzyCorpus<Map<String, dynamic>>(items,
          stringOf: (m) => (m[field] ?? '').toString(), options: options,
          matchPaths: matchPaths, preferPrefix: preferPrefix);

  static FuzzyCorpus<Map<String, dynamic>> byKeys(
      Iterable<Map<String, dynamic>> items, List<String> fields,
      {FuzzyOptions options = const FuzzyOptions(), bool matchPaths = false,
      bool preferPrefix = false, String? libraryPath}) {
    if (fields.isEmpty) throw ArgumentError.value(fields, 'fields', 'must not be empty');
    final c = FuzzyCorpus<Map<String, dynamic>>([],
        stringOf: (m) => (m[fields.first] ?? '').toString(), options: options,
        matchPaths: matchPaths, preferPrefix: preferPrefix);
    for (final item in items) {
      if (fields.length == 1) { c.add(item); }
      else {
        c.addKey(item, [for (var i = 1; i < fields.length; i++)
          FuzzyKey((item[fields[i]] ?? '').toString(), kind: FuzzyKeyKind.custom.code)]);
      }
    }
    return c;
  }

  static Future<FuzzyCorpus<T>> asyncBuild<T>(Iterable<T> items,
      {required String Function(T) stringOf, FuzzyOptions options = const FuzzyOptions(),
      bool matchPaths = false, bool preferPrefix = false, String? libraryPath}) async {
    final c = FuzzyCorpus<T>([], stringOf: stringOf, options: options,
        matchPaths: matchPaths, preferPrefix: preferPrefix);
    await c.asyncAddAll(items);
    return c;
  }

  // ── WASM-specific state ───────────────────────────────────────────────────

  int _cp = 0;         // WASM corpus pointer
  bool _deferred = false; // true if constructed before WASM was ready
  bool _matchPaths = false;
  bool _preferPrefix = false;

  /// Completes when [ffuzzyInit] finishes (success or failure).
  /// On failure [isReady] stays `false` and searches return `[]`.
  Future<void> get ready => _ready ? Future.value() : _readyCompleter.future;

  /// `true` once the WASM engine has loaded successfully.
  bool get isReady => _ready;

  // Called at search time. If WASM has since loaded, do the one-time C alloc
  // + rebuild; otherwise stays deferred and searches return [].
  void _ensureReady() {
    if (!_deferred || !_ready) return;
    _deferred = false;
    _cp = _M.newCfg2(_matchPaths ? 1 : 0, _preferPrefix ? 1 : 0, options.scoring._c);
    if (_cp == 0) throw const FuzzyException('ffz_ffi_new_cfg2 returned null (OOM)');
    rebuild_();
  }

  // ── Bridge (WASM) ─────────────────────────────────────────────────────────

  @override
  void cAdd_(Uint8List bytes) {
    if (_deferred) return; // buffered in items_; will be pushed on first _ensureReady()
    final sp = _wAlloc(bytes);
    try { _M.add(_cp, sp, bytes.isEmpty ? 0 : bytes.length); }
    finally { _wFree(sp); }
  }

  @override
  void cAddKeyed_(Uint8List primary, List<FuzzyKey> keys) {
    if (_deferred) return;
    final M = _M;
    final sp = _wAlloc(primary);
    final n = keys.length;
    final ta = M.malloc(n * 4);
    final la = M.malloc(n * 4);
    final ka = M.malloc(n * 4);
    final h32 = M.heap32.toDart;
    final kPtrs = <int>[];
    try {
      for (var i = 0; i < n; i++) {
        final kb = toUtf8(keys[i].text);
        final kp = _wAlloc(kb);
        kPtrs.add(kp);
        h32[(ta >> 2) + i] = kp;
        h32[(la >> 2) + i] = kb.isEmpty ? 0 : kb.length;
        h32[(ka >> 2) + i] = keys[i].kind;
      }
      M.addKeyed(_cp, sp, primary.isEmpty ? 0 : primary.length, ta, la, ka, n);
    } finally {
      for (final p in kPtrs) { _wFree(p); }
      _wFree(ta); _wFree(la); _wFree(ka); _wFree(sp);
    }
  }

  @override void cClear_() { if (!_deferred) _M.corpusClear(_cp); }
  @override void cFree_()  { if (!_deferred) _M.corpusFree(_cp); }

  // ── Search bridge ─────────────────────────────────────────────────────────

  @override
  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o) {
    check_();
    _ensureReady();
    if (_deferred) return [];
    if (mode != mFuzzy) return dartSearch(items_, stringOf_, mode, q, o);
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = o.highlight
          ? M.filterEx2(_cp, qp, qb.isEmpty ? 0 : qb.length, mode,
              o.caseMatching._c, o.normalization._c, o.parallel ? 1 : 0,
              o.threads, o.limit, o.scoring._c)
          : M.filterRaws(_cp, qp, qb.isEmpty ? 0 : qb.length, mode,
              o.caseMatching._c, o.normalization._c, o.parallel ? 1 : 0,
              o.threads, o.limit, o.scoring._c);
      if (r == 0) throw StateError('ffz filter returned null (OOM)');
      return _readHits(M, r, o.highlight);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

  @override
  List<T> searchRaws_(int mode, String q, FuzzyOptions o) {
    check_();
    _ensureReady();
    if (_deferred) return [];
    if (mode != mFuzzy) return dartSearchRaws(items_, stringOf_, mode, q, o);
    return [for (final h in search_(mode, q, o.copyWith(highlight: false))) h.raw];
  }

  // Web: WASM is synchronous. If deferred, async variants wait for the engine
  // to load before executing; they return real results (not []) once ready.
  @override
  Future<List<FuzzyHit<T>>> searchAsync_(int mode, String q, FuzzyOptions o) async {
    check_();
    if (_deferred) { await _readyCompleter.future; _ensureReady(); }
    inFlight_++;
    try { return search_(mode, q, o); }
    finally { inFlight_--; signalIfIdle_(); }
  }

  @override
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o) async {
    check_();
    if (_deferred) { await _readyCompleter.future; _ensureReady(); }
    inFlight_++;
    try { return searchRaws_(mode, q, o); }
    finally { inFlight_--; signalIfIdle_(); }
  }

  @override
  List<FuzzyHit<T>>? searchFallback_(String q, int maxDist, FuzzyOptions o) {
    check_(); _ensureReady();
    if (_deferred) return null;
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = M.filterFallback(_cp, qp, qb.isEmpty ? 0 : qb.length,
          o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (r == 0) return null;
      return _readHits(M, r, false);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

  @override
  FuzzyDualResult<T>? searchDualC_(String q, int maxDist, FuzzyOptions o) {
    check_(); _ensureReady();
    if (_deferred) return null;
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int d = 0;
    try {
      d = M.filterDual(_cp, qp, qb.isEmpty ? 0 : qb.length,
          o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (d == 0) return null;
      final sr = M.dualSeq(d);
      final er = M.dualEdit(d);
      final seqHits  = sr != 0 ? _readHits(M, sr, false) : <FuzzyHit<T>>[];
      final editHits = er != 0 ? _readHits(M, er, false) : <FuzzyHit<T>>[];
      return FuzzyDualResult(fuzzy: seqHits, approx: editHits);
    } finally {
      _wFree(qp);
      if (d != 0) M.dualFree(d);
    }
  }

  @override
  List<FuzzyHit<T>>? searchMerge_(String q, int maxDist, FuzzyOptions o) {
    check_();
    _ensureReady();
    if (_deferred) return null;
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = M.filterMerge(_cp, qp, qb.isEmpty ? 0 : qb.length,
          o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (r == 0) return null;
      return _readHits(M, r, false);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

  @override
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o) {
    check_();
    _ensureReady();
    if (_deferred) return [];
    final M = _M;
    final qb = toUtf8(q);
    final qp = _wAlloc(qb);
    int r = 0;
    try {
      r = M.filterEdit(_cp, qp, qb.isEmpty ? 0 : qb.length,
          maxDist, o.caseMatching._c, o.normalization._c, o.limit);
      if (r == 0) return [];
      return _readHits(M, r, false);
    } finally {
      _wFree(qp);
      if (r != 0) M.rFree(r);
    }
  }

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
      out.add(FuzzyHit<T>(items_[idx], idx, M.rScore(r, i),
          kindOf(kind), kind, M.rKey(r, i), indices));
    }
    return out;
  }

  // ── Async build ───────────────────────────────────────────────────────────

  Future<void> asyncAddAll(Iterable<T> items) async {
    checkMutate_(); building_ = true;
    try { await Future.microtask(() => addAll(items)); }
    finally { building_ = false; signalIfIdle_(); }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void dispose() {
    if (disposed_) return;
    disposed_ = true;
    if (inFlight_ > 0 || building_) { unawaited(asyncDispose()); return; }
    if (!freed_) { freed_ = true; cFree_(); }
  }

  Future<void> asyncDispose() async {
    disposed_ = true;
    if (inFlight_ > 0 || building_) { await (idle_ ??= Completer<void>()).future; }
    if (freed_) return;
    freed_ = true; cFree_();
  }
}

// ── FuzzyCrash (stub on web) ──────────────────────────────────────────────────

class FuzzyCrash {
  FuzzyCrash._();
  static bool install({String? breadcrumbPath, String? libraryPath}) => false;
  static String? lastReport({String? breadcrumbPath}) => null;
}
