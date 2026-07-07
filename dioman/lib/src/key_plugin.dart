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

  /// Merged (union, not replaced) with the plugin's default `ignoreKeys`
  /// for this request only. Applies to both query params and body map keys.
  ///
  /// 仅本次请求，跟插件默认的`ignoreKeys`做合并（union，不是替换）。同时
  /// 作用于query参数和body字段。
  final List<String>? ignores;

  /// Overrides the plugin's `builder` for this request only. Takes priority
  /// over [key]/[fastMode]/deep-key computation when set.
  ///
  /// 仅本次请求覆盖插件的`builder`。设置后优先级高于[key]/[fastMode]/deep模式计算。
  final String Function(RequestOptions)? builder;
}

/// Generates a unique key for each request and stores it in
/// `options.extra[kRequestKey]`. Cache and share plugins depend on this key.
///
/// 为每个请求生成唯一key，存入`options.extra[kRequestKey]`。cache和share插件
/// 依赖这个key。
///
/// Two modes:
/// - **fast** (`fastMode: true`): `METHOD:url` — cheapest, good for most cases.
/// - **deep** (default): `METHOD:url:params:data` — serialises query params and
///   request body into the key. Use when the same URL is called with different
///   payloads and you want them cached/deduped independently.
///
/// 两种模式：
/// - **fast**（`fastMode: true`）：`METHOD:url`——最省事，多数场景够用。
/// - **deep**（默认）：`METHOD:url:params:data`——把query参数和body都序列化进key。
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
///   ..add(DiomanCache())
///   ..add(DiomanShare());
///
/// // Override per request:
/// dio.get('/list', options: Options(extra: {'dioman:qid': const DiomanKeyOptions(key: 'product-list')}));
/// dio.get('/list', options: Options(extra: {'dioman:qid': const DiomanKeyOptions(enabled: false)})); // skip
/// ```
class DiomanKey extends DiomanPlugin {
  const DiomanKey({
    this.fastMode = false,
    this.ignores = const [],
    this.enabled = true,
    this.builder,
  });

  /// If true, use only `METHOD:url` as the key (fastest).
  ///
  /// 为true时只用`METHOD:url`当key（最快）。
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

  static const _name = 'dioman:qid';

  @override
  String get name => _name;

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

  String _fastKey(RequestOptions o) =>
      '${o.method.toUpperCase()}:${o.uri.path}';

  String _deepKey(RequestOptions o, List<String> ignoreKeys) {
    final buf = StringBuffer(_fastKey(o));

    // Query params.
    final params = Map<String, dynamic>.from(o.queryParameters)
      ..removeWhere((k, _) => ignoreKeys.contains(k));
    if (params.isNotEmpty) buf.write(':${_encode(params)}');

    // Body.
    final data = o.data;
    if (data is Map) {
      final filtered = Map<String, dynamic>.from(data)
        ..removeWhere((k, _) => ignoreKeys.contains(k));
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
