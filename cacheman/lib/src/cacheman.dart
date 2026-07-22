import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:get_storage/get_storage.dart';

import 'entity.dart';
import 'options.dart';

/// Unified, type-safe wrapper over `get_storage` (persistent): TTL & absolute
/// expiry, sliding renewal, namespaces, pluggable serialization, an optional
/// codec hook, and batch ops. All the read/write/expiry/namespace logic lives
/// directly on this class — there is no internal `Engine` (or `.ls`)
/// indirection.
///
/// **Design note — why this is fully synchronous (unlike the sibling
/// `@codejoo/storage` TS project, whose `db`/IndexedDB tier returns
/// Promises)**: `get_storage`'s `read`/`write`/`remove` are synchronous
/// against its in-memory map once `init()` has completed — disk flush
/// happens in the background, debounced, and never blocks a read. There's no
/// second, genuinely-async persistent backend to justify a sync/async dual
/// API the way the TS version's `ls` (sync) vs `db` (async IndexedDB) split
/// does. So `Cacheman.create()` is the only `Future` boundary; every method
/// on [Cacheman] after that is synchronous.
///
/// 统一、类型安全地封装 `get_storage`（持久层）：TTL/绝对过期、滑动续期、
/// 命名空间、可插拔序列化、可选 codec 钩子、批量操作。全部读写/过期/命名
/// 空间逻辑都直接挂在本类上——没有内部 `Engine`（或 `.ls`）这层间接。
///
/// **设计说明——为什么这里全同步（不像姊妹 TS 项目 `@codejoo/storage`的
/// `db`/IndexedDB 层要返回 Promise）**：`get_storage` 的
/// `read`/`write`/`remove` 在 `init()` 完成之后，对它自己的内存态就是同步
/// 的——落盘是后台防抖做的，从不阻塞读。这里没有第二个真正异步的持久后端，
/// 犯不着像 TS 版 `ls`（同步）vs `db`（异步 IndexedDB）那样搞一套同步/异步
/// 二态 API。所以 `Cacheman.create()` 是唯一的 `Future` 边界，之后 [Cacheman]
/// 上的每个方法都是同步的。
///
/// ```dart
/// final cache = await Cacheman.create();
/// cache.write('token', 'abc');         // persists across restarts
/// cache.read<String>('token');         // 'abc' — synchronous
/// cache.setNamespace('alice');         // per-account isolation
/// ```
class Cacheman {
  Cacheman._(this._gs, this._opts) : _ns = _initialNs(_opts.namespace) {
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

  /// Creates and initializes a [Cacheman] instance. Must be awaited before
  /// first use — this is the only `Future` boundary in the whole API (see
  /// the class doc).
  ///
  /// [container]/[path] are forwarded to `GetStorage` (same container name ⇒
  /// same underlying data across `create()` calls — `get_storage` caches
  /// instances per container internally). [options] apply to this instance.
  ///
  /// 创建并初始化一个 [Cacheman] 实例。首次使用前必须 await——这是整个 API
  /// 里唯一的 `Future` 边界（见类文档）。
  ///
  /// [container]/[path] 透传给 `GetStorage`（同一个 container 名 ⇒
  /// `create()` 多次调用间是同一份底层数据——`get_storage` 内部按 container
  /// 名缓存实例）。[options] 作用于本实例。
  static Future<Cacheman> create({
    String container = 'cacheman',
    String? path,
    CachemanOptions options = const CachemanOptions(),
  }) async {
    // 不走 GetStorage.init(container)——它内部固定用 GetStorage(container)（不带
    // path）去建/取缓存实例，一旦先跑过一次就把这个 container 名永久钉死成
    // path=null，我们后面再传 path 也没用（factory 按 container 名读缓存，
    // 命中就直接返回旧实例，构造参数被无视）。这里改成自己先用带 path 的调用
    // 建好实例，再自己 await 它的 initStorage——WidgetsFlutterBinding 也要
    // 自己确保初始化（原来是 init() 内部帮着调的）。
    //
    // Not going through GetStorage.init(container) — it internally always
    // calls GetStorage(container) (no path) to create/fetch the cached
    // instance; once that's run once for this container name, `path` is
    // permanently baked in as null and any `path` we pass later is ignored
    // (the factory caches by container name — a cache hit just returns the
    // old instance, constructor args and all). Instead, construct the
    // instance ourselves WITH `path` first, then await its own
    // `initStorage` — and ensure `WidgetsFlutterBinding` ourselves (`init()`
    // used to do that for us).
    WidgetsFlutterBinding.ensureInitialized();
    final gs = GetStorage(container, path);
    await gs.initStorage;
    return Cacheman._(gs, options);
  }

  /// The `get_storage` container this instance persists to.
  ///
  /// get_storage's `read`/`write`/`remove` are synchronous against its
  /// in-memory map (the disk flush happens in the background, debounced) —
  /// so every method below that touches [_gs] is synchronous too, and the
  /// flush Future is fire-and-forget with an attached error handler
  /// ([_reportError] via `.catchError`).
  ///
  /// **Real difference from the sibling `@codejoo/storage` TS project**: TS's
  /// `force` option retries synchronously (persist throws → purge expired →
  /// retry once) because `localStorage.setItem` fails *synchronously* on
  /// quota. get_storage's flush failure surfaces *asynchronously*, decoupled
  /// from any single call (it writes the whole current map, not one key) —
  /// there's no reliable synchronous failure signal to retry against.
  /// [CachemanOptions.onError] is still called on an eventual flush failure,
  /// but there is no purge-and-retry step for it (that only applies to
  /// [_persist]'s own synchronous try/catch, see its doc).
  ///
  /// 本实例落盘的 get_storage container。
  ///
  /// get_storage 的 `read`/`write`/`remove` 对它自己的内存态是同步的（落盘是
  /// 后台防抖做的）——所以下面每个碰 [_gs] 的方法也都是同步的，flush 的
  /// Future 是即发即弃、挂了错误处理的（经 `.catchError` 调 [_reportError]）。
  ///
  /// **跟姊妹 TS 项目 `@codejoo/storage` 的真实差异**：TS 的 `force` 选项是
  /// 同步重试的（persist 抛错 → 清过期 → 重试一次），因为
  /// `localStorage.setItem` 在配额超限时是**同步**失败的。get_storage 的
  /// 落盘失败是**异步**冒出来的，且跟某一次具体调用脱钩（它落盘的是当前整个
  /// map，不是单个 key）——没有可靠的同步失败信号可供重试。
  /// [CachemanOptions.onError] 仍会在落盘最终失败时触发，但这里没有
  /// "清过期后重试"这一步（那一步只针对 [_persist] 自己的同步 try/catch，
  /// 见其文档）。
  final GetStorage _gs;

  /// The underlying `get_storage` container this instance persists to.
  /// Exposed for interop that needs the raw container — e.g. `listenKey`
  /// for external change notifications (see [storageKey] for the key to
  /// pass it).
  ///
  /// 本实例落盘的底层 `get_storage` container。给需要拿到原始 container 的
  /// 互操作场景用——比如用 `listenKey` 监听外部变更（配合 [storageKey] 拿
  /// 要传给它的 key）。
  GetStorage get container => _gs;

  final CachemanOptions _opts;

  String _ns;

  bool get _codeable => _opts.codeable && _opts.codec != null;
  bool get _enckey => _opts.enckey && _opts.codec != null;

  final Map<String, String> _ekCache = <String, String>{};

  /// Current namespace prefix (`''` if none set).
  ///
  /// 当前命名空间前缀（未设置时为 `''`）。
  String get namespace => _ns;

  /// Switches the namespace prefix **in place** (great for per-account
  /// isolation on login/logout) — handles you already hold keep working; it
  /// only isolates, it does not erase the previous namespace's persisted
  /// data.
  ///
  /// 原地切换命名空间前缀（很适合登入/登出时按账号隔离）——已经持有
  /// 的引用继续生效；只做隔离，不清除上个命名空间的落盘数据。
  void setNamespace([String? namespace]) {
    _ns = _initialNs(namespace);
    _ownedKeysCache = null; // ownership predicate (_owns) just changed — stale under the old ns
  }

  // ── key helpers ──────────────────────────────────────────────────────────

  /// The actual key [key] is persisted under in [container] — namespace
  /// prefixed and, with `enckey`, codec-encoded on top. External listeners
  /// (e.g. `container.listenKey(...)`) must watch this, not [key] itself,
  /// since the raw storage key is otherwise opaque (the codec is a
  /// pluggable, private implementation detail).
  ///
  /// [key] 在 [container] 里实际落盘用的 key——加了命名空间前缀，`enckey`
  /// 时还会经 codec 编码。外部监听器（比如 `container.listenKey(...)`）必须
  /// 监听这个，而不是 [key] 本身，因为原始存储 key 否则是不透明的（codec 是
  /// 可插拔的私有实现细节）。
  String storageKey(String key) => _fullKey(key);

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

  // ── delete / collect / purge ─────────────────────────────────────────────

  void _del(String storageKey) {
    _gs.remove(storageKey).catchError((Object e, StackTrace s) => _reportFlushError(storageKey, e, s));
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
  /// cache. A different [Cacheman] instance sharing the same namespace on the
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
  /// 在同一个 backend 上被另一个 [Cacheman] 实例同时使用（比如同一个
  /// container+namespace 建了两个 `Cacheman.create()`），这个缓存可能读不到
  /// 对方的变更而过期——原来的每次全扫版本没有这个限制。正常的"每个
  /// namespace 只有一个存活实例"用法（比如按账号隔离）下没问题。
  Set<String>? _ownedKeysCache;

  void _trackOwned(String storageKey) => _ownedKeysCache?.add(storageKey);

  void _untrackOwned(String storageKey) => _ownedKeysCache?.remove(storageKey);

  /// Walks `get_storage`'s key iterable directly instead of allocating a
  /// full `toString()`'d, materialized `List` first — this only runs once
  /// (to seed [_ownedKeysCache]), so the intermediate `.toSet()` is the only
  /// allocation.
  ///
  /// 直接遍历 get_storage 的 key 迭代器，不预先物化成完整 `List`——这只在
  /// 建缓存时跑一次（用来播种 [_ownedKeysCache]），中间的 `.toSet()` 已经是
  /// 唯一的一次分配。
  List<String> _ownKeys() => (_ownedKeysCache ??= _gs.getKeys<Iterable<dynamic>>().map((k) => k.toString()).where(_owns).toSet()).toList(growable: false);

  bool _isExpired(CacheEntity? e, int now) => e != null && e.expireAt != null && e.createdAt != null && now >= e.expireAt!;

  void _purgeExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final k in _ownKeys()) {
      final raw = _gsGet(k);
      if (raw != null && _isExpired(_load(raw), now)) _del(k);
    }
  }

