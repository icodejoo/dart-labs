import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Shared helpers and mixins for the countman per-widget `*Style` classes.
///
/// countman 各组件 `*Style` 类共用的 helper 与 mixin。

/// Value-equality mixin for the immutable `*Style` classes.
///
/// A class mixes this in and implements [props] — the ordered list of its
/// fields. [operator ==] and [hashCode] are then derived from that list,
/// removing the per-class boilerplate each `*Style` used to hand-write.
///
/// 不可变 `*Style` 类的值相等性 mixin。
///
/// 类混入本 mixin 并实现 [props]（其字段的有序列表），[operator ==] 与
/// [hashCode] 即由该列表派生，省去每个 `*Style` 过去手写的样板。
mixin StyleProps {
  /// The ordered field values backing [operator ==] and [hashCode].
  ///
  /// Two instances are equal iff same runtime type and element-wise-equal props.
  ///
  /// 支撑 [operator ==] 与 [hashCode] 的有序字段值列表。
  ///
  /// 两实例相等当且仅当运行时类型相同且 props 逐元素相等。
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other.runtimeType == runtimeType &&
          other is StyleProps &&
          listEquals(other.props, props));

  @override
  int get hashCode => Object.hashAll(props);
}

/// Wraps [child] with optional [padding] then [decoration].
///
/// The decoration is applied OUTSIDE the padding so the background/border
/// covers the padded area (the conventional `Container` order). Returns
/// [child] unchanged when both are null — zero overhead for the common case.
///
/// 用可选的 [padding] 再 [decoration] 包裹 [child]。
///
/// decoration 包在 padding 外层，使背景/边框覆盖内边距区域（与 `Container` 的
/// 常规顺序一致）。当两者都为空时原样返回 [child]——常见情形零开销。
///
/// @param child The widget to wrap.
///
///   要包裹的 widget。
///
/// @param padding Optional inner padding.
///
///   可选的内边距。
///
/// @param decoration Optional box decoration (background, border, radius,
///   gradient, shadow — any Flutter [Decoration]).
///
///   可选的盒装饰（背景、边框、圆角、渐变、阴影——任意 Flutter [Decoration]）。
///
/// @returns The wrapped widget, or [child] itself when nothing to apply.
///
///   包裹后的 widget；无可应用项时返回 [child] 本身。
Widget applyBoxStyle(
  Widget child, {
  EdgeInsetsGeometry? padding,
  Decoration? decoration,
}) {
  Widget w = child;
  if (padding != null) w = Padding(padding: padding, child: w);
  if (decoration != null) w = DecoratedBox(decoration: decoration, child: w);
  return w;
}

/// Field contract for the container-decoration layer every `*Style` carries:
/// [padding] + [decoration]. Applied via [applyBoxStyle].
///
/// 每个 `*Style` 都携带的容器装饰层字段契约：[padding] + [decoration]。
/// 通过 [applyBoxStyle] 应用。
mixin BoxStyleFields {
  /// Inner padding around the widget's content.
  ///
  /// widget 内容周围的内边距。
  EdgeInsetsGeometry? get padding;

  /// Box decoration (background/border/radius/gradient/shadow).
  ///
  /// 盒装饰（背景/边框/圆角/渐变/阴影）。
  Decoration? get decoration;
}

/// Field contract for the textual layer shared by text-like counters:
/// the number [textStyle] plus optional [prefixStyle] / [suffixStyle].
///
/// 文本类计数器共用的文字层字段契约：数字 [textStyle] 以及可选的
/// [prefixStyle] / [suffixStyle]。
mixin TextualStyleFields {
  /// Text style for the number itself.
  ///
  /// 数字本身的文本样式。
  TextStyle? get textStyle;

  /// Text style for the prefix string (falls back to [textStyle]).
  ///
  /// 前缀字符串的文本样式（回退到 [textStyle]）。
  TextStyle? get prefixStyle;

  /// Text style for the suffix string (falls back to [textStyle]).
  ///
  /// 后缀字符串的文本样式（回退到 [textStyle]）。
  TextStyle? get suffixStyle;
}
