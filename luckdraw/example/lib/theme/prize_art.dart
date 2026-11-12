import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:luckdraw/wheel.dart';

import 'demo_theme.dart';

/// 在 [canvas] 的非空 [rect] 内绘制奖品；[variant] 为非负的奖品编号。
///
/// 例如 `paintDemoPrize(canvas, rect, 0)` 绘制礼盒，其余编号循环选择图案。
void paintDemoPrize(Canvas canvas, Rect rect, int variant) {
  final center = rect.center;
  final unit = rect.shortestSide;
  final paint = Paint();
  final color = switch (variant % 3) {
    0 => DemoPalette.coral,
    1 => DemoPalette.blue,
    _ => DemoPalette.mint,
  };
  canvas.save();
  canvas.translate(center.dx, center.dy);
  paint.color = color;
  switch (variant % 3) {
    case 0:
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(0, unit * .1),
                  width: unit * .7,
                  height: unit * .58),
              Radius.circular(unit * .08)),
          paint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(0, -unit * .18),
                  width: unit * .8,
                  height: unit * .2),
              Radius.circular(unit * .04)),
          paint);
      paint.color = DemoPalette.gold;
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(0, unit * .08),
              width: unit * .12,
              height: unit * .65),
          paint);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = unit * .07;
      canvas.drawOval(
          Rect.fromLTWH(-unit * .26, -unit * .46, unit * .26, unit * .2),
          paint);
      canvas.drawOval(
          Rect.fromLTWH(0, -unit * .46, unit * .26, unit * .2), paint);
    case 1:
      final path = Path()
        ..moveTo(-unit * .45, -unit * .12)
        ..lineTo(-unit * .24, -unit * .4)
        ..lineTo(unit * .24, -unit * .4)
        ..lineTo(unit * .45, -unit * .12)
        ..lineTo(0, unit * .44)
        ..close();
      canvas.drawPath(path, paint);
      paint.color = DemoPalette.periwinkle;
      canvas.drawPath(
          Path()
            ..moveTo(-unit * .16, -unit * .12)
            ..lineTo(0, -unit * .4)
            ..lineTo(unit * .16, -unit * .12)
            ..lineTo(0, unit * .44)
            ..close(),
          paint);
      paint.color = Colors.white;
      paint.strokeWidth = unit * .035;
      canvas.drawLine(Offset(-unit * .34, -unit * .12),
          Offset(unit * .34, -unit * .12), paint);
    default:
      canvas.drawCircle(Offset.zero, unit * .46, paint);
      paint.color = DemoPalette.ink;
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5;
        final radius = unit * (i.isEven ? .3 : .14);
        final point =
            Offset(math.cos(angle) * radius, math.sin(angle) * radius);
        if (i == 0) {
          star.moveTo(point.dx, point.dy);
        } else {
          star.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(star..close(), paint);
  }
  canvas.restore();
}

/// 扇区奖品插画；原点与朝向遵循公开 [WheelPrizePaintContext] 契约。
///
/// 例如 `WheelPrize(painter: paintWheelPrize)` 使用当前扇区编号选择插画。
void paintWheelPrize(Canvas canvas, WheelPrizePaintContext context) =>
    paintDemoPrize(
      canvas,
      Rect.fromCenter(
          center: Offset(0, context.prizeHeight * .5), width: 30, height: 30),
      context.index,
    );

/// 九宫格奖品插画；高亮时保持图标形状以利辨识。
///
/// [rect] 为当前格子的内容矩形，[active] 为激活状态；用于 GridPrize.painter。
void paintGridPrize(Canvas canvas, Rect rect, bool active) => paintDemoPrize(
      canvas,
      Rect.fromCenter(
          center: rect.center.translate(0, -8), width: 32, height: 32),
      (rect.left / rect.width).floor() + (rect.top / rect.height).floor(),
    );

/// 滚轮奖品插画，与轮内文字分别排版。
///
/// [size] 为当前奖品格的尺寸，[index] 为奖品编号；用于 SlotPrize.painter。
void paintSlotPrize(Canvas canvas, Size size, int index) => paintDemoPrize(
      canvas,
      Rect.fromCenter(
          center: Offset(size.width / 2, size.height * .38),
          width: 42,
          height: 42),
      index,
    );

/// 不参与命中的舞台灯珠；仅转盘页面启用圆形装饰。
class DemoStagePainter extends CustomPainter {
  /// [wheel] 为 true 时沿转盘外圈绘制灯珠。
  const DemoStagePainter({required this.wheel});

  /// 是否为圆形转盘舞台。
  final bool wheel;

  /// 绘制固定位置的灯珠，避免额外常驻动画。
  @override
  void paint(Canvas canvas, Size size) {
    if (!wheel) return;
    final paint = Paint()..color = DemoPalette.cream;
    final radius = size.shortestSide / 2 - 23;
    final center = size.center(Offset.zero);
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      canvas.drawCircle(
          center + Offset(math.cos(angle), math.sin(angle)) * radius,
          2.6,
          paint);
    }
  }

  /// 玩法类型变化时更新静态装饰。
  @override
  bool shouldRepaint(DemoStagePainter oldDelegate) =>
      wheel != oldDelegate.wheel;
}
