// ignore_for_file: prefer_initializing_formals
import 'package:dio/dio.dart';
import 'build_key_plugin.dart';
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
/// **Depends on [BuildKeyPlugin]** for the request key. Install that first.
///
/// Per-request control via `options.extra['cache']`:
/// - `false` → skip cache for this request
/// - `true`  → enable with plugin defaults
/// - `{expires: int, clone: CacheClone}` → custom per-request settings
///
/// ```dart
/// dio.interceptors
///   ..add(BuildKeyPlugin())
///   ..add(CachePlugin(expires: 30000)); // 30 s
///
/// // Per-request:
/// dio.get('/list', options: Options(extra: {
///   'cache': {'expires': 5000, 'clone': CacheClone.shallow},
/// }));
/// ```
class CachePlugin extends DioPlugin {
  CachePlugin({
    this.expires = 60000, // milliseconds
    this.clone = CacheClone.none,
    bool Function(RequestOptions)? shouldCache,
  })  : _shouldCache = shouldCache ?? _defaultShouldCache;

  /// Default TTL in **milliseconds**.
  final int expires;

  /// Default clone strategy.
  final CacheClone clone;

  final bool Function(RequestOptions) _shouldCache;
  final _store = <String, _Entry>{};

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
      if (entry.expiresAt > DateTime.now().millisecondsSinceEpoch) {
        // Fresh hit.
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
    options.extra['_cache_key'] = key;
    options.extra['_cache_ttl'] = cacheOpt.expires;
    options.extra['_cache_clone'] = cacheOpt.clone;
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final opts = response.requestOptions;
    final key = opts.extra['_cache_key'] as String?;
    if (key != null &&
        (response.statusCode ?? 0) >= 200 &&
        (response.statusCode ?? 0) < 300) {
      final ttl = opts.extra['_cache_ttl'] as int? ?? expires;
      _store[key] = _Entry(
        response.data,
        DateTime.now().millisecondsSinceEpoch + ttl,
      );
    }
    handler.next(response);
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
    final v = opts.extra['cache'];
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
        if (data is Map) return Map<dynamic, dynamic>.from(data);
        if (data is List) return List<dynamic>.from(data);
        return data;
      case CacheClone.deep:
        return _deepCopy(data);
    }
  }

  static dynamic _deepCopy(dynamic v) {
    if (v is Map) return Map.fromEntries(v.entries.map((e) => MapEntry(e.key, _deepCopy(e.value))));
    if (v is List) return v.map(_deepCopy).toList();
    return v;
  }

  @override
  void dispose() => _store.clear();
}
