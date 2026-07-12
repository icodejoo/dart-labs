import 'package:flutter/material.dart';

/// Opacity of the muted default track (behind the progress fill) when no
/// explicit track color is given.
///
/// 未显式给定轨道色时，默认淡色轨道（进度填充背后）的不透明度。
const double kMutedTrackAlpha = 0.12;

/// The fill + track colors a progress display resolves to.
///
/// 进度显示解析出的填充色 + 轨道色。
typedef ProgressColors = ({Color fill, Color track});

/// Resolves the fill and track colors for ring/bar displays through the shared
/// fallback chain: explicit style → provider scalar → theme.
///
/// Centralizes the `?? scope?.color ?? scheme.primary` / muted-track fallback
/// (and the [kMutedTrackAlpha] magic number) that all four ring/bar widgets
/// used to repeat inline.
///
/// 通过共享回退链为环形/进度条显示解析填充色与轨道色：显式样式 → provider 标量 →
/// 主题。集中四个 ring/bar 组件过去各自内联重复的回退逻辑（及 [kMutedTrackAlpha]
/// 魔数）。
///
/// @param context Build context for [Theme] lookup.
///
///   用于查找 [Theme] 的 build 上下文。
///
/// @param color Style-resolved fill color (may be null).
///
///   样式解析出的填充色（可空）。
///
/// @param trackColor Style-resolved track color (may be null).
///
///   样式解析出的轨道色（可空）。
///
/// @param scopeColor Provider scalar fill fallback (may be null).
///
///   provider 标量填充回退（可空）。
///
/// @param scopeTrackColor Provider scalar track fallback (may be null).
///
///   provider 标量轨道回退（可空）。
///
/// @returns The resolved ([ProgressColors]) fill and track colors.
///
///   解析后的填充色与轨道色（[ProgressColors]）。
ProgressColors resolveProgressColors(
  BuildContext context, {
  Color? color,
  Color? trackColor,
  Color? scopeColor,
  Color? scopeTrackColor,
}) {
  final scheme = Theme.of(context).colorScheme;
  return (
    fill: color ?? scopeColor ?? scheme.primary,
    track: trackColor ??
        scopeTrackColor ??
        scheme.onSurface.withValues(alpha: kMutedTrackAlpha),
  );
}

/// Wires the per-tick progress paint scaffold shared by CounterRing/Bar and
/// CountdownRing/Bar: a percentage [Semantics] wrapper around a [CustomPaint].
///
/// This is the ONLY value-dependent part, so it belongs inside the per-tick
/// builder. The value-independent box layer (padding + decoration via
/// `applyBoxStyle`) and any [RepaintBoundary] are intentionally left to the
/// caller to wrap ONCE outside the builder — keeping them off the per-tick
/// rebuild path.
///
/// 接线 CounterRing/Bar 与 CountdownRing/Bar 共用的每 tick 进度绘制脚手架：包裹
/// [CustomPaint] 的百分比 [Semantics]。
///
/// 这是唯一依赖值的部分，故置于每 tick 的 builder 内。不依赖值的盒层（padding +
/// decoration，经 `applyBoxStyle`）与 [RepaintBoundary] 刻意留给调用方在 builder
/// 外只包一次——使其不在每 tick 重建路径上。
///
/// @param size Paint size (square for rings, W×H for bars).
///
///   绘制尺寸（环形为正方形，进度条为 宽×高）。
///
/// @param progress Current 0–1 fill fraction (drives the a11y percentage).
///
///   当前 0–1 填充比例（驱动无障碍百分比）。
///
/// @param painter The [CustomPainter] to render.
///
///   要渲染的 [CustomPainter]。
///
/// @param paintChild Optional child painted over the custom paint (e.g. a ring
///   center).
///
///   可选的绘制其上的子组件（如环形中心）。
///
/// @returns The semantics-wrapped paint widget (no box layer).
///
///   带无障碍语义的绘制 widget（不含盒层）。
Widget buildProgressPaint({
  required Size size,
  required double progress,
  required CustomPainter painter,
  Widget? paintChild,
}) {
  return Semantics(
    container: true,
    value: '${(progress * 100).round()}%',
    child: CustomPaint(size: size, painter: painter, child: paintChild),
  );
}
