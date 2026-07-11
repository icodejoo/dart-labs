import 'package:flutter/material.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_widget.dart';
import 'painter/bar_painter.dart';
import 'providers.dart';

/// A linear progress-bar countdown display. Composes [CountdownBuilder].
///
/// The bar shrinks from full as time elapses. Progress = remaining / total,
/// where `total` is the initial remaining duration captured at start. Same
/// underlying model as [CountdownRing] — pick whichever shape fits.
///
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// ```dart
/// CountdownBar(to: const Duration(minutes: 5), width: 240)
/// ```
///
/// For large numbers of concurrent instances set [repaintBoundary] = false.
class CountdownBar extends StatelessWidget {
  const CountdownBar({
    super.key,
    required this.to,
    this.width = 200.0,
    this.height = 8.0,
    this.trackHeight,
    this.color,
    this.trackColor,
    this.gradient,
    this.trackGradient,
    this.borderRadius = const Radius.circular(4),
    this.borderRadiusGeometry,
    this.fillFromStart = true,
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

  final double width;
  final double height;

  /// Track/fill height, vertically centered within [height]. Defaults to
  /// [height] when null.
  final double? trackHeight;

  /// Fill color. Defaults to the theme's `colorScheme.primary`.
  final Color? color;

  /// Track (background) color. Defaults to a muted theme color.
  final Color? trackColor;

  /// Optional fill gradient, overriding [color].
  final Gradient? gradient;

  /// Optional track gradient, overriding [trackColor].
  final Gradient? trackGradient;

  /// Uniform corner radius. Ignored when [borderRadiusGeometry] is set.
  final Radius borderRadius;

  /// Optional per-corner radius, overriding the uniform [borderRadius].
  final BorderRadius? borderRadiusGeometry;

  /// When true (default) the fill anchors at the start edge; false = end edge.
  final bool fillFromStart;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  /// Falls back to the provider, then to `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in [BarPainter]. All style parameters above are ignored then.
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
    final fill = color ?? scope?.color ?? scheme.primary;
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
        final bar = Semantics(
          container: true,
          value: '${(progress * 100).round()}%',
          child: CustomPaint(
            size: Size(width, height),
            painter: painterBuilder != null
                ? painterBuilder!(ctx, progress)
                : BarPainter(
                    progress: progress,
                    color: fill,
                    trackColor: track,
                    borderRadius: borderRadius,
                    borderRadiusGeometry: borderRadiusGeometry,
                    gradient: gradient,
                    trackGradient: trackGradient,
                    fillFromStart: fillFromStart,
                    trackHeight: trackHeight,
                  ),
          ),
        );
        return effRepaint ? RepaintBoundary(child: bar) : bar;
      },
    );
  }
}
