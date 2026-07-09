import 'package:flutter/material.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_widget.dart';
import 'painter/bar_painter.dart';

/// A linear progress-bar countdown display. Composes [CountdownWidget].
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
    this.color,
    this.trackColor,
    this.borderRadius = const Radius.circular(4),
    this.repaintBoundary = true,
    this.plugin,
    this.controller,
    this.onComplete,
    this.threshold,
    this.onThreshold,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final Object to;

  final double width;
  final double height;

  /// Fill color. Defaults to the theme's `colorScheme.primary`.
  final Color? color;

  /// Track (background) color. Defaults to a muted theme color.
  final Color? trackColor;
  final Radius borderRadius;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onComplete;

  /// When remaining first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check.
  final Duration? threshold;

  /// Called once when remaining crosses [threshold].
  final void Function()? onThreshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? scheme.primary;
    final track = trackColor ?? scheme.onSurface.withValues(alpha: 0.12);

    return CountdownWidget(
      to: to,
      plugin: plugin,
      controller: controller,
      onComplete: onComplete,
      threshold: threshold,
      onThreshold: onThreshold,
      builder: (_, p) {
        final progress = p.progress;
        final bar = Semantics(
          container: true,
          value: '${(progress * 100).round()}%',
          child: CustomPaint(
            size: Size(width, height),
            painter: BarPainter(
              progress: progress,
              color: fill,
              trackColor: track,
              borderRadius: borderRadius,
            ),
          ),
        );
        return repaintBoundary ? RepaintBoundary(child: bar) : bar;
      },
    );
  }
}
