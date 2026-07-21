// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'package:dio/dio.dart';
import 'key_plugin.dart';
import 'dioman_plugin.dart';

/// Clone strategy for cache hits.
///
/// 缓存命中时的克隆策略。
enum DiomanClonePolicy {
  /// Return a reference to the cached data directly (zero copy). Treat it as
  /// read-only or use immutable-update patterns.
  ///
  /// 直接返回缓存数据的引用（零拷贝）。请当只读处理，或用不可变更新方式。
  none,

  /// Shallow-copy the top-level map / list. Nested objects are still shared.
  ///
  /// 浅拷贝顶层map/list，嵌套对象仍共享。
  shallow,

  /// Deep-copy via [Map.from] / [List.from] recursively. Safe for mutation.
  ///
  /// 通过[Map.from]/[List.from]递归深拷贝，可安全修改。
  deep,
}

/// Where a cached entry lives: memory, [DiomanCache.persist], or both.
///
/// 缓存条目存在哪：内存、[DiomanCache.persist]，或两者。
enum DiomanCachePolicy {
  /// Don't cache this request at all.
  ///
  /// 完全不缓存该请求。
  none,

  /// In-memory `_store` only — not durable, gone on restart/dispose.
  ///
  /// 只用内存层——不持久，重启或dispose后丢失。
  memo,

  /// [DiomanCache.persist] only.
  ///
  /// 只用[DiomanCache.persist]。
  persist,

  /// Both, kept in sync: a write goes to memory and [DiomanCache.persist]; a
  /// memory miss falls back to `persist.read` and backfills memory.
  ///
  /// 两者同步：写入时内存和[DiomanCache.persist]都写；内存未命中时回退读取
  /// `persist`并回填内存。
  both,
}

class _Entry {
  _Entry(this.data, this.expiresAt);

  /// The cached (post-normalize) response payload.
  ///
  /// 缓存的响应负载（已经过normalize处理）。
  final dynamic data;

  /// Expiry timestamp, epoch milliseconds.
  ///
  /// 过期时间戳，epoch毫秒。
  final int expiresAt;
}

/// Pluggable persistence hook for [DiomanCache] — no built-in implementation,
/// the caller wires up their own durability technology (file / sqlite / Hive
/// / get_storage / ...). [read] may be sync or async (`FutureOr`); [write]/
/// [remove]/[erase] are always async. Called without awaiting; implementations
/// must serialize their own I/O so calls land in the order they were issued,
/// and must catch their own errors — a rejected [write]/[remove]/[erase] is
/// never observed by [DiomanCache].
///
/// 落盘扩展点：不内置任何实现，由调用方接入自己的持久化技术（文件/sqlite/
/// Hive/get_storage等）。[read]可以是同步也可以是异步（`FutureOr`）；
/// [write]/[remove]/[erase]永远异步。调用时不等待完成；实现方需要自己保证
/// 调用落地的顺序跟发出顺序一致，也要自己捕获异常——[write]/[remove]/
/// [erase]的失败[DiomanCache]不会感知到。
///
/// ```dart
/// class MyGetStoragePersist implements DiomanCachePersist {
///   final _box = GetStorage('dioman_cache');
///   @override
///   dynamic read(String key) => _box.read(key); // sync example
///   @override
///   Future<void> write(String key, Map<String, dynamic> value) =>
///       _box.write(key, value);
///   @override
///   Future<void> remove(String key) => _box.remove(key);
///   @override
///   Future<void> erase() => _box.erase();
/// }
/// ```
abstract class DiomanCachePersist {
  /// Reads whatever was last persisted for [key], or `null` if there's
  /// nothing. May return synchronously or a `Future`.
  ///
  /// 读取[key]最后一次落盘的内容，没有则返回`null`。可以同步返回，也可以返回
  /// 一个`Future`。
  FutureOr<dynamic> read(String key);

  /// Persists [value] under [key]. Always a plain, JSON-encodable
  /// `{'data': ..., 'expiresAt': ...}` map — safe to `jsonEncode` directly
  /// in the implementation.
  ///
  /// 落盘保存[key]对应的[value]。固定是可直接`jsonEncode`的
  /// `{'data': ..., 'expiresAt': ...}` map。
  Future<void> write(String key, Map<String, dynamic> value);

  /// Removes a single persisted entry.
  ///
  /// 移除单条落盘数据。
  Future<void> remove(String key);

