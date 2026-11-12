import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 赔付线，每列填写相对中心行的偏移；例如 `const SlotPayline([0, 0, 0])`。
@immutable
final class SlotPayline {
  /// 创建线；列表长度应与列数一致。
  const SlotPayline(this.rowOffsets,
      {this.color = const Color(0xFFFFD700), this.width = 3});

  /// 每列行偏移，0 为中心，负数为前一行。
  final List<int> rowOffsets;

  /// 线颜色。
  final Color color;

  /// 线宽，逻辑像素。
  final double width;

  /// 返回仅替换非 null 参数的副本；例如 `value.copyWith()` 保留全部配置。
  SlotPayline copyWith({List<int>? rowOffsets, Color? color, double? width}) =>
      SlotPayline(rowOffsets ?? this.rowOffsets,
          color: color ?? this.color, width: width ?? this.width);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is SlotPayline &&
      listEquals(rowOffsets, other.rowOffsets) &&
      color == other.color &&
      width == other.width;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(Object.hashAll(rowOffsets), color, width);
}

/// 接收线上各列的奖品下标，返回是否中奖。
typedef SlotPaylinePredicate = bool Function(List<int> symbols);

/// 非空且全部为同一有效奖品时返回 true。
bool allEqualPaylinePredicate(List<int> symbols) =>
    symbols.isNotEmpty &&
    symbols.first >= 0 &&
    symbols.every((symbol) => symbol == symbols.first);
