import 'dart:convert';
import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// The key in [RequestOptions.extra] where the computed key is stored.
/// Other plugins (cache, share) read from this slot. Fixed — not meant to be
/// reconfigured (it's the cross-plugin wire protocol between key, cache
/// and share, not a caller-facing option).
const kRequestKey = 'dioman:key';

/// Generates a unique key for each request and stores it in
/// `options.extra[kRequestKey]`. Cache and share plugins depend on this key.
///
/// Two modes:
/// - **fast** (`fastMode: true`): `METHOD:url` — cheapest, good for most cases.
/// - **deep** (default): `METHOD:url:params:data` — serialises query params and
///   request body into the key. Use when the same URL is called with different
///   payloads and you want them cached/deduped independently.
///
/// Per-request key override: `options.extra[KeyPlugin.configProperty] =
/// 'my-key'`. Set to `false` to skip key generation for that request.
///
/// ```dart
/// // Install before cache and share:
/// dio.interceptors
///   ..add(KeyPlugin())
///   ..add(CachePlugin())
///   ..add(SharePlugin());
///
/// // Override per request:
/// dio.get('/list', options: Options(extra: {KeyPlugin.configProperty: 'product-list'}));
/// dio.get('/list', options: Options(extra: {KeyPlugin.configProperty: false})); // skip
/// ```
class KeyPlugin extends DioPlugin {
  /// The `extra` key callers use to override/skip key generation for a
  /// single request. Change this to remap it, e.g. if it collides with
  /// another package's `extra` usage.
  static String configProperty = 'dioman:qid';

  const KeyPlugin({
    this.fastMode = false,
    this.ignoreParams = const [],
    this.ignoreDataKeys = const [],
    String Function(RequestOptions)? builder,
  }) : _builder = builder;

  /// If true, use only `METHOD:url` as the key (fastest).
  final bool fastMode;

  /// Query parameter names excluded from the key.
  final List<String> ignoreParams;

  /// Data map keys excluded from the key.
  final List<String> ignoreDataKeys;

  final String Function(RequestOptions)? _builder;

  @override
  String get name => 'key';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Honour per-request override.
    final raw = options.extra[KeyPlugin.configProperty];
    if (raw == false) return handler.next(options); // explicit skip
    if (raw is String && raw.isNotEmpty) {
      options.extra[kRequestKey] = raw;
      return handler.next(options);
    }

    if (_builder != null) {
      options.extra[kRequestKey] = _builder(options);
      return handler.next(options);
    }

    options.extra[kRequestKey] = fastMode
        ? _fastKey(options)
        : _deepKey(options);

    handler.next(options);
  }

  String _fastKey(RequestOptions o) =>
      '${o.method.toUpperCase()}:${o.uri.path}';

  String _deepKey(RequestOptions o) {
    final buf = StringBuffer(_fastKey(o));

    // Query params.
    final params = Map<String, dynamic>.from(o.queryParameters)
      ..removeWhere((k, _) => ignoreParams.contains(k));
    if (params.isNotEmpty) buf.write(':${_encode(params)}');

    // Body.
    final data = o.data;
    if (data is Map) {
      final filtered = Map<String, dynamic>.from(data)
        ..removeWhere((k, _) => ignoreDataKeys.contains(k));
      if (filtered.isNotEmpty) buf.write(':${_encode(filtered)}');
    } else if (data is String && data.isNotEmpty) {
      buf.write(':$data');
    } else if (data != null) {
      // Non-serialisable body (FormData / bytes / stream, etc.): there's no
      // stable content representation, so fold in object identity. Two
      // distinct bodies then get distinct keys (never falsely deduped or
      // cached as one), while the SAME object reused across a retry keeps a
      // stable key.
      buf.write(':#${identityHashCode(data)}');
    }

    return buf.toString();
  }

  static String _encode(Object v) {
    try {
      // Sort keys for deterministic output.
      if (v is Map) {
        final sorted = Map.fromEntries(
          (v.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
        );
        return jsonEncode(sorted);
      }
      return jsonEncode(v);
    } catch (_) {
      return v.toString();
    }
  }
}