  /// Wipes every persisted entry this store holds.
  ///
  /// 清空该存储的全部落盘数据。
  Future<void> erase();
}

/// Per-request override for [DiomanCache], read from `extra['dioman:cache']`.
///
/// [DiomanCache]的单请求覆盖，从`extra['dioman:cache']`读取。
class DiomanCacheOptions {
  const DiomanCacheOptions({
    this.enabled,
    this.expires,
    this.clone,
    this.maxEntries,
    this.shouldCache,
    this.now,
    this.cachePolicy,
  });

  /// `false` skips cache for this request. `null` (default) inherits the
  /// plugin's own [DiomanCache.enabled].
  ///
  /// `false`表示本次请求跳过缓存。`null`（默认）沿用插件自身的[DiomanCache.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default TTL for this request only.
  ///
  /// 仅本次请求覆盖插件默认的TTL。
  final int? expires;

  /// Overrides the plugin's default clone strategy for this request only.
  ///
  /// 仅本次请求覆盖插件默认的克隆策略。
  final DiomanClonePolicy? clone;

  /// Mirrors the constructor's `maxEntries` for structural symmetry. Not
  /// consulted per-request — the store's eviction bound is a whole-cache
  /// property, not something a single call can sensibly override.
  ///
  /// 镜像构造函数的`maxEntries`，纯粹结构对称——不会在单请求时读取，因为淘汰上限
  /// 是整个缓存共享的属性，单次调用覆盖没有意义。
  final int? maxEntries;

  /// Overrides the plugin's `shouldCache` decision for this request only.
  ///
  /// 仅本次请求覆盖插件的`shouldCache`判定函数。
  final bool Function(RequestOptions)? shouldCache;

  /// Overrides the plugin's `now` clock for this request only.
  ///
  /// 仅本次请求覆盖插件的时钟函数`now`。
  final DateTime Function()? now;

  /// Overrides the plugin's default [DiomanCachePolicy] for this request only.
  ///
  /// 仅本次请求覆盖插件默认的[DiomanCachePolicy]。
  final DiomanCachePolicy? cachePolicy;
}

/// TTL-based response cache.
///
/// 基于TTL的响应缓存。
///
/// **Depends on [DiomanKey]** for the request key. Install that first.
///
/// **依赖[DiomanKey]**提供请求key，须先安装它。
///
/// Per-request control via `options.extra['dioman:cache']`:
/// - `const DiomanCacheOptions(enabled: false)` → skip cache for this request
/// - `const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow)` → custom per-request settings
///
/// ```dart
/// dio.interceptors
///   ..add(DiomanKey())
///   ..add(DiomanCache(
///     persist: MyDiomanCachePersist(), // your own DiomanCachePersist impl
///     cachePolicy: DiomanCachePolicy.both, // sync memory + persist
///     expires: 30000, // 30 s
///   ));
///
/// // Per-request:
/// dio.get('/list', options: Options(extra: {
///   'dioman:cache': const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow),
/// }));
/// ```
class DiomanCache extends DiomanPlugin {
  DiomanCache({
    required this.persist,
    this.cachePolicy = DiomanCachePolicy.none,
    this.expires = 60000, // milliseconds
    this.clone = DiomanClonePolicy.shallow,
    this.maxEntries = 500,
    this.enabled = true,
    bool Function(RequestOptions)? shouldCache,
    DateTime Function() now = DateTime.now,
  })  : _shouldCache = shouldCache ?? _defaultShouldCache,
        _now = now;

  /// Backing store for [DiomanCachePolicy.persist]/[DiomanCachePolicy.both].
  /// Required regardless of [cachePolicy]'s default.
  ///
  /// [DiomanCachePolicy.persist]/[DiomanCachePolicy.both]的落盘后端。不管
  /// [cachePolicy]默认是什么都必传。
  final DiomanCachePersist persist;

  /// Default [DiomanCachePolicy] for every request, overridable per request
  /// via [DiomanCacheOptions.cachePolicy].
  ///
  /// 每个请求的默认[DiomanCachePolicy]，可通过
  /// [DiomanCacheOptions.cachePolicy]按请求覆盖。
  final DiomanCachePolicy cachePolicy;

  /// `false` disables the plugin entirely — every request passes through
  /// untouched and nothing is ever cached.
  ///
  /// `false`时插件整体失效——所有请求原样通过，永不缓存。
  final bool enabled;

