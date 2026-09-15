part of 'curved_dual_tab_bar.dart';

/// Two-way tab header (e.g. "DEPOSIT" / "WITHDRAW") built on top of
/// [CurvedTabBackground] and a real Material [TabBar]: the [TabBar] is the
/// only foreground element — it owns tap targets, the selection indicator,
/// ripple/hover/focus feedback and a11y semantics — while all background
/// painting/animation is delegated to [CurvedTabBackground] via its
/// [CurvedTabBackground.progress] hook, driven by the same single
/// [TabController].
///
/// Most [TabBar] properties with no equivalent in this widget's own curve
/// styling are passed straight through (see the trailing constructor
/// parameters), so callers aren't limited to what this widget explicitly
/// re-exposes.
///
/// 两段式 Tab 头（比如 "DEPOSIT" / "WITHDRAW"），构建在 [CurvedTabBackground]
/// 和一个真正的 Material [TabBar] 之上：前景只有这一个 [TabBar]——点击区域、
/// 选中态指示器、水波纹/hover/焦点反馈、无障碍语义都是它自己的；所有背景
/// 绘制/动画都通过 [CurvedTabBackground.progress] 交给 [CurvedTabBackground]，
/// 由同一个 [TabController] 驱动。
///
/// 大部分在本组件曲线样式里没有对应项的 [TabBar] 属性都做了透传（见构造函数
/// 末尾那些参数），调用方不会被限制在本组件显式重新暴露的那几个里。
///
/// Example (self-managed state):
/// ```dart
/// CurvedDualTabBar(
///   titles: const ['DEPOSIT', 'WITHDRAW'],
///   selectedIndex: selectedIndex,
///   onChanged: (i) => setState(() => selectedIndex = i),
/// )
/// ```
///
/// Example (controller as the sole source of truth — an ancestor
/// [DefaultTabController] shared with a sibling `TabBarView`, or an explicit
/// [controller]): omit [selectedIndex]/[onChanged] entirely, the controller
/// drives everything.
/// ```dart
/// DefaultTabController(
///   length: 2,
///   child: Column(
///     children: [
///       const CurvedDualTabBar(titles: ['DEPOSIT', 'WITHDRAW']),
///       const Expanded(child: TabBarView(children: [DepositPage(), WithdrawPage()])),
///     ],
///   ),
/// )
/// ```
class CurvedDualTabBar extends StatefulWidget {
  const CurvedDualTabBar({
    super.key,
    required this.titles,
    this.selectedIndex,
    this.onChanged,
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
    this.activeTextColor,
    this.inactiveTextColor,
    this.textStyle,
    this.duration = const Duration(milliseconds: 320),
    this.curve = Curves.easeInOutCubic,
    this.animated = true,
    this.indicatorColor,
    this.indicator,
    this.indicatorSize,
    this.indicatorWeight = 2.0,
    this.indicatorPadding = EdgeInsets.zero,
    this.indicatorAnimation,
    this.automaticIndicatorColorAdjustment = true,
    this.controller,
    this.scrollController,
    this.tabDividerColor = Colors.transparent,
    this.tabDividerHeight,
    this.padding,
    this.labelPadding,
    this.unselectedLabelStyle,
    this.isScrollable = false,
    this.overlayColor,
    this.mouseCursor,
    this.enableFeedback,
    this.onTap,
    this.onHover,
    this.onFocusChange,
    this.physics,
    this.splashFactory,
    this.splashBorderRadius,
    this.dragStartBehavior = DragStartBehavior.start,
    this.tabAlignment,
    this.textScaler,
  }) : assert(
         titles.length == 2,
         'CurvedDualTabBar only supports exactly 2 tabs',
       );

  /// The two tab labels, e.g. `['DEPOSIT', 'WITHDRAW']`.
  ///
  /// 两个 Tab 文案，比如 `['DEPOSIT', 'WITHDRAW']`。
  final List<String> titles;

