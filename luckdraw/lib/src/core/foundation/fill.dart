import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'color_utils.dart';
import 'constants.dart';

/// 有效渐变所需的最少色标数量。
const int _minimumColorStops = 2;

/// 背景填充；只有 null 表示无背景，透明纯色仍表示有背景。
///
/// 例如 `const LuckyFill.color(Color(0xFFFF0000))` 表示红色背景。
@immutable
sealed class LuckyFill {
  /// 供填充子类调用的常量构造。
  const LuckyFill();

  /// 以 [color] 创建纯色背景。
  const factory LuckyFill.color(Color color) = LuckyColorFill;

  /// 以 Flutter [gradient] 创建随目标矩形变化的渐变背景。
  const factory LuckyFill.gradient(Gradient gradient) = LuckyGradientFill;

  /// 创建上游几何渐变；[stops] 至少两个，且调用方须保持列表不可变。
  const factory LuckyFill.legacyLinear(
    LuckyLegacyGradientDirection direction,
    List<LuckyColorStop> stops,
  ) = LuckyLegacyLinearFill;

  /// 把填充写入 [paint]；渐变使用 [rect]，纯色清除原 shader。
  void applyTo(Paint paint, Rect rect);

  /// 纯色透明度（0–255）；渐变返回 null，供阴影透明度合成使用。
  int? get solidAlpha8;
}

/// 纯色背景填充。
final class LuckyColorFill extends LuckyFill {
  /// 创建指定 [color] 的填充。
  const LuckyColorFill(this.color);

  /// 填充颜色，允许全透明。
  final Color color;

  /// 设置颜色并清除 [paint] 的 shader；[rect] 不影响纯色。
  @override
  void applyTo(Paint paint, Rect rect) => paint
    ..color = color
    ..shader = null;

  /// 返回填充颜色的八位透明度。
  @override
  int get solidAlpha8 => colorAlpha8(color);

  /// 返回替换 [color] 的副本；null 保留原值。
  LuckyColorFill copyWith({Color? color}) =>
      LuckyColorFill(color ?? this.color);

  /// 比较填充颜色。
  @override
  bool operator ==(Object other) =>
      other is LuckyColorFill && other.color == color;

  /// 与颜色相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(LuckyColorFill, color);
}

/// 按目标矩形创建 shader 的 Flutter 渐变填充。
final class LuckyGradientFill extends LuckyFill {
  /// 创建指定 [gradient] 的填充。
  const LuckyGradientFill(this.gradient);

  /// Flutter 原生渐变配置。
  final Gradient gradient;

  /// 按 [rect] 设置 [paint] 的 shader，并将基色设为不透明黑色。
  @override
  void applyTo(Paint paint, Rect rect) => paint
    ..color = kLuckyDefaultFontColor
    ..shader = gradient.createShader(rect);

  /// 渐变没有单一透明度，返回 null。
  @override
  int? get solidAlpha8 => null;

  /// 返回替换 [gradient] 的副本；null 保留原值。
  LuckyGradientFill copyWith({Gradient? gradient}) =>
      LuckyGradientFill(gradient ?? this.gradient);

  /// 比较 Flutter 渐变配置。
  @override
  bool operator ==(Object other) =>
      other is LuckyGradientFill && other.gradient == gradient;

  /// 与渐变配置相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(LuckyGradientFill, gradient);
}

/// 复刻上游八扇区端点几何的线性渐变填充。
final class LuckyLegacyLinearFill extends LuckyFill {
  /// 创建渐变；[stops] 至少两个，列表须由调用方保持不可变。
  const LuckyLegacyLinearFill(this.direction, this.stops);

  /// 渐变方向。
  final LuckyLegacyGradientDirection direction;

  /// 色标；省略位置时两个取 0、1，多个按下标均分。
  final List<LuckyColorStop> stops;

  /// 按 [rect] 设置 [paint]；色标少于两个时抛出 [ArgumentError]。
  @override
  void applyTo(Paint paint, Rect rect) {
    if (stops.length < _minimumColorStops) {
      throw ArgumentError.value(stops, 'stops', '渐变至少需要两个色标');
    }
    final (p0, p1) = direction.endpoints(rect);
    if (p0 == p1) {
      // 上游 Canvas 对重合端点不绘制，包括端点向零截断后的退化情形。
      paint
        ..color = const Color(0x00000000)
        ..shader = null;
      return;
    }
    paint
      ..color = kLuckyDefaultFontColor
      ..shader = ui.Gradient.linear(
          p0, p1, [for (final stop in stops) stop.color], _offsets());
  }

  /// 返回显式位置或按色标下标均分的位置。
  List<double> _offsets() => [
        for (var index = 0; index < stops.length; index++)
          stops[index].offset ?? index / (stops.length - 1),
      ];

  /// 渐变没有单一透明度，返回 null。
  @override
  int? get solidAlpha8 => null;

  /// 返回替换指定字段的副本；null 保留原值，列表须保持不可变。
  LuckyLegacyLinearFill copyWith(
          {LuckyLegacyGradientDirection? direction,
          List<LuckyColorStop>? stops}) =>
      LuckyLegacyLinearFill(direction ?? this.direction, stops ?? this.stops);

