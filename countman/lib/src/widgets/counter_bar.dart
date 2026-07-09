import 'package:flutter/material.dart';
import 'package:countman/src/counter/plugin.dart';
import 'counter_builder.dart';
import 'painter/bar_painter.dart';

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
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.width = 200.0,
    this.height = 8.0,
    this.color,
    this.trackColor,
    this.borderRadius = const Radius.circular(4),
    this.repaintBoundary = true,
    this.onComplete,
  });

  /// Start value. Defaults to 0.
  final double? from;

  /// Target value the bar fills toward.
  final double to;

  final Duration duration;
  final Curve curve;

  /// When `false` (default) the value never goes below 0. Set `true` to
  /// allow negative targets/values.
  final bool allowNegative;

  /// Optional [Counter] group for isolation. Defaults to the shared instance.
  final Counter? plugin;

  final double width;
  final double height;

  /// Fill color. Defaults to the theme's `colorScheme.primary`.
  final Color? color;

  /// Track (background) color. Defaults to a muted theme color.
  final Color? trackColor;
  final Radius borderRadius;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  @override
  Widget build(BuildContext context) {
    final from = this.from ?? 0;
    final span = to - from;
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? scheme.primary;
    final track = trackColor ?? scheme.onSurface.withValues(alpha: 0.12);

    return CounterBuilder(
      from: this.from,
      to: to,
      duration: duration,
      curve: curve,
      allowNegative: allowNegative,
      plugin: plugin,
      repaintBoundary: repaintBoundary,
      onComplete: onComplete,
      builder: (_, v) {
        final progress = span != 0 ? ((v - from) / span).clamp(0.0, 1.0) : 1.0;
        return Semantics(
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
      },
    );
  }
}
