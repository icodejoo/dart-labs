/// `CustomPainter` 渲染层：把核心层产出的 [DrawCommand] 列表画到 Flutter Canvas 上。
///
/// 对应 TS 版本的 `renderer-canvas/canvas-renderer.ts`：每帧对指令列表全量重绘，
/// 不做增量 diff（diff 发生在更上层的 `panel/road_panel.dart`，只决定当前帧要画
/// 哪些插值后的指令，画布本身永远是"整份重画"）。这个模型天然贴合 Flutter 的
/// `CustomPainter`：`shouldRepaint` 对应 TS 里"要不要在下一帧调 `render()`"。
///
/// 移植自 `src/renderer-canvas/canvas-renderer.ts`。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/types.dart';

/// 把核心层的 ARGB 整数颜色转成 Flutter [Color]。
Color colorFromArgb(int argb) => Color(argb);

/// 单个路面板的 `CustomPainter`：消费 [commands]，按 [viewport] 做变换绘制，
/// 可选绘制背景网格 [grid]。
class RoadPainter extends CustomPainter {
  /// 待绘制的指令列表（已按当前帧插值完毕，全量重绘）。
  final List<DrawCommand> commands;

  /// 内容总宽（逻辑像素），用于可视裁剪。
  final double contentWidth;

  /// 当前视口偏移/缩放。
  final Offset viewportOffset;

  /// 当前视口缩放倍率。
  final double viewportScale;

  /// 背景网格配置，null 表示不绘制网格。
  final GridSpec? grid;

  /// 画布背景色。
  final int background;

  const RoadPainter({
    required this.commands,
    required this.contentWidth,
    required this.viewportOffset,
    required this.viewportScale,
    this.grid,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = colorFromArgb(background));

    // 1. 背景网格：不参与 scroll 变换，始终铺满面板。
    if (grid != null) {
      _paintGrid(canvas, w, h, grid!);
    }

    // 2. 内容层：应用 viewport 变换。
    canvas.save();
    canvas.translate(viewportOffset.dx, viewportOffset.dy);
    canvas.scale(viewportScale);

    final visL = -viewportOffset.dx / viewportScale;
    final visR = (-viewportOffset.dx + w) / viewportScale;
    final margin = contentWidth > 0 ? contentWidth * 0.05 : 50;

    for (final cmd in commands) {
      if (_isOutside(cmd, visL - margin, visR + margin)) continue;
      _paintCommand(canvas, cmd);
    }

    canvas.restore();
  }

