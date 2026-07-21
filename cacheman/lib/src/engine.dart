import 'dart:convert';

import 'entity.dart';
import 'interface.dart';

/// Per-call `write` options. Only these apply per call — everything else
/// (codec, sliding, raw, ...) is instance-level, see [CachemanOptions].
///
/// 单次 `write` 调用的选项。只有这些是 per-call 的——其余（codec/sliding/raw
/// 等）都是实例级配置，见 [CachemanOptions]。
class CacheOptions {
  const CacheOptions({this.ttl, this.expireAt, this.memoized});

  /// Time-to-live in ms (relative). Sets `expireAt = now + ttl`. An invalid
  /// value (`<= 0` or non-finite) is warned and ignored — the value still
  /// persists, just with no expiry.
  ///
  /// 存活时间（毫秒，相对）。设置 `expireAt = now + ttl`。非法值（`<=0` 或
  /// 非有限数）会警告并忽略——值照样写入，只是不带过期。
  final int? ttl;

  /// Absolute expiry: a `DateTime`, or ms-since-epoch. If in the past (and
  /// not renewable via `sliding` + `ttl`), the write is skipped with a
  /// warning.
  ///
  /// 绝对过期时间：`DateTime`，或毫秒时间戳。如果已经过去（且无法靠
  /// `sliding` + `ttl` 从现在续期），整次写入会被跳过并警告。
  final Object? expireAt;

  /// Mirror this write into the memo read cache (overrides the instance-level
  /// `memoized`).
  ///
  /// 把这次写入同步存入 memo 读缓存（覆盖实例级 `memoized`）。
  final bool? memoized;
}

/// Whether a copy is returned for a value shared with the memo cache
/// ([CachemanOptions.cloned] must be `true` for either of these to apply).
///
/// 是否给跟 memo 共享的值返回拷贝（[CachemanOptions.cloned] 必须为 `true`
/// 这两个才谈得上生效）。
class CachemanOptions {
  const CachemanOptions({
    this.memoized = false,
    this.cloned = false,
    this.deepCloned = false,
    String Function(CacheEntity)? serialize,
    CacheEntity Function(String)? deserialize,
    this.codeable = false,
    this.codec,
    this.sliding = false,
    this.namespace,
    this.raw = false,
    this.force = true,
    this.readonly = false,
    this.enckey = false,
    this.onError,
  })  : serialize = serialize ?? defaultSerialize,
        deserialize = deserialize ?? defaultDeserialize;

  /// Enable the in-memory read cache: writes mirror to cache, reads hit cache
  /// first, deletes are dual. Opt-in (not a full mirror), so memory grows
  /// only with use.
  ///
  /// 启用内存读缓存：写入双写、读取缓存优先、删除双删。选择性开启（非全量
  /// 镜像），只随实际使用增长。
  final bool memoized;

  /// Return a copy (not the memo-shared reference) for object/list/map
  /// values. Defaults to `false` (share the reference, zero cost). Shallow by
  /// default (`Map.of`/`List.of`); see [deepCloned].
  ///
  /// 对象/list/map 类值返回拷贝而非跟 memo 共享的引用。默认 `false`（共享
  /// 引用，零开销）。默认浅拷贝（`Map.of`/`List.of`）；见 [deepCloned]。
  final bool cloned;

  /// Only takes effect when [cloned] is `true`: makes the copy a *deep* one
  /// (re-decodes the already-serialized JSON string) instead of the default
  /// shallow copy. A shallow copy only isolates the top-level
  /// container — nested objects/lists are still shared; mutate a nested
  /// value and it leaks into the memo cache. Use `deepCloned` if you intend
  /// to mutate anything beyond the top level.
  ///
  /// 只有 [cloned] 为 `true` 时才谈得上生效：让拷贝变成**深拷贝**（重新解码
  /// 已经序列化好的 JSON 字符串），而不是默认的浅拷贝。浅拷贝只隔离最外层
  /// 容器——嵌套的对象/list 仍是共享的，改了嵌套值会污染 memo 缓存。打算修改
  /// 顶层以外的内容时用 `deepCloned`。
  final bool deepCloned;

