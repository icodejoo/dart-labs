import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../game/frame.dart';
import '../game/layout.dart';

/// 绘制层插入的位置。
enum LuckyLayerPosition {
  /// 块背景之前。
  background,

  /// 块背景之后、条目之前。
  belowItems,

  /// 条目之后、按钮之前。
  aboveItems,

  /// 全部内容之上。
  foreground,
}

/// 自定义绘制层；静态层应只依赖布局。
abstract class LuckyLayer<L extends LuckyLayout, F extends LuckyFrame> {
  /// 创建层；随盘旋转只适用于转盘的条目前后位置。
  const LuckyLayer(
      {this.position = LuckyLayerPosition.foreground,
      this.isStatic = false,
      this.rotatesWithWheel = false});

  /// 绘制位置。
  final LuckyLayerPosition position;

  /// 是否录入静态缓存。
  final bool isStatic;

  /// 是否随盘旋转。
  final bool rotatesWithWheel;

  /// 绘制当前层；不可保存复用的 [context]。
  void paint(Canvas canvas, LuckyLayerContext<L, F> context);

  /// 静态内容变化时返回 true，以失效对应缓存。
  bool shouldRepaint(covariant LuckyLayer<L, F> oldLayer) => false;
}

/// 渲染器复用的可变层上下文，用户不可保留它。
final class LuckyLayerContext<L extends LuckyLayout, F extends LuckyFrame> {
  /// 创建空上下文，绘制前须填入布局和帧。
  LuckyLayerContext();

  /// 逻辑盒子尺寸。
  late Size size;

  /// 当前布局。
  late L layout;

  /// 复用的帧。
  late F frame;

  /// 当前设备像素比。
  double devicePixelRatio = 1;
}

/// 回调形式的绘制层，例如 `LuckyCallbackLayer(drawIndicator)`。
final class LuckyCallbackLayer<L extends LuckyLayout, F extends LuckyFrame>
    extends LuckyLayer<L, F> {
  /// 创建回调层。
  const LuckyCallbackLayer(this.onPaint,
      {super.position, super.isStatic, super.rotatesWithWheel});

  /// 绘制回调，不可保留上下文。
  final void Function(Canvas canvas, LuckyLayerContext<L, F> context) onPaint;

  /// 转交绘制回调。
  @override
  void paint(Canvas canvas, LuckyLayerContext<L, F> context) =>
      onPaint(canvas, context);
}

/// 回放 [position] 位置的用户层：有 [pictures] 缓存的直接回放，其余调用动态绘制。
///
/// [isolate] 为真时每层包在 save/restore 里；[rotate] 非空时，对 `rotatesWithWheel`
/// 的层先用它施加转盘旋转。例如
/// `luckyReplayLayers(canvas, data.layers, _layerPictures, position, _context)`。
void luckyReplayLayers<L extends LuckyLayout, F extends LuckyFrame>(
    Canvas canvas,
    List<LuckyLayer<L, F>> layers,
    List<ui.Picture?> pictures,
    LuckyLayerPosition position,
    LuckyLayerContext<L, F> context,
    {bool isolate = true,
    void Function(Canvas canvas)? rotate}) {
  for (var i = 0; i < layers.length; i++) {
    final layer = layers[i];
    if (layer.position != position) continue;
    if (isolate) canvas.save();
    if (layer.rotatesWithWheel) rotate?.call(canvas);
    final picture = pictures[i];
    if (picture == null) {
      layer.paint(canvas, context);
    } else {
      canvas.drawPicture(picture);
    }
    if (isolate) canvas.restore();
  }
}
