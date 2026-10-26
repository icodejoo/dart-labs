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

/// 原生平台的初始化兼容入口；[webUrl] 和 [webAssetsUrl] 均被忽略。
/// 返回立即完成的 Future，可供跨平台启动代码统一调用。
///
/// 示例：`await ffuzzyInit();`。
Future<void> ffuzzyInit({String? webUrl, String? webAssetsUrl}) async {}

// 新增条目失败的信息。
const _addOom =
    'ffuzzy: add failed (OOM or incompatible engine; rebuild engine)';
// 过滤结果分配失败的信息。
const _filterOom = 'ffz filter returned null (OOM)';
// 双路结果分配失败的信息。
const _dualOom = 'ffz_ffi_filter_dual returned null (OOM)';

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

// ── Native library handle ─────────────────────────────────────────────────────

typedef _Vpp = Void Function(Pointer<Void>);
typedef _Np2 = Pointer<Void> Function(Int32, Int32, Int32);
typedef _Na = Int32 Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _Nak = Int32 Function(Pointer<Void>, Pointer<Uint8>, Size,
    Pointer<Pointer<Uint8>>, Pointer<Size>, Pointer<Int32>, Size);
typedef _Nfr = Void Function(Pointer<Void>);
typedef _Nfx2 = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Size,
    Int32, Int32, Int32, Int32, Int32, Size, Int32);
// ffz_ffi_filter_merge/filter_fallback/filter_dual's C signature is
// (corpus, q, qn, cm, nm, max_distance, scoring, parallel, threads, limit) —
// six Int32 trailing params followed by a size_t `limit`. This is NOT the
// same shape as _Nfx2 above (which has Size in slot 6 / Int32 in slot 7, the
// reverse), so it needs its own typedef rather than reusing _Nfx2.
typedef _Nfm = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, Size,
    Int32, Int32, Int32, Int32, Int32, Int32, Size);
typedef _Nvp = Void Function(Pointer<Void>);
typedef _Ri = Uint32 Function(Pointer<Void>, Size);
typedef _Rni = Size Function(Pointer<Void>, Size);
typedef _Rid = Uint32 Function(Pointer<Void>, Size, Size);
typedef _Rs = Int32 Function(Pointer<Void>, Size);
typedef _Nfe = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, Size, Int32, Int32, Int32, Size);