  /// Currently selected tab, 0 or 1. Omit this (along with [onChanged]) when
  /// a [controller] — explicit or an ancestor [DefaultTabController] — is
  /// already the sole source of truth for the selection: without it, this
  /// widget never force-syncs the controller back to a caller-tracked value,
  /// so it can't fight a `TabBarView` swipe that already moved the shared
  /// controller. Provide it to run this widget as a classic controlled
  /// component instead (own [State.setState] managing the index).
  ///
  /// 当前选中的 Tab，取值 0 或 1。当 [controller]（不管是显式传入的，还是
  /// 祖先的 [DefaultTabController]）已经是选中态的唯一真相来源时，把这个
  /// （连同 [onChanged]）一起省略掉：省略后本组件不会再把 controller 强行
  /// 同步回调用方记录的值，也就不会跟已经被 `TabBarView` 滑动改过的共享
  /// controller"打架"。想把本组件当成传统的受控组件用（自己
  /// `setState` 管理下标）时再传它。
  final int? selectedIndex;

  /// Called with the tapped tab's index. Only meaningful when
  /// [selectedIndex] is also provided (controlled-component mode); safe to
  /// omit when a shared [controller] already drives selection.
  ///
  /// 点击某个 Tab 时回调其下标。只有在同时提供了 [selectedIndex]（受控组件
  /// 模式）时才有意义；当共享 [controller] 已经在驱动选中态时可以省略。
  final ValueChanged<int>? onChanged;

  /// Bar height. See [CurvedTabBackground.height].
  ///
  /// 整个 Tab 头的高度，见 [CurvedTabBackground.height]。
  final double height;

  /// See [CurvedTabBackground.borderRadius].
  ///
  /// 见 [CurvedTabBackground.borderRadius]。
  final double borderRadius;

  /// See [CurvedTabBackground.leanAmplitude].
  ///
  /// 见 [CurvedTabBackground.leanAmplitude]。
  final double leanAmplitude;

  /// See [CurvedTabBackground.backgroundColor].
  ///
  /// 见 [CurvedTabBackground.backgroundColor]。
  final Color backgroundColor;

  /// See [CurvedTabBackground.unselectedTopInset].
  ///
  /// 见 [CurvedTabBackground.unselectedTopInset]。
  final double unselectedTopInset;

  /// See [CurvedTabBackground.unselectedColor].
  ///
  /// 见 [CurvedTabBackground.unselectedColor]。
  final Color? unselectedColor;

  /// See [CurvedTabBackground.unselectedBorderColor].
  ///
  /// 见 [CurvedTabBackground.unselectedBorderColor]。
  final Color? unselectedBorderColor;

  /// See [CurvedTabBackground.unselectedBorderWidth].
  ///
  /// 见 [CurvedTabBackground.unselectedBorderWidth]。
  final double unselectedBorderWidth;

  /// See [CurvedTabBackground.activeColor].
  ///
  /// 见 [CurvedTabBackground.activeColor]。
  final Color? activeColor;

  /// See [CurvedTabBackground.inactiveColor].
  ///
  /// 见 [CurvedTabBackground.inactiveColor]。
  final Color inactiveColor;

  /// See [CurvedTabBackground.activeGradient].
  ///
  /// 见 [CurvedTabBackground.activeGradient]。
  final LinearGradient? activeGradient;

  /// See [CurvedTabBackground.inactiveGradient].
  ///
  /// 见 [CurvedTabBackground.inactiveGradient]。
  final LinearGradient? inactiveGradient;

  /// See [CurvedTabBackground.dividerColor].
  ///
  /// 见 [CurvedTabBackground.dividerColor]。
  final Color? dividerColor;

  /// See [CurvedTabBackground.dividerWidth].
  ///
  /// 见 [CurvedTabBackground.dividerWidth]。
  final double dividerWidth;

  /// See [CurvedTabBackground.dividerGradient].
  ///
  /// 见 [CurvedTabBackground.dividerGradient]。
  final Gradient? dividerGradient;

  /// See [CurvedTabBackground.dividerCap].
  ///
  /// 见 [CurvedTabBackground.dividerCap]。
  final StrokeCap dividerCap;

  /// See [CurvedTabBackground.dividerShadow].
  ///
  /// 见 [CurvedTabBackground.dividerShadow]。
  final BoxShadow? dividerShadow;

  /// See [CurvedTabBackground.topControlOffset].
  ///
  /// 见 [CurvedTabBackground.topControlOffset]。
  final Offset topControlOffset;