  /// Default TTL in **milliseconds**.
  ///
  /// 默认TTL，单位**毫秒**。
  final int expires;

  /// Default clone strategy. Defaults to [DiomanClonePolicy.shallow] so a caller that
  /// reassigns top-level fields on a cache hit can't corrupt the stored entry;
  /// use [DiomanClonePolicy.deep] if callers mutate nested objects, or
  /// [DiomanClonePolicy.none] for zero-copy when the result is treated as read-only.
  ///
  /// 默认克隆策略，默认[DiomanClonePolicy.shallow]——命中方重新赋值顶层字段不会污染
  /// 存储的条目；若会改嵌套对象用[DiomanClonePolicy.deep]，只读场景用[DiomanClonePolicy.none]
  /// 做零拷贝。
  final DiomanClonePolicy clone;

  /// Maximum number of in-memory entries, LRU-evicted once exceeded. `0`
  /// disables the cap. Only applies to the memory store — [persist]'s
  /// capacity is entirely the caller's concern.
  ///
  /// 内存层条目上限，超出后按LRU淘汰。`0`关闭上限。只作用于内存层——
  /// [persist]的容量完全是调用方自己的事。
  final int maxEntries;

  /// Decides whether a request should be cached at all. Defaults to GET-only.
  /// Overridable per request via [DiomanCacheOptions.shouldCache].
  ///
  /// 判断某请求是否要缓存，默认只缓存GET。可通过
  /// [DiomanCacheOptions.shouldCache]按请求覆盖。
  final bool Function(RequestOptions) _shouldCache;

  /// Clock used for TTL expiry checks (injectable for deterministic tests).
  /// Overridable per request via [DiomanCacheOptions.now].
  ///
  /// TTL过期检查用的时钟（可注入以便做确定性测试）。可通过
  /// [DiomanCacheOptions.now]按请求覆盖。
  final DateTime Function() _now;

  final _store = <String, _Entry>{};

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:cache';
  static const _kCacheKey = '$pluginName:key';
  static const _kCacheTtl = '$pluginName:ttl';
  static const _kCacheClone = '$pluginName:clone';
  static const _kCachePolicy = '$pluginName:policy';

  /// Keys of the `{data, expiresAt}` map handed to/read back from [persist].
  ///
  /// 传给/从[persist]读回的`{data, expiresAt}` map的字段名。
  static const _kPersistData = 'data';
  static const _kPersistExpiresAt = 'expiresAt';

  static bool _defaultShouldCache(RequestOptions o) =>
      o.method.toUpperCase() == 'GET';

  @override
  String get name => pluginName;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final $options = _resolve(options);
    if ($options == null) return handler.next(options);

    final key = options.extra[kKey] as String?;
    if (key == null) return handler.next(options); // no key → no cache

    final policy = $options.cachePolicy;
    final useMemo = policy == DiomanCachePolicy.memo ||
        policy == DiomanCachePolicy.both;
    final usePersist = policy == DiomanCachePolicy.persist ||
        policy == DiomanCachePolicy.both;

