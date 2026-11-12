import 'package:flutter/foundation.dart' show ValueListenable;
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

/// Wires the per-tick progress paint scaffold shared by RingCounter/Bar and
/// RingCountdown/Bar: a percentage [Semantics] wrapper around a [CustomPaint].
///
/// This is the ONLY value-dependent part, so it belongs inside the per-tick
/// builder. The value-independent box layer (padding + decoration via
/// `applyBoxStyle`) and any [RepaintBoundary] are intentionally left to the
/// caller to wrap ONCE outside the builder — keeping them off the per-tick
/// rebuild path.
///
/// 接线 RingCounter/Bar 与 RingCountdown/Bar 共用的每 tick 进度绘制脚手架：包裹
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

/// 进度来源的换算视图：监听原始值（数值或 `TimeParts`），换算成 0–1 进度，
/// 并按整数百分比去抖，供常驻 painter 与语义使用。
///
/// 自身是 [ValueListenable]，每次原始值通知时原地更新 [value] 并通知监听者（即
/// painter 的 repaint 源），不分配对象。
class _ProgressView<T> extends ChangeNotifier implements ValueListenable<double> {
  /// 绑定原始值来源 [source] 与换算函数 [toProgress]，并立即换算一次初值。
  _ProgressView(this._source, this._toProgress) {
    _progress = _toProgress(_source.value);
    percent = ValueNotifier<int>((_progress * 100).round());
    _source.addListener(_onSource);
  }

  /// 原始值来源。
  ValueListenable<T> _source;

  /// 原始值 → 0–1 进度的换算函数。
  double Function(T value) _toProgress;

  /// 最近一次换算出的进度。
  late double _progress;

  /// 整数百分比；只在百分比整数变化时通知，驱动 Semantics。
  late final ValueNotifier<int> percent;

  @override
  double get value => _progress;

  /// 原始值变化：换算、更新百分比并通知 painter。
  void _onSource() {
    _progress = _toProgress(_source.value);
    percent.value = (_progress * 100).round();
    notifyListeners();
  }

  /// 换绑来源或换算函数；进度因此变化时通知 painter 重绘。
  void rebind(ValueListenable<T> source, double Function(T value) toProgress) {
    if (!identical(source, _source)) {
      _source.removeListener(_onSource);
      _source = source;
      _source.addListener(_onSource);
    }
    _toProgress = toProgress;
    final next = toProgress(source.value);
    if (next == _progress) return;
    _progress = next;
    percent.value = (next * 100).round();
    notifyListeners();
  }

  /// 解除对来源的监听并释放通知器。
  @override
  void dispose() {
    _source.removeListener(_onSource);
    percent.dispose();
    super.dispose();
  }
}

/// 常驻 painter 的进度绘制：painter 随组件生命周期创建，进度通过 `repaint` 监听原地更新，
/// 不随进度逐帧新建 painter / Semantics / 百分比字符串。
///
/// [source] 推送原始值（计数值或 `TimeParts`），[toProgress] 把它换算成 0–1；
/// [painterFactory] 收到可监听的进度，应把它交给 painter 的 `progressListenable`。
/// [configKey] 是视觉配置的值相等键（样式、颜色、文字方向等）：它变化时才重建 painter，
/// 其余重建复用同一个实例。Semantics 的百分比只在整数百分比变化时重建。
///
/// 示例：
/// ```dart
/// ResidentProgressPaint<double>(
///   source: value, toProgress: (v) => v / 100, size: const Size.square(80),
///   configKey: (style, color),
///   painterFactory: (progress) => ringPainterFrom(style,
///       progressListenable: progress, color: color, trackColor: track),
/// )
/// ```
class ResidentProgressPaint<T> extends StatefulWidget {
  /// 创建常驻进度绘制；[child] 绘制在 painter 之上（如环形中心）。
  const ResidentProgressPaint({
    super.key,
    required this.source,
    required this.toProgress,
    required this.size,
    required this.configKey,
    required this.painterFactory,
    this.child,
  });

  /// 原始值来源。
  final ValueListenable<T> source;

  /// 原始值 → 0–1 进度的换算函数。
  final double Function(T value) toProgress;

  /// 绘制尺寸。
  final Size size;

  /// 视觉配置的值相等键；变化时重建 painter。
  final Object? configKey;

  /// 用可监听的进度创建 painter。
  final CustomPainter Function(ValueListenable<double> progress) painterFactory;

  /// 绘制在 painter 之上的子组件。
  final Widget? child;

  @override
  State<ResidentProgressPaint<T>> createState() =>
      _ResidentProgressPaintState<T>();
}

/// 持有常驻 painter 与进度视图。
class _ResidentProgressPaintState<T> extends State<ResidentProgressPaint<T>> {
  /// 进度换算视图，生命周期与本 State 一致。
  late final _ProgressView<T> _view;

  /// 常驻 painter；仅在 [ResidentProgressPaint.configKey] 变化时重建。
  late CustomPainter _painter;

  @override
  void initState() {
    super.initState();
    _view = _ProgressView<T>(widget.source, widget.toProgress);
    _painter = widget.painterFactory(_view);
  }

  @override
  void didUpdateWidget(ResidentProgressPaint<T> old) {
    super.didUpdateWidget(old);
    _view.rebind(widget.source, widget.toProgress);
    if (old.configKey != widget.configKey) {
      _painter = widget.painterFactory(_view);
    }
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _view.percent,
      child: CustomPaint(
        size: widget.size,
        painter: _painter,
        child: widget.child,
      ),
      builder: (_, percent, child) =>
          Semantics(container: true, value: '$percent%', child: child),
    );
  }
}
