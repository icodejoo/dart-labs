import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

/// 构键参数错误的统一名称。
const _diomanKeyArgument = 'key';

/// 客户端和请求级的构键配置；空字段继承客户端值。
class DiomanKeyOptions {
  /// 创建配置，例如 `DiomanKeyOptions(fastMode: true)`。
  const DiomanKeyOptions(
      {this.fastMode, this.ignores, this.builder, this.namespace, this.key});

  /// 快速模式编码方法、来源、路径与响应格式。
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
  /// 自动构键允许按内容哈希的最大字节数。
  static const maxBodyBytes = 64 * 1024;

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
      throw ArgumentError.value(override, _diomanKeyArgument);
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
        ? _scopedKey(
            jsonEncode([_fastKey(request), request.responseType.name]), scope)
        : _deepKey(request, ignores, scope);
  }

  /// 为快速键或自定义键增加独立作用域字段，空作用域保持原键。
  static String _scopedKey(String key, String? scope) =>
      scope == null || scope.isEmpty ? key : jsonEncode([key, scope]);

  /// 把[override]与[base]取并集合并；[override]为`null`时原样返回[base]。
  static List<String> _merge(List<String> base, List<String>? override) =>
      override == null ? base : {...base, ...override}.toList();

  /// 使用方法、来源和路径生成快速键。
  String _fastKey(RequestOptions o) =>
      '${o.method.toUpperCase()}:${o.uri.hasAuthority ? o.uri.origin : ''}${o.uri.path}';

  /// 分字段编码查询和安全请求体，不透明载荷不生成自动键。
  String? _deepKey(RequestOptions o, List<String> ignoreKeys, String? scope) {
    final uri = o.uri;
    final params = <String, dynamic>{
      for (final e in uri.queryParametersAll.entries)
        if (!ignoreKeys.contains(e.key))
          e.key: e.value.length == 1 ? e.value.single : e.value,
    };
    final data = o.data;
    Object? body;
    if (data is Map) {
      final filtered = <Object?, dynamic>{
        for (final e in data.entries)
          if (!ignoreKeys.contains('${e.key}')) e.key: e.value,
      };
      if (filtered.isNotEmpty) {
        final encoded = _encode(filtered);
        if (encoded == null) return null;
        body = {'map': encoded};
      }
    } else if (data is String) {
      if (data.isNotEmpty) body = {'string': data};
    } else if (data is Uint8List) {
      if (data.length > maxBodyBytes) return null;
      var hash = 0x811c9dc5;
      for (final byte in data) {
        hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
      }
      body = {
        'bytes': [data.length, hash, base64Encode(data)]
      };
    } else if (data is List) {
      final encoded = _encode(data);
      if (encoded == null) return null;
      body = {'list': encoded};
    } else if (data != null) {
      return null;
    }
    final query = _encode(params);
    return jsonEncode([
      _fastKey(o),
      query,
      body,
      o.responseType.name,
      if (scope != null && scope.isNotEmpty) scope,
    ]);
  }

  /// 递归排序 Map 字段并保留 List 顺序后编码，失败则禁用自动键。
  static String? _encode(Object v) {
    try {
      return jsonEncode(_normalize(v));
    } catch (_) {
      return null;
    }
  }

  /// 只接受可稳定编码的标量键，以类型标签隔离同形文字。
  static String _mapKey(Object? key) {
    if (key == null) return 'null:';
    if (key is String) return 'string:$key';
    if (key is num) return 'number:${jsonEncode(key)}';
    if (key is bool) return 'bool:$key';
    throw ArgumentError.value(key, _diomanKeyArgument, '不支持不透明 Map 键');
  }

  /// Map 键按带类型标签的编码排序，List 保序，其他值原样保留。
  static Object? _normalize(Object? v) {
    if (v is Map) {
      final entries = v.entries
          .map((e) => MapEntry(_mapKey(e.key), _normalize(e.value)))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return Map.fromEntries(entries);
    }
    if (v is List) return v.map(_normalize).toList();
    return v;
  }
}
