import 'package:flutter/widgets.dart';
import 'package:countman/src/counter/plugin.dart';
import 'countman_theme.dart';
import 'counter_builder.dart';
import 'animate_once.dart';
import 'providers.dart';
import 'bar_style.dart';
import 'progress_display.dart';
import 'style_support.dart';

export 'bar_style.dart' show BarCounterStyle;

/// A linear progress-bar counter display — the fill-toward-a-goal counterpart
/// to `BarCountdown`. Progress = `(value - from) / (to - from)`.
///
/// Composes [CounterBuilder]; visual appearance via [style] ([BarCounterStyle]).
///
/// ```dart
/// BarCounter(to: 100, style: const BarCounterStyle(width: 240))
/// ```
/// 条形计数器，支持首次播放策略与竖向默认尺寸。
class BarCounter extends StatelessWidget {
  /// 创建进度计数器；animateOnce 可选覆盖 provider 的首次播放策略。
  const BarCounter({
    super.key,
    this.from,
    required this.to,
    this.duration,
    this.curve,
    this.allowNegative,
    this.plugin,
    this.controller,
    this.animateOnce,
    this.style,
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

  /// When `false` (default) the value never goes below 0. Falls back to provider.
  final bool? allowNegative;

  /// Optional [Counter] group for isolation. Defaults to the shared instance.
  final Counter? plugin;

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterValueController? controller;

  /// 是否仅首次入场播放；null 继承 CounterProvider，false 始终播放。
  /// 配合稳定 ValueKey 使用，例如 `BarCounter(key: ValueKey('score'), to: 10, animateOnce: true)`。
  /// 再次挂载直接显示目标值，controller.value 同步为该显示值。
  final bool? animateOnce;

  /// Visual style. Merged over the enclosing [CounterProvider]'s defaults.
  ///
  /// 视觉样式。叠加在所在 [CounterProvider] 的默认值之上。
  final BarCounterStyle? style;

  /// Wraps in [RepaintBoundary]. Falls back to the provider, then `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in bar painter. All [style] visuals are ignored then.
  final CustomPainter Function(BuildContext context, double progress)?
      painterBuilder;

  /// Called every frame with the raw animated value.
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  /// Lifecycle callbacks: enqueued / first frame / cancelled before completion.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  /// 解析样式、方向与稳定身份，并构建进度展示。
  @override
  Widget build(BuildContext context) {
    final from = this.from ?? 0;
    final span = to - from;
    final scope = CountmanScope.maybeOf<Counter>(context);
    final effStyle = (style ?? const BarCounterStyle())
        .merge(scope?.barCounterStyle)
        .merge(CountmanTheme.maybeOf(context)?.barCounterStyle);
    final effW = effStyle.width ??
        (effStyle.vertical == true ? defaultBarThickness : defaultBarLength);
    final effH = effStyle.height ??
        (effStyle.vertical == true ? defaultBarLength : defaultBarThickness);
    final colors = resolveProgressColors(
      context,
      color: effStyle.color,
      trackColor: effStyle.trackColor,
      scopeColor: scope?.color,
      scopeTrackColor: scope?.trackColor,
    );

    // Box layer is value-independent — wrap it ONCE around the builder.
    //
    // 盒层不依赖值——在 builder 外只包一次。
    final core = CounterBuilder(
      from: this.from,
      to: to,
      duration:
          duration ?? scope?.duration ?? const Duration(milliseconds: 1000),
      curve: curve ?? scope?.curve ?? Curves.easeOut,
      allowNegative: allowNegative ?? scope?.allowNegative ?? false,
      plugin: plugin,
      controller: controller,
      animateOnce: animateOnce,
      onceId: stableOnceIdFromKey(key),
      repaintBoundary: repaintBoundary ?? scope?.repaintBoundary ?? true,
      onUpdate: onUpdate,
      onComplete: onComplete,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      builder: (ctx, v, __) {
        final progress = span != 0 ? ((v - from) / span).clamp(0.0, 1.0) : 1.0;
        return buildProgressPaint(
          size: Size(effW, effH),
          progress: progress,
          painter: painterBuilder != null
              ? painterBuilder!(ctx, progress)
              : barPainterFrom(effStyle,
                  textDirection: Directionality.maybeOf(context),
                  progress: progress,
                  color: colors.fill,
                  trackColor: colors.track),
        );
      },
    );
    return applyBoxStyle(core,
        padding: effStyle.padding, decoration: effStyle.decoration);
  }
}
