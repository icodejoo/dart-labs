// ignore_for_file: prefer_initializing_formals
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
///   ..add(DiomanCache(expires: 30000)); // 30 s
///
/// // Per-request:
/// dio.get('/list', options: Options(extra: {
///   'dioman:cache': const DiomanCacheOptions(expires: 5000, clone: CacheClone.shallow),
/// }));
/// ```
class DiomanCache extends DiomanPlugin {
  DiomanCache({
    this.expires = 60000, // milliseconds
    this.clone = DiomanClonePolicy.shallow,
    this.maxEntries = 500,
    this.enabled = true,
    bool Function(RequestOptions)? shouldCache,
    DateTime Function() now = DateTime.now,
  })  : _shouldCache = shouldCache ?? _defaultShouldCache,
        _now = now;

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

  /// Maximum number of cached entries (LRU-evicted once exceeded). Without a
  /// cap, keys that vary per request (e.g. deep [DiomanKey] mode on
  /// paginated/search endpoints) accumulate forever, since an entry is only
  /// otherwise removed when its *exact* key is requested again after expiry.
  /// Set to `0` to disable the cap.
  ///
  /// 缓存条目上限（超出后按LRU淘汰）。没有上限的话，每次请求都不同的key
  /// （比如分页/搜索接口用deep模式的[DiomanKey]）会无限堆积，因为条目只有在
  /// 过期后被*完全相同*的key再请求一次才会被清掉。设为`0`关闭上限。
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

  static bool _defaultShouldCache(RequestOptions o) =>
      o.method.toUpperCase() == 'GET';

  @override
  String get name => pluginName;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final $options = _resolve(options);
    if ($options == null) return handler.next(options);

    final key = options.extra[kKey] as String?;
    if (key == null) return handler.next(options); // no key → no cache

    final $now = $options.now;
    final entry = _store[key];
    if (entry != null) {
      if (entry.expiresAt > $now().millisecondsSinceEpoch) {
        // Fresh hit — move to the end so eviction is true LRU (most-recently
        // *used*, not merely most-recently-written); otherwise a hot but old
        // entry would be evicted ahead of a colder, newer one.
        _store.remove(key);
        _store[key] = entry;
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
      _store.remove(key); // expired
    }

    // Mark for writing on response.
    options.extra[_kCacheKey] = key;
    options.extra[_kCacheTtl] = $options.expires;
    options.extra[_kCacheClone] = $options.clone;
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
      // Remove-then-reinsert moves this key to the end of iteration order
      // (Dart's default Map is insertion-ordered), so eviction below always
      // drops the least-recently-written entry first.
      _store.remove(key);
      _store[key] = _Entry(
        response.data,
        $now().millisecondsSinceEpoch + ttl,
      );
      _evictIfNeeded();
    }
    handler.next(response);
  }

  void _evictIfNeeded() {
    if (maxEntries <= 0) return;
    while (_store.length > maxEntries) {
      _store.remove(_store.keys.first);
    }
  }

  // ── Cache management ──────────────────────────────────────────────────────

  /// Removes a single cached entry by key.
  ///
  /// 按key移除单条缓存条目。
  void remove(String key) => _store.remove(key);

  /// Removes every cached entry whose key satisfies [test].
  ///
  /// 移除所有满足[test]的缓存条目。
  void removeWhere(bool Function(String key) test) =>
      _store.removeWhere((k, _) => test(k));

  /// Clears the entire cache.
  ///
  /// 清空整个缓存。
  void clear() => _store.clear();

  /// Current number of cached entries.
  ///
  /// 当前缓存条目数。
  int get size => _store.length;

  // ── Helpers ───────────────────────────────────────────────────────────────

  ({int expires, DiomanClonePolicy clone, DateTime Function() now})? _resolve(
      RequestOptions opts) {
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
