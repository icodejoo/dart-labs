import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_builder.dart';
import 'providers.dart';
import 'ring_style.dart';
import 'progress_display.dart';
import 'style_support.dart';

export 'ring_style.dart' show RingCountdownStyle;

/// A circular arc countdown display. Composes [CountdownBuilder].
///
/// The ring depletes from full as time elapses. Progress = remaining / total.
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// Visual appearance is configured via [style] ([RingCountdownStyle]).
///
/// ```dart
/// RingCountdown(
///   to: const Duration(minutes: 5),
///   style: const RingCountdownStyle(size: 80),
///   center: TextCountdown(to: const Duration(minutes: 5)),
/// )
/// ```
class RingCountdown extends StatelessWidget {
  const RingCountdown({
    super.key,
    required this.to,
    this.style,
    this.center,
    this.repaintBoundary,
    this.painterBuilder,
    this.plugin,
    this.controller,
    this.onComplete,
    this.onTick,
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

  /// Visual style. Merged over the enclosing [CountdownProvider]'s defaults.
  ///
  /// 视觉样式。叠加在所在 [CountdownProvider] 的默认值之上。
  final RingCountdownStyle? style;

  /// Optional widget rendered in the center of the ring.
  final Widget? center;

  /// Wraps in [RepaintBoundary]. Falls back to the provider, then `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in ring painter. All [style] visuals are ignored then.
  final CustomPainter Function(BuildContext context, double progress)? painterBuilder;

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onComplete;

  /// Called every tick with the current remaining [TimeParts].
  ///
  /// 每 tick 以当前剩余 [TimeParts] 回调。
  final void Function(TimeParts parts)? onTick;

  /// When remaining first drops to or below this, [onThreshold] fires once.
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
    final scope = CountmanScope.maybeOf<Countdown>(context);
    final effStyle = (style ?? const RingCountdownStyle()).merge(scope?.ringCountdownStyle);
    final effSize = effStyle.size ?? 80.0;
    final colors = resolveProgressColors(
      context,
      color: effStyle.color,
      trackColor: effStyle.trackColor,
      scopeColor: scope?.color,
      scopeTrackColor: scope?.trackColor,
    );
    final effRepaint = repaintBoundary ?? scope?.repaintBoundary ?? true;

    // Center overlay is value-independent — build once and pass through the
    // builder's child slot so the per-tick repaint skips it.
    //
    // 中心叠层不依赖值——只建一次，经 builder 的 child 槽透传，使每 tick 重绘跳过它。
    final centerChild = center != null
        ? SizedBox.square(
            dimension: effSize,
            child: Align(
              alignment: effStyle.centerAlignment ?? Alignment.center,
              child: center,
            ),
          )
        : null;

    final driver = CountdownBuilder(
      to: to,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      onComplete: onComplete,
      onTick: onTick,
      threshold: threshold,
      onThreshold: onThreshold,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      onPause: onPause,
      onResume: onResume,
      child: centerChild,
      builder: (ctx, p, centerWidget) {
        final progress = p.progress;
        return buildProgressPaint(
          size: Size.square(effSize),
          progress: progress,
          painter: painterBuilder != null
              ? painterBuilder!(ctx, progress)
              : ringPainterFrom(effStyle,
                  progress: progress,
                  color: colors.fill,
                  trackColor: colors.track,
                  // Countdown depletes: pin the arc's far end so the empty gap
                  // opens at 12 o'clock and sweeps clockwise. A leading thumb
                  // dot (on by default here, off/customizable via style) rides
                  // the depleting edge so even a slow long countdown visibly
                  // moves every tick while keeping rounded ends.
                  //
                  // 倒计时递减：锚定弧远端，使空缺从 12 点顺时针扫过。前导游标圆点
                  // （此处默认开，可经 style 关闭/定制）骑在递减边缘，使即便缓慢的
                  // 长倒计时也每 tick 明显移动，同时保留圆头。
                  anchorAtEnd: true,
                  defaultShowThumb: true),
          paintChild: centerWidget,
        );
      },
    );

    // Box layer (padding + decoration) is value-independent — wrap ONCE outside
    // the per-tick builder; RepaintBoundary (if any) is the outermost layer.
    //
    // 盒层（padding + decoration）不依赖值——在每 tick 的 builder 外只包一次；
    // RepaintBoundary（若有）为最外层。
    final decorated =
        applyBoxStyle(driver, padding: effStyle.padding, decoration: effStyle.decoration);
    return effRepaint ? RepaintBoundary(child: decorated) : decorated;
  }
}