  /// Custom entity -> string serializer, defaults to `jsonEncode`.
  ///
  /// 自定义 entity -> 字符串序列化，默认 `jsonEncode`。
  final String Function(CacheEntity) serialize;

  /// Custom string -> entity deserializer, must pair with [serialize].
  ///
  /// 自定义字符串 -> entity 反序列化，须与 [serialize] 配对。
  final CacheEntity Function(String) deserialize;

  /// Whether to invoke [codec]. Lets you toggle encoding per environment
  /// (dev/prod) without removing the codec itself.
  ///
  /// 是否调用 [codec]。可以按环境（开发/生产）开关，而不用整个拿掉 codec。
  final bool codeable;

  /// Encode/decode the serialized string. Takes effect on values only when
  /// [codeable] is `true`. No implementation ships with this package.
  ///
  /// 对序列化后的字符串做编解码。只有 [codeable] 为 `true` 时才对值生效。
  /// 本包不内置任何实现。
  final Codec? codec;

  /// Sliding expiry: renew by the original `ttl` on each read hit (good for
  /// sessions/auth). The write-back is skipped while more than 90% of the
  /// ttl remains, so hot reads don't amplify writes.
  ///
  /// 滑动过期：每次读命中后按原始 `ttl` 续期（适合登录态/会话类数据）。剩余
  /// 寿命超过 90% ttl 时跳过回写，避免高频读放大写次数。
  final bool sliding;

  /// Key prefix (`namespace:key`) to isolate apps/modules sharing the same
  /// underlying container.
  ///
  /// 键前缀（`namespace:key`），隔离共用同一底层 container 的不同应用/模块。
  final String? namespace;

  /// Store the raw value directly, skipping the entity envelope (no
  /// ttl/codec). The value must be a [String] — anything else is warned and
  /// the write is skipped (mirrors a fix in the sibling `@codejoo/storage` TS
  /// project).
  ///
  /// 直接存裸值，跳过 entity 信封（不带 ttl/codec）。值必须是 [String]——
  /// 其它类型会警告并跳过写入（对齐姊妹 TS 项目 `@codejoo/storage` 修过的
  /// 一个坑）。
  final bool raw;

  /// On a write exception, purge expired entries and retry the write once;
  /// otherwise log and give up. Only meaningfully triggers for a *synchronous*
  /// failure (e.g. a custom [serialize] throwing) — the persistent (`ls`)
  /// tier's actual disk-flush failures surface asynchronously and are
  /// reported via [onError] separately, not retried here (see
  /// `GetStorageAdapter`'s class doc).
  ///
  /// 写入抛异常时，清理过期条目后重试一次；否则记录日志并放弃。只对**同步**
  /// 失败（比如自定义 [serialize] 抛错）有实际触发场景——持久层（`ls`）真正
  /// 的落盘失败是异步冒出来的，走单独的 [onError] 上报，不会走这里的重试
  /// （见 `GetStorageAdapter` 的类文档）。
  final bool force;

  /// Write-once: only write when the key is empty (absent/expired);
  /// otherwise discard the write.
  ///
  /// 只写一次：仅当键为空（不存在/已过期）时才写入，否则丢弃本次写入。
  final bool readonly;

  /// Also obfuscate the key: when enabled with a [codec], the storage key is
  /// deterministically run through the codec. Requires a [codec], else it
  /// warns and degrades to plaintext keys.
  ///
  /// 也对键做混淆：设置且提供了 [codec] 时，存储键会经 codec 做确定性变换。
  /// 需要 [codec]，否则警告并降级为明文键。
  final bool enckey;

  /// Write-failure callback.
  ///
  /// 写入失败回调。
  final CachemanOnError? onError;
}

