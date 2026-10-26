import 'dart:convert';
import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// The key in [RequestOptions.extra] where the computed key is stored.
/// Other plugins (cache, share) read from this slot. Fixed — not meant to be
/// reconfigured (it's the cross-plugin wire protocol between key, cache
/// and share, not a caller-facing option).
///
/// [RequestOptions.extra]中存放计算出的key的槽位。其它插件（cache、share）从
/// 这里读取。固定不可改——这是key/cache/share之间的跨插件协议，不是给调用方
/// 用的选项。
const kKey = 'dioman:key';

/// Per-request override for [DiomanKey], read from `extra['dioman:qid']`.
///
/// [DiomanKey]的单请求覆盖，从`extra['dioman:qid']`读取。
class DiomanKeyOptions {
  /// 创建单请求覆盖配置。
  const DiomanKeyOptions({
    this.enabled,
    this.key,
    this.fastMode,
    this.ignores,
    this.builder,
  });

  /// `false` skips key generation for this request. `null` (default)
  /// inherits [DiomanKey.enabled].
  ///
  /// `false`表示本次请求跳过key生成。`null`（默认）沿用[DiomanKey.enabled]。
  final bool? enabled;

  /// A specific key to use for this request instead of the computed one.
  ///
  /// 本次请求直接使用的指定key，替代自动计算出的key。
  final String? key;

  /// Overrides the plugin's default `fastMode` for this request only.
  ///
  /// 仅本次请求覆盖插件默认的`fastMode`。
  final bool? fastMode;

  /// Merged (union, not replaced) with the plugin's default `ignores`
  /// for this request only. Applies to both query params and body map keys.
  ///
  /// 仅本次请求，跟插件默认的`ignores`做合并（union，不是替换）。同时
  /// 作用于query参数和body字段。
  final List<String>? ignores;

  /// Overrides the plugin's `builder` for this request only. Takes priority
  /// over [key]/[fastMode]/deep-key computation when set.
  ///
  /// 仅本次请求覆盖插件的`builder`。设置后优先级高于[key]/[fastMode]/deep模式计算。
  final String Function(RequestOptions)? builder;
}

/// Generates a unique key for each request and stores it in
/// `options.extra[kKey]`. Cache and share plugins depend on this key.
///
/// 为每个请求生成唯一key，存入`options.extra[kKey]`。cache和share插件
/// 依赖这个key。
///
/// Two modes:
/// - **fast** (`fastMode: true`): `METHOD:origin/path` — cheapest, good for most cases.
/// - **deep** (default): `[METHOD:origin/path, query, body]` — serialises query params and
///   request body into the key. Use when the same URL is called with different
///   payloads and you want them cached/deduped independently.
///
/// 两种模式：
/// - **fast**（`fastMode: true`）：`METHOD:origin/path`——最省事，多数场景够用。
/// - **deep**（默认）：`[METHOD:origin/path, query, body]`——把query参数和body都序列化进key。
///   同一URL不同payload、想分别缓存/去重时用这个。
///
/// Per-request key override: `options.extra['dioman:qid'] =
/// const DiomanKeyOptions(key: 'my-key')`. Use `enabled: false` to skip key
/// generation for that request.
///
/// ```dart
/// // Install before cache and share:
/// dio.interceptors
///   ..add(DiomanKey())
///   ..add(DiomanCache(persist: yourCachePersist))
///   ..add(DiomanShare());
///
/// // Override per request:
/// dio.get('/list', options: Options(extra: {'dioman:qid': const DiomanKeyOptions(key: 'product-list')}));
/// dio.get('/list', options: Options(extra: {'dioman:qid': const DiomanKeyOptions(enabled: false)})); // skip
/// ```
class DiomanKey extends DiomanPlugin {
  /// 创建插件实例。
  const DiomanKey({
    this.fastMode = false,
    this.ignores = const [],
    this.enabled = true,
    this.builder,
  });

  /// If true, use only `METHOD:origin/path` as the key (fastest).
  ///
  /// 为true时只用`METHOD:origin/path`当key（最快）。
  final bool fastMode;

  /// Names excluded from the key — applies to both query params and body
  /// map keys.
  ///
  /// key计算时排除的名字——同时作用于query参数和body字段。
  final List<String> ignores;

  /// `false` disables the plugin entirely — no key is ever written.
  ///
  /// `false`时插件整体失效——永不写入key。
  final bool enabled;

  /// Custom key-builder function; when provided, takes priority over
  /// `fastMode`/deep-key computation. Overridable per request via
  /// [DiomanKeyOptions.builder].
  ///
  /// 自定义key构造函数；提供时优先级高于`fastMode`/deep模式计算。可通过
  /// [DiomanKeyOptions.builder]按请求覆盖。
  final String Function(RequestOptions)? builder;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:qid';

  /// 插件的公开协议名称。
  @override
  String get name => pluginName;

  /// 处理请求并完成当前请求出口。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Honour per-request override.
    final override = options.extra[name];
    final o = override is DiomanKeyOptions ? override : null;

    final $enabled = o?.enabled ?? enabled;
    if (!$enabled) return handler.next(options);

    if (o?.key != null && o!.key!.isNotEmpty) {
      options.extra[kKey] = o.key;
      return handler.next(options);
    }

    final $builder = o?.builder ?? builder;
    if ($builder != null) {
      options.extra[kKey] = $builder(options);
      return handler.next(options);
    }

    final $fastMode = o?.fastMode ?? fastMode;
    final $ignores = _merge(ignores, o?.ignores);

    options.extra[kKey] =
        $fastMode ? _fastKey(options) : _deepKey(options, $ignores);

    handler.next(options);
  }

  /// Merges [override] into [base] (union), or returns [base] unchanged when
  /// [override] is `null`.
  ///
  /// 把[override]与[base]取并集合并；[override]为`null`时原样返回[base]。
  static List<String> _merge(List<String> base, List<String>? override) =>
      override == null ? base : {...base, ...override}.toList();

  /// 使用方法、来源和路径生成快速键。
  String _fastKey(RequestOptions o) =>
      '${o.method.toUpperCase()}:${o.uri.hasAuthority ? o.uri.origin : ''}${o.uri.path}';

  /// 分字段编码规范化查询及请求体，保留非结构化对象的身份。
  String _deepKey(RequestOptions o, List<String> ignoreKeys) {
    final uri = o.uri;
    final params = <String, dynamic>{
      for (final e in uri.queryParametersAll.entries)
        if (!ignoreKeys.contains(e.key))
          e.key: e.value.length == 1 ? e.value.single : e.value,
    };
    final data = o.data;
    Object? body;
    if (data is Map) {
      final filtered = <String, dynamic>{
        for (final e in data.entries)
          if (!ignoreKeys.contains('${e.key}')) '${e.key}': e.value,
      };
      if (filtered.isNotEmpty) body = {'map': _encode(filtered)};
    } else if (data is String && data.isNotEmpty) {
      body = {'string': data};
    } else if (data != null) {
      body = {'identity': identityHashCode(data)};
    }
    return jsonEncode([_fastKey(o), _encode(params), body]);
  }

  /// 对字段排序后编码，无法序列化时保留字符串表示。
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