  /// See [CurvedTabBackground.bottomControlOffset].
  ///
  /// 见 [CurvedTabBackground.bottomControlOffset]。
  final Offset bottomControlOffset;

  /// See [CurvedTabBackground.activeBorderColor].
  ///
  /// 见 [CurvedTabBackground.activeBorderColor]。
  final Color? activeBorderColor;

  /// See [CurvedTabBackground.inactiveBorderColor].
  ///
  /// 见 [CurvedTabBackground.inactiveBorderColor]。
  final Color? inactiveBorderColor;

  /// See [CurvedTabBackground.splitBorderWidth].
  ///
  /// 见 [CurvedTabBackground.splitBorderWidth]。
  final double splitBorderWidth;

  /// Text color for the selected label, forwarded to [TabBar.labelColor].
  /// Defaults to `colorScheme.onSurface`.
  ///
  /// 选中态文字颜色，转发给 [TabBar.labelColor]，默认取
  /// `colorScheme.onSurface`。
  final Color? activeTextColor;

  /// Text color for the unselected label, forwarded to
  /// [TabBar.unselectedLabelColor]. Defaults to `colorScheme.onSurfaceVariant`.
  ///
  /// 未选中态文字颜色，转发给 [TabBar.unselectedLabelColor]，默认取
  /// `colorScheme.onSurfaceVariant`。
  final Color? inactiveTextColor;

  /// Base text style forwarded to [TabBar.labelStyle] (bolded) and, unless
  /// [unselectedLabelStyle] overrides it, to [TabBar.unselectedLabelStyle]
  /// too.
  ///
  /// 转发给 [TabBar.labelStyle]（会加粗）的基础文字样式；[unselectedLabelStyle]
  /// 未覆盖时也同样用于 [TabBar.unselectedLabelStyle]。
  final TextStyle? textStyle;

  /// See [CurvedTabBackground.duration]. Also used as the [TabController]'s
  /// tap-to-tap animation duration.
  ///
  /// 见 [CurvedTabBackground.duration]，同时也是 [TabController] 点击切换的
  /// 动画时长。
  final Duration duration;

  /// See [CurvedTabBackground.curve].
  ///
  /// 见 [CurvedTabBackground.curve]。
  final Curve curve;

  /// See [CurvedTabBackground.animated]. When `false`, an externally-driven
  /// [selectedIndex] change snaps the [TabController] straight to the target
  /// index instead of animating to it.
  ///
  /// 见 [CurvedTabBackground.animated]。为 `false` 时，外部驱动的
  /// [selectedIndex] 变化会让 [TabController] 直接跳到目标下标，而不是动画过去。
  final bool animated;

  /// Forwarded to [TabBar.indicatorColor].
  ///
  /// 透传给 [TabBar.indicatorColor]。
  final Color? indicatorColor;

  /// Forwarded to [TabBar.indicator].
  ///
  /// 透传给 [TabBar.indicator]。
  final Decoration? indicator;

  /// Forwarded to [TabBar.indicatorSize].
  ///
  /// 透传给 [TabBar.indicatorSize]。
  final TabBarIndicatorSize? indicatorSize;

  /// Forwarded to [TabBar.indicatorWeight].
  ///
  /// 透传给 [TabBar.indicatorWeight]。
  final double indicatorWeight;

  /// Forwarded to [TabBar.indicatorPadding].
  ///
  /// 透传给 [TabBar.indicatorPadding]。
  final EdgeInsetsGeometry indicatorPadding;

  /// Forwarded to [TabBar.indicatorAnimation].
  ///
  /// 透传给 [TabBar.indicatorAnimation]。
  final TabIndicatorAnimation? indicatorAnimation;

  /// Forwarded to [TabBar.automaticIndicatorColorAdjustment].
  ///
  /// 透传给 [TabBar.automaticIndicatorColorAdjustment]。
  final bool automaticIndicatorColorAdjustment;

