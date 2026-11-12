import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'length.dart';

/// 首帧图片转换函数，允许同步或异步返回图片。
///
/// 参数为解码后的源图片；可原样返回，返回的新图片所有权归 luckdraw。
typedef LuckyImageFormatter = FutureOr<ui.Image> Function(ui.Image source);

/// 图片项，可被玩法扩展；长度基准由所在布局约定。
///
/// 例如 `const LuckyImage(AssetImage('gift.png'), width: LuckyLength.percent(40))`。
@immutable
class LuckyImage {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyImage(this.image,
      {this.top,
      this.left,
      this.width,
      this.height,
      this.formatter,
      this.borderRadius,
      this.opacity = 1,
      this.fallback,
      this.semanticLabel});

  /// 主图片 provider。
  final ImageProvider<Object> image;

  /// 顶部偏移；null 按零处理。
  final LuckyLength? top;

  /// 水平偏移；null 使用居中位置。
  final LuckyLength? left;

  /// 目标宽度；null 按自然尺寸或高度等比推导。
  final LuckyLength? width;

  /// 目标高度；null 按自然尺寸或宽度等比推导。
  final LuckyLength? height;

  /// 首帧解码后的图片转换函数。
  final LuckyImageFormatter? formatter;

  /// 图片圆角半径（逻辑像素）；null 表示无圆角。
  final double? borderRadius;

  /// 绘制不透明度，调用方应提供 0–1 的值。
  final double opacity;

  /// 主图片失败时使用的后备 provider。
  final ImageProvider<Object>? fallback;

  /// 图片的无障碍描述。
  final String? semanticLabel;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `image.copyWith(opacity: 0.5)` 保留图片与尺寸，仅调整透明度。
  LuckyImage copyWith(
          {ImageProvider<Object>? image,
          LuckyLength? top,
          LuckyLength? left,
          LuckyLength? width,
          LuckyLength? height,
          LuckyImageFormatter? formatter,
          double? borderRadius,
          double? opacity,
          ImageProvider<Object>? fallback,
          String? semanticLabel}) =>
      LuckyImage(image ?? this.image,
          top: top ?? this.top,
          left: left ?? this.left,
          width: width ?? this.width,
          height: height ?? this.height,
          formatter: formatter ?? this.formatter,
          borderRadius: borderRadius ?? this.borderRadius,
          opacity: opacity ?? this.opacity,
          fallback: fallback ?? this.fallback,
          semanticLabel: semanticLabel ?? this.semanticLabel);

  /// 按图片 provider、尺寸及绘制配置比较图片项。
  @override
  bool operator ==(Object other) =>
      other is LuckyImage &&
      other.image == image &&
      other.top == top &&
      other.left == left &&
      other.width == width &&
      other.height == height &&
      other.formatter == formatter &&
      other.borderRadius == borderRadius &&
      other.opacity == opacity &&
      other.fallback == fallback &&
      other.semanticLabel == semanticLabel;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(image, top, left, width, height, formatter,
      borderRadius, opacity, fallback, semanticLabel);
}

/// 图片槽标识，由分组、条目、图片下标和激活态组成。
///
/// 例如 `const LuckyImageSlot('prizes', 1, 0)` 标识第二个奖品的首张图片。
@immutable
final class LuckyImageSlot {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyImageSlot(this.group, this.itemIndex, this.imageIndex,
      {this.active = false});

  /// 分组名，例如 prizes。
  final String group;

  /// 分组内条目下标，从零开始。
  final int itemIndex;

  /// 条目内图片下标，从零开始。
  final int imageIndex;

  /// 是否为激活态图片。
  final bool active;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `slot.copyWith(active: true)` 切换到同一槽位的激活图。
  LuckyImageSlot copyWith(
          {String? group, int? itemIndex, int? imageIndex, bool? active}) =>
      LuckyImageSlot(group ?? this.group, itemIndex ?? this.itemIndex,
          imageIndex ?? this.imageIndex,
          active: active ?? this.active);

