import 'package:dio/dio.dart';

/// 以请求覆盖值 [override] 替换 [base]，适合没有字段合并的标量选项。
/// 例如 `resolveOption<int>(2, base: 1, merge: replaceOption)` 返回 2。
T replaceOption<T>(T base, T override) => override;

/// 插件请求级选项键；按对象身份隔离，建议使用静态 final 实例。
class DiomanOptionKey<T> {
  /// [description] 仅供调试，例如 `DiomanOptionKey<int>('retry')`。
  DiomanOptionKey(this.description);

  /// 调试说明。
  final String description;
}

/// 解析统一选项；省略/true 复用 [base]，false 关闭；[optIn] 控制省略时关闭。
/// [merge] 合并类型化覆盖，[shorthand] 返回简写解析值；未知类型抛 ArgumentError。
/// 示例：`resolveOption<int>(true, base: 3, merge: (a, b) => b)`。
T? resolveOption<T>(Object? value,
    {required T base,
    required T Function(T base, T override) merge,
    T? Function(Object value)? shorthand,
    bool optIn = false}) {
  if (value == false || (value == null && optIn)) return null;
  if (value == null || value == true) return base;
  if (value is T) return merge(base, value as T);
  final short = shorthand?.call(value);
  if (short != null) return merge(base, short);
  throw ArgumentError.value(value, 'value', '不支持的插件选项');
}

/// 一次逻辑调用的配置；省略字段沿用 Dio 或客户端配置。
class DiomanCall {
  /// 创建调用配置，例如 `DiomanCall(key: false, envelope: false)`。
  const DiomanCall(
      {this.headers,
      this.connectTimeout,
      this.sendTimeout,
      this.receiveTimeout,
      this.cancelToken,
      this.key,
      this.envelope,
      this.silent = false,
      this.options = const {}});

  /// 按不区分大小写的键覆盖请求头。
  final Map<String, dynamic>? headers;

  /// 连接超时。
  final Duration? connectTimeout;

  /// 发送超时。
  final Duration? sendTimeout;

  /// 接收超时。
  final Duration? receiveTimeout;

  /// 用户取消令牌。
  final CancelToken? cancelToken;

  /// String、false 或 DiomanKeyOptions；null 为自动计算。
  final Object? key;

  /// false 禁用本次信封识别。
  final bool? envelope;

  /// 是否静默通知。
  final bool silent;

  /// 插件的类型化请求级选项。
  final Map<DiomanOptionKey, Object?> options;
}
