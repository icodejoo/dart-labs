import 'dart:convert';
import 'package:dio/dio.dart';

/// 客户端和请求级的构键配置；空字段继承客户端值。
class DiomanKeyOptions {
  /// 创建配置，例如 `DiomanKeyOptions(fastMode: true)`。
  const DiomanKeyOptions(
      {this.fastMode, this.ignores, this.builder, this.namespace, this.key});

  /// 快速模式只编码方法和路径。
  final bool? fastMode;

  /// 与客户端取并集的忽略字段。
  final List<String>? ignores;

  /// 自定义构键器；抛错按程序异常处理。
  final String Function(RequestOptions)? builder;

  /// 客户端账号作用域，不应返回敏感令牌。
  final String? Function()? namespace;

  /// 请求级显式键；空串沿用自动计算。
  final String? key;
}

/// 与旧版算法独立共存的构键服务。
class DiomanKeyService {
  /// 创建服务，例如 `DiomanKeyService(const DiomanKeyOptions())`。
  const DiomanKeyService(this.options);

  /// 客户端构键配置。
  final DiomanKeyOptions options;

  /// 按请求 builder、请求 key、客户端 builder、计算的次序返回键；false 返回 null。
  String? build(RequestOptions request, [Object? override]) {
    if (override == false) return null;
    if (override != null &&
        override is! String &&
        override is! DiomanKeyOptions) {
      throw ArgumentError.value(override, 'key');
    }
    final o = override is DiomanKeyOptions ? override : null;
    final scope = options.namespace?.call();
    final explicit = override is String ? override : o?.key;
    if (o?.builder != null) return _scopedKey(o!.builder!(request), scope);
    if (explicit != null && explicit.isNotEmpty) {
      return _scopedKey(explicit, scope);
    }
    if (options.builder != null) {
      return _scopedKey(options.builder!(request), scope);
    }
    final ignores = _merge(options.ignores ?? const [], o?.ignores);
    return (o?.fastMode ?? options.fastMode ?? false)
        ? _scopedKey(_fastKey(request), scope)
        : _deepKey(request, ignores, scope);
  }

  /// 为快速键或自定义键增加独立作用域字段，空作用域保持原键。
  static String _scopedKey(String key, String? scope) =>
      scope == null || scope.isEmpty ? key : jsonEncode([key, scope]);

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
  String _deepKey(RequestOptions o, List<String> ignoreKeys, String? scope) {
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
    return jsonEncode([
      _fastKey(o),
      _encode(params),
      body,
      if (scope != null && scope.isNotEmpty) scope,
    ]);
  }

  /// 递归排序Map字段并保留List顺序后编码，无法序列化时保留原Map的字符串表示。
  static String _encode(Map v) {
    try {
      return jsonEncode(_normalize(v));
    } catch (_) {
      return v.toString();
    }
  }

  /// 返回递归规范化的副本：Map键按字符串比较排序，List保序，其他值原样保留。
  static Object? _normalize(Object? v) {
    if (v is Map) {
      final entries = v.entries.toList()
        ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
      return Map.fromEntries(
        entries.map((e) => MapEntry(e.key, _normalize(e.value))),
      );
    }
    if (v is List) return v.map(_normalize).toList();
    return v;
  }
}
