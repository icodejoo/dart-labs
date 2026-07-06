import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// Substitutes named path variables in the URL before the request is sent.
///
/// Variable syntax — any of these work out of the box:
/// - `{id}`   — curly braces
/// - `:id`    — colon (Express style)
/// - `[id]`   — square brackets
///
/// Values are resolved from `queryParameters` first, then from `data` (if a
/// Map). When [removeKey] is `true` (default), the key is deleted from the
/// source map after substitution so it is not sent as a query param / body
/// field as well.
///
/// Per-request opt-out: `options.extra[RepathPlugin.configProperty] = false`.
///
/// ```dart
/// dio.interceptors.add(RepathPlugin());
///
/// dio.get(
///   '/user/{id}/posts/:postId',
///   queryParameters: {'id': '42', 'postId': '7', 'page': 1},
/// );
/// // → GET /user/42/posts/7?page=1
/// ```
class RepathPlugin extends DioPlugin {
  /// The `extra` key callers use to opt a single request out of path
  /// substitution. Change this to remap it.
  static String configProperty = 'dioman:repath';

  RepathPlugin({
    this.removeKey = true,
    RegExp? pattern,
  }) : pattern = pattern ??
            RegExp(r'\{([^}]+)\}|\[([^\]]+)]|:([^/?#\s]+)');

  /// When true, removes the substituted key from the source map.
  final bool removeKey;

  /// Variable-matching pattern. Capture group 1, 2, or 3 holds the name.
  final RegExp pattern;

  @override
  String get name => 'repath';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[RepathPlugin.configProperty] == false) return handler.next(options);

    options.path = options.path.replaceAllMapped(pattern, (m) {
      final key = m.group(1) ?? m.group(2) ?? m.group(3);
      if (key == null) return m.group(0)!;

      // 1. Try queryParameters.
      if (options.queryParameters.containsKey(key)) {
        final v = options.queryParameters[key];
        if (removeKey) options.queryParameters.remove(key);
        return '$v';
      }

      // 2. Fall back to data map.
      final data = options.data;
      if (data is Map && data.containsKey(key)) {
        final v = data[key];
        if (removeKey) data.remove(key);
        return '$v';
      }

      return m.group(0)!; // no match — leave placeholder as-is
    });

    handler.next(options);
  }
}
