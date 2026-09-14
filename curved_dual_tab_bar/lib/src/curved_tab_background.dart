part of 'curved_dual_tab_bar.dart';

/// Paint-and-animation-only primitive behind [CurvedDualTabBar]: renders the
/// three background layers (base fill, resting pill, S-curve split) and
/// drives a `0..1` progress value between [selectedIndex] `0`/`1`, but knows
/// nothing about tab labels, gestures or underlines — [builder] receives the
/// current progress `t` and returns whatever foreground the caller wants
/// (a custom `Row` of tabs, a real `TabBar`, anything), so it can compose
/// with any tab-selection widget instead of only [CurvedDualTabBar]'s own.
///
/// Set [animated] to `false` to skip the tween entirely: `t` jumps straight
/// to the target value on the next frame, no [duration]/[curve] involved.
///
/// [CurvedDualTabBar] 背后的纯绘制+动画组件：只画三层背景（底色、静态底板、
/// S 曲线分割），并在 [selectedIndex] 的 `0`/`1` 之间驱动一个 `0..1` 的进度值，
/// 完全不知道 tab 文案、手势、下划线这些——[builder] 拿到当前进度 `t`，
/// 自己决定画什么前景（自定义的 `Row` tabs、真正的 `TabBar`，都行），
/// 因此可以跟任意 tab 选择组件搭配，不局限于 [CurvedDualTabBar] 自带的那套。
///
/// [animated] 传 `false` 可以完全跳过补间动画：`t` 在下一帧直接跳到目标值，
/// 不走 [duration]/[curve]。
///
/// Example:
/// ```dart
/// CurvedTabBackground(
///   selectedIndex: selectedIndex,
///   builder: (context, t) => MyOwnTabRow(t: t),
/// )
/// ```
class CurvedTabBackground extends StatefulWidget {
  const CurvedTabBackground({
    super.key,
    required this.selectedIndex,
    this.builder,
    this.height = 56,
    this.borderRadius = 20,
    this.leanAmplitude = 0.1,
    this.backgroundColor = Colors.transparent,
    this.unselectedTopInset = 14,
    this.unselectedColor,
    this.unselectedBorderColor,
    this.unselectedBorderWidth = 1,
    this.activeColor,
    this.inactiveColor = Colors.transparent,
    this.activeGradient,
    this.inactiveGradient,
    this.dividerColor,
    this.dividerWidth = 1.5,
    this.dividerGradient,
    this.dividerCap = StrokeCap.butt,
    this.dividerShadow,
    this.topControlOffset = Offset.zero,
    this.bottomControlOffset = Offset.zero,
    this.activeBorderColor,
    this.inactiveBorderColor,
    this.splitBorderWidth = 1.5,
    this.duration = const Duration(milliseconds: 320),
    this.curve = Curves.easeInOutCubic,
    this.animated = true,
    this.progress,
    this.child,
  });

  /// Currently selected side, 0 or 1. Only used as the tween's target — the
  /// widget itself has no notion of tabs or selection changes. Ignored
  /// (except as the initial value) when [progress] is supplied.
  ///
  /// 当前选中的一侧，取值 0 或 1。只作为补间动画的目标值使用——组件本身
  /// 不知道什么是 tab 或选中态切换。提供了 [progress] 时此项被忽略
  /// （仅用作初始值）。
  final int selectedIndex;

  /// Drive `t` directly from an external `0..1` animation (e.g. a 2-tab
  /// `TabController.animation`) instead of tweening internally off
  /// [selectedIndex]. Use this to keep the background perfectly in sync
  /// with a real `TabBar`'s drag/swipe, rather than snapping only after
  /// [selectedIndex] changes at the end of its own transition.
  ///
  /// 直接用外部的 `0..1` 动画（比如 2 个 tab 的 `TabController.animation`）
  /// 驱动 `t`，而不是自己根据 [selectedIndex] 做补间。用它可以让背景跟真正
  /// `TabBar` 的拖拽/滑动保持完全同步，而不是等 [selectedIndex] 在动画
  /// 结束后才变化、才跟着动一次。
  final Animation<double>? progress;

