// Native (dart:ffi) platform — C bridge implementation.
// FuzzyCorpusProtected<T> provides all corpus logic; this file implements the
// abstract bridge methods that call into the native C library.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'ffuzzy_types.dart';
import 'ffuzzy_corpus.dart';

export 'ffuzzy_types.dart';
export 'ffuzzy_corpus.dart' hide FuzzyCorpusProtected;

/// No-op on native. Call from shared code that also targets web.
/// No-op on native — both parameters are ignored.
/// Provided so cross-platform code compiles without `kIsWeb` guards.
Future<void> ffuzzyInit({String? webUrl, String? webAssetsUrl}) async {}

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

// ── Native library handle ─────────────────────────────────────────────────────

typedef _Vpp  = Void Function(Pointer<Void>);
typedef _Np2  = Pointer<Void> Function(Int32, Int32, Int32);
typedef _Na   = Void Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _Nak  = Void Function(Pointer<Void>, Pointer<Uint8>, Size,
                               Pointer<Pointer<Uint8>>, Pointer<Size>, Pointer<Int32>, Size);
typedef _Nfr  = Void Function(Pointer<Void>);
typedef _Nfx2 = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Size,
                               Int32, Int32, Int32, Int32, Int32, Size, Int32);
typedef _Nvp  = Void Function(Pointer<Void>);
typedef _Ri   = Uint32 Function(Pointer<Void>, Size);
typedef _Rni  = Size Function(Pointer<Void>, Size);
typedef _Rid  = Uint32 Function(Pointer<Void>, Size, Size);
typedef _Rs   = Int32 Function(Pointer<Void>, Size);
typedef _Nfe  = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Size, Int32, Int32, Int32, Size);

class _Lib {
  _Lib(this.lib)
      : add       = lib.lookupFunction<_Na, void Function(Pointer<Void>,Pointer<Uint8>,int)>('ffz_ffi_add'),
        clear     = lib.lookupFunction<_Vpp, void Function(Pointer<Void>)>('ffz_ffi_clear'),
        rLen      = lib.lookupFunction<Size Function(Pointer<Void>), int Function(Pointer<Void>)>('ffz_ffi_results_len'),
        rItem     = lib.lookupFunction<_Ri, int Function(Pointer<Void>,int)>('ffz_ffi_results_item'),
        rScore    = lib.lookupFunction<_Rs, int Function(Pointer<Void>,int)>('ffz_ffi_results_score'),
        rKind     = lib.lookupFunction<_Rs, int Function(Pointer<Void>,int)>('ffz_ffi_results_kind'),
        rKey      = lib.lookupFunction<_Ri, int Function(Pointer<Void>,int)>('ffz_ffi_results_key'),
        rNIdx     = lib.lookupFunction<_Rni, int Function(Pointer<Void>,int)>('ffz_ffi_results_nindices'),
        rIdx      = lib.lookupFunction<_Rid, int Function(Pointer<Void>,int,int)>('ffz_ffi_results_index'),
        rFree     = lib.lookupFunction<_Vpp, void Function(Pointer<Void>)>('ffz_ffi_results_free'),
        free      = lib.lookupFunction<_Nfr, void Function(Pointer<Void>)>('ffz_ffi_free'),
        crash     = _optCrash(lib),
        newCfg2       = lib.lookupFunction<_Np2, Pointer<Void> Function(int,int,int)>('ffz_ffi_new_cfg2'),
        addKeyed      = lib.lookupFunction<_Nak, void Function(Pointer<Void>,Pointer<Uint8>,int,Pointer<Pointer<Uint8>>,Pointer<Size>,Pointer<Int32>,int)>('ffz_ffi_add_keyed'),
        filterEx2     = lib.lookupFunction<_Nfx2, Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int)>('ffz_ffi_filter_ex2'),
        filterRaw     = lib.lookupFunction<_Nfx2, Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int)>('ffz_ffi_filter_raws'),
        filterEdit    = lib.lookupFunction<_Nfe, Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int)>('ffz_ffi_filter_edit'),
        filterMerge   = lib.lookupFunction<_Nfx2, Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int)>('ffz_ffi_filter_merge'),
        filterFallback= lib.lookupFunction<_Nfx2, Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int)>('ffz_ffi_filter_fallback'),
        filterDual    = lib.lookupFunction<_Nfx2, Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int)>('ffz_ffi_filter_dual'),
        dualSeq       = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('ffz_ffi_dual_seq'),
        dualEdit      = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('ffz_ffi_dual_edit'),
        dualFree      = lib.lookupFunction<_Nvp, void Function(Pointer<Void>)>('ffz_ffi_dual_free'),
        finalizer     = NativeFinalizer(lib.lookup<NativeFunction<_Nfr>>('ffz_ffi_free').cast());

  static int Function(Pointer<Utf8>)? _optCrash(DynamicLibrary lib) {
    try { return lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ffz_ffi_install_crash_handler'); }
    catch (_) { return null; }
  }

  final DynamicLibrary lib;
  final void Function(Pointer<Void>,Pointer<Uint8>,int) add;
  final void Function(Pointer<Void>) clear;
  final int Function(Pointer<Void>) rLen;
  final int Function(Pointer<Void>,int) rItem, rKey;
  final int Function(Pointer<Void>,int) rScore, rKind;
  final int Function(Pointer<Void>,int) rNIdx;
  final int Function(Pointer<Void>,int,int) rIdx;
  final void Function(Pointer<Void>) rFree, free;
  final int Function(Pointer<Utf8>)? crash;
  final Pointer<Void> Function(int,int,int) newCfg2;
  final void Function(Pointer<Void>,Pointer<Uint8>,int,Pointer<Pointer<Uint8>>,Pointer<Size>,Pointer<Int32>,int) addKeyed;
  final Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int) filterEx2;
  final Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int) filterRaw;
  final Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int) filterEdit;
  final Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int) filterMerge;
  final Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int) filterFallback;
  final Pointer<Void> Function(Pointer<Void>,Pointer<Uint8>,int,int,int,int,int,int,int,int) filterDual;
  final Pointer<Void> Function(Pointer<Void>) dualSeq;
  final Pointer<Void> Function(Pointer<Void>) dualEdit;
  final void Function(Pointer<Void>) dualFree;
  final NativeFinalizer finalizer;

  static final Map<String, _Lib> _cache = {};
  static _Lib resolve(String? path) =>
      _cache.putIfAbsent(path ?? '<default>', () => _Lib(_open(path)));
  static DynamicLibrary _open(String? path) {
    try {
      if (path != null) return DynamicLibrary.open(path);
      if (Platform.isWindows) return DynamicLibrary.open('ffz.dll');
      if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
      return DynamicLibrary.open('libffz.so');
    } on ArgumentError catch (e) {
      throw FuzzyException('failed to load ffz native library: $e');
    }
  }
}

