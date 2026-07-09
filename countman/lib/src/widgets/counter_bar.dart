import 'package:flutter/material.dart';
import 'package:countman/src/counter/plugin.dart';
import 'counter_builder.dart';
import 'painter/bar_painter.dart';
import 'providers.dart';

/// A linear progress-bar count-up display — the fill-toward-a-goal
/// counterpart to [CountdownBar]'s deplete-to-zero. Same underlying model
/// as [CounterRing]; pick whichever shape fits the layout.
///
/// Progress = `(value - from) / (to - from)`. Composes [CounterBuilder].
///
/// ```dart
/// CounterBar(to: 100, width: 240)
/// ```
///
/// For large numbers of concurrent instances set [repaintBoundary] = false.
class CounterBar extends StatelessWidget {
  const CounterBar({
    super.key,
    this.from,
    required this.to,
    this.duration,
    this.curve,
    this.allowNegative,
    this.plugin,
    this.controller,
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
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
  });

  /// Start value. Defaults to 0.
  final double? from;

  /// Target value the bar fills toward.
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

  /// When true (default) the fill grows from the start edge; false = end edge.
  final bool fillFromStart;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  /// Falls back to the provider, then to `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in [BarPainter]. All style parameters above are ignored then.
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
    final fill = color ?? scope?.color ?? scheme.primary;
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
      },
    );
  }
}