// 绑定并缓存原生动态库符号。
class _Lib {
  // 绑定整数新增状态及搜索接口，避免宿主记录未提交的条目。
  _Lib(this.lib)
      : add = lib.lookupFunction<_Na,
            int Function(Pointer<Void>, Pointer<Uint8>, int)>('ffz_ffi_add'),
        clear = lib.lookupFunction<_Vpp, void Function(Pointer<Void>)>(
            'ffz_ffi_clear'),
        rLen = lib.lookupFunction<Size Function(Pointer<Void>),
            int Function(Pointer<Void>)>('ffz_ffi_results_len'),
        rItem = lib.lookupFunction<_Ri, int Function(Pointer<Void>, int)>(
            'ffz_ffi_results_item'),
        rScore = lib.lookupFunction<_Rs, int Function(Pointer<Void>, int)>(
            'ffz_ffi_results_score'),
        rKind = lib.lookupFunction<_Rs, int Function(Pointer<Void>, int)>(
            'ffz_ffi_results_kind'),
        rKey = lib.lookupFunction<_Ri, int Function(Pointer<Void>, int)>(
            'ffz_ffi_results_key'),
        rNIdx = lib.lookupFunction<_Rni, int Function(Pointer<Void>, int)>(
            'ffz_ffi_results_nindices'),
        rIdx = lib.lookupFunction<_Rid, int Function(Pointer<Void>, int, int)>(
            'ffz_ffi_results_index'),
        rFree = lib.lookupFunction<_Vpp, void Function(Pointer<Void>)>(
            'ffz_ffi_results_free'),
        free = lib
            .lookupFunction<_Nfr, void Function(Pointer<Void>)>('ffz_ffi_free'),
        crash = _optCrash(lib),
        newCfg2 =
            lib.lookupFunction<_Np2, Pointer<Void> Function(int, int, int)>(
                'ffz_ffi_new_cfg2'),
        addKeyed = lib.lookupFunction<
            _Nak,
            int Function(
                Pointer<Void>,
                Pointer<Uint8>,
                int,
                Pointer<Pointer<Uint8>>,
                Pointer<Size>,
                Pointer<Int32>,
                int)>('ffz_ffi_add_keyed'),
        filterEx2 = lib.lookupFunction<
            _Nfx2,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int, int, int, int)>('ffz_ffi_filter_ex2'),
        filterRaw = lib.lookupFunction<
            _Nfx2,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int, int, int, int)>('ffz_ffi_filter_raws'),
        filterEdit = lib.lookupFunction<
            _Nfe,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int)>('ffz_ffi_filter_edit'),
        filterEditRaw = lib.lookupFunction<
            _Nfe,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int)>('ffz_ffi_filter_edit_raws'),
        filterMerge = lib.lookupFunction<
            _Nfm,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int, int, int, int)>('ffz_ffi_filter_merge'),
        filterFallback = lib.lookupFunction<
            _Nfm,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int, int, int, int)>('ffz_ffi_filter_fallback'),
        filterDual = lib.lookupFunction<
            _Nfm,
            Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
                int, int, int, int, int)>('ffz_ffi_filter_dual'),
        dualSeq = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)>('ffz_ffi_dual_seq'),
        dualEdit = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)>('ffz_ffi_dual_edit'),
        dualFree = lib.lookupFunction<_Nvp, void Function(Pointer<Void>)>(
            'ffz_ffi_dual_free'),
        finalizer = NativeFinalizer(
            lib.lookup<NativeFunction<_Nfr>>('ffz_ffi_free').cast());

  static int Function(Pointer<Utf8>)? _optCrash(DynamicLibrary lib) {
    try {
      return lib.lookupFunction<Int32 Function(Pointer<Utf8>),
          int Function(Pointer<Utf8>)>('ffz_ffi_install_crash_handler');
    } catch (_) {
      return null;
    }
  }

  final DynamicLibrary lib;
  // 新增条目的原生函数，返回一表示提交成功。
  final int Function(Pointer<Void>, Pointer<Uint8>, int) add;
  final void Function(Pointer<Void>) clear;
  final int Function(Pointer<Void>) rLen;
  // 读取条目下标和命中键下标的原生函数。
  final int Function(Pointer<Void>, int) rItem, rKey;
  // 读取分数和键类型的原生函数。
  final int Function(Pointer<Void>, int) rScore, rKind;
  // 读取高亮数量的原生函数。
  final int Function(Pointer<Void>, int) rNIdx;
  // 读取高亮下标的原生函数。
  final int Function(Pointer<Void>, int, int) rIdx;
  final void Function(Pointer<Void>) rFree, free;
  final int Function(Pointer<Utf8>)? crash;
  // 创建带评分配置的语料库的原生函数。
  final Pointer<Void> Function(int, int, int) newCfg2;
  // 新增带附加键条目的原生函数。
  final int Function(Pointer<Void>, Pointer<Uint8>, int,
      Pointer<Pointer<Uint8>>, Pointer<Size>, Pointer<Int32>, int) addKeyed;
  final Pointer<Void> Function(
          Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int)
      filterEx2;
  final Pointer<Void> Function(
          Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int)
      filterRaw;
  final Pointer<Void> Function(
      Pointer<Void>, Pointer<Uint8>, int, int, int, int, int) filterEdit;
  final Pointer<Void> Function(
      Pointer<Void>, Pointer<Uint8>, int, int, int, int, int) filterEditRaw;
  final Pointer<Void> Function(
          Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int)
      filterMerge;
  final Pointer<Void> Function(
          Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int)
      filterFallback;
  final Pointer<Void> Function(
          Pointer<Void>, Pointer<Uint8>, int, int, int, int, int, int, int, int)
      filterDual;
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

// 分配并复制查询字节，空串保留零长度。
Pointer<Uint8> _alloc(Uint8List bytes) {
  final p = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) {
    p.asTypedList(bytes.length).setAll(0, bytes);
  } else {
    p[0] = 0;
  }
  return p;
}

// ── FuzzyCorpus (native) ──────────────────────────────────────────────────────

