import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_builder.dart';
import 'countman_theme.dart';
import 'providers.dart';
import 'bar_style.dart';
import 'progress_display.dart';
import 'style_support.dart';

export 'bar_style.dart' show BarCountdownStyle;

/// A linear progress-bar countdown display. Composes [CountdownBuilder].
///
/// The bar shrinks from full as time elapses. Progress = remaining / total.
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// Visual appearance via [style] ([BarCountdownStyle]).
///
/// ```dart
/// BarCountdown(to: const Duration(minutes: 5), style: const BarCountdownStyle(width: 240))
/// ```
class BarCountdown extends StatelessWidget {
  const BarCountdown({
    super.key,
    required this.to,
    this.style,
    this.repaintBoundary,
    this.painterBuilder,
    this.plugin,
    this.total,
    this.rounding = CountdownRounding.floor,
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
  final BarCountdownStyle? style;

  /// Wraps in [RepaintBoundary]. Falls back to the provider, then `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current 0–1 progress, replacing
  /// the built-in bar painter. All [style] visuals are ignored then.
  final CustomPainter Function(BuildContext context, double progress)?
      painterBuilder;

  final Countdown? plugin;

  /// 进度分母；为空时沿用挂载那一刻的剩余时间。例如拍卖整段时长：
  /// `to: end, total: end.difference(start)`。详见 [CountdownBuilder.total]。
  final Duration? total;

  /// 显示取整方式，默认 [CountdownRounding.floor]；[CountdownRounding.ceil] 让
  /// 剩余 9.3 秒显示 10。详见 [CountdownBuilder.rounding]。
  final CountdownRounding rounding;
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

  /// 剩余时间换算的 0–1 进度（剩余 / 分母）。
  static double _progressOf(TimeParts p) => p.progress;

  /// 解析样式、方向与稳定身份，并构建进度展示。
  @override
  Widget build(BuildContext context) {
    final scope = CountmanScope.maybeOf<Countdown>(context);
    final effStyle = (style ?? const BarCountdownStyle())
        .merge(scope?.barCountdownStyle)
        .merge(CountmanTheme.maybeOf(context)?.barCountdownStyle);
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
    final effRepaint = repaintBoundary ?? scope?.repaintBoundary ?? true;

    final dir = Directionality.maybeOf(context);
    final driver = CountdownBuilder.listenable(
      to: to,
      plugin: plugin,
      total: total,
      rounding: rounding,
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
      // 默认路径：painter 常驻，进度经 repaint 原地更新；自定义 painterBuilder 保持
      // 原有行为（每次进度变化调用一次）。
      listenableBuilder: (ctx, parts, _) {
        final custom = painterBuilder;
        if (custom != null) {
          return ValueListenableBuilder<TimeParts>(
            valueListenable: parts,
            builder: (ctx, p, _) {
              final progress = p.progress;
              return buildProgressPaint(
                size: Size(effW, effH),
                progress: progress,
                painter: custom(ctx, progress),
              );
            },
          );
        }
        return ResidentProgressPaint<TimeParts>(
          source: parts,
          toProgress: _progressOf,
          size: Size(effW, effH),
          configKey: (effStyle, colors.fill, colors.track, dir),
          painterFactory: (progress) => barPainterFrom(effStyle,
              textDirection: dir,
              progressListenable: progress,
              color: colors.fill,
              trackColor: colors.track),
        );
      },
    );

    // Box layer is value-independent — wrap ONCE outside the per-tick builder;
    // RepaintBoundary (if any) is the outermost layer.
    //
    // 盒层不依赖值——在每 tick 的 builder 外只包一次；RepaintBoundary（若有）为最外层。
    final decorated = applyBoxStyle(driver,
        padding: effStyle.padding, decoration: effStyle.decoration);
    return effRepaint ? RepaintBoundary(child: decorated) : decorated;
  }
}