  /// Builds the foreground given the current `0..1` progress between side 0
  /// and side 1 (mirrors [selectedIndex]'s animated value), plus [child]
  /// passed through unchanged — same caching trick as [AnimatedBuilder]:
  /// put any part of the foreground that doesn't depend on `t` into [child]
  /// instead of rebuilding it on every animation tick.
  ///
  /// Omit this entirely when the foreground doesn't depend on `t` at all —
  /// it then just renders [child] as-is, so you don't need to write a
  /// pass-through `(context, t, child) => child!`.
  ///
  /// 根据当前 0 到 1 侧之间的进度值（[selectedIndex] 的动画值）构建前景，
  /// 并原样收到 [child]——跟 [AnimatedBuilder] 一样的缓存手法：前景里不依赖
  /// `t` 的部分放进 [child]，而不是每帧都重新构建。
  ///
  /// 前景完全不依赖 `t` 时可以整个不传——这时直接渲染 [child]，不用自己写
  /// 一句透传的 `(context, t, child) => child!`。
  final Widget Function(
    BuildContext context,
    double animateValue,
    Widget? child,
  )?
  builder;

  /// Passed straight through to [builder] on every rebuild, without being
  /// rebuilt itself; rendered as-is if [builder] is omitted. See [builder].
  ///
  /// 每次重建时原样传给 [builder]，自己不会被重建；[builder] 缺省时直接
  /// 渲染这个值。见 [builder]。
  final Widget? child;

  /// Bar height.
  ///
  /// 整个背景的高度。
  final double height;

  /// Corner radius applied to the outer top-left/top-right corners of the
  /// whole bar, and to layer 2's own top corners. Bottom corners are always
  /// square.
  ///
  /// 整个背景外侧顶部两个角的圆角半径，也用于第 2 层自己的顶部圆角。
  /// 底部两个角始终是直角。
  final double borderRadius;

  /// How far the split curve's top/bottom endpoints lean away from the
  /// bar's horizontal center, as a fraction of its width. The curve is
  /// always centered — this only controls how wide its swing is, never
  /// its position.
  ///
  /// 分割曲线上下两端偏离水平中心的幅度，占宽度的比例。曲线始终以中心为
  /// 基准，这个值只控制摆动的宽度，不影响位置。
  final double leanAmplitude;

  /// Layer 1 (base) fill. Defaults to fully transparent.
  ///
  /// 第 1 层（底层）的填充色，默认全透明。
  final Color backgroundColor;

  /// How far layer 2's resting pill is inset from the top edge.
  ///
  /// 第 2 层静态底板距离顶部的缩进距离。
  final double unselectedTopInset;

  /// Layer 2's fill color. Defaults to `colorScheme.surfaceContainerHigh`.
  ///
  /// 第 2 层的填充色，默认取 `colorScheme.surfaceContainerHigh`。
  final Color? unselectedColor;

  /// Layer 2's border color. Defaults to `colorScheme.outlineVariant`.
  ///
  /// 第 2 层的边框色，默认取 `colorScheme.outlineVariant`。
  final Color? unselectedBorderColor;

  /// Layer 2's border width.
  ///
  /// 第 2 层的边框宽度。
  final double unselectedBorderWidth;

  /// Layer 3's fill color for whichever side is currently selected.
  /// Defaults to `colorScheme.surface`. Ignored if [activeGradient] is set.
  ///
  /// 第 3 层中，当前选中一侧的填充色，默认取 `colorScheme.surface`。
  /// 设置了 [activeGradient] 时此项被忽略。
  final Color? activeColor;

  /// Layer 3's fill color for whichever side is currently unselected.
  /// Defaults to fully transparent, letting layer 2 show through. Ignored
  /// if [inactiveGradient] is set.
  ///
  /// 第 3 层中，当前未选中一侧的填充色，默认全透明，让第 2 层的底板露出来。
  /// 设置了 [inactiveGradient] 时此项被忽略。
  final Color inactiveColor;