  /// Reads the raw stored string for [key], or `null` if absent.
  ///
  /// This package only ever writes `String`s through [_persist]; if a
  /// non-`String` value is read back, it means external code wrote something
  /// else into the same container — treated as unrecognized data (absent),
  /// not an error.
  ///
  /// 读取 [key] 的原始存储串，不存在则 `null`。
  ///
  /// 本库只经 [_persist] 写入字符串；若读到非字符串，说明外部代码往同一个
  /// container 里塞了别的东西——视为不认识的数据（当缺失处理），不抛异常。
  String? _gsGet(String key) {
    final v = _gs.read<dynamic>(key);
    return v is String ? v : null;
  }

  // ── persist ──────────────────────────────────────────────────────────────

  /// Writes [str] under [storageKey].
  ///
  /// get_storage's `write` is synchronous against its in-memory map; the
  /// actual disk flush happens in the background (debounced) and is
  /// fire-and-forget here — a flush failure surfaces later, asynchronously,
  /// via [_reportFlushError], decoupled from this specific call (see [_gs]'s
  /// class-level doc for why that rules out a synchronous retry there).
  ///
  /// The try/catch below only ever catches a *synchronous* failure — e.g. a
  /// custom [CachemanOptions.serialize] throwing before `_gs.write` is even
  /// reached — and is the only thing [CachemanOptions.force] retries against.
  ///
  /// 把 [str] 写到 [storageKey] 下。
  ///
  /// get_storage 的 `write` 对它自己的内存态是同步的；真正落盘是后台防抖做的，
  /// 这里即发即弃——落盘失败会晚一点、异步地通过 [_reportFlushError] 冒出来，
  /// 跟这一次具体调用脱钩（为什么这排除了同步重试，见 [_gs] 的类级文档）。
  ///
  /// 下面的 try/catch 只捕获**同步**失败——比如自定义 [CachemanOptions.serialize]
  /// 在 `_gs.write` 还没跑到之前就抛了错——这也是 [CachemanOptions.force]
  /// 唯一会重试的对象。
  bool _persist(String storageKey, String str) {
    try {
      _gs.write(storageKey, str).catchError((Object e, StackTrace s) => _reportFlushError(storageKey, e, s));
      _trackOwned(storageKey);
      return true;
    } catch (e) {
      if (!_opts.force) {
        _reportError(storageKey, e);
        return false;
      }
      _purgeExpired();
      try {
        _gs.write(storageKey, str).catchError((Object e2, StackTrace s) => _reportFlushError(storageKey, e2, s));
        _trackOwned(storageKey);
        return true;
      } catch (e2) {
        _reportError(storageKey, e2);
        return false;
      }
    }
  }

