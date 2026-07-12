import 'package:flutter/widgets.dart';
import 'package:countman/src/counter/plugin.dart';
import 'counter_builder.dart';
import 'providers.dart';
import 'ring_style.dart';
import 'progress_display.dart';
import 'style_support.dart';

export 'ring_style.dart' show RingCounterStyle;

/// A circular arc counter display — the fill-toward-a-goal counterpart to
/// `RingCountdown`. Progress = `(value - from) / (to - from)`.
///
/// Composes [CounterBuilder] for the animation drive; visual appearance is
/// configured via [style] ([RingCounterStyle]).
///
/// ```dart
/// RingCounter(
///   to: 100,
///   style: const RingCounterStyle(size: 80),
///   center: TextCounter(to: 100, suffix: '%'),
/// )
/// ```
class RingCounter extends StatelessWidget {
  const RingCounter({
    super.key,
    this.from,
    required this.to,
    this.duration,
    this.curve,
    this.allowNegative,
    this.plugin,
    this.controller,
    this.style,
    this.center,
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

  /// When `false` (default) the value never goes below 0. Falls back to provider.
  final bool? allowNegative;

  /// Optional [Counter] group for isolation. Defaults to the shared instance.
  final Counter? plugin;

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterValueController? controller;

  /// Visual style. Merged over the enclosing [CounterProvider]'s defaults.
  ///
  /// 视觉样式。叠加在所在 [CounterProvider] 的默认值之上。
  final RingCounterStyle? style;

  /// Optional widget rendered in the center of the ring.
  final Widget? center;

  /// Wraps in [RepaintBoundary]. Falls back to the provider, then `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in ring painter. All [style] visuals are ignored then.
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
    final scope = CountmanScope.maybeOf<Counter>(context);
    final effStyle = (style ?? const RingCounterStyle()).merge(scope?.ringCounterStyle);
    final effSize = effStyle.size ?? 80.0;
    final colors = resolveProgressColors(
      context,
      color: effStyle.color,
      trackColor: effStyle.trackColor,
      scopeColor: scope?.color,
      scopeTrackColor: scope?.trackColor,
    );

    // Center overlay doesn't depend on the animated value — build it once and
    // pass as the builder's child so each frame's rebuild skips it.
    //
    // 中心叠层不依赖动画值——只建一次并作为 builder 的 child 传入，使每帧重建跳过它。
    final centerChild = center != null
        ? SizedBox.square(
            dimension: effSize,
            child: Align(
              alignment: effStyle.centerAlignment ?? Alignment.center,
              child: center,
            ),
          )
        : null;

    // Box layer (padding + decoration) is value-independent — wrap it ONCE
    // around the builder so the per-tick rebuild never touches it.
    //
    // 盒层（padding + decoration）不依赖值——在 builder 外只包一次，使每 tick 重建
    // 不碰它。
    final core = CounterBuilder(
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
      child: centerChild,
      builder: (ctx, v, centerWidget) {
        final progress = span != 0 ? ((v - from) / span).clamp(0.0, 1.0) : 1.0;
        return buildProgressPaint(
          size: Size.square(effSize),
          progress: progress,
          painter: painterBuilder != null
              ? painterBuilder!(ctx, progress)
              : ringPainterFrom(effStyle,
                  progress: progress, color: colors.fill, trackColor: colors.track),
          paintChild: centerWidget,
        );
      },
    );
    return applyBoxStyle(core, padding: effStyle.padding, decoration: effStyle.decoration);
  }
}
