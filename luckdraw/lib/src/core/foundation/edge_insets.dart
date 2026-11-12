import 'package:flutter/foundation.dart';

/// 逻辑像素内边距，简写采用 CSS 的上、右、下、左顺序。
///
/// 例如 `LuckyEdgeInsets.css([8, 12])` 表示上下 8、左右 12。
@immutable
final class LuckyEdgeInsets {
  /// 分别指定四边内边距，未指定的边为零。
  const LuckyEdgeInsets.only({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });

  /// 将四边内边距设为 [value]。
  const LuckyEdgeInsets.all(double value)
      : top = value,
        right = value,
        bottom = value,
        left = value;

  /// 分别设置上下 [vertical] 与左右 [horizontal] 的内边距。
  const LuckyEdgeInsets.symmetric({double vertical = 0, double horizontal = 0})
      : top = vertical,
        bottom = vertical,
        left = horizontal,
        right = horizontal;

  /// 从 1–4 个 [values] 解析 CSS 简写，其它长度抛出 [ArgumentError]。
  ///
  /// 三值为上、左右、下，四值为上、右、下、左。
  factory LuckyEdgeInsets.css(List<double> values) => switch (values) {
        [final all] => LuckyEdgeInsets.all(all),
        [final vertical, final horizontal] =>
          LuckyEdgeInsets.symmetric(vertical: vertical, horizontal: horizontal),
        [final top, final horizontal, final bottom] => LuckyEdgeInsets.only(
            top: top, right: horizontal, bottom: bottom, left: horizontal),
        [final top, final right, final bottom, final left] =>
          LuckyEdgeInsets.only(
              top: top, right: right, bottom: bottom, left: left),
        _ => throw ArgumentError.value(values, 'values', '需要 1–4 个 CSS 内边距值'),
      };

  /// 四边为零的内边距。
  static const LuckyEdgeInsets zero = LuckyEdgeInsets.all(0);

  /// 上边距。
  final double top;

  /// 右边距。
  final double right;

  /// 下边距。
  final double bottom;

  /// 左边距。
  final double left;

  /// 返回替换指定边距的副本；参数为 null 时保留原值。
  LuckyEdgeInsets copyWith(
          {double? top, double? right, double? bottom, double? left}) =>
      LuckyEdgeInsets.only(
          top: top ?? this.top,
          right: right ?? this.right,
          bottom: bottom ?? this.bottom,
          left: left ?? this.left);

  /// 比较四边的内边距。
  @override
  bool operator ==(Object other) =>
      other is LuckyEdgeInsets &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  /// 与四边内边距相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}