  /// 渲染背景网格（相位与内容坐标同步对齐，随 viewport 平移/缩放连续绘制，铺满
  /// 整个可视区域）。与内容层共用同一份 viewport 变换语义，不受内容边界限制——
  /// 避免"内容自绘网格"与"渲染层背景网格"两套独立系统各自计算坐标导致的错位。
  void _paintGrid(Canvas canvas, double w, double h, GridSpec grid) {
    final cellSize = grid.cellSize;
    final stroke = grid.stroke ?? 0x14FFFFFF;
    final colSpan = grid.colSpan;
    final rowSpan = grid.rowSpan;
    final tileFill = grid.tileFill ?? 0x14FFFFFF;
    final tileRadiusRatio = grid.tileRadiusRatio;
    final tileInsetRatio = grid.tileInsetRatio;

    final scale = viewportScale;
    final spanW = cellSize * colSpan * scale;
    final spanH = cellSize * rowSpan * scale;

    // 相位：X/Y 均按当前 offset 动态计算（同步内容平移）。
    final phaseX = ((viewportOffset.dx % spanW) + spanW) % spanW;
    final phaseY = ((viewportOffset.dy % spanH) + spanH) % spanH;

    canvas.save();

    if (grid.style == GridStyle.tile) {
      final insetX = spanW * tileInsetRatio;
      final insetY = spanH * tileInsetRatio;
      final radius = math.min(spanW, spanH) * tileRadiusRatio;
      final paint = Paint()..color = colorFromArgb(tileFill);
      // 从 phase-span 起步，保证左/上边缘的半截瓷砖也能画出来，不留空隙。
      for (var y = phaseY - spanH; y <= h + spanH; y += spanH) {
        for (var x = phaseX - spanW; x <= w + spanW; x += spanW) {
          final rw = spanW - 2 * insetX;
          final rh = spanH - 2 * insetY;
          if (rw <= 0 || rh <= 0) continue;
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + insetX, y + insetY, rw, rh), Radius.circular(radius)),
            paint,
          );
        }
      }
    } else {
      final paint = Paint()
        ..color = colorFromArgb(stroke)
        ..strokeWidth = 0.5;
      for (var x = phaseX; x <= w + spanW; x += spanW) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
      }
      for (var y = phaseY; y <= h + spanH; y += spanH) {
        canvas.drawLine(Offset(0, y), Offset(w, y), paint);
      }
    }

    canvas.restore();
  }

  /// 可视范围裁剪（剔除明显在面板外的指令，提升性能）。
  bool _isOutside(DrawCommand cmd, double visL, double visR) => switch (cmd) {
    CircleCommand c => c.x < visL || c.x > visR,
    SlashCommand c => c.x < visL || c.x > visR,
    DotCommand c => c.x < visL || c.x > visR,
    BadgeCommand c => c.x < visL || c.x > visR,
    LineCommand c => (c.points.isNotEmpty ? c.points[0] : 0) < visL || (c.points.isNotEmpty ? c.points[0] : 0) > visR,
    RectCommand c => c.x + c.w < visL || c.x > visR,
  };

  /// 回放单条绘制指令，支持 [DrawCommand.alpha] 透明度（动画插值用）。
  void _paintCommand(Canvas canvas, DrawCommand cmd) {
    final alpha = cmd.alpha ?? 1;
    switch (cmd) {
      case CircleCommand c:
        if (c.fill != null) {
          canvas.drawCircle(Offset(c.x, c.y), c.r, Paint()..color = _withAlpha(c.fill!, alpha));
        }
        if (c.stroke != null) {
          canvas.drawCircle(
            Offset(c.x, c.y),
            c.r,
            Paint()
              ..color = _withAlpha(c.stroke!, alpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = c.lineWidth ?? 2,
          );
        }
      case LineCommand c:
        final path = Path();
        for (var i = 0; i < c.points.length; i += 2) {
          final x = c.points[i];
          final y = i + 1 < c.points.length ? c.points[i + 1] : 0.0;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = _withAlpha(c.stroke, alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = c.lineWidth ?? 2,
        );
      case SlashCommand c:
        canvas.drawLine(
          Offset(c.x - c.r, c.y + c.r),
          Offset(c.x + c.r, c.y - c.r),
          Paint()
            ..color = _withAlpha(c.stroke, alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = c.lineWidth ?? 2,
        );
      case DotCommand c:
        canvas.drawCircle(Offset(c.x, c.y), c.r, Paint()..color = _withAlpha(c.fill, alpha));
      case BadgeCommand c:
        final fs = c.fontSize ?? 12;
        final tp = TextPainter(
          text: TextSpan(
            text: c.text,
            style: TextStyle(color: _withAlpha(c.fill ?? 0xFFFFFFFF, alpha), fontSize: fs),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c.x - tp.width / 2, c.y - tp.height / 2));
      case RectCommand c:
        final rect = Rect.fromLTWH(c.x, c.y, c.w, c.h);
        if (c.radius != null) {
          final rrect = RRect.fromRectAndRadius(rect, Radius.circular(c.radius!));
          if (c.fill != null) canvas.drawRRect(rrect, Paint()..color = _withAlpha(c.fill!, alpha));
          if (c.stroke != null) {
            canvas.drawRRect(
              rrect,
              Paint()
                ..color = _withAlpha(c.stroke!, alpha)
                ..style = PaintingStyle.stroke,
            );
          }
        } else {
          if (c.fill != null) canvas.drawRect(rect, Paint()..color = _withAlpha(c.fill!, alpha));
          if (c.stroke != null) {
            canvas.drawRect(
              rect,
              Paint()
                ..color = _withAlpha(c.stroke!, alpha)
                ..style = PaintingStyle.stroke,
            );
          }
        }
    }
  }

  Color _withAlpha(int argb, double alpha) => colorFromArgb(argb).withValues(alpha: alpha);

  @override
  bool shouldRepaint(covariant RoadPainter oldDelegate) =>
      !identical(oldDelegate.commands, commands) ||
      oldDelegate.contentWidth != contentWidth ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportScale != viewportScale ||
      oldDelegate.grid != grid ||
      oldDelegate.background != background;
}

/// [ui.Image] 相关工具预留（暂未使用，供后续离屏位图缓存优化时扩展）。