  /// Externally-supplied [TabController], forwarded to [TabBar.controller].
  /// When omitted, an ancestor [DefaultTabController] is used instead if one
  /// exists; only when neither is available does this widget create and own
  /// a controller internally. Whichever one ends up in charge is kept in
  /// sync with [selectedIndex]/[onChanged] the same way. Pass the same
  /// controller a sibling `TabBarView` uses to keep this bar's curve/
  /// indicator perfectly in sync with that view's drag/swipe, instead of
  /// only snapping once [selectedIndex] changes at the end of it.
  ///
  /// 外部传入的 [TabController]，透传给 [TabBar.controller]。缺省时优先用
  /// 祖先的 [DefaultTabController]（如果存在）；只有两者都没有时，本组件才
  /// 会自己创建并持有一个内部 controller。不管最终用的是哪一个，都会跟
  /// [selectedIndex]/[onChanged] 保持同步。把兄弟 `TabBarView` 用的同一个
  /// controller 传进来，可以让本组件的曲线/指示器和那个视图的拖拽/滑动
  /// 完全同步，而不是等滑动结束、[selectedIndex] 变化后才跳一下。
  final TabController? controller;

  /// Forwarded to [TabBar.scrollController].
  ///
  /// 透传给 [TabBar.scrollController]。
  final TabBarScrollController? scrollController;

  /// Forwarded to [TabBar.dividerColor] (named to avoid clashing with
  /// [dividerColor], which styles the curve's own seam). Defaults to
  /// [Colors.transparent] since the curved background already provides
  /// visual separation.
  ///
  /// 透传给 [TabBar.dividerColor]（换了个名字，避免跟给曲线分割线用的
  /// [dividerColor] 撞名）。默认全透明，因为曲线背景本身已经提供了视觉分隔。
  final Color? tabDividerColor;

  /// Forwarded to [TabBar.dividerHeight].
  ///
  /// 透传给 [TabBar.dividerHeight]。
  final double? tabDividerHeight;

  /// Forwarded to [TabBar.padding].
  ///
  /// 透传给 [TabBar.padding]。
  final EdgeInsetsGeometry? padding;

  /// Forwarded to [TabBar.labelPadding].
  ///
  /// 透传给 [TabBar.labelPadding]。
  final EdgeInsetsGeometry? labelPadding;

  /// Forwarded to [TabBar.unselectedLabelStyle]. Defaults to [textStyle].
  ///
  /// 透传给 [TabBar.unselectedLabelStyle]，默认取 [textStyle]。
  final TextStyle? unselectedLabelStyle;

  /// Forwarded to [TabBar.isScrollable].
  ///
  /// 透传给 [TabBar.isScrollable]。
  final bool isScrollable;

  /// Forwarded to [TabBar.overlayColor].
  ///
  /// 透传给 [TabBar.overlayColor]。
  final WidgetStateProperty<Color?>? overlayColor;

  /// Forwarded to [TabBar.mouseCursor].
  ///
  /// 透传给 [TabBar.mouseCursor]。
  final MouseCursor? mouseCursor;

  /// Forwarded to [TabBar.enableFeedback].
  ///
  /// 透传给 [TabBar.enableFeedback]。
  final bool? enableFeedback;

  /// Forwarded to [TabBar.onTap]. Fires on every tap, even a tap on the
  /// already-selected tab; use [onChanged] for selection changes.
  ///
  /// 透传给 [TabBar.onTap]。每次点击（包括点当前已选中的 tab）都会触发；
  /// 选中态变化请用 [onChanged]。
  final ValueChanged<int>? onTap;

  /// Forwarded to [TabBar.onHover].
  ///
  /// 透传给 [TabBar.onHover]。
  final TabValueChanged<bool>? onHover;

  /// Forwarded to [TabBar.onFocusChange].
  ///
  /// 透传给 [TabBar.onFocusChange]。
  final TabValueChanged<bool>? onFocusChange;

  /// Forwarded to [TabBar.physics].
  ///
  /// 透传给 [TabBar.physics]。
  final ScrollPhysics? physics;

  /// Forwarded to [TabBar.splashFactory].
  ///
  /// 透传给 [TabBar.splashFactory]。
  final InteractiveInkFeatureFactory? splashFactory;

  /// Forwarded to [TabBar.splashBorderRadius].
  ///
  /// 透传给 [TabBar.splashBorderRadius]。
  final BorderRadius? splashBorderRadius;

