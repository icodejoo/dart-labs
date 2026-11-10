import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../foundation/constants.dart';
import '../foundation/image.dart';
import '../foundation/length.dart';

/// 根据自然尺寸和可选宽高返回图片绘制尺寸。
///
/// 百分比各按 [maxWidth]/[maxHeight] 解析；只给一边时等比缩放，两边未给则用 [natural]。
Size computeImageBox(
    {required Size natural,
    LuckyLength? width,
    LuckyLength? height,
    required double maxWidth,
    required double maxHeight}) {
  // 上游 lucky.ts:290-316；保留比例计算的括号。
  if (width == null && height == null) {
    return Size(natural.width, natural.height);
  }
  if (width != null && height == null) {
    final w = width.resolve(maxWidth);
    return Size(w, natural.height * (w / natural.width));
  }
  if (width == null && height != null) {
    final h = height.resolve(maxHeight);
    return Size(natural.width * (h / natural.height), h);
  }
  return Size(width!.resolve(maxWidth), height!.resolve(maxHeight));
}

/// 图片的容器、尺寸和偏移解析规则；例如 `placement.place(natural)` 返回绘制矩形。
@immutable
final class LuckyImagePlacement {
  /// 创建规则；各基准和 [yOffset] 均为逻辑像素。
  const LuckyImagePlacement(
      {required this.slot,
      required this.image,
      required this.box,
      required this.maxWidth,
      required this.maxHeight,
      required this.leftBase,
      required this.topBase,
      this.yOffset = 0});

  /// 图片槽。
  final LuckyImageSlot slot;

  /// 图片项。
  final LuckyImage image;

  /// 容器矩形；宽零表示以 box.left 为水平中心。
  final Rect box;

  /// 宽度百分比基准。
  final double maxWidth;

  /// 高度百分比基准。
  final double maxHeight;

  /// 水平偏移百分比基准。
  final double leftBase;

  /// 顶部偏移百分比基准。
  final double topBase;

  /// 附加纵向偏移。
  final double yOffset;

  /// 用 [natural] 计算水平居中后叠加 left/top 偏移的绘制矩形。
  Rect place(Size natural) {
    final size = computeImageBox(
        natural: natural,
        width: image.width,
        height: image.height,
        maxWidth: maxWidth,
        maxHeight: maxHeight);
    return Rect.fromLTWH(
        box.left +
            (box.width - size.width) / kLuckyHalfDivisor +
            (image.left?.resolve(leftBase) ?? 0),
        box.top + (image.top?.resolve(topBase) ?? 0) + yOffset,
        size.width,
        size.height);
  }
}