/// The engine shared by `ls` and `ss` — same logic, different backend
/// ([Store]) and memo cache instance. Mirrors the sibling `@codejoo/storage`
/// TS project's `proxy()`, minus the sync/async duality (everything here is
/// synchronous — see the design note in `cacheman.dart`).
///
/// `ls`/`ss`共用的引擎——逻辑一样，后端（[Store]）和 memo 缓存实例不同。对齐
/// 姊妹 TS 项目 `@codejoo/storage` 的 `proxy()`，去掉了同步/异步二态（这里
/// 全部同步——设计缘由见 `cacheman.dart`）。
class Engine {
  Engine(this._store, this._memo, this._opts) : _ns = _initialNs(_opts.namespace) {
    if (_opts.enckey && _opts.codec == null) {
      // ignore: avoid_print
      print('[cacheman] `enckey` requires a `codec`; none provided — keys remain in plaintext.');
    }
    if (_opts.codeable && _opts.codec == null) {
      // ignore: avoid_print
      print('[cacheman] `codeable` requires a `codec`; none provided — values are not encoded.');
    }
  }

  static String _initialNs(String? namespace) => namespace != null && namespace.isNotEmpty ? '$namespace:' : '';

  final Store _store;
  final MemoCache _memo;
  final CachemanOptions _opts;

  String _ns;

  bool get _codeable => _opts.codeable && _opts.codec != null;
  bool get _enckey => _opts.enckey && _opts.codec != null;

  final Map<String, String> _ekCache = <String, String>{};

  String get namespace => _ns;

  void setNamespace([String? ns]) {
    _memo.clear();
    _ns = _initialNs(ns);
    _ownedKeysCache = null; // ownership predicate (_owns) just changed — stale under the old ns
  }

  // ── key helpers ──────────────────────────────────────────────────────────

  String _fullKey(String key) {
    final nk = '$_ns$key';
    if (!_enckey) return nk;
    final cached = _ekCache[nk];
    if (cached != null) return cached;
    if (_ekCache.length >= 1024) _ekCache.clear(); // 防动态键名场景无限增长
    final encoded = _opts.codec!.encode(nk);
    _ekCache[nk] = encoded;
    return encoded;
  }

  String _decKey(String storageKey) => _enckey ? (_opts.codec!.decode(storageKey) ?? storageKey) : storageKey;

  /// Whether this storage key is owned by this instance (namespace matches;
  /// with `enckey`, it must decode successfully).
  ///
  /// 该存储键是否归本实例管辖（命名空间匹配；`enckey` 时须能解开）。
  bool _owns(String storageKey) {
    if (_enckey) {
      final decoded = _opts.codec!.decode(storageKey);
      return decoded != null && decoded.startsWith(_ns);
    }
    return storageKey.startsWith(_ns);
  }

  String _logical(String storageKey) {
    final fk = _decKey(storageKey);
    return _ns.isNotEmpty && fk.startsWith(_ns) ? fk.substring(_ns.length) : fk;
  }

  // ── serialize / codec ────────────────────────────────────────────────────

  String _dump(CacheEntity e) {
    final s = _opts.serialize(e);
    return _codeable ? _opts.codec!.encode(s) : s;
  }

  CacheEntity? _load(String raw) {
    try {
      final text = _codeable ? _opts.codec!.decode(raw) : raw;
      return text == null ? null : _opts.deserialize(text);
    } catch (_) {
      return null;
    }
  }

  dynamic _dup(dynamic value) {
    if (!_opts.cloned) return value;
    if (_opts.deepCloned) {
      // 深拷贝：借道已经序列化好的字符串再解码一次，天然深拷贝，不需要额外的
      // 通用 clone 原语（Dart 没有 structuredClone 的等价物）。
      try {
        return jsonDecode(jsonEncode(value));
      } catch (_) {
        return value; // 不可 JSON 化的值：拷贝不了，原样返回（跟共享引用等价，不再报错）
      }
    }
    // `value is Map` alone promotes to `Map<dynamic, dynamic>` (the type test
    // has no type args), so `Map.of(value)` would build a `<dynamic,
    // dynamic>` copy regardless of the original's actual key type — breaking
    // a caller's `get<Map<String, dynamic>>()` cast. Check the concrete
    // shape first (true for anything that went through JSON, which only ever
    // has String keys) so the copy keeps it.
    //
    // 单写 `value is Map`（类型测试不带类型参数）只会把类型提升到
    // `Map<dynamic, dynamic>`，导致 `Map.of(value)` 不管原始 key 类型是什么
    // 都造出一个 `<dynamic, dynamic>` 副本——破坏调用方 `get<Map<String,
    // dynamic>>()` 的类型转换。先判具体形状（凡是走过 JSON 的都必然是
    // String key），拷贝时才保得住类型。
    if (value is Map<String, dynamic>) return Map<String, dynamic>.of(value);
    if (value is Map) return Map.of(value);
    if (value is List) return List.of(value);
    if (value is Set) return Set.of(value);
    return value; // 标量天然不可变，跳过
  }

