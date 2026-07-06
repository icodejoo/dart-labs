// ignore_for_file: prefer_initializing_formals
import 'package:dio/dio.dart';
import 'key_plugin.dart';
import 'dio_plugin.dart';

/// Clone strategy for cache hits.
enum CacheClone {
  /// Return a reference to the cached data directly (zero copy). Treat it as
  /// read-only or use immutable-update patterns.
  none,

  /// Shallow-copy the top-level map / list. Nested objects are still shared.
  shallow,

  /// Deep-copy via [Map.from] / [List.from] recursively. Safe for mutation.
  deep,
}

class _Entry {
  _Entry(this.data, this.expiresAt);
  final dynamic data;
  final int expiresAt; // epoch ms
}

/// TTL-based response cache.
///
/// **Depends on [KeyPlugin]** for the request key. Install that first.
///
/// Per-request control via `options.extra[CachePlugin.configProperty]`:
/// - `false` → skip cache for this request
/// - `true`  → enable with plugin defaults
/// - `{expires: int, clone: CacheClone}` → custom per-request settings
///
/// ```dart
/// dio.interceptors
///   ..add(KeyPlugin())
///   ..add(CachePlugin(expires: 30000)); // 30 s
///
/// // Per-request:
/// dio.get('/list', options: Options(extra: {
///   CachePlugin.configProperty: {'expires': 5000, 'clone': CacheClone.shallow},
/// }));
/// ```
class CachePlugin extends DioPlugin {
  /// The `extra` key callers use to opt out of / reconfigure caching for a
  /// single request. Change this to remap it.
  static String configProperty = 'dioman:cache';

  CachePlugin({
    this.expires = 60000, // milliseconds
    this.clone = CacheClone.shallow,
    this.maxEntries = 500,
    bool Function(RequestOptions)? shouldCache,
    DateTime Function() now = DateTime.now,
  })  : _shouldCache = shouldCache ?? _defaultShouldCache,
        _now = now;

  /// Default TTL in **milliseconds**.
  final int expires;

  /// Default clone strategy. Defaults to [CacheClone.shallow] so a caller that
  /// reassigns top-level fields on a cache hit can't corrupt the stored entry;
  /// use [CacheClone.deep] if callers mutate nested objects, or
  /// [CacheClone.none] for zero-copy when the result is treated as read-only.
  final CacheClone clone;

  /// Maximum number of cached entries (LRU-evicted once exceeded). Without a
  /// cap, keys that vary per request (e.g. deep [KeyPlugin] mode on
  /// paginated/search endpoints) accumulate forever, since an entry is only
  /// otherwise removed when its *exact* key is requested again after expiry.
  /// Set to `0` to disable the cap.
  final int maxEntries;

  final bool Function(RequestOptions) _shouldCache;
  final DateTime Function() _now;
  final _store = <String, _Entry>{};

  static const _kCacheKey = 'dioman:cache:key';
  static const _kCacheTtl = 'dioman:cache:ttl';
  static const _kCacheClone = 'dioman:cache:clone';

  static bool _defaultShouldCache(RequestOptions o) =>
      o.method.toUpperCase() == 'GET';

  @override
  String get name => 'cache';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final cacheOpt = _resolve(options);
    if (cacheOpt == null) return handler.next(options);

    final key = options.extra[kRequestKey] as String?;
    if (key == null) return handler.next(options); // no key → no cache

    final entry = _store[key];
    if (entry != null) {
      if (entry.expiresAt > _now().millisecondsSinceEpoch) {
        // Fresh hit — move to the end so eviction is true LRU (most-recently
        // *used*, not merely most-recently-written); otherwise a hot but old
        // entry would be evicted ahead of a colder, newer one.
        _store.remove(key);
        _store[key] = entry;
        return handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            data: _applyClone(entry.data, cacheOpt.clone),
            statusCode: 200,
            statusMessage: 'OK (cached)',
          ),
        );
      }
      _store.remove(key); // expired
    }

    // Mark for writing on response.
    options.extra[_kCacheKey] = key;
    options.extra[_kCacheTtl] = cacheOpt.expires;
    options.extra[_kCacheClone] = cacheOpt.clone;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    final key = opts.extra[_kCacheKey] as String?;
    if (key != null &&
        (response.statusCode ?? 0) >= 200 &&
        (response.statusCode ?? 0) < 300) {
      final ttl = opts.extra[_kCacheTtl] as int? ?? expires;
      // Remove-then-reinsert moves this key to the end of iteration order
      // (Dart's default Map is insertion-ordered), so eviction below always
      // drops the least-recently-written entry first.
      _store.remove(key);
      _store[key] = _Entry(
        response.data,
        _now().millisecondsSinceEpoch + ttl,
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

  void remove(String key) => _store.remove(key);

  void removeWhere(bool Function(String key) test) =>
      _store.removeWhere((k, _) => test(k));

  void clear() => _store.clear();
  int get size => _store.length;

  // ── Helpers ───────────────────────────────────────────────────────────────

  ({int expires, CacheClone clone})? _resolve(RequestOptions opts) {
    if (!_shouldCache(opts)) return null;
    final v = opts.extra[CachePlugin.configProperty];
    if (v == false) return null;
    if (v == true || v == null) return (expires: expires, clone: clone);
    if (v is Map) {
      return (
        expires: (v['expires'] as int?) ?? expires,
        clone: (v['clone'] as CacheClone?) ?? clone,
      );
    }
    return null;
  }

  static dynamic _applyClone(dynamic data, CacheClone strategy) {
    switch (strategy) {
      case CacheClone.none:
        return data;
      case CacheClone.shallow:
        // Preserve the concrete generic type — a JSON body is
        // Map<String, dynamic> / List<dynamic>, and downcasting it to
        // dynamic keys here would break a typed `dio.get<Map<String, dynamic>>`.
        if (data is Map<String, dynamic>) return Map<String, dynamic>.of(data);
        if (data is Map) return Map.of(data);
        if (data is List) return List.of(data);
        return data;
      case CacheClone.deep:
        return _deepCopy(data);
    }
  }

  static dynamic _deepCopy(dynamic v) {
    if (v is Map<String, dynamic>) {
      return <String, dynamic>{for (final e in v.entries) e.key: _deepCopy(e.value)};
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