  /// Reports a *synchronous* write failure ([_persist]'s own try/catch, after
  /// [CachemanOptions.force]'s retry — if enabled — also failed).
  ///
  /// 上报一次**同步**写入失败（[_persist] 自己的 try/catch，若启用了
  /// [CachemanOptions.force] 重试也失败之后）。
  void _reportError(String key, Object error) {
    final cb = _opts.onError;
    if (cb != null) {
      cb(key, error);
    } else {
      // ignore: avoid_print
      print('[cacheman] write failed for "$key", giving up: $error');
    }
  }

  /// Reports an *asynchronous* background disk-flush failure (`_gs.write`/
  /// `_gs.remove`/`_gs.erase`'s Future rejecting). Never retried — see [_gs]'s
  /// class-level doc for why.
  ///
  /// 上报一次**异步**的后台落盘失败（`_gs.write`/`_gs.remove`/`_gs.erase`
  /// 返回的 Future 被 reject）。从不重试——原因见 [_gs] 的类级文档。
  void _reportFlushError(String key, Object error, StackTrace stack) {
    final cb = _opts.onError;
    if (cb != null) {
      cb(key, error);
    } else {
      // ignore: avoid_print
      print('[cacheman] background flush failed for "$key": $error');
    }
  }

  // ── read resolution ──────────────────────────────────────────────────────