/// 可反复搜索的语料库；用完后调用 dispose 释放资源。
/// 类型参数 T 为原始条目类型。
///
/// 示例：`final c = FuzzyCorpus.strings(["你好"]); c.dispose();`。
final class FuzzyCorpus<T> extends FuzzyCorpusProtected<T>
    implements Finalizable {
  /// 创建语料库；[items] 为初始条目，[stringOf] 提取搜索文本，[options] 为默认选项。
  /// [matchPaths] 启用路径匹配，[preferPrefix] 优先前缀，[libraryPath] 为动态库路径。
  /// 返回新实例；文本提取异常向上传递，资源不足抛 FuzzyException。
  ///
  /// 示例：`final c = FuzzyCorpus(["你好"], stringOf: (s) => s); c.dispose();`。
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
    _ptr = _l.newCfg2(
        matchPaths ? 1 : 0, preferPrefix ? 1 : 0, options.scoring._c);
    if (_ptr == nullptr) {
      throw const FuzzyException(
          'ffz_ffi_new_cfg returned null (out of memory)');
    }
    _l.finalizer.attach(this, _ptr.cast(), detach: this);
    addAll(items);
  }

  // ── Static constructors ───────────────────────────────────────────────────

  /// 创建字符串语料库；[items] 为条目，[options] 为搜索选项。
  /// [matchPaths] 启用路径匹配，[preferPrefix] 优先前缀，[libraryPath] 为可选动态库路径。
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
          preferPrefix: preferPrefix,
          libraryPath: libraryPath);

  /// 以 [items] 中的 [field] 字段建立语料库，缺失字段视为空文本。
  /// [options] 为搜索选项，[matchPaths] 启用路径匹配，[preferPrefix] 优先前缀，[libraryPath] 为动态库路径。
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
          preferPrefix: preferPrefix,
          libraryPath: libraryPath);

  /// 以 [items] 中 [fields] 的首字段为原始文本，其余为附加键；缺失字段视为空文本。
  /// [fields] 为空时抛 ArgumentError；[options] 为选项，[matchPaths] 启用路径匹配，[preferPrefix] 优先前缀，[libraryPath] 为动态库路径。
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
        preferPrefix: preferPrefix,
        libraryPath: libraryPath);
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
  /// [matchPaths] 启用路径匹配，[preferPrefix] 优先前缀，[libraryPath] 为动态库路径。
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
        preferPrefix: preferPrefix,
        libraryPath: libraryPath);
    await c.asyncAddAll(items);
    return c;
  }

  // ── Native-specific state ─────────────────────────────────────────────────

  final _Lib _l;
  final String? _libPath;
  late Pointer<Void> _ptr;
  // 已写入文本字节数的估计。
  int _estBytes = 0;

  // 根据估计的原生内存用量更新终结器。
  void _refreshFinalizer() {
    _l.finalizer.detach(this);
    _l.finalizer
        .attach(this, _ptr.cast(), detach: this, externalSize: _estBytes);
  }

  // 保持当前语料库存活直到原生调用结束。
  void _keepAlive() =>
      disposed_; // touch field → object stays reachable through await

  // ── Bridge (C) ────────────────────────────────────────────────────────────

  // 新增原始键，失败时抛错并阻止宿主提交条目。
  @override
  void cAdd_(Uint8List bytes) {
    final p = _alloc(bytes);
    try {
      if (_l.add(_ptr, p, bytes.length) != 1) {
        throw const FuzzyException(_addOom);
      }
    } finally {
      malloc.free(p);
    }
    _estBytes += bytes.length;
    _refreshFinalizer();
  }

  // 新增原始键及附加键，失败时阻止宿主提交条目。
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
        ta[i] = kp;
        la[i] = kb.length;
        ka[i] = keys[i].kind;
        kptrs.add(kp);
        _estBytes += kb.length;
      }
      if (_l.addKeyed(_ptr, ip, primary.length, ta, la, ka, n) != 1) {
        throw const FuzzyException(_addOom);
      }
    } finally {
      for (final p in kptrs) {
        malloc.free(p);
      }
      malloc.free(ta);
      malloc.free(la);
      malloc.free(ka);
      malloc.free(ip);
    }
    _refreshFinalizer();
  }

  // 清空平台索引并释放键存储。
  @override
  void cClear_() {
    _l.clear(_ptr);
    _estBytes = 0;
    _refreshFinalizer();
  }

  // 释放平台语料库。
  @override
  void cFree_() => _l.free(_ptr);

  // ── Search bridge ─────────────────────────────────────────────────────────

  // 执行指定模式的同步搜索。
  @override
  List<FuzzyHit<T>> search_(int mode, String q, FuzzyOptions o) {
    check_();
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = _nativeFilter(qp, qb.length, mode, o, o.highlight);
      if (r == nullptr) throw StateError(_filterOom);
      return _readHits(r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) _l.rFree(r);
    }
  }

  // 仅返回指定模式搜索的原始条目。
  @override
  List<T> searchRaws_(int mode, String q, FuzzyOptions o) {
    check_();
    return [
      for (final h in search_(mode, q, o.copyWith(highlight: false))) h.raw
    ];
  }

  // 执行异步搜索并跟踪在途调用。
  @override
  Future<List<FuzzyHit<T>>> searchAsync_(
      int mode, String q, FuzzyOptions o) async {
    check_();
    // _isoSearch below already forwards `mode` straight to filterEx2/filterRaw,
    // which support all 5 modes — no need to special-case fuzzy here.
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final raws =
          await Isolate.run(() => _isoSearch(libPath, addr, qb, mode, o));
      return _fromRaws(raws);
    } finally {
      inFlight_--;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // 异步返回原始条目并维护生命周期。
  @override
  Future<List<T>> searchRawsAsync_(int mode, String q, FuzzyOptions o) async {
    check_();
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final indices =
          await Isolate.run(() => _isoSearchRaws(libPath, addr, qb, mode, o));
      return [
        for (final i in indices)
          if (i < items_.length) items_[i]
      ];
    } finally {
      inFlight_--;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // 执行编辑距离搜索并按需读取高亮。
  @override
  List<FuzzyHit<T>> searchEdit_(String q, int maxDist, FuzzyOptions o) {
    check_();
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      final fn = o.highlight ? _l.filterEdit : _l.filterEditRaw;
      r = fn(_ptr, qp, qb.length, maxDist, o.caseMatching._c,
          o.normalization._c, o.limit);
      if (r == nullptr) {
        throw StateError('ffz_ffi_filter_edit returned null (OOM)');
      }
      return _readHits(r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) _l.rFree(r);
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  // 按高亮选项选择原生过滤入口。
  Pointer<Void> _nativeFilter(
      Pointer<Uint8> qp, int qlen, int mode, FuzzyOptions o, bool highlight) {
    return highlight
        ? _l.filterEx2(
            _ptr,
            qp,
            qlen,
            mode,
            o.caseMatching._c,
            o.normalization._c,
            o.parallel ? 1 : 0,
            o.threads,
            o.limit,
            o.scoring._c)
        : _l.filterRaw(
            _ptr,
            qp,
            qlen,
            mode,
            o.caseMatching._c,
            o.normalization._c,
            o.parallel ? 1 : 0,
            o.threads,
            o.limit,
            o.scoring._c);
  }

  // 复用查询缓冲及结果释放逻辑调用组合搜索。
  List<FuzzyHit<T>> _callFfiFilter(
      Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int, int,
              int, int, int, int)
          fn,
      String q,
      int maxDist,
      FuzzyOptions o) {
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = fn(_ptr, qp, qb.length, o.caseMatching._c, o.normalization._c,
          maxDist, o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (r == nullptr) throw StateError('ffuzzy: filter returned null (OOM)');
      return _readHits(r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) _l.rFree(r);
    }
  }

  // 执行子序列与近似结果合并搜索。
  @override
  List<FuzzyHit<T>> searchMerge_(String q, int maxDist, FuzzyOptions o) =>
      _callFfiFilter(_l.filterMerge, q, maxDist, o);

  // 先执行子序列搜索，无命中时回退到近似搜索。
  @override
  List<FuzzyHit<T>> searchFallback_(String q, int maxDist, FuzzyOptions o) =>
      _callFfiFilter(_l.filterFallback, q, maxDist, o);

  // 分别读取子序列与近似搜索结果。
  @override
  FuzzyDualResult<T> searchDualC_(String q, int maxDist, FuzzyOptions o) {
    final qb = toUtf8(q);
    final qp = _alloc(qb);
    var d = Pointer<Void>.fromAddress(0);
    try {
      d = _l.filterDual(
          _ptr,
          qp,
          qb.length,
          o.caseMatching._c,
          o.normalization._c,
          maxDist,
          o.scoring._c,
          o.parallel ? 1 : 0,
          o.threads,
          o.limit);
      if (d == nullptr) {
        throw StateError(_dualOom);
      }
      final sr = _l.dualSeq(d);
      final er = _l.dualEdit(d);
      final seqHits =
          sr != nullptr ? _readHits(sr, o.highlight) : <FuzzyHit<T>>[];
      final editHits =
          er != nullptr ? _readHits(er, o.highlight) : <FuzzyHit<T>>[];
      return FuzzyDualResult(fuzzy: seqHits, approx: editHits);
    } finally {
      malloc.free(qp);
      if (d != nullptr) _l.dualFree(d);
    }
  }

  // ── Async bridge (edit/merge/fallback/dual) ───────────────────────────────
  // Mirrors searchAsync_ above: offload the native call to a worker isolate
  // instead of just wrapping the synchronous call in an async function (which
  // would still block the calling isolate for the whole native call).

  // 将隔离区返回的索引记录映射为宿主命中对象。
  List<FuzzyHit<T>> _fromRaws(List<(int, int, int, int, List<int>)> raws) => [
        for (final r in raws)
          if (r.$1 < items_.length)
            FuzzyHit<T>(
                items_[r.$1], r.$1, r.$2, kindOf(r.$3), r.$3, r.$4, r.$5)
      ];

  // 异步执行编辑距离搜索。
  @override
  Future<List<FuzzyHit<T>>> searchEditAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final raws = await Isolate.run(
          () => _isoSearchEdit(libPath, addr, qb, maxDist, o));
      return _fromRaws(raws);
    } finally {
      inFlight_--;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // 异步执行合并搜索。
  @override
  Future<List<FuzzyHit<T>>> searchMergeAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final raws = await Isolate.run(
          () => _isoSearchMF(libPath, addr, qb, maxDist, o, true));
      return _fromRaws(raws);
    } finally {
      inFlight_--;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // 异步执行回退搜索。
  @override
  Future<List<FuzzyHit<T>>> searchFallbackAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final raws = await Isolate.run(
          () => _isoSearchMF(libPath, addr, qb, maxDist, o, false));
      return _fromRaws(raws);
    } finally {
      inFlight_--;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // 异步执行双路搜索。
  @override
  Future<FuzzyDualResult<T>> searchDualAsync_(
      String q, int maxDist, FuzzyOptions o) async {
    check_();
    final addr = _ptr.address;
    final libPath = _libPath;
    final qb = toUtf8(q);
    inFlight_++;
    try {
      final (seqRaws, editRaws) = await Isolate.run(
          () => _isoSearchDual(libPath, addr, qb, maxDist, o));
      return FuzzyDualResult(
          fuzzy: _fromRaws(seqRaws), approx: _fromRaws(editRaws));
    } finally {
      inFlight_--;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // 将原生结果转换为宿主命中对象，按需读取高亮。
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
      out.add(FuzzyHit<T>(items_[idx], idx, _l.rScore(r, i), kindOf(kind), kind,
          _l.rKey(r, i), indices));
    }
    return out;
  }

  // 读取可跨隔离区传递的索引、分数、键和高亮。
  static List<(int, int, int, int, List<int>)> _readRaws(
      _Lib lib, Pointer<Void> r, bool highlight) {
    if (r == nullptr) return const [];
    return [
      for (var i = 0; i < lib.rLen(r); i++)
        (
          lib.rItem(r, i),
          lib.rScore(r, i),
          lib.rKind(r, i),
          lib.rKey(r, i),
          highlight
              ? List<int>.generate(lib.rNIdx(r, i), (j) => lib.rIdx(r, i, j))
              : const <int>[]
        )
    ];
  }

  // 在隔离区搜索并返回索引、分数、键和高亮。
  static List<(int, int, int, int, List<int>)> _isoSearch(
      String? libPath, int addr, Uint8List qb, int mode, FuzzyOptions o) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      if (o.highlight) {
        r = lib.filterEx2(
            ptr,
            qp,
            qb.length,
            mode,
            o.caseMatching._c,
            o.normalization._c,
            o.parallel ? 1 : 0,
            o.threads,
            o.limit,
            o.scoring._c);
      } else {
        r = lib.filterRaw(
            ptr,
            qp,
            qb.length,
            mode,
            o.caseMatching._c,
            o.normalization._c,
            o.parallel ? 1 : 0,
            o.threads,
            o.limit,
            o.scoring._c);
      }
      if (r == nullptr) throw StateError(_filterOom);
      return _readRaws(lib, r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) lib.rFree(r);
    }
  }

  // 在隔离区执行搜索，仅返回命中条目索引。
  static List<int> _isoSearchRaws(
      String? libPath, int addr, Uint8List qb, int mode, FuzzyOptions o) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      r = lib.filterRaw(
          ptr,
          qp,
          qb.length,
          mode,
          o.caseMatching._c,
          o.normalization._c,
          o.parallel ? 1 : 0,
          o.threads,
          o.limit,
          o.scoring._c);
      if (r == nullptr) throw StateError(_filterOom);
      final n = lib.rLen(r);
      final out =
          List<int>.generate(n, (i) => lib.rItem(r, i), growable: false);
      lib.rFree(r);
      r = nullptr;
      return out;
    } finally {
      malloc.free(qp);
      if (r != nullptr) lib.rFree(r);
    }
  }

  // 在隔离区执行编辑距离搜索并返回可传递记录。
  static List<(int, int, int, int, List<int>)> _isoSearchEdit(
      String? libPath, int addr, Uint8List qb, int maxDist, FuzzyOptions o) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      final fn = o.highlight ? lib.filterEdit : lib.filterEditRaw;
      r = fn(ptr, qp, qb.length, maxDist, o.caseMatching._c, o.normalization._c,
          o.limit);
      if (r == nullptr) throw StateError(_filterOom);
      return _readRaws(lib, r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) lib.rFree(r);
    }
  }

  // 在隔离区执行合并或回退搜索并释放临时结果。
  static List<(int, int, int, int, List<int>)> _isoSearchMF(String? libPath,
      int addr, Uint8List qb, int maxDist, FuzzyOptions o, bool useMerge) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var r = Pointer<Void>.fromAddress(0);
    try {
      final fn = useMerge ? lib.filterMerge : lib.filterFallback;
      r = fn(ptr, qp, qb.length, o.caseMatching._c, o.normalization._c, maxDist,
          o.scoring._c, o.parallel ? 1 : 0, o.threads, o.limit);
      if (r == nullptr) throw StateError(_filterOom);
      return _readRaws(lib, r, o.highlight);
    } finally {
      malloc.free(qp);
      if (r != nullptr) lib.rFree(r);
    }
  }

  // 在隔离区执行双路搜索并分别返回两路记录。
  static (
    List<(int, int, int, int, List<int>)>,
    List<(int, int, int, int, List<int>)>
  ) _isoSearchDual(
      String? libPath, int addr, Uint8List qb, int maxDist, FuzzyOptions o) {
    final lib = _Lib.resolve(libPath);
    final ptr = Pointer<Void>.fromAddress(addr);
    final qp = _alloc(qb);
    var d = Pointer<Void>.fromAddress(0);
    try {
      d = lib.filterDual(
          ptr,
          qp,
          qb.length,
          o.caseMatching._c,
          o.normalization._c,
          maxDist,
          o.scoring._c,
          o.parallel ? 1 : 0,
          o.threads,
          o.limit);
      if (d == nullptr) throw StateError(_filterOom);
      final seq = _readRaws(lib, lib.dualSeq(d), o.highlight);
      final edit = _readRaws(lib, lib.dualEdit(d), o.highlight);
      return (seq, edit);
    } finally {
      malloc.free(qp);
      if (d != nullptr) lib.dualFree(d);
    }
  }

  // ── Async build ───────────────────────────────────────────────────────────

  /// 异步追加 [items]，返回完成的 Future；文本提取异常向上传递。
  /// 销毁后、构建中或搜索未完成时调用抛 StateError；资源不足抛 FuzzyException。
  /// 写入失败会恢复旧索引；恢复也失败时销毁语料库并抛 StateError。
  ///
  /// 示例：`await corpus.asyncAddAll(["你好"]);`。
  Future<void> asyncAddAll(Iterable<T> items) async {
    checkMutate_();
    final list = List<T>.of(items);
    final texts = <Uint8List>[for (final it in list) toUtf8(stringOf_(it))];
    checkMutate_();
    final addr = _ptr.address;
    final libPath = _libPath;
    building_ = true;
    try {
      await Isolate.run(() {
        final lib = _Lib.resolve(libPath);
        final p = Pointer<Void>.fromAddress(addr);
        for (final bytes in texts) {
          final mp = _alloc(bytes);
          try {
            if (lib.add(p, mp, bytes.length) != 1) {
              throw const FuzzyException(_addOom);
            }
          } finally {
            malloc.free(mp);
          }
        }
      });
      for (final item in list) {
        items_.add(item);
        keys_.add(null);
      }
      for (final t in texts) {
        _estBytes += t.length;
      }
      _refreshFinalizer();
    } catch (e, st) {
      _l.clear(_ptr);
      _estBytes = 0;
      try {
        rebuild_();
      } catch (re) {
        disposed_ = true;
        freed_ = true;
        building_ = false;
        _l.finalizer.detach(this);
        _l.free(_ptr);
        Error.throwWithStackTrace(
            StateError(
                'asyncAddAll: worker failed ($e) and rebuild failed: $re'),
            st);
      }
      Error.throwWithStackTrace(e, st);
    } finally {
      building_ = false;
      signalIfIdle_();
      _keepAlive();
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// 释放语料库；无参数，无返回值，可重复调用。
  /// 调用后再搜索或修改抛 StateError；未结束的操作完成后释放资源。
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
      _l.finalizer.detach(this);
      cFree_();
    }
  }

  /// 销毁语料库并等待在途操作完成；无参数，返回资源释放完成的 Future。
  /// 可重复调用；调用后再搜索或修改抛 StateError。
  ///
  /// 示例：`await corpus.asyncDispose();`。
  Future<void> asyncDispose() async {
    disposed_ = true;
    if (inFlight_ > 0 || building_) {
      await (idle_ ??= Completer<void>()).future;
    }
    if (freed_) return;
    freed_ = true;
    _l.finalizer.detach(this);
    cFree_();
  }
}

