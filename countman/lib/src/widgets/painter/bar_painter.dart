import 'package:flutter/widgets.dart';

/// Draws a filled rounded-rect bar over a track — the shared rendering core
/// for `BarCountdown` (bar shrinks) and `BarCounter` (bar grows). Both widgets
/// only differ in how they compute [progress]; the fill math lives here once.
///
/// Supports horizontal (default) and [vertical] orientation, filling from
/// either edge ([fillFromStart]), an optional [gradient]/[trackGradient], a
/// thinner cross-axis band ([trackHeight]), per-corner rounding, and a
/// hideable track ([showTrack]).
///
/// 绘制轨道上的圆角填充条——`BarCountdown`/`BarCounter` 的共享渲染核心。支持水平
/// （默认）与 [vertical] 竖向、从任一端填充、渐变、更细的横轴带、逐角圆角、可隐藏
/// 轨道。
class BarPainter extends CustomPainter {
  const BarPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.borderRadius = const Radius.circular(4),
    this.borderRadiusGeometry,
    this.gradient,
    this.trackGradient,
    this.fillFromStart = true,
    this.trackHeight,
    this.showTrack = true,
    this.vertical = false,
  });

  /// 0.0–1.0 fraction of the bar to fill.
  final double progress;
  final Color color;
  final Color trackColor;

  /// Uniform corner radius. Ignored when [borderRadiusGeometry] is set.
  final Radius borderRadius;

  /// Optional per-corner radius, overriding the uniform [borderRadius].
  final BorderRadius? borderRadiusGeometry;

  /// Optional gradient painted over the fill, overriding [color].
  final Gradient? gradient;

  /// Optional gradient painted over the track, overriding [trackColor].
  final Gradient? trackGradient;

  /// When true (default) the fill grows from the start edge — left (horizontal)
  /// or bottom (vertical); when false it grows from the opposite edge.
  final bool fillFromStart;

  /// Cross-axis thickness of the track/fill band, centered within the paint
  /// size. Defaults to the full cross-axis extent when null.
  final double? trackHeight;

  /// When false, the background track is not drawn (only the fill).
  ///
  /// 为 false 时不绘制背景轨道（只画填充）。
  final bool showTrack;

  /// When true, the bar fills along the vertical axis instead of horizontal.
  ///
  /// 为 true 时沿竖直轴填充，而非水平。
  final bool vertical;

  /// Cross-axis band the bar occupies within [size], honoring [trackHeight].
  Rect bandFor(Size size) {
    if (vertical) {
      final w = trackHeight ?? size.width;
      final left = (size.width - w) / 2;
      return Rect.fromLTWH(left, 0, w, size.height);
    }
    final h = trackHeight ?? size.height;
    final top = (size.height - h) / 2;
    return Rect.fromLTWH(0, top, size.width, h);
  }

  /// The track's rounded-rect shape within [size]. Override for a custom shape.
  RRect trackRRect(Size size) {
    final band = bandFor(size);
    return borderRadiusGeometry != null
        ? borderRadiusGeometry!.toRRect(band)
        : RRect.fromRectAndRadius(band, borderRadius);
  }

  /// Draws the background track. Override to customize or skip it.
  void paintTrack(Canvas canvas, RRect track) {
    if (!showTrack) return;
    final paint = Paint();
    if (trackGradient != null) {
      paint.shader = trackGradient!.createShader(track.outerRect);
    } else {
      paint.color = trackColor;
    }
    canvas.drawRRect(track, paint);
  }

  /// Draws the filled portion, clipped to [track]'s shape. Override to
  /// customize (striped pattern, a trailing "thumb", etc).
  void paintFill(Canvas canvas, RRect track, Size size) {
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final band = bandFor(size);
    final Rect fillRect;
    if (vertical) {
      final hh = band.height * p;
      fillRect = fillFromStart
          ? Rect.fromLTWH(band.left, band.bottom - hh, band.width, hh)
          : Rect.fromLTWH(band.left, band.top, band.width, hh);
    } else {
      final w = band.width * p;
      fillRect = fillFromStart
          ? Rect.fromLTWH(band.left, band.top, w, band.height)
          : Rect.fromLTWH(band.right - w, band.top, w, band.height);
    }
    final paint = Paint();
    if (gradient != null) {
      paint.shader = gradient!.createShader(band);
    } else {
      paint.color = color;
    }
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(fillRect, paint);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final track = trackRRect(size);
    paintTrack(canvas, track);
    paintFill(canvas, track, size);
  }

  @override
  bool shouldRepaint(BarPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.borderRadius != borderRadius ||
      old.borderRadiusGeometry != borderRadiusGeometry ||
      old.gradient != gradient ||
      old.trackGradient != trackGradient ||
      old.fillFromStart != fillFromStart ||
      old.trackHeight != trackHeight ||
      old.showTrack != showTrack ||
      old.vertical != vertical;
}