    final $now = $options.now;
    var entry = useMemo ? _store[key] : null;
    if (entry == null && usePersist) {
      // Memory miss (or memory not in play for this policy) — persist may
      // still hold the entry (durable across restarts, or the only layer
      // this policy uses at all).
      entry = await _hydrateFromPersist(key);
    }
    if (entry != null) {
      if (entry.expiresAt > $now().millisecondsSinceEpoch) {
        if (useMemo) {
          // Fresh hit — move to the end so eviction is true LRU
          // (most-recently *used*, not merely most-recently-written); also
          // how a `both`-policy persist hydration backfills memory.
          _store.remove(key);
          _store[key] = entry;
        }
        // callFollowingResponseInterceptor: true — a cache hit must still
        // run onResponse of everything installed after cache (share, mock,
        // cancel, loading, auth, retry, log, normalize), same as a real
        // response, so e.g. DiomanNormalize still unwraps a cached envelope.
        return handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            data: _applyClone(entry.data, $options.clone),
            statusCode: 200,
            statusMessage: 'OK (cached)',
          ),
          true,
        );
      }
      // Expired — clean up wherever this policy looked for it.
      if (useMemo) _store.remove(key);
      if (usePersist) unawaited(persist.remove(key));
    }

    // Mark for writing on response.
    options.extra[_kCacheKey] = key;
    options.extra[_kCacheTtl] = $options.expires;
    options.extra[_kCacheClone] = $options.clone;
    options.extra[_kCachePolicy] = policy;
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    final key = opts.extra[_kCacheKey] as String?;
    if (key != null &&
        (response.statusCode ?? 0) >= 200 &&
        (response.statusCode ?? 0) < 300) {
      final ttl = opts.extra[_kCacheTtl] as int? ?? expires;
      final override = opts.extra[name];
      final o = override is DiomanCacheOptions ? override : null;
      final $now = o?.now ?? _now;
      final policy =
          opts.extra[_kCachePolicy] as DiomanCachePolicy? ?? cachePolicy;
      final useMemo = policy == DiomanCachePolicy.memo ||
          policy == DiomanCachePolicy.both;
      final usePersist = policy == DiomanCachePolicy.persist ||
          policy == DiomanCachePolicy.both;
      // Remove-then-reinsert moves this key to the end of iteration order
      // (Dart's default Map is insertion-ordered), so eviction below always
      // drops the least-recently-written entry first.
      final expiresAt = $now().millisecondsSinceEpoch + ttl;
      if (useMemo) {
        _store.remove(key);
        _store[key] = _Entry(response.data, expiresAt);
        _evictIfNeeded();
      }
      if (usePersist) {
        unawaited(
          persist.write(key,
              {_kPersistData: response.data, _kPersistExpiresAt: expiresAt}),
        );
      }
    }
    handler.next(response);
  }

  void _evictIfNeeded() {
    if (maxEntries <= 0) return;
    while (_store.length > maxEntries) {
      _store.remove(_store.keys.first);
    }
  }

  /// Reads a single [_Entry] back from [persist] for [key], if any.
  ///
  /// 从[persist]为[key]读回单条[_Entry]（如果有的话）。
  Future<_Entry?> _hydrateFromPersist(String key) async {
    final raw = await persist.read(key);
    if (raw is Map && raw[_kPersistExpiresAt] is int) {
      return _Entry(raw[_kPersistData], raw[_kPersistExpiresAt] as int);
    }
    return null;
  }

  // ── Cache management ──────────────────────────────────────────────────────

  /// Removes a single cached entry by key (memory and [persist] both).
  ///
  /// 按key移除单条缓存条目（同时清掉内存和[persist]落盘的部分）。
  void remove(String key) {
    _store.remove(key);
    unawaited(persist.remove(key));
  }

  /// Clears the entire cache — memory and [persist] both.
  ///
  /// 清空整个缓存——内存和[persist]落盘的部分都清空。
  void clear() {
    _store.clear();
    unawaited(persist.erase());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  ({
    int expires,
    DiomanClonePolicy clone,
    DateTime Function() now,
    DiomanCachePolicy cachePolicy
  })? _resolve(RequestOptions opts) {
    final override = opts.extra[name];
    final o = override is DiomanCacheOptions ? override : null;
    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return null;
    final $shouldCache = o?.shouldCache ?? _shouldCache;
    if (!$shouldCache(opts)) return null;
    return (
      expires: o?.expires ?? expires,
      clone: o?.clone ?? clone,
      now: o?.now ?? _now,
      cachePolicy: o?.cachePolicy ?? cachePolicy,
    );
  }

  static dynamic _applyClone(dynamic data, DiomanClonePolicy strategy) {
    switch (strategy) {
      case DiomanClonePolicy.none:
        return data;
      case DiomanClonePolicy.shallow:
        // Preserve the concrete generic type — a JSON body is
        // Map<String, dynamic> / List<dynamic>, and downcasting it to
        // dynamic keys here would break a typed `dio.get<Map<String, dynamic>>`.
        if (data is Map<String, dynamic>) return Map<String, dynamic>.of(data);
        if (data is Map) return Map.of(data);
        if (data is List) return List.of(data);
        return data;
      case DiomanClonePolicy.deep:
        return _deepCopy(data);
    }
  }

  static dynamic _deepCopy(dynamic v) {
    if (v is Map<String, dynamic>) {
      return <String, dynamic>{
        for (final e in v.entries) e.key: _deepCopy(e.value)
      };
    }
    if (v is Map) {
      return {for (final e in v.entries) e.key: _deepCopy(e.value)};
    }
    if (v is List) return [for (final e in v) _deepCopy(e)];
    return v;
  }

  @override
  void dispose() => _store.clear();
}
