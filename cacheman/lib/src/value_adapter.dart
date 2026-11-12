/// Business value ↔ JSON-compatible data, independent of envelope codecs.
/// 业务值 ↔ JSON 兼容数据的转换，与信封 codec 独立。
/// Example / 示例：`final names = ValueAdapter.listOf<String>();`.
class ValueAdapter<T> {
  /// Conversion failures use SerializeError on write / TypeMismatchError on read.
  /// 转换失败在写入时为 SerializeError，读取时为 TypeMismatchError。
  /// Example / 示例：
  /// ```dart
  /// ValueAdapter<User>(toJson: (u) => u.toJson(),
  ///   fromJson: (j) => User.fromJson(j as Map<String, dynamic>));
  /// ```
  const ValueAdapter({required this.toJson, required this.fromJson});

  /// Converts to JSON-compatible data. / 转换成 JSON 兼容数据。
  final Object? Function(T value) toJson;

  /// Reconstructs a typed value; may throw on invalid data.
  /// 重建类型化的值；无效数据可抛异常。
  final T Function(Object? json) fromJson;

  /// Copies a JSON list, eagerly checking every element as E.
  /// 复制 JSON 列表，立即检查每个元素是否为 E。
  /// Example / 示例：`ValueAdapter.listOf<String>()`.
  static ValueAdapter<List<E>> listOf<E>() => ValueAdapter(
        toJson: (value) => value,
        fromJson: (json) => List<E>.from(json as List),
      );

  /// Copies a JSON map, eagerly checking String keys and V values.
  /// 复制 JSON 映射，立即检查 String 键及 V 值。
  /// Example / 示例：`ValueAdapter.mapOf<int>()`.
  static ValueAdapter<Map<String, V>> mapOf<V>() => ValueAdapter(
        toJson: (value) => value,
        fromJson: (json) => Map<String, V>.from(json as Map),
      );
}