// ── FuzzyCrash ────────────────────────────────────────────────────────────────

/// 原生崩溃报告接口，无需创建实例。
///
/// 示例：`FuzzyCrash.install();`。
class FuzzyCrash {
  FuzzyCrash._();
  static String? _path;

  /// 安装崩溃报告处理器；[breadcrumbPath] 为可选报告路径，[libraryPath] 为可选动态库路径。
  /// 返回是否安装成功，平台不支持时返回假；库加载失败抛 FuzzyException。
  ///
  /// 示例：`FuzzyCrash.install(breadcrumbPath: "crash.log");`。
  static bool install({String? breadcrumbPath, String? libraryPath}) {
    final f = _Lib.resolve(libraryPath).crash;
    if (f == null) return false;
    _path = breadcrumbPath;
    final p = breadcrumbPath == null ? nullptr : breadcrumbPath.toNativeUtf8();
    try {
      return f(p.cast()) != 0;
    } finally {
      if (p != nullptr) malloc.free(p);
    }
  }

  /// 读取并消费上次崩溃报告；[breadcrumbPath] 省略时使用安装时的路径。
  /// 返回报告文本；未配置路径、文件不存在或内容为空时返回空值，读取失败抛 FileSystemException。
  ///
  /// 示例：`final report = FuzzyCrash.lastReport(breadcrumbPath: "crash.log");`。
  static String? lastReport({String? breadcrumbPath}) {
    final p = breadcrumbPath ?? _path;
    if (p == null) return null;
    final f = File(p);
    if (!f.existsSync()) return null;
    final s = f.readAsStringSync();
    try {
      f.deleteSync();
    } catch (_) {
      try {
        f.writeAsBytesSync(const []);
      } catch (_) {}
    }
    return s.isEmpty ? null : s;
  }
}
