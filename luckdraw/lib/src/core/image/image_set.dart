import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../foundation/image.dart';

/// 已解析图片的只读视图；例如 `images[slot]?.naturalSize`。
abstract interface class LuckyImageSet {
  /// 图片到达、失败或请求集合更新后的版本。
  int get generation;

  /// 返回 [slot] 对应图片，尚未成功时为 null。
  LuckyResolvedImage? operator [](LuckyImageSlot slot);

  /// 所有请求是否都已成功或失败。
  bool get isSettled;
}

/// 解析结果；图片所有权由解析器持有，调用方不可释放。
@immutable
final class LuckyResolvedImage {
  /// 用图片和逻辑像素自然尺寸创建结果。
  const LuckyResolvedImage(this.image, this.naturalSize);

  /// 可绘制的首帧图片。
  final ui.Image image;

  /// 自然尺寸，单位为逻辑像素。
  final ui.Size naturalSize;
}
