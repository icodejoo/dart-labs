import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Per-request override for [DiomanRepath], read from `extra['dioman:repath']`.
///
/// [DiomanRepath]的单请求覆盖，从`extra['dioman:repath']`读取。
class DiomanRepathOptions {
  const DiomanRepathOptions({this.enabled, this.removeKey, this.pattern});

  /// `false` skips path substitution for this request. `null` (default)
  /// inherits [DiomanRepath.enabled].
  ///
  /// `false`表示本次请求跳过路径替换。`null`（默认）沿用[DiomanRepath.enabled]。
  final bool? enabled;

  /// Overrides the plugin's default `removeKey` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`removeKey`。
  final bool? removeKey;

  /// Overrides the plugin's default `pattern` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`pattern`。
  final RegExp? pattern;
}

/// Substitutes named path variables in the URL before the request is sent.
///
/// 发送前替换URL里的命名路径变量。
///
/// Variable syntax — any of these work out of the box:
/// - `{id}`   — curly braces
/// - `:id`    — colon (Express style)
/// - `[id]`   — square brackets
///
/// 变量语法——以下写法都直接支持：
/// - `{id}`——花括号
/// - `:id`——冒号（Express风格）
/// - `[id]`——方括号
///
/// Values are resolved from `queryParameters` first, then from `data` (if a
/// Map). When [removeKey] is `true` (default), the key is deleted from the
/// source map after substitution so it is not sent as a query param / body
/// field as well.
///
/// 先从`queryParameters`取值，取不到再从`data`（若为Map）取。[removeKey]为
/// `true`（默认）时，替换后会把该键从源map删除，避免又被当成query参数/body
/// 字段发出去。
///
/// Per-request opt-out: `options.extra['dioman:repath'] = const DiomanRepathOptions(enabled: false)`.
///
/// ```dart
/// dio.interceptors.add(DiomanRepath());
///
/// dio.get(
///   '/user/{id}/posts/:postId',
///   queryParameters: {'id': '42', 'postId': '7', 'page': 1},
/// );
/// // → GET /user/42/posts/7?page=1
/// ```
class DiomanRepath extends DiomanPlugin {
  DiomanRepath({
    this.removeKey = true,
    this.enabled = true,
    RegExp? pattern,
  }) : pattern = pattern ??
            RegExp(r'\{([^}]+)\}|\[([^\]]+)]|:([^/?#\s]+)');

  /// When true, removes the substituted key from the source map.
  /// Overridable per request via [DiomanRepathOptions.removeKey].
  ///
  /// 为true时，替换后从源map里移除该键。可通过[DiomanRepathOptions.removeKey]
  /// 按请求覆盖。
  final bool removeKey;

  /// `false` disables the plugin entirely — every path is left untouched.
  ///
  /// `false`时插件整体失效——所有路径原样不动。
  final bool enabled;

  /// Variable-matching pattern. Capture group 1, 2, or 3 holds the name.
  /// Overridable per request via [DiomanRepathOptions.pattern].
  ///
  /// 变量匹配的正则，捕获组1、2或3存放变量名。可通过
  /// [DiomanRepathOptions.pattern]按请求覆盖。
  final RegExp pattern;

  static const _name = 'dioman:repath';

  @override
  String get name => _name;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra[name];
    final o = override is DiomanRepathOptions ? override : null;

    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(options);

    final $removeKey = o?.removeKey ?? removeKey;
    final $pattern = o?.pattern ?? pattern;

    options.path = options.path.replaceAllMapped($pattern, (m) {
      final key = m.group(1) ?? m.group(2) ?? m.group(3);
      if (key == null) return m.group(0)!;

      // 1. Try queryParameters.
      if (options.queryParameters.containsKey(key)) {
        final v = options.queryParameters[key];
        if ($removeKey) options.queryParameters.remove(key);
        return '$v';
      }

      // 2. Fall back to data map.
      final data = options.data;
      if (data is Map && data.containsKey(key)) {
        final v = data[key];
        if ($removeKey) data.remove(key);
        return '$v';
      }

      return m.group(0)!; // no match — leave placeholder as-is
    });

    handler.next(options);
  }
}