  /// 按分组、条目、图片下标与激活态比较槽位。
  @override
  bool operator ==(Object other) =>
      other is LuckyImageSlot &&
      other.group == group &&
      other.itemIndex == itemIndex &&
      other.imageIndex == imageIndex &&
      other.active == active;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(group, itemIndex, imageIndex, active);

  /// 返回可读槽位路径，例如 `prizes[1].imgs[0]`；激活图以 activeImgs 标识。
  @override
  String toString() =>
      '$group[$itemIndex].${active ? 'activeImgs' : 'imgs'}[$imageIndex]';
}

/// 图片加载请求，包含槽位、图片项、实际 provider 与可选解码尺寸。
///
/// 例如 `request.copyWith(decodeLogicalWidth: 100)` 指定解码的逻辑宽度。
@immutable
final class LuckyImageRequest {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyImageRequest(
      {required this.slot,
      required this.image,
      required this.provider,
      this.decodeLogicalWidth,
      this.decodeLogicalHeight});

  /// 图片所属槽位。
  final LuckyImageSlot slot;

  /// 图片项配置。
  final LuckyImage image;

  /// 本次实际解析的 provider。
  final ImageProvider<Object> provider;

  /// 目标解码宽度（逻辑像素）；null 不指定。
  final double? decodeLogicalWidth;

  /// 目标解码高度（逻辑像素）；null 不指定。
  final double? decodeLogicalHeight;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `request.copyWith(provider: fallback)` 保留槽位并替换实际 provider。
  LuckyImageRequest copyWith(
          {LuckyImageSlot? slot,
          LuckyImage? image,
          ImageProvider<Object>? provider,
          double? decodeLogicalWidth,
          double? decodeLogicalHeight}) =>
      LuckyImageRequest(
          slot: slot ?? this.slot,
          image: image ?? this.image,
          provider: provider ?? this.provider,
          decodeLogicalWidth: decodeLogicalWidth ?? this.decodeLogicalWidth,
          decodeLogicalHeight: decodeLogicalHeight ?? this.decodeLogicalHeight);

  /// 按槽位、图片项、provider 与目标尺寸比较请求。
  @override
  bool operator ==(Object other) =>
      other is LuckyImageRequest &&
      other.slot == slot &&
      other.image == image &&
      other.provider == provider &&
      other.decodeLogicalWidth == decodeLogicalWidth &&
      other.decodeLogicalHeight == decodeLogicalHeight;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      slot, image, provider, decodeLogicalWidth, decodeLogicalHeight);
}

/// 图片加载错误，保留槽位与后备图使用状态。
///
/// 例如 `diagnostic.copyWith(usedFallback: true)` 记录已使用后备图。
@immutable
final class LuckyImageError {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyImageError(
      {required this.slot,
      required this.error,
      this.stackTrace,
      this.usedFallback = false});

  /// 失败图片所属槽位。
  final LuckyImageSlot slot;

  /// 加载或转换时抛出的错误对象。
  final Object error;

  /// 原始错误堆栈；未提供时为 null。
  final StackTrace? stackTrace;

  /// 是否已使用后备图。
  final bool usedFallback;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 例如 `diagnostic.copyWith(stackTrace: trace)` 附加原始错误堆栈。
  LuckyImageError copyWith(
          {LuckyImageSlot? slot,
          Object? error,
          StackTrace? stackTrace,
          bool? usedFallback}) =>
      LuckyImageError(
          slot: slot ?? this.slot,
          error: error ?? this.error,
          stackTrace: stackTrace ?? this.stackTrace,
          usedFallback: usedFallback ?? this.usedFallback);

  /// 按槽位、原始错误、堆栈与后备图状态比较诊断。
  @override
  bool operator ==(Object other) =>
      other is LuckyImageError &&
      other.slot == slot &&
      other.error == error &&
      other.stackTrace == stackTrace &&
      other.usedFallback == usedFallback;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(slot, error, stackTrace, usedFallback);
}
