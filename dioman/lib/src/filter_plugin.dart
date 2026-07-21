import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Per-request override for [DiomanFilter], read from `extra['dioman:filter']`.
///
/// [DiomanFilter]的单请求覆盖，从`extra['dioman:filter']`读取。
class DiomanFilterOptions {
  const DiomanFilterOptions({this.enabled, this.ignoreKeys, this.ignoreValues, this.predicate});

  /// `false` skips filtering for this request. `null` (default) inherits
  /// [DiomanFilter.enabled].
  ///
  /// `false`表示本次请求跳过过滤。`null`（默认）沿用[DiomanFilter.enabled]。
  final bool? enabled;

  /// Merged (union, not replaced) with the plugin's default `ignoreKeys`
  /// for this request only.
  ///
  /// 仅本次请求，跟插件默认的`ignoreKeys`做合并（union，不是替换）。
  final List<String>? ignoreKeys;

  /// Merged (union, not replaced) with the plugin's default `ignoreValues`
  /// for this request only.
  ///
  /// 仅本次请求，跟插件默认的`ignoreValues`做合并（union，不是替换）。
  final List<dynamic>? ignoreValues;

  /// Overrides the plugin's default `predicate` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`predicate`判定函数。
  final bool Function(String key, dynamic value)? predicate;
}

/// Filters "empty" fields from `queryParameters` and `data` (Map) before the
/// request is sent, preventing meaningless keys from polluting server logs,
/// cache keys, or request signatures.
///
/// 发送前从`queryParameters`和`data`（Map）中剔除"空"字段，避免无意义的键
/// 污染服务端日志、缓存key或请求签名。
///
/// **Default predicate**: drops `null`, empty string `''` (after trim).
/// Provide a custom [predicate] to change what "empty" means.
///
/// **默认判定**：剔除`null`、（trim后的）空字符串`''`。传自定义[predicate]
/// 可改变"空"的定义。
///
/// Per-request opt-out: `options.extra['dioman:filter'] = const DiomanFilterOptions(enabled: false)`.
/// Per-request options: `options.extra['dioman:filter'] = const DiomanFilterOptions(ignoreKeys: ['page'])`.
///
/// ```dart
/// dio.interceptors.add(DiomanFilter(
///   ignoreKeys: ['timestamp'],   // keep even if null/empty
///   ignoreValues: [0, false],    // keep these specific values
/// ));
/// ```
class DiomanFilter extends DiomanPlugin {
  const DiomanFilter({
    this.predicate,
    this.ignoreKeys = const [],
    this.ignoreValues = const [],
    this.enabled = true,
  });

  /// Returns true to **drop** a field. Defaults to null / empty string.
  /// Overridable per request via [DiomanFilterOptions.predicate].
  ///
  /// 返回true表示**剔除**该字段，默认剔除null/空字符串。可通过
  /// [DiomanFilterOptions.predicate]按请求覆盖。
  final bool Function(String key, dynamic value)? predicate;

  /// Keys never dropped regardless of their value.
  ///
  /// 不论值是什么都不剔除的键。
  final List<String> ignoreKeys;

  /// Values never dropped regardless of their key.
  ///
  /// 不论键是什么都不剔除的值。
  final List<dynamic> ignoreValues;

  /// `false` disables the plugin entirely — no field is ever dropped.
  ///
  /// `false`时插件整体失效——永不剔除任何字段。
  final bool enabled;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:filter';

  @override
  String get name => pluginName;

  static bool _defaultPredicate(String key, dynamic value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
    return false;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final override = options.extra[name];
    final o = override is DiomanFilterOptions ? override : null;
    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(options);

    // Merge (union), don't replace — a per-request ignoreKeys/ignoreValues
    // adds to the plugin's defaults rather than shadowing them.
    //
    // 合并（union），不替换——单请求的ignoreKeys/ignoreValues是叠加在插件
    // 默认值之上，而不是遮蔽它们。
    final $ignoreKeys = o?.ignoreKeys == null ? ignoreKeys : {...ignoreKeys, ...o!.ignoreKeys!}.toList();
    final $ignoreValues = o?.ignoreValues == null ? ignoreValues : {...ignoreValues, ...o!.ignoreValues!}.toList();
    final $predicate = o?.predicate ?? predicate ?? _defaultPredicate;

    // Filter queryParameters.
    options.queryParameters.removeWhere(
      (k, v) => !$ignoreKeys.contains(k) && !$ignoreValues.contains(v) && $predicate(k, v),
    );

    // Filter data map.
    final data = options.data;
    if (data is Map) {
      data.removeWhere(
        (k, v) =>
            !$ignoreKeys.contains('$k') && !$ignoreValues.contains(v) && $predicate('$k', v),
      );
    }

    handler.next(options);
  }
}
