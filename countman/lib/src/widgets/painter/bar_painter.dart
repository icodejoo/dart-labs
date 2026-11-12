import 'package:flutter/foundation.dart' show ValueListenable;
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
  /// 创建进度画笔；方向性渐变需传 textDirection，如 TextDirection.rtl。
  ///
  /// 常驻用法：传 [progressListenable]，画笔随组件生命周期只创建一次，进度变化
  /// 通过它触发重绘（repaint）并在绘制时原地读取，不再每帧新建画笔。
  const BarPainter({
    required double progress,
    required this.color,
    required this.trackColor,
    this.borderRadius = const Radius.circular(4),
    this.borderRadiusGeometry,
    this.gradient,
    this.trackGradient,
    this.textDirection,
    this.fillFromStart = true,
    this.trackHeight,
    this.showTrack = true,
    this.vertical = false,
    this.progressListenable,
  })  : _progress = progress,
        super(repaint: progressListenable);

  /// 构造时给定的静态进度，[progressListenable] 为空时使用。
  final double _progress;

  /// 可选的进度来源：非空时画笔以它的值为进度，并在它通知时重绘（作为 repaint 源）。
  /// 例如 `BarPainter(progress: 0, progressListenable: notifier, ...)`。
  final ValueListenable<double>? progressListenable;

  /// 0.0–1.0 fraction of the bar to fill. 有 [progressListenable] 时读取它的当前值。
  double get progress => progressListenable?.value ?? _progress;
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

  /// 渐变的文字方向；默认 null，使用方向性 Alignment 时需显式提供。
  /// 例如 `textDirection: TextDirection.rtl`，仅影响渐变解析。
  final TextDirection? textDirection;

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

  /// 绘制背景轨道，并用 textDirection 解析方向性渐变。
  void paintTrack(Canvas canvas, RRect track) {
    if (!showTrack) return;
    final paint = Paint();
    if (trackGradient != null) {
      paint.shader = trackGradient!
          .createShader(track.outerRect, textDirection: textDirection);
    } else {
      paint.color = trackColor;
    }
    canvas.drawRRect(track, paint);
  }

  /// 在轨道内绘制进度填充，并用 textDirection 解析方向性渐变。
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
      paint.shader = gradient!.createShader(band, textDirection: textDirection);
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

  /// 方向或视觉配置改变时重新绘制。
  @override
  bool shouldRepaint(BarPainter old) =>
      old.textDirection != textDirection ||
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
