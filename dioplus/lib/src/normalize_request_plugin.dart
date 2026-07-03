import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// Filters "empty" fields from `queryParameters` and `data` (Map) before the
/// request is sent, preventing meaningless keys from polluting server logs,
/// cache keys, or request signatures.
///
/// **Default predicate**: drops `null`, empty string `''` (after trim).
/// Provide a custom [predicate] to change what "empty" means.
///
/// Per-request opt-out: `options.extra['filter'] = false`.
/// Per-request options: `options.extra['filter'] = {'ignoreKeys': ['page']}`.
///
/// ```dart
/// dio.interceptors.add(NormalizeRequestPlugin(
///   ignoreKeys: ['timestamp'],   // keep even if null/empty
///   ignoreValues: [0, false],    // keep these specific values
/// ));
/// ```
class NormalizeRequestPlugin extends DioPlugin {
  const NormalizeRequestPlugin({
    bool Function(String key, dynamic value)? predicate,
    this.ignoreKeys = const [],
    this.ignoreValues = const [],
  }) : _predicate = predicate;

  /// Returns true to **drop** a field. Defaults to null / empty string.
  final bool Function(String key, dynamic value)? _predicate;

  /// Keys never dropped regardless of their value.
  final List<String> ignoreKeys;

  /// Values never dropped regardless of their key.
  final List<dynamic> ignoreValues;

  @override
  String get name => 'normalize-request';

  static bool _defaultPredicate(String key, dynamic value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
    return false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final filter = options.extra['filter'];
    if (filter == false) return handler.next(options);

    // Resolve per-request overrides.
    List<String> keys = ignoreKeys;
    List<dynamic> vals = ignoreValues;
    bool Function(String, dynamic) pred = _predicate ?? _defaultPredicate;

    if (filter is Map) {
      if (filter['ignoreKeys'] is List) keys = List<String>.from(filter['ignoreKeys'] as List);
      if (filter['ignoreValues'] is List) vals = List<dynamic>.from(filter['ignoreValues'] as List);
    }

    // Filter queryParameters.
    options.queryParameters.removeWhere(
      (k, v) => !keys.contains(k) && !vals.contains(v) && pred(k, v),
    );

    // Filter data map.
    final data = options.data;
    if (data is Map) {
      data.removeWhere(
        (k, v) =>
            !keys.contains('$k') && !vals.contains(v) && pred('$k', v),
      );
    }

    handler.next(options);
  }
}