  // ── delete / collect / purge ─────────────────────────────────────────────

  void _del(String storageKey) {
    _memo.remove(storageKey);
    _store.remove(storageKey);
    _untrackOwned(storageKey);
  }

  /// Lazily-built, incrementally-maintained cache of this instance's own
  /// storage keys — avoids re-scanning the whole (possibly shared) backend on
  /// every [keys]/[length]/[key]/[erase]/[purge] call. Built once on first
  /// access via a full scan, then kept in sync by [_trackOwned]/
  /// [_untrackOwned] as this instance writes/deletes. Invalidated wholesale on
  /// [setNamespace] (the ownership predicate changed).
  ///
  /// **Caveat**: only writes/deletes made *through this instance* update the
  /// cache. A different [Engine] instance sharing the same namespace on the
  /// same backend (e.g. two `Cacheman.create()` calls for the same
  /// container+namespace) can drift this cache stale — the original
  /// always-full-scan behavior didn't have that limitation. Fine when each
  /// namespace is owned by exactly one live instance, which is the normal
  /// per-account-isolation use case.
  ///
  /// 懒建、增量维护的"本实例自有 key"缓存——避免每次 [keys]/[length]/[key]/
  /// [erase]/[purge] 都把（可能是共享的）后端整个扫一遍。首次访问时全扫建一
  /// 次，之后靠 [_trackOwned]/[_untrackOwned] 随本实例的写入/删除增量维护。
  /// [setNamespace] 时整体失效（所有权判定变了）。
  ///
  /// **注意**：只有经过本实例的写入/删除才会更新缓存。如果同一个 namespace
  /// 在同一个 backend 上被另一个 [Engine] 实例同时使用（比如同一个
  /// container+namespace 建了两个 `Cacheman.create()`），这个缓存可能读不到
  /// 对方的变更而过期——原来的每次全扫版本没有这个限制。正常的"每个
  /// namespace 只有一个存活实例"用法（比如按账号隔离）下没问题。
  Set<String>? _ownedKeysCache;

  void _trackOwned(String storageKey) => _ownedKeysCache?.add(storageKey);

  void _untrackOwned(String storageKey) => _ownedKeysCache?.remove(storageKey);

  List<String> _ownKeys() => (_ownedKeysCache ??= _store.keys().where(_owns).toSet()).toList(growable: false);

  bool _isExpired(CacheEntity? e, int now) => e != null && e.expireAt != null && e.createdAt != null && now >= e.expireAt!;

