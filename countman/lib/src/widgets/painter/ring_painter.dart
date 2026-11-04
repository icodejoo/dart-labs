import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Draws a circular arc over a track — the shared rendering core for
/// `RingCountdown` (arc depletes) and `RingCounter` (arc fills). Both widgets
/// only differ in how they compute [progress]; the arc math lives here once.
///
/// The track/arc span a configurable [sweepAngle] (default a full circle),
/// so partial-arc "gauge" styles (e.g. a 270° speedometer) work by passing
/// `sweepAngle: 270 * pi / 180`. An optional [backgroundColor] fills the disc
/// behind the ring, and [showTrack] can hide the track entirely.
///
/// Every drawing step is a separate overridable method so a subclass can
/// customize one piece without reimplementing [paint].
///
/// 绘制轨道上的圆弧——`RingCountdown`（弧递减）与 `RingCounter`（弧填充）的
/// 共享渲染核心。轨道/弧跨越可配置的 [sweepAngle]（默认整圆），因此传入
/// `sweepAngle: 270 * pi / 180` 即可实现部分弧的"仪表盘"样式。可选的
/// [backgroundColor] 在环形背后填充圆盘，[showTrack] 可完全隐藏轨道。
class RingPainter extends CustomPainter {
  /// 默认游标半径与描边宽度的比例。
  static const double _thumbScale = 0.7;