// ── Memory helpers ────────────────────────────────────────────────────────────

Pointer<Uint8> _alloc(Uint8List bytes) {
  final p = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) { p.asTypedList(bytes.length).setAll(0, bytes); }
  else { p[0] = 0; }
  return p;
}

// ── FuzzyCorpus (native) ──────────────────────────────────────────────────────

final class FuzzyCorpus<T> extends FuzzyCorpusProtected<T>
    implements Finalizable {

  FuzzyCorpus(
    Iterable<T> items, {
    required String Function(T) stringOf,
    FuzzyOptions options = const FuzzyOptions(),
    bool matchPaths = false,
    bool preferPrefix = false,
    String? libraryPath,
  })  : _l = _Lib.resolve(libraryPath),
        _libPath = libraryPath,
        super(options: options, stringOf_: stringOf) {
    _ptr = _l.newCfg2(matchPaths ? 1 : 0, preferPrefix ? 1 : 0, options.scoring._c);
    if (_ptr == nullptr) {
      throw const FuzzyException('ffz_ffi_new_cfg returned null (out of memory)');
    }
    _l.finalizer.attach(this, _ptr.cast(), detach: this);
    addAll(items);
  }

  // ── Static constructors ───────────────────────────────────────────────────

  static FuzzyCorpus<String> strings(Iterable<String> items,
          {FuzzyOptions options = const FuzzyOptions(), bool matchPaths = false,
          bool preferPrefix = false, String? libraryPath}) =>
      FuzzyCorpus<String>(items, stringOf: (s) => s, options: options,
          matchPaths: matchPaths, preferPrefix: preferPrefix, libraryPath: libraryPath);

  static FuzzyCorpus<Map<String, dynamic>> byKey(
      Iterable<Map<String, dynamic>> items, String field,
      {FuzzyOptions options = const FuzzyOptions(), bool matchPaths = false,
      bool preferPrefix = false, String? libraryPath}) =>
      FuzzyCorpus<Map<String, dynamic>>(items,
          stringOf: (m) => (m[field] ?? '').toString(), options: options,
          matchPaths: matchPaths, preferPrefix: preferPrefix, libraryPath: libraryPath);

  static FuzzyCorpus<Map<String, dynamic>> byKeys(
      Iterable<Map<String, dynamic>> items, List<String> fields,
      {FuzzyOptions options = const FuzzyOptions(), bool matchPaths = false,
      bool preferPrefix = false, String? libraryPath}) {
    if (fields.isEmpty) throw ArgumentError.value(fields, 'fields', 'must not be empty');
    final c = FuzzyCorpus<Map<String, dynamic>>([],
        stringOf: (m) => (m[fields.first] ?? '').toString(), options: options,
        matchPaths: matchPaths, preferPrefix: preferPrefix, libraryPath: libraryPath);
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
        matchPaths: matchPaths, preferPrefix: preferPrefix, libraryPath: libraryPath);
    await c.asyncAddAll(items);
    return c;
  }

  // ── Native-specific state ─────────────────────────────────────────────────


  final _Lib _l;
  final String? _libPath;
  late Pointer<Void> _ptr;
  int _estBytes = 0;

  void _refreshFinalizer() {
    _l.finalizer.detach(this);
    _l.finalizer.attach(this, _ptr.cast(), detach: this, externalSize: _estBytes);
  }
  void _keepAlive() => disposed_; // touch field → object stays reachable through await

  // ── Bridge (C) ────────────────────────────────────────────────────────────

  @override
  void cAdd_(Uint8List bytes) {
    final p = _alloc(bytes);
    _l.add(_ptr, p, bytes.isEmpty ? 0 : bytes.length);
    malloc.free(p);
    _estBytes += bytes.length;
    _refreshFinalizer();
  }

  @override
  void cAddKeyed_(Uint8List primary, List<FuzzyKey> keys) {
    final ip = _alloc(primary);
    _estBytes += primary.length;
    final n = keys.length;
    final ta = malloc<Pointer<Uint8>>(n);
    final la = malloc<Size>(n);
    final ka = malloc<Int32>(n);
    final kptrs = <Pointer<Uint8>>[];
    try {
      for (var i = 0; i < n; i++) {
        final kb = toUtf8(keys[i].text);
        final kp = _alloc(kb);
        ta[i] = kp; la[i] = kb.isEmpty ? 0 : kb.length; ka[i] = keys[i].kind;
        kptrs.add(kp); _estBytes += kb.length;
      }
      _l.addKeyed(_ptr, ip, primary.isEmpty ? 0 : primary.length, ta, la, ka, n);
    } finally {
      for (final p in kptrs) { malloc.free(p); }
      malloc.free(ta); malloc.free(la); malloc.free(ka); malloc.free(ip);
    }
    _refreshFinalizer();
  }

  @override
  void cClear_() {
    _l.clear(_ptr);
    _estBytes = 0;
    _refreshFinalizer();
  }

  @override
  void cFree_() => _l.free(_ptr);

  // ── Search bridge ─────────────────────────────────────────────────────────

  @override
  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o) {
    check_();
    if (mode != mFuzzy) return dartSearch(items_, stringOf_, mode, q, o);
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = _nativeFilter(qp, qb.isEmpty ? 0 : qb.length, mode, o, o.highlight);
      if (r == nullptr) throw StateError('ffz filter returned null (OOM)');
      return _readHits(r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) _l.rFree(r);
    }
  }

  @override
  List<T> searchRaws_(int mode, String q, FuzzyOptions o) {
    check_();
    if (mode != mFuzzy) return dartSearchRaws(items_, stringOf_, mode, q, o);
    return [for (final h in search_(mode, q, o.copyWith(highlight: false))) h.raw];
  }

  @override
  Future<List<FuzzyHit<T>>> searchAsync_(int mode, String q, FuzzyOptions o) async {
    check_();
    if (mode != mFuzzy) return search_(mode, q, o);
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final raws = await Isolate.run(() => _isoSearch(libPath, addr, qb, mode, o));
      return [for (final r in raws) if (r.$1 < items_.length)
        FuzzyHit<T>(items_[r.$1], r.$1, r.$2, kindOf(r.$3), r.$3, r.$4, r.$5)];
    } finally { inFlight_--; signalIfIdle_(); _keepAlive(); }
  }

  @override
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o) async {
    check_();
    if (mode != mFuzzy) return searchRaws_(mode, q, o);
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final indices = await Isolate.run(() => _isoSearchRaws(libPath, addr, qb, mode, o));
      return [for (final i in indices) if (i < items_.length) items_[i]];
    } finally { inFlight_--; signalIfIdle_(); _keepAlive(); }
  }

  @override
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o) {
    check_();
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = _l.filterEdit(_ptr, qp, qb.isEmpty ? 0 : qb.length, maxDist,
          o.caseMatching._c, o.normalization._c, o.limit);
      if (r == nullptr) throw StateError('ffz_ffi_filter_edit returned null (OOM)');
      return _readHits(r, false);
    } finally {
      malloc.free(qp);
      if (r != nullptr) _l.rFree(r);
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  Pointer<Void> _nativeFilter(Pointer<Uint8> qp, int qlen, int mode,
      FuzzyOptions o, bool highlight) {
    return highlight
        ? _l.filterEx2(_ptr, qp, qlen, mode, o.caseMatching._c, o.normalization._c,
            o.parallel ? 1 : 0, o.threads, o.limit, o.scoring._c)
        : _l.filterRaw(_ptr, qp, qlen, mode, o.caseMatching._c, o.normalization._c,
            o.parallel ? 1 : 0, o.threads, o.limit, o.scoring._c);
  }

  List<FuzzyHit<T>> _callFfiFilter(
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int,
          int, int, int, int, int, int, int) fn,
      String q, int maxDist, FuzzyOptions o) {
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = fn(_ptr, qp, qb.isEmpty ? 0 : qb.length,
          o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (r == nullptr) throw StateError('ffuzzy: filter returned null (OOM)');
      return _readHits(r, false);
    } finally {
      malloc.free(qp);
      if (r != nullptr) _l.rFree(r);
    }
  }

  @override
  List<FuzzyHit<T>> searchMerge_(String q, int maxDist, FuzzyOptions o) =>
      _callFfiFilter(_l.filterMerge, q, maxDist, o);

  @override
  List<FuzzyHit<T>> searchFallback_(String q, int maxDist, FuzzyOptions o) =>
      _callFfiFilter(_l.filterFallback, q, maxDist, o);

  @override
  FuzzyDualResult<T> searchDualC_(String q, int maxDist, FuzzyOptions o) {
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var d = Pointer<Void>.fromAddress(0);
    try {
      d = _l.filterDual(_ptr, qp, qb.isEmpty ? 0 : qb.length,
          o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (d == nullptr) throw StateError('ffz_ffi_filter_dual returned null (OOM)');
      final sr = _l.dualSeq(d);
      final er = _l.dualEdit(d);
      final seqHits  = sr != nullptr ? _readHits(sr, false) : <FuzzyHit<T>>[];
      final editHits = er != nullptr ? _readHits(er, false) : <FuzzyHit<T>>[];
      return FuzzyDualResult(fuzzy: seqHits, approx: editHits);
    } finally {
      malloc.free(qp);
      if (d != nullptr) _l.dualFree(d);
    }
  }

  List<FuzzyHit<T>> _readHits(Pointer<Void> r, bool highlight) {
    final n = _l.rLen(r);
    final out = <FuzzyHit<T>>[];
    for (var i = 0; i < n; i++) {
      final idx = _l.rItem(r, i);
      if (idx >= items_.length) continue;
      List<int> indices = const [];
      if (highlight) {
        final ni = _l.rNIdx(r, i);
        indices = List<int>.generate(ni, (j) => _l.rIdx(r, i, j));
      }
      final kind = _l.rKind(r, i);
      out.add(FuzzyHit<T>(items_[idx], idx, _l.rScore(r, i),
          kindOf(kind), kind, _l.rKey(r, i), indices));
    }
    return out;
  }

  // Isolate-safe search — returns (index, score, kind, key, indices)
  static List<(int, int, int, int, List<int>)> _isoSearch(
      String? libPath, int addr, Uint8List qb, int mode, FuzzyOptions o) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      if (o.highlight) {
        r = lib.filterEx2(ptr, qp, qb.length, mode, o.caseMatching._c,
            o.normalization._c, o.parallel ? 1 : 0, o.threads, o.limit, o.scoring._c);
      } else {
        r = lib.filterRaw(ptr, qp, qb.length, mode, o.caseMatching._c,
            o.normalization._c, o.parallel ? 1 : 0, o.threads, o.limit, o.scoring._c);
      }
      if (r == nullptr) return const [];
      final n = lib.rLen(r);
      final out = <(int, int, int, int, List<int>)>[];
      for (var i = 0; i < n; i++) {
        List<int> idx = const [];
        if (o.highlight) {
          final ni = lib.rNIdx(r, i);
          idx = List<int>.generate(ni, (j) => lib.rIdx(r, i, j));
        }
        out.add((lib.rItem(r,i), lib.rScore(r,i), lib.rKind(r,i), lib.rKey(r,i), idx));
      }
      lib.rFree(r); r = nullptr;
      return out;
    } finally {
      malloc.free(qp);
      if (r != nullptr) lib.rFree(r);
    }
  }

  static List<int> _isoSearchRaws(
      String? libPath, int addr, Uint8List qb, int mode, FuzzyOptions o) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = lib.filterRaw(ptr, qp, qb.length, mode, o.caseMatching._c,
          o.normalization._c, o.parallel ? 1 : 0, o.threads, o.limit, o.scoring._c);
      if (r == nullptr) return const [];
      final n = lib.rLen(r);
      final out = List<int>.generate(n, (i) => lib.rItem(r, i), growable: false);
      lib.rFree(r); r = nullptr;
      return out;
    } finally {
      malloc.free(qp);
      if (r != nullptr) lib.rFree(r);
    }
  }

  // ── Async build ───────────────────────────────────────────────────────────

  Future<void> asyncAddAll(Iterable<T> items) async {
    checkMutate_();
    final list = List<T>.of(items);
    final texts = <Uint8List>[for (final it in list) toUtf8(stringOf_(it))];
    final addr = _ptr.address;
    final libPath = _libPath;
    building_ = true;
    try {
      await Isolate.run(() {
        final lib = _Lib.resolve(libPath);
        final p = Pointer<Void>.fromAddress(addr);
        for (final bytes in texts) {
          final mp = _alloc(bytes);
          lib.add(p, mp, bytes.isEmpty ? 0 : bytes.length);
          malloc.free(mp);
        }
      });
      for (final item in list) { items_.add(item); keys_.add(null); }
      for (final t in texts) { _estBytes += t.length; }
      _refreshFinalizer();
    } catch (e, st) {
      _l.clear(_ptr); _estBytes = 0;
      try { rebuild_(); } catch (re) {
        disposed_ = true; freed_ = true; building_ = false;
        _l.finalizer.detach(this); _l.free(_ptr);
        Error.throwWithStackTrace(
            StateError('asyncAddAll: worker failed ($e) and rebuild failed: $re'), st);
      }
      Error.throwWithStackTrace(e, st);
    } finally { building_ = false; signalIfIdle_(); _keepAlive(); }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void dispose() {
    if (disposed_) return;
    disposed_ = true;
    if (inFlight_ > 0 || building_) { unawaited(asyncDispose()); return; }
    if (!freed_) { freed_ = true; _l.finalizer.detach(this); cFree_(); }
  }

  Future<void> asyncDispose() async {
    disposed_ = true;
    if (inFlight_ > 0 || building_) { await (idle_ ??= Completer<void>()).future; }
    if (freed_) return;
    freed_ = true; _l.finalizer.detach(this); cFree_();
  }
}

// ── FuzzyCrash ────────────────────────────────────────────────────────────────

class FuzzyCrash {
  FuzzyCrash._();
  static String? _path;

  static bool install({String? breadcrumbPath, String? libraryPath}) {
    final f = _Lib.resolve(libraryPath).crash;
    if (f == null) return false;
    _path = breadcrumbPath;
    final p = breadcrumbPath == null ? nullptr : breadcrumbPath.toNativeUtf8();
    try { return f(p.cast()) != 0; }
    finally { if (p != nullptr) malloc.free(p); }
  }

  static String? lastReport({String? breadcrumbPath}) {
    final p = breadcrumbPath ?? _path;
    if (p == null) return null;
    final f = File(p);
    if (!f.existsSync()) return null;
    final s = f.readAsStringSync();
    try { f.deleteSync(); } catch (_) { try { f.writeAsBytesSync(const []); } catch (_) {} }
    return s.isEmpty ? null : s;
  }
}