  /// Overrides [activeColor] with a gradient fill for the selected side.
  ///
  /// 用渐变替代 [activeColor]，作为选中一侧的填充。
  final LinearGradient? activeGradient;

  /// Overrides [inactiveColor] with a gradient fill for the unselected
  /// side.
  ///
  /// 用渐变替代 [inactiveColor]，作为未选中一侧的填充。
  final LinearGradient? inactiveGradient;

  /// Stroke color for the S-curve seam itself, drawn on top of the two
  /// fills. `null` (the default) draws no stroke — the curve then only
  /// reads as a boundary if [activeColor]/[inactiveColor] (or their
  /// gradients) actually differ.
  ///
  /// S 曲线本身的描边颜色，画在两块填充的上面。默认 `null` 不描边——这种
  /// 情况下曲线只有在 [activeColor]/[inactiveColor]（或对应渐变）真的不同
  /// 时才看得出分界。
  final Color? dividerColor;

  /// Stroke width for the S-curve seam. Ignored unless [dividerColor] or
  /// [dividerGradient] is set.
  ///
  /// S 曲线描边的宽度。[dividerColor] 和 [dividerGradient] 都为 `null` 时
  /// 不生效。
  final double dividerWidth;

  /// Overrides [dividerColor] with a gradient stroke for the S-curve seam.
  ///
  /// 用渐变替代 [dividerColor]，作为 S 曲线描边的颜色。
  final Gradient? dividerGradient;

  /// Stroke cap for the S-curve seam (and its [dividerShadow], if any).
  /// Defaults to [StrokeCap.butt] — a flat cut right at the top/bottom
  /// edges. [StrokeCap.round] extends a rounded cap past them instead.
  ///
  /// S 曲线描边（以及 [dividerShadow]，如果有）的线帽样式。默认
  /// [StrokeCap.butt]——在顶/底边处直接齐平截断。[StrokeCap.round] 则会
  /// 在边缘外多出一段圆头。
  final StrokeCap dividerCap;

  /// Soft shadow/glow stroked once behind the S-curve seam, using the same
  /// path — its [BoxShadow.color]/[BoxShadow.blurRadius]/[BoxShadow.offset]
  /// apply as they would to any shadow, and [BoxShadow.spreadRadius] widens
  /// the stroke (added to [dividerWidth] on each side) rather than growing a
  /// filled shape. Ignored unless [dividerColor] or [dividerGradient] is
  /// set.
  ///
  /// 在 S 曲线描边后面，沿同一条路径再描一遍的柔和阴影/发光——
  /// [BoxShadow.color]/[BoxShadow.blurRadius]/[BoxShadow.offset] 跟用在普通
  /// 阴影上的效果一样，[BoxShadow.spreadRadius] 则是把描边加宽（在
  /// [dividerWidth] 两侧各加一份），而不是撑大一个填充形状。[dividerColor]
  /// 和 [dividerGradient] 都为 `null` 时不生效。
  final BoxShadow? dividerShadow;

  /// Offset added to the top endpoint's control point (which otherwise sits
  /// at the horizontal center, giving a flat tangent at the top edge — see
  /// the curve construction note below). Use this to break that flatness or
  /// shift where the curve's upper bulge sits, independent of
  /// [leanAmplitude].
  ///
  /// 加到顶部端点控制点上的偏移量（该控制点默认落在水平中心，让曲线在顶边
  /// 处切线是水平的）。用它可以打破这种"贴平"的效果，或者独立于
  /// [leanAmplitude] 去改变曲线上半部分鼓起的位置。
  final Offset topControlOffset;

  /// Same as [topControlOffset], for the bottom endpoint's control point.
  ///
  /// 跟 [topControlOffset] 一样，只是作用于底部端点的控制点。
  final Offset bottomControlOffset;

  /// Outline color for whichever side is currently selected — traces that
  /// side's whole region (top/side/bottom edges, not just the seam).
  /// `null` (the default) draws no outline.
  ///
  /// 当前选中一侧的整体描边颜色——沿着那一侧的完整轮廓描边（不只是分界线），
  /// 默认 `null` 不描边。
  final Color? activeBorderColor;

