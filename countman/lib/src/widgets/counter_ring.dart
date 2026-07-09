import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:countman/src/counter/plugin.dart';
import 'counter_builder.dart';
import 'painter/ring_painter.dart';
import 'providers.dart';

/// A circular arc count-up display — the fill-toward-a-goal counterpart to
/// [CountdownRing]'s deplete-to-zero. Progress = `(value - from) / (to - from)`.
///
/// Composes [CounterBuilder] for the animation drive; this widget only maps
/// the value to arc progress and paints it.
///
/// ```dart
/// CounterRing(
///   to: 100,
///   size: 80,
///   center: CounterText(to: 100, suffix: '%'),
/// )
/// ```
///
/// For large numbers of concurrent instances set [repaintBoundary] = false.
class CounterRing extends StatelessWidget {
  const CounterRing({
    super.key,
    this.from,
    required this.to,
    this.duration,
    this.curve,
    this.allowNegative,
    this.plugin,
    this.controller,
    this.size = 80.0,
    this.strokeWidth = 8.0,
    this.trackStrokeWidth,
    this.color,
    this.trackColor,
    this.gradient,
    this.trackGradient,
    this.startAngle = -math.pi / 2,
    this.strokeCap = StrokeCap.round,
    this.padding = EdgeInsets.zero,
    this.center,
    this.clockwise = true,
    this.repaintBoundary,
    this.painterBuilder,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
  });

  /// Start value. Defaults to 0.
  final double? from;

  /// Target value the arc fills toward.
  final double to;

  /// Animation duration. Falls back to the [CounterProvider], then to 1000ms.
  final Duration? duration;

  /// Easing curve. Falls back to the provider, then to [Curves.easeOut].
  final Curve? curve;

  /// When `false` (default) the value never goes below 0. Set `true` to
  /// allow negative targets/values. Falls back to the provider.
  final bool? allowNegative;

  /// Optional [Counter] group for isolation. Defaults to the shared instance.
  final Counter? plugin;

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterController? controller;

  final double size;
  final double strokeWidth;

  /// Track stroke width. Defaults to [strokeWidth] when null.
  final double? trackStrokeWidth;

  /// Arc color. Defaults to the theme's `colorScheme.primary`.
  final Color? color;

  /// Track (background circle) color. Defaults to a muted theme color.
  final Color? trackColor;

  /// Optional arc gradient, overriding [color].
  final Gradient? gradient;

  /// Optional track gradient, overriding [trackColor].
  final Gradient? trackGradient;

  /// Angle (radians) the arc starts from. Default: 12 o'clock.
  final double startAngle;

  /// Cap drawn at the arc ends. Default: [StrokeCap.round].
  final StrokeCap strokeCap;

  /// Inset applied before the ring is laid out within [size].
  final EdgeInsets padding;

  /// Optional widget rendered in the center of the ring.
  final Widget? center;

  /// Arc direction. True = clockwise (default).
  final bool clockwise;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  /// Falls back to the provider, then to `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in [RingPainter]. All style parameters above are ignored then.
  final CustomPainter Function(BuildContext context, double progress)? painterBuilder;

  /// Called every frame with the raw animated value.
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  /// Lifecycle callbacks: enqueued / first frame / cancelled before completion.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final from = this.from ?? 0;
    final span = to - from;
    final scheme = Theme.of(context).colorScheme;
    // Resolve unset values from the nearest CounterProvider, then defaults.
    final scope = CountmanScope.maybeOf<Counter>(context);
    final arcColor = color ?? scope?.color ?? scheme.primary;
    final track = trackColor ?? scope?.trackColor ?? scheme.onSurface.withValues(alpha: 0.12);

    return CounterBuilder(
      from: this.from,
      to: to,
      duration: duration ?? scope?.duration ?? const Duration(milliseconds: 1000),
      curve: curve ?? scope?.curve ?? Curves.easeOut,
      allowNegative: allowNegative ?? scope?.allowNegative ?? false,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      repaintBoundary: repaintBoundary ?? scope?.repaintBoundary ?? true,
      onUpdate: onUpdate,
      onComplete: onComplete,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      builder: (ctx, v, __) {
        final progress = span != 0 ? ((v - from) / span).clamp(0.0, 1.0) : 1.0;
        return Semantics(
          container: true,
          value: '${(progress * 100).round()}%',
          child: CustomPaint(
            size: Size.square(size),
            painter: painterBuilder != null
                ? painterBuilder!(ctx, progress)
                : RingPainter(
                    progress: progress,
                    color: arcColor,
                    trackColor: track,
                    strokeWidth: strokeWidth,
                    trackStrokeWidth: trackStrokeWidth,
                    clockwise: clockwise,
                    startAngle: startAngle,
                    strokeCap: strokeCap,
                    gradient: gradient,
                    trackGradient: trackGradient,
                    padding: padding,
                  ),
            child: center != null
                ? SizedBox.square(dimension: size, child: Center(child: center))
                : null,
          ),
        );
      },
    );
  }
}