  /// entity 命中后的过期/续期处理，返回最终值。
  dynamic _resolve(CacheEntity entity, String storageKey, dynamic fallback) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isExpired(entity, now)) {
      _del(storageKey);
      return fallback;
    }
    if (_opts.sliding && entity.ttl != null && entity.expireAt != null && entity.expireAt! - now <= entity.ttl! * 0.9) {
      final renewed = entity.renewed(now + entity.ttl!);
      _persist(storageKey, _dump(renewed));
      return entity.value;
    }
    return entity.value;
  }

  dynamic _hydrate(String? raw, String storageKey, dynamic fallback) {
    if (raw == null) return fallback;
    if (_opts.raw) return raw;
    final entity = _load(raw);
    if (entity == null) {
      _del(storageKey);
      return fallback;
    }
    return _resolve(entity, storageKey, fallback);
  }

  // ── public: read ─────────────────────────────────────────────────────────

  /// Reads a key. Returns [defaultValue] if absent/expired.
  ///
  /// 读取一个键。不存在/已过期时返回 [defaultValue]。
  T? read<T>(String key, [T? defaultValue]) {
    final storageKey = _fullKey(key);
    return _hydrate(_gsGet(storageKey), storageKey, defaultValue) as T?;
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

  /// Writes a key, with optional per-call [ttl]/[expireAt].
  ///
  /// 写入一个键，可选 per-call 的 [ttl]/[expireAt]。
  void write<T>(String key, T value, {int? ttl, Object? expireAt}) {
    final storageKey = _fullKey(key);

    void write() {
      if (_opts.raw) {
        if (value is! String) {
          // ignore: avoid_print
          print('[cacheman] raw mode requires a String value for "$key", got ${value.runtimeType}; skipped');
          return;
        }
        _persist(storageKey, value);
        return;
      }
      final entity = _mkEntity(value, ttl, expireAt, key);
      if (entity == null) return;
      _persist(storageKey, _dump(entity));
    }

    if (_opts.readonly) {
      if (read<dynamic>(key) == null) write();
      return;
    }
    write();
  }

  /// Batch write: [values] pairs positionally with [keys]; [ttl]/[expireAt]
  /// apply to every key. If [values] is shorter, missing slots are
  /// skipped (warned).
  ///
  /// 批量写入：[values] 跟 [keys] 逐位对应；[ttl]/[expireAt] 对
  /// 全部键生效。[values] 短于 [keys] 时，缺位的键跳过（警告）。
  void writeAll(List<String> keys, List<dynamic> values, {int? ttl, Object? expireAt}) {
    if (values.length < keys.length) {
      // ignore: avoid_print
      print('[cacheman] batch set: values(${values.length}) shorter than keys(${keys.length}); missing entries skipped');
    }
    final n = keys.length < values.length ? keys.length : values.length;
    for (var i = 0; i < n; i++) {
      write<dynamic>(keys[i], values[i], ttl: ttl, expireAt: expireAt);
    }
  }

  // ── public: remove / erase / keys / purge ────────────────────────────────

  /// Removes a key.
  ///
  /// 删除一个键。
  void remove(String key) => _del(_fullKey(key));

  /// Removes several keys at once.
  ///
  /// 一次删除多个键。
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
    if (_ns.isEmpty && !_enckey) {
      _gs.erase().catchError((Object e, StackTrace s) => _reportFlushError('*', e, s));
      _ownedKeysCache = <String>{};
      return;
    }
    for (final k in _ownKeys()) {
      _gs.remove(k).catchError((Object e, StackTrace s) => _reportFlushError(k, e, s));
      _untrackOwned(k);
    }
  }

  /// The `index`-th logical key (decrypted, namespace-stripped).
  ///
  /// Without a namespace/`enckey`, walks `get_storage`'s key iterable
  /// directly instead of going through [keys]/[_ownKeys] — those allocate a
  /// full `toString()`'d, materialized `List` for every key just to then
  /// index into it once. get_storage exposes no positional-access API, so
  /// this is still O(index) (can't do better than a walk), but it skips the
  /// wasted full-list allocation.
  ///
  /// 第 `index` 个逻辑键（已解密、去命名空间前缀）。
  ///
  /// 没有 namespace/`enckey` 时，直接遍历 get_storage 的 key 迭代器，不经过
  /// [keys]/[_ownKeys]——它们会把每个 key 都 `toString()` 一遍、物化成完整
  /// `List`，只为了取其中一个下标。get_storage 没有按下标直接访问的 API，
  /// 所以这里仍是 O(index)（避不开遍历），但省掉了那次浪费的整表分配。
  String? key(int index) {
    if (_ns.isNotEmpty || _enckey) {
      final ks = _ownKeys();
      return index < 0 || index >= ks.length ? null : _logical(ks[index]);
    }
    if (index < 0) return null;
    var i = 0;
    for (final k in _gs.getKeys<Iterable<dynamic>>()) {
      if (i == index) return _logical(k.toString());
      i++;
    }
    return null;
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
  /// Without a namespace/`enckey`, counts `get_storage`'s key iterable
  /// directly instead of `keys().length` — same rationale as [key]: no need
  /// to `toString()`/materialize every key just to count them.
  ///
  /// 条目数。带 `namespace`/`enckey` 时只数本实例管辖的键；否则是后端的
  /// 全局条目数。
  ///
  /// 没有 namespace/`enckey` 时，直接数 get_storage key 迭代器的元素个数，
  /// 不走 `keys().length`——理由同 [key]：数个数用不着把每个 key 都
  /// `toString()`/物化一遍。
  int get length => _ns.isNotEmpty || _enckey ? _ownKeys().length : _gs.getKeys<Iterable<dynamic>>().length;
}