  void _purgeExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final k in _ownKeys()) {
      final raw = _store.get(k);
      if (raw != null && _isExpired(_load(raw), now)) _del(k);
    }
  }

  // ── persist ──────────────────────────────────────────────────────────────

  bool _persist(String storageKey, String str) {
    try {
      _store.set(storageKey, str);
      _trackOwned(storageKey);
      return true;
    } catch (e) {
      if (!_opts.force) {
        _reportError(storageKey, e);
        return false;
      }
      _purgeExpired();
      try {
        _store.set(storageKey, str);
        _trackOwned(storageKey);
        return true;
      } catch (e2) {
        _reportError(storageKey, e2);
        return false;
      }
    }
  }

  void _reportError(String key, Object error) {
    final cb = _opts.onError;
    if (cb != null) {
      cb(key, error);
    } else {
      // ignore: avoid_print
      print('[cacheman] write failed for "$key", giving up: $error');
    }
  }

  // ── read resolution ──────────────────────────────────────────────────────

  /// entity 命中后的过期/续期处理，返回最终值。
  dynamic _resolve(CacheEntity entity, String storageKey, bool fromMemoHit, dynamic fallback) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isExpired(entity, now)) {
      _del(storageKey);
      return fallback;
    }
    final shared = fromMemoHit || _opts.memoized;
    if (_opts.sliding && entity.ttl != null && entity.expireAt != null && entity.expireAt! - now <= entity.ttl! * 0.9) {
      final renewed = entity.renewed(now + entity.ttl!);
      if (_persist(storageKey, _dump(renewed))) {
        if (_opts.memoized) _memo.set(storageKey, renewed);
        return shared ? _dup(entity.value) : entity.value;
      }
      return shared ? _dup(entity.value) : entity.value;
    }
    if (!fromMemoHit && _opts.memoized) _memo.set(storageKey, entity);
    return shared ? _dup(entity.value) : entity.value;
  }

  dynamic _hydrate(String? raw, String storageKey, dynamic fallback) {
    if (raw == null) return fallback;
    if (_opts.raw) {
      if (_opts.memoized) _memo.set(storageKey, raw);
      return raw;
    }
    final entity = _load(raw);
    if (entity == null) {
      _del(storageKey);
      return fallback;
    }
    return _resolve(entity, storageKey, false, fallback);
  }

  /// memo 命中检查：raw 接受任意非空值；entity 仅接受 [CacheEntity]。
  ({bool hit, dynamic value}) _fromMemo(String storageKey, dynamic fallback) {
    final m = _memo.get(storageKey);
    if (_opts.raw) {
      return m != null ? (hit: true, value: _dup(m)) : (hit: false, value: null);
    }
    if (m is CacheEntity) return (hit: true, value: _resolve(m, storageKey, true, fallback));
    return (hit: false, value: null);
  }

  // ── public: read ─────────────────────────────────────────────────────────

  T? read<T>(String key, [T? defaultValue]) {
    final storageKey = _fullKey(key);
    final fallback = defaultValue;
    final memoHit = _fromMemo(storageKey, fallback);
    if (memoHit.hit) return memoHit.value as T?;
    return _hydrate(_store.get(storageKey), storageKey, fallback) as T?;
  }

  /// Batch read: returns a same-length list, positionally paired with
  /// [defaults] (missing slots fall back to `null`).
  ///
  /// 批量读取：返回等长 list，跟 [defaults] 逐位对应（缺位为 `null`）。
  List<dynamic> readAll(List<String> keys, [List<dynamic>? defaults]) => [
        for (var i = 0; i < keys.length; i++) read<dynamic>(keys[i], defaults != null && i < defaults.length ? defaults[i] : null),
      ];

  // ── public: write ────────────────────────────────────────────────────────

  /// Builds the entity to persist; `null` means validation failed (already
  /// warned) and the write should be skipped.
  ///
  /// 构造要落盘的 entity；`null` 表示校验没过（已经警告过），应放弃写入。
  CacheEntity? _mkEntity(dynamic value, int? ttl, Object? expireAt, String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    int? finalTtl = ttl;
    if (finalTtl != null && finalTtl <= 0) {
      // ignore: avoid_print
      print('[cacheman] ttl must be a positive number of ms, got $finalTtl; ignoring ttl for "$key"');
      finalTtl = null;
    }
    int? entityExpireAt;
    if (finalTtl != null) entityExpireAt = now + finalTtl;
    if (expireAt != null) {
      final abs = expireAt is DateTime
          ? expireAt.millisecondsSinceEpoch
          : expireAt is int
              ? expireAt
              : null;
      if (abs == null || (abs <= now && !(_opts.sliding && finalTtl != null))) {
        // ignore: avoid_print
        print('[cacheman] expireAt is invalid or in the past; skipped writing "$key"');
        return null;
      }
      entityExpireAt = abs <= now ? now + finalTtl! : abs;
    }
    return CacheEntity(value: value, createdAt: now, expireAt: entityExpireAt, ttl: finalTtl);
  }

  void write<T>(String key, T value, {int? ttl, Object? expireAt, bool? memoized}) {
    final storageKey = _fullKey(key);
    final $memoized = memoized ?? _opts.memoized;

    void write() {
      if (_opts.raw) {
        if (value is! String) {
          // ignore: avoid_print
          print('[cacheman] raw mode requires a String value for "$key", got ${value.runtimeType}; skipped');
          return;
        }
        if (_persist(storageKey, value) && $memoized) _memo.set(storageKey, value);
        return;
      }
      final entity = _mkEntity(value, ttl, expireAt, key);
      if (entity == null) return;
      if (_persist(storageKey, _dump(entity)) && $memoized) _memo.set(storageKey, entity);
    }

    if (_opts.readonly) {
      if (read<dynamic>(key) == null) write();
      return;
    }
    write();
  }

  /// Batch write: [values] pairs positionally with [keys]; [ttl]/[expireAt]/
  /// [memoized] apply to every key. If [values] is shorter, missing slots are
  /// skipped (warned).
  ///
  /// 批量写入：[values] 跟 [keys] 逐位对应；[ttl]/[expireAt]/[memoized] 对
  /// 全部键生效。[values] 短于 [keys] 时，缺位的键跳过（警告）。
  void writeAll(List<String> keys, List<dynamic> values, {int? ttl, Object? expireAt, bool? memoized}) {
    if (values.length < keys.length) {
      // ignore: avoid_print
      print('[cacheman] batch set: values(${values.length}) shorter than keys(${keys.length}); missing entries skipped');
    }
    final n = keys.length < values.length ? keys.length : values.length;
    for (var i = 0; i < n; i++) {
      write<dynamic>(keys[i], values[i], ttl: ttl, expireAt: expireAt, memoized: memoized);
    }
  }

  // ── public: remove / erase / keys / purge / destroy ─────────────────────

  void remove(String key) => _del(_fullKey(key));

  void removeAll(List<String> keys) {
    for (final k in keys) {
      _del(_fullKey(k));
    }
  }

  /// With `namespace` or `enckey`: removes only this instance's keys.
  /// Otherwise erases the whole backend.
  ///
  /// 带 `namespace` 或 `enckey` 时：只删本实例管辖的键。否则整个后端清空。
  void erase() {
    _memo.clear();
    if (_ns.isEmpty && !_enckey) {
      _store.clear();
      _ownedKeysCache = <String>{};
      return;
    }
    for (final k in _ownKeys()) {
      _store.remove(k);
      _untrackOwned(k);
    }
  }

  /// The `index`-th logical key (decrypted, namespace-stripped).
  ///
  /// 第 `index` 个逻辑键（已解密、去命名空间前缀）。
  String? key(int index) {
    if (_ns.isNotEmpty || _enckey) {
      final ks = _ownKeys();
      return index < 0 || index >= ks.length ? null : _logical(ks[index]);
    }
    final sk = _store.key(index);
    return sk == null ? null : _logical(sk);
  }

  /// All logical keys owned by this instance (decrypted, namespace-stripped).
  ///
  /// 本实例管辖的全部逻辑键（已解密、去命名空间前缀）。
  List<String> keys() => _ownKeys().map(_logical).toList(growable: false);

  /// Proactively deletes expired entries (owned, written by this library).
  /// Expiry is otherwise lazy.
  ///
  /// 主动清理已过期条目（本实例管辖、本库写入的）。平时是懒过期。
  void purge() => _purgeExpired();

  /// Entry count. With `namespace`/`enckey`, counts only owned keys;
  /// otherwise the backend's global count.
  ///
  /// 条目数。带 `namespace`/`enckey` 时只数本实例管辖的键；否则是后端的
  /// 全局条目数。
  int get length => _ns.isNotEmpty || _enckey ? _ownKeys().length : _store.length;

  /// Releases resources: clears the memo cache. Keeps persisted data.
  ///
  /// 释放资源：清空 memo 缓存。不删除已落盘数据。
  void destroy() => _memo.clear();
}