  /// 按方向和色标内容比较填充。
  @override
  bool operator ==(Object other) =>
      other is LuckyLegacyLinearFill &&
      other.direction == direction &&
      listEquals(other.stops, stops);

  /// 与方向和色标内容相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(direction, Object.hashAll(stops));
}

/// 上游线性渐变方向关键字。
enum LuckyGradientKeyword {
  /// 自下向上。
  top,

  /// 自上向下。
  bottom,

  /// 自右向左。
  left,

  /// 自左向右。
  right,

  /// 无方向，端点均为原点。
  none,
}

/// 上游线性渐变的角度或关键字方向。
///
/// 例如 `const LuckyLegacyGradientDirection.angle(90)` 自下向上。
@immutable
final class LuckyLegacyGradientDirection {
  /// 创建有限角度 [degrees] 的方向，负角度在解析时归一化。
  const LuckyLegacyGradientDirection.angle(double this.degrees)
      : keyword = null;

  /// 创建关键字 [keyword] 指定的方向。
  const LuckyLegacyGradientDirection.keyword(LuckyGradientKeyword this.keyword)
      : degrees = null;

  /// 角度（度），关键字方向时为 null。
  final double? degrees;

  /// 关键字，角度方向时为 null。
  final LuckyGradientKeyword? keyword;

  /// 返回 [rect] 上的两个端点，全部坐标向零截断，保留上游运算顺序。
  (Offset, Offset) endpoints(Rect rect) {
    final x = rect.left;
    final y = rect.top;
    final w = rect.width;
    final h = rect.height;
    final angle = degrees;
    final (double x0, double y0, double x1, double y1) points;
    if (angle == null) {
      points = switch (keyword!) {
        LuckyGradientKeyword.top => (x, y + h, x, y),
        LuckyGradientKeyword.bottom => (x, y, x, y + h),
        LuckyGradientKeyword.left => (x + w, y, x, y),
        LuckyGradientKeyword.right => (x, y, x + w, y),
        LuckyGradientKeyword.none => (0.0, 0.0, 0.0, 0.0),
      };
    } else {
      var deg = angle.remainder(kLuckyFullTurnDeg);
      if (deg < 0) deg += kLuckyFullTurnDeg;
      const sector = kLuckyGradientSectorDeg;
      // 上游 utils/math.ts:104-113；先除以 180，再乘 π，不复用 getAngle。
      /// 按上游除后乘的次序计算角度正切。
      double tan(double value) => math.tan(value / kLuckyHalfTurnDeg * math.pi);
      if (deg < sector) {
        points = (x, y + h, x + w, y + h - w * tan(deg - 0));
      } else if (deg < sector * 2) {
        points = (x, y + h, (x + w) - h * tan(deg - sector), y);
      } else if (deg < sector * 3) {
        points = (x + w, y + h, (x + w) - h * tan(deg - sector * 2), y);
      } else if (deg < sector * 4) {
        points = (x + w, y + h, x, y + w * tan(deg - sector * 3));
      } else if (deg < sector * 5) {
        points = (x + w, y, x, y + w * tan(deg - sector * 4));
      } else if (deg < sector * 6) {
        points = (x + w, y, x + h * tan(deg - sector * 5), y + h);
      } else if (deg < sector * 7) {
        points = (x, y, x + h * tan(deg - sector * 6), y + h);
      } else {
        points = (x, y, x + w, y + h - w * tan(deg - sector * 7));
      }
    }
    return (
      Offset(points.$1.toInt().toDouble(), points.$2.toInt().toDouble()),
      Offset(points.$3.toInt().toDouble(), points.$4.toInt().toDouble())
    );
  }

  /// 返回替换方向的副本；同时提供两种方向时抛出 [ArgumentError]。
  ///
  /// 都为 null 时保留原方向；提供任一种即切换到该方向。
  LuckyLegacyGradientDirection copyWith(
      {double? degrees, LuckyGradientKeyword? keyword}) {
    if (degrees != null && keyword != null) {
      throw ArgumentError('角度与关键字不能同时提供');
    }
    if (degrees != null) return LuckyLegacyGradientDirection.angle(degrees);
    if (keyword != null) return LuckyLegacyGradientDirection.keyword(keyword);
    return this;
  }

  /// 比较角度或关键字值。
  @override
  bool operator ==(Object other) =>
      other is LuckyLegacyGradientDirection &&
      other.degrees == degrees &&
      other.keyword == keyword;

  /// 与方向值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(degrees, keyword);
}

/// 渐变颜色与可选位置。
@immutable
final class LuckyColorStop {
  /// 创建色标，[offset] 范围为 0–1；null 表示按下标均分。
  const LuckyColorStop(this.color, [this.offset]);

  /// 色标颜色。
  final Color color;

  /// 位置（0–1）；null 表示自动分配。
  final double? offset;

  /// 返回替换指定字段的副本；参数为 null 时保留原值。
  LuckyColorStop copyWith({Color? color, double? offset}) =>
      LuckyColorStop(color ?? this.color, offset ?? this.offset);

  /// 比较色标的颜色和位置。
  @override
  bool operator ==(Object other) =>
      other is LuckyColorStop && other.color == color && other.offset == offset;

  /// 与色标值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(color, offset);
}
