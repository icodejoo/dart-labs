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
/// Example:
/// ```dart
/// CurvedDualTabBar(
///   titles: const ['DEPOSIT', 'WITHDRAW'],
///   selectedIndex: selectedIndex,
///   onChanged: (i) => setState(() => selectedIndex = i),
/// )
/// ```
class CurvedDualTabBar extends StatefulWidget {
  const CurvedDualTabBar({
    super.key,
    required this.titles,
    required this.selectedIndex,
    required this.onChanged,
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

  /// Currently selected tab, 0 or 1.
  ///
  /// 当前选中的 Tab，取值 0 或 1。
  final int selectedIndex;

  /// Called with the tapped tab's index.
  ///
  /// 点击某个 Tab 时回调其下标。
  final ValueChanged<int> onChanged;

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
  /// When omitted, this widget creates and owns its own controller
  /// internally, kept in sync with [selectedIndex]/[onChanged] either way.
  ///
  /// 外部传入的 [TabController]，透传给 [TabBar.controller]。缺省时本组件
  /// 会自己创建并持有一个 controller；不管哪种情况，都会跟
  /// [selectedIndex]/[onChanged] 保持同步。
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
  // Owned by this widget only when the caller doesn't supply its own
  // `controller`; `null` whenever an external controller is in charge, so
  // `dispose` never tears down something it doesn't own.
  //
  // 只有调用方没传自己的 `controller` 时才由本组件持有；用了外部 controller
  // 时始终是 `null`，这样 `dispose` 就不会去销毁不属于自己的东西。
  TabController? _internalController;

  TabController get _tabController => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TabController(
        length: 2,
        initialIndex: widget.selectedIndex,
        vsync: this,
      );
    }
    if (_tabController.index != widget.selectedIndex) {
      _tabController.index = widget.selectedIndex;
    }
    _tabController.addListener(_handleTabControllerTick);
  }

  void _handleTabControllerTick() {
    if (!_tabController.indexIsChanging) {
      widget.onChanged(_tabController.index);
    }
  }

  @override
  void didUpdateWidget(covariant CurvedDualTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      final oldController = oldWidget.controller ?? _internalController;
      oldController?.removeListener(_handleTabControllerTick);

      if (widget.controller == null) {
        _internalController ??= TabController(
          length: 2,
          initialIndex: oldController?.index ?? 0,
          vsync: this,
        );
      } else if (oldWidget.controller == null) {
        _internalController?.dispose();
        _internalController = null;
      }
      _tabController.addListener(_handleTabControllerTick);
    }

    if (_tabController.index != widget.selectedIndex) {
      if (widget.animated) {
        _tabController.animateTo(
          widget.selectedIndex,
          duration: widget.duration,
          curve: widget.curve,
        );
      } else {
        _tabController.index = widget.selectedIndex;
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabControllerTick);
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
      selectedIndex: widget.selectedIndex,
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