  /// Outline color for whichever side is currently unselected. `null` (the
  /// default) draws no outline.
  ///
  /// 当前未选中一侧的整体描边颜色，默认 `null` 不描边。
  final Color? inactiveBorderColor;

  /// Stroke width for [activeBorderColor]/[inactiveBorderColor].
  ///
  /// [activeBorderColor]/[inactiveBorderColor] 的描边宽度。
  final double splitBorderWidth;

  /// Duration of the morph animation when [selectedIndex] changes. Ignored
  /// when [animated] is `false`.
  ///
  /// [selectedIndex] 变化时的变形动画时长。[animated] 为 `false` 时不生效。
  final Duration duration;

  /// Easing curve of the morph animation. Ignored when [animated] is
  /// `false`.
  ///
  /// 变形动画的缓动曲线。[animated] 为 `false` 时不生效。
  final Curve curve;

  /// Whether [selectedIndex] changes tween smoothly. `false` snaps `t`
  /// straight to the target value with no animation.
  ///
  /// [selectedIndex] 变化时是否走补间动画。`false` 时 `t` 直接跳到目标值，
  /// 不做任何动画。
  final bool animated;

  @override
  State<CurvedTabBackground> createState() => _CurvedTabBackgroundState();
}

class _CurvedTabBackgroundState extends State<CurvedTabBackground>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.progress == null) {
      _controller = AnimationController(
        vsync: this,
        duration: widget.duration,
        value: widget.selectedIndex == 1 ? 1 : 0,
      );
    }
  }

  Animation<double> get _animation => widget.progress ?? _controller!;

  @override
  void didUpdateWidget(covariant CurvedTabBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress == null &&
        oldWidget.selectedIndex != widget.selectedIndex) {
      final target = widget.selectedIndex == 1 ? 1.0 : 0.0;
      if (widget.animated) {
        _controller!.animateTo(
          target,
          duration: widget.duration,
          curve: widget.curve,
        );
      } else {
        _controller!.value = target;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unselectedColor =
        widget.unselectedColor ?? colorScheme.surfaceContainerHigh;
    final unselectedBorderColor =
        widget.unselectedBorderColor ?? colorScheme.outlineVariant;
    final activeColor = widget.activeColor ?? colorScheme.surface;

    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) {
        final t = _animation.value.clamp(0.0, 1.0);
        return Container(
          height: widget.height,
          decoration: _CurvedTabBackgroundDecoration(
            borderRadius: widget.borderRadius,
            leanAmplitude: widget.leanAmplitude,
            backgroundColor: widget.backgroundColor,
            unselectedTopInset: widget.unselectedTopInset,
            unselectedColor: unselectedColor,
            unselectedBorderColor: unselectedBorderColor,
            unselectedBorderWidth: widget.unselectedBorderWidth,
            leanSign: 2 * t - 1,
            leftColor: Color.lerp(activeColor, widget.inactiveColor, t)!,
            rightColor: Color.lerp(widget.inactiveColor, activeColor, t)!,
            leftGradient: LinearGradient.lerp(
              widget.activeGradient,
              widget.inactiveGradient,
              t,
            ),
            rightGradient: LinearGradient.lerp(
              widget.inactiveGradient,
              widget.activeGradient,
              t,
            ),
            dividerColor: widget.dividerColor,
            dividerWidth: widget.dividerWidth,
            dividerGradient: widget.dividerGradient,
            dividerCap: widget.dividerCap,
            dividerShadow: widget.dividerShadow,
            topControlOffset: widget.topControlOffset,
            bottomControlOffset: widget.bottomControlOffset,
            leftBorderColor: Color.lerp(
              widget.activeBorderColor,
              widget.inactiveBorderColor,
              t,
            ),
            rightBorderColor: Color.lerp(
              widget.inactiveBorderColor,
              widget.activeBorderColor,
              t,
            ),
            splitBorderWidth: widget.splitBorderWidth,
          ),
          child: widget.builder?.call(context, t, child) ?? child,
        );
      },
    );
  }
}