  /// 创建进度画笔；方向性渐变需传 textDirection，如 TextDirection.rtl。
  const RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.clockwise,
    this.startAngle = -math.pi / 2,
    this.strokeCap = StrokeCap.round,
    this.gradient,
    this.trackGradient,
    this.textDirection,
    this.trackStrokeWidth,
    this.padding = EdgeInsets.zero,
    this.sweepAngle = 2 * math.pi,
    this.showTrack = true,
    this.backgroundColor,
    this.anchorAtEnd = false,
    this.showThumb = false,
    this.thumbColor,
    this.thumbRadius,
  });

  /// 0.0–1.0 fraction of the arc to draw.
  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final bool clockwise;

  /// Angle (radians) the arc starts from. Default: `-pi/2` (12 o'clock).
  final double startAngle;

  /// Cap drawn at the arc ends. Default: [StrokeCap.round].
  final StrokeCap strokeCap;

  /// Optional gradient painted along the arc, overriding [color].
  final Gradient? gradient;

  /// Optional gradient painted on the track, overriding [trackColor].
  final Gradient? trackGradient;

  /// 渐变的文字方向；默认 null，使用方向性 Alignment 时需显式提供。
  /// 例如 `textDirection: TextDirection.rtl`，仅影响渐变解析。
  final TextDirection? textDirection;

  /// Track stroke width. Defaults to [strokeWidth] when null.
  final double? trackStrokeWidth;

  /// Inset applied before computing the ring's center and radius.
  final EdgeInsets padding;

  /// Total angular span (radians) of the track. Default: `2*pi` (full circle).
  /// Values below `2*pi` produce a partial-arc gauge; the progress arc fills
  /// [progress] of this span.
  ///
  /// 轨道的总角跨度（弧度）。默认 `2*pi`（整圆）。小于 `2*pi` 得到部分弧仪表盘；
  /// 进度弧填充此跨度的 [progress]。
  final double sweepAngle;

  /// When false, the background track is not drawn (only the progress arc).
  ///
  /// 为 false 时不绘制背景轨道（只画进度弧）。
  final bool showTrack;

  /// Optional solid fill of the disc behind the ring (radius up to the ring).
  ///
  /// 可选：环形背后圆盘的实心填充（半径至环形处）。
  final Color? backgroundColor;

  /// Anchors the progress arc at its END instead of its start.
  ///
  /// With the default (false), the arc grows/shrinks from [startAngle] — the
  /// natural "fill toward a goal" behavior for a counter. With `true`, the arc
  /// is pinned at its far end and its START recedes as [progress] drops, so a
  /// countdown's empty gap opens at [startAngle] and sweeps in the drawing
  /// direction (clockwise by default) instead of the leftover arc retreating
  /// the other way.
  ///
  /// 将进度弧锚定在其**末端**而非起点。
  ///
  /// 默认（false）时弧从 [startAngle] 增长/收缩——计数器"向目标填充"的自然行为。
  /// 为 `true` 时弧固定在远端、起点随 [progress] 下降而后退，使倒计时的空缺从
  /// [startAngle] 开始、沿绘制方向（默认顺时针）扫过，而非剩余弧向反方向回退。
  final bool anchorAtEnd;

  /// Draws a filled dot ("thumb") at the arc's moving/leading edge. A distinct
  /// dot that slides each tick reads as "alive" even when a long countdown's
  /// gap grows only ~1px/second — solving the "looks frozen at first" problem
  /// while keeping round caps.
  ///
  /// 在弧的移动/前导边缘绘制一个实心圆点（"游标"）。即便长倒计时缺口每秒只增长
  /// ~1px，一个每 tick 滑动的醒目圆点也让人一眼看出"在动"——在保留圆头的同时解决
  /// "初期看似静止"的问题。
  final bool showThumb;

  /// Thumb fill color. Defaults to the arc [color] when null.
  ///
  /// 游标填充色。为空时取弧的 [color]。
  final Color? thumbColor;

  /// Thumb radius. Defaults to `strokeWidth * 0.7` (a knob slightly proud of
  /// the stroke) when null.
  ///
  /// 游标半径。为空时取 `strokeWidth * 0.7`（略高于描边的小旋钮）。
  final double? thumbRadius;

  /// The drawing rect after applying [padding].
  Rect rectFor(Size size) => padding.deflateRect(Offset.zero & size);

  /// Center of the ring within [size]. Override to offset it.
  Offset centerFor(Size size) => rectFor(size).center;

  /// 按描边与游标中较大的外伸距离预留余量，避免游标超出 size。
  double radiusFor(Size size) {
    final maxStroke = math.max(strokeWidth, trackStrokeWidth ?? strokeWidth);
    final inset = showThumb
        ? math.max(maxStroke / 2, thumbRadius ?? strokeWidth * _thumbScale)
        : maxStroke / 2;
    final r = rectFor(size).shortestSide / 2 - inset;
    return r < 0 ? 0 : r;
  }

  /// Builds the [Paint] shared by [paintTrack] and [paintArc].
  Paint buildStrokePaint() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = strokeCap
    ..isAntiAlias = true;

  /// Fills the disc behind the ring with [backgroundColor], when set.
  ///
  /// 当设置了 [backgroundColor] 时，填充环形背后的圆盘。
  void paintBackground(Canvas canvas, Offset center, double radius) {
    if (backgroundColor == null) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = backgroundColor!
        ..isAntiAlias = true,
    );
  }

  /// 绘制轨道弧，并用 textDirection 解析方向性渐变。
  void paintTrack(Canvas canvas, Offset center, double radius, Paint paint) {
    if (!showTrack) return;
    paint.strokeWidth = trackStrokeWidth ?? strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (trackGradient != null) {
      paint.shader =
          trackGradient!.createShader(rect, textDirection: textDirection);
    } else {
      paint.shader = null;
      paint.color = trackColor;
    }
    canvas.drawArc(
        rect, startAngle, sweepAngle * (clockwise ? 1 : -1), false, paint);
  }

  /// 返回进度弧的起点和有方向的 sweep，供绘制与几何测试复用。
  /// 满环圆头/方头先扣除端帽间隙，再乘 progress，确保全区间连续变化。
  /// 部分环及 butt 端帽保持原跨度；anchorAtEnd 为 true 时固定远端。
  /// 参数为弧度、布局半径与 0–1 进度；例如 progress: 0.99 会立即缩短弧。
  static ({double start, double sweep}) arcGeometry({
    required double startAngle,
    required double sweepAngle,
    required double progress,
    required double strokeWidth,
    required double radius,
    required StrokeCap strokeCap,
    required bool clockwise,
    required bool anchorAtEnd,
  }) {
    final dir = clockwise ? 1.0 : -1.0;
    var drawnSweep = sweepAngle * progress;
    if (strokeCap != StrokeCap.butt &&
        radius > 0 &&
        sweepAngle >= 2 * math.pi - 1e-3) {
      final capGap = strokeWidth / radius; // ~one cap diameter, in radians
      // max(0, …) guards a degenerate stroke thicker than the circumference.
      final maxSweep = math.max(0.0, sweepAngle - capGap);
      drawnSweep = maxSweep * progress;
    }
    final emptied = sweepAngle - drawnSweep;
    final start = anchorAtEnd ? startAngle + emptied * dir : startAngle;
    return (start: start, sweep: drawnSweep * dir);
  }

  /// 绘制按进度缩放的弧，并用 textDirection 解析方向性渐变。
  void paintArc(Canvas canvas, Offset center, double radius, Paint paint) {
    if (progress <= 0) return;
    paint.strokeWidth = strokeWidth;
    final rect = Rect.fromCircle(center: center, radius: radius);
    if (gradient != null) {
      paint.shader = gradient!.createShader(rect, textDirection: textDirection);
    } else {
      paint.shader = null;
      paint.color = color;
    }
    final g = arcGeometry(
      startAngle: startAngle,
      sweepAngle: sweepAngle,
      progress: progress,
      strokeWidth: strokeWidth,
      radius: radius,
      strokeCap: strokeCap,
      clockwise: clockwise,
      anchorAtEnd: anchorAtEnd,
    );
    canvas.drawArc(rect, g.start, g.sweep, false, paint);
  }

  /// Draws the [showThumb] dot at the arc's leading (moving) edge — the arc
  /// start for a depleting [anchorAtEnd] ring, else the arc end. Override to
  /// customize the marker.
  ///
  /// 在弧的前导（移动）边缘绘制 [showThumb] 圆点——递减的 [anchorAtEnd] 环取弧起点，
  /// 否则取弧末端。可重写以自定义标记。
  void paintThumb(Canvas canvas, Offset center, double radius) {
    if (!showThumb || progress <= 0) return;
    final g = arcGeometry(
      startAngle: startAngle,
      sweepAngle: sweepAngle,
      progress: progress,
      strokeWidth: strokeWidth,
      radius: radius,
      strokeCap: strokeCap,
      clockwise: clockwise,
      anchorAtEnd: anchorAtEnd,
    );
    final leadingAngle = anchorAtEnd ? g.start : g.start + g.sweep;
    final pos = Offset(
      center.dx + radius * math.cos(leadingAngle),
      center.dy + radius * math.sin(leadingAngle),
    );
    canvas.drawCircle(
      pos,
      thumbRadius ?? strokeWidth * _thumbScale,
      Paint()
        ..style = PaintingStyle.fill
        ..color = thumbColor ?? color
        ..isAntiAlias = true,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerFor(size);
    final radius = radiusFor(size);
    paintBackground(canvas, center, radius);
    final paint = buildStrokePaint();
    paintTrack(canvas, center, radius, paint);
    paintArc(canvas, center, radius, paint);
    paintThumb(canvas, center, radius);
  }

  /// 方向或视觉配置改变时重新绘制。
  @override
  bool shouldRepaint(RingPainter old) =>
      old.textDirection != textDirection ||
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.clockwise != clockwise ||
      old.startAngle != startAngle ||
      old.strokeCap != strokeCap ||
      old.gradient != gradient ||
      old.trackGradient != trackGradient ||
      old.trackStrokeWidth != trackStrokeWidth ||
      old.padding != padding ||
      old.sweepAngle != sweepAngle ||
      old.showTrack != showTrack ||
      old.backgroundColor != backgroundColor ||
      old.anchorAtEnd != anchorAtEnd ||
      old.showThumb != showThumb ||
      old.thumbColor != thumbColor ||
      old.thumbRadius != thumbRadius;
}