  /// Forwarded to [TabBar.dragStartBehavior].
  ///
  /// 透传给 [TabBar.dragStartBehavior]。
  final DragStartBehavior dragStartBehavior;

  /// Forwarded to [TabBar.tabAlignment].
  ///
  /// 透传给 [TabBar.tabAlignment]。
  final TabAlignment? tabAlignment;

  /// Forwarded to [TabBar.textScaler].
  ///
  /// 透传给 [TabBar.textScaler]。
  final TextScaler? textScaler;

  @override
  State<CurvedDualTabBar> createState() => _CurvedDualTabBarState();
}

class _CurvedDualTabBarState extends State<CurvedDualTabBar>
    with SingleTickerProviderStateMixin {
  // Lazily created only when neither an explicit `widget.controller` nor an
  // ancestor `DefaultTabController` is available. Left alive (not disposed)
  // if a later rebuild finds one of those instead, in case the dependency
  // swings back — `dispose` is the only place that tears it down.
  //
  // 仅在既没有显式的 `widget.controller`、也没有祖先 `DefaultTabController`
  // 时才惰性创建。即使后续构建改用了其中之一，也不会立刻销毁它——万一
  // 依赖关系又变回来；只有 `dispose` 会真正销毁它。
  TabController? _internalController;

  // Currently active controller, resolved with priority: explicit
  // `widget.controller` > ancestor `DefaultTabController.of(context)` >
  // `_internalController`. Recomputed in [_syncTabController], which needs
  // `context` for the `DefaultTabController` lookup, so it can only run
  // from `didChangeDependencies`/`didUpdateWidget`, never `initState`.
  //
  // 当前生效的 controller，按优先级解析：显式的 `widget.controller` >
  // 祖先 `DefaultTabController.of(context)` > `_internalController`。
  // 在 [_syncTabController] 里重新计算——它需要 `context` 去查找
  // `DefaultTabController`，所以只能从 `didChangeDependencies`/
  // `didUpdateWidget` 里调用，不能放在 `initState`。
  TabController? _resolvedController;

  TabController get _tabController => _resolvedController!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTabController();
  }

  /// Resolves the effective controller — explicit [CurvedDualTabBar.controller]
  /// first, then an ancestor [DefaultTabController], finally a lazily-created
  /// internal one — and moves the tick listener over if it changed.
  ///
  /// 解析当前生效的 controller——优先取显式的 [CurvedDualTabBar.controller]，
  /// 其次取祖先 [DefaultTabController]，最后才惰性创建一个内部
  /// controller——如果发生变化就把 tick 监听挪过去。
  void _syncTabController() {
    final next =
        widget.controller ??
        DefaultTabController.maybeOf(context) ??
        (_internalController ??= TabController(
          length: 2,
          initialIndex: widget.selectedIndex ?? 0,
          vsync: this,
        ));
    assert(
      next.length == 2,
      'CurvedDualTabBar only supports a TabController with length 2',
    );

    if (identical(next, _resolvedController)) return;

    _resolvedController?.removeListener(_handleTabControllerTick);
    _resolvedController = next;
    if (widget.selectedIndex != null && next.index != widget.selectedIndex) {
      next.index = widget.selectedIndex!;
    }
    next.addListener(_handleTabControllerTick);
  }

  void _handleTabControllerTick() {
    if (!_tabController.indexIsChanging) {
      widget.onChanged?.call(_tabController.index);
    }
  }

  @override
  void didUpdateWidget(covariant CurvedDualTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      _syncTabController();
    }

    // No caller-tracked `selectedIndex` to reconcile against — the
    // controller (shared or internal) is the only source of truth, so
    // there's nothing to force it back to.
    //
    // 没有调用方自己记录的 `selectedIndex` 可以对照——controller（不管共享
    // 还是内部）就是唯一真相来源，没有什么需要强行同步回去的。
    if (widget.selectedIndex == null) return;

    if (_tabController.index != widget.selectedIndex) {
      if (widget.animated) {
        _tabController.animateTo(
          widget.selectedIndex!,
          duration: widget.duration,
          curve: widget.curve,
        );
      } else {
        _tabController.index = widget.selectedIndex!;
      }
    }
  }

  @override
  void dispose() {
    _resolvedController?.removeListener(_handleTabControllerTick);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeTextColor = widget.activeTextColor ?? colorScheme.onSurface;
    final inactiveTextColor =
        widget.inactiveTextColor ?? colorScheme.onSurfaceVariant;
    final baseTextStyle =
        widget.textStyle ?? Theme.of(context).textTheme.titleMedium;

    return CurvedTabBackground(
      // Only used by `CurvedTabBackground` as the initial tween value when
      // no `progress` is given; `progress` is always supplied below, so
      // this never actually drives anything — `_tabController.index` is
      // just a harmless, always-available fallback when there's no
      // caller-tracked `selectedIndex`.
      //
      // `CurvedTabBackground`只在没有传 `progress` 时才用这个值做补间初值；
      // 下面总是传了 `progress`，所以这里实际上从不会真正生效——没有调用方
      // 自己记录的 `selectedIndex` 时，`_tabController.index` 只是个随手可用
      // 的无害兜底值。
      selectedIndex: widget.selectedIndex ?? _tabController.index,
      progress: _tabController.animation,
      height: widget.height,
      borderRadius: widget.borderRadius,
      leanAmplitude: widget.leanAmplitude,
      backgroundColor: widget.backgroundColor,
      unselectedTopInset: widget.unselectedTopInset,
      unselectedColor: widget.unselectedColor,
      unselectedBorderColor: widget.unselectedBorderColor,
      unselectedBorderWidth: widget.unselectedBorderWidth,
      activeColor: widget.activeColor,
      inactiveColor: widget.inactiveColor,
      activeGradient: widget.activeGradient,
      inactiveGradient: widget.inactiveGradient,
      dividerColor: widget.dividerColor,
      dividerWidth: widget.dividerWidth,
      dividerGradient: widget.dividerGradient,
      dividerCap: widget.dividerCap,
      dividerShadow: widget.dividerShadow,
      topControlOffset: widget.topControlOffset,
      bottomControlOffset: widget.bottomControlOffset,
      activeBorderColor: widget.activeBorderColor,
      inactiveBorderColor: widget.inactiveBorderColor,
      splitBorderWidth: widget.splitBorderWidth,
      duration: widget.duration,
      curve: widget.curve,
      animated: widget.animated,
      // TabBar doesn't depend on `t` itself (its indicator/label crossfade
      // listens to `_tabController.animation` directly), so it lives in
      // `child` and never gets rebuilt by CurvedTabBackground's own
      // animation ticks.
      //
      // TabBar 本身不依赖 `t`（它的指示器/文字渐变直接监听
      // `_tabController.animation`），所以放进 `child`，不会被
      // CurvedTabBackground 自己的动画帧重建。
      child: TabBar(
        controller: _tabController,
        scrollController: widget.scrollController,
        tabs: [for (final title in widget.titles) Tab(text: title)],
        indicatorColor: widget.indicatorColor,
        indicator: widget.indicator,
        indicatorSize: widget.indicatorSize,
        indicatorWeight: widget.indicatorWeight,
        indicatorPadding: widget.indicatorPadding,
        indicatorAnimation: widget.indicatorAnimation,
        automaticIndicatorColorAdjustment:
            widget.automaticIndicatorColorAdjustment,
        dividerColor: widget.tabDividerColor,
        dividerHeight: widget.tabDividerHeight,
        labelColor: activeTextColor,
        unselectedLabelColor: inactiveTextColor,
        labelStyle: baseTextStyle?.copyWith(fontWeight: FontWeight.bold),
        unselectedLabelStyle: widget.unselectedLabelStyle ?? baseTextStyle,
        padding: widget.padding,
        labelPadding: widget.labelPadding,
        isScrollable: widget.isScrollable,
        overlayColor: widget.overlayColor,
        mouseCursor: widget.mouseCursor,
        enableFeedback: widget.enableFeedback,
        onTap: widget.onTap,
        onHover: widget.onHover,
        onFocusChange: widget.onFocusChange,
        physics: widget.physics,
        splashFactory: widget.splashFactory,
        splashBorderRadius: widget.splashBorderRadius,
        dragStartBehavior: widget.dragStartBehavior,
        tabAlignment: widget.tabAlignment,
        textScaler: widget.textScaler,
      ),
    );
  }
}
