import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_widget.dart';
import 'painter/ring_painter.dart';
import 'providers.dart';

/// A circular arc countdown display. Composes [CountdownBuilder].
///
/// The ring depletes from full as time elapses.
/// Progress = remaining / total, where `total` is the initial remaining
/// duration captured when the timer started.
///
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// ```dart
/// CountdownRing(
///   to: const Duration(minutes: 5),
///   size: 80,
///   center: CountdownText(to: const Duration(minutes: 5)),
/// )
/// ```
///
/// For large numbers of concurrent instances set [repaintBoundary] = false.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.to,
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
    this.plugin,
    this.controller,
    this.onComplete,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final Object to;

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

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onComplete;

  /// When remaining first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check.
  final Duration? threshold;

  /// Called once when remaining crosses [threshold].
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Resolve unset values from the nearest CountdownProvider.
    final scope = CountmanScope.maybeOf<Countdown>(context);
    final arcColor = color ?? scope?.color ?? scheme.primary;
    final track = trackColor ?? scope?.trackColor ?? scheme.onSurface.withValues(alpha: 0.12);
    final effRepaint = repaintBoundary ?? scope?.repaintBoundary ?? true;

    return CountdownBuilder(
      to: to,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      onComplete: onComplete,
      threshold: threshold,
      onThreshold: onThreshold,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      onPause: onPause,
      onResume: onResume,
      builder: (ctx, p) {
        final progress = p.progress;
        final ring = Semantics(
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
        return effRepaint ? RepaintBoundary(child: ring) : ring;
      },
    );
  }
}
