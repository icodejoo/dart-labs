import 'package:flutter/material.dart';
import 'package:countman/src/counter/plugin.dart';
import 'counter_builder.dart';
import 'painter/ring_painter.dart';

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
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.size = 80.0,
    this.strokeWidth = 8.0,
    this.color,
    this.trackColor,
    this.center,
    this.clockwise = true,
    this.repaintBoundary = true,
    this.onComplete,
  });

  /// Start value. Defaults to 0.
  final double? from;

  /// Target value the arc fills toward.
  final double to;

  final Duration duration;
  final Curve curve;

  /// When `false` (default) the value never goes below 0. Set `true` to
  /// allow negative targets/values.
  final bool allowNegative;

  /// Optional [Counter] group for isolation. Defaults to the shared instance.
  final Counter? plugin;

  final double size;
  final double strokeWidth;

  /// Arc color. Defaults to the theme's `colorScheme.primary`.
  final Color? color;

  /// Track (background circle) color. Defaults to a muted theme color.
  final Color? trackColor;

  /// Optional widget rendered in the center of the ring.
  final Widget? center;

  /// Arc direction. True = clockwise (default).
  final bool clockwise;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  @override
  Widget build(BuildContext context) {
    final from = this.from ?? 0;
    final span = to - from;
    final scheme = Theme.of(context).colorScheme;
    final arcColor = color ?? scheme.primary;
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
            size: Size.square(size),
            painter: RingPainter(
              progress: progress,
              color: arcColor,
              trackColor: track,
              strokeWidth: strokeWidth,
              clockwise: clockwise,
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
