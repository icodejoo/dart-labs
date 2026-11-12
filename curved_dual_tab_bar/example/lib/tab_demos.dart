import 'package:curved_dual_tab_bar/curved_dual_tab_bar.dart';
import 'package:flutter/material.dart';

import 'demo_kit/demo_kit.dart';
import 'demo_palette.dart';

/// 放慢演示动画，便于观察曲线与指示器同步。
const demoTransition = Duration(milliseconds: 700);

/// 双段标签的固定数量。
const _tabCount = 2;

/// 每个滑动内容区的紧凑高度。
const _panelHeight = 80.0;

/// 原生标签栏的默认高度。
const _barHeight = 56.0;

/// 强调描边的宽度。
const _strokeWidth = 3.0;

/// 所有卡片共用的双语短文案。
abstract final class DemoCopy {
  /// 左侧标签。
  static String left(BuildContext context) => tr(context, 'Left', '左侧');

  /// 右侧标签。
  static String right(BuildContext context) => tr(context, 'Right', '右侧');

  /// 月度标签。
  static String monthly(BuildContext context) => tr(context, 'Monthly', '月度');

  /// 年度标签。
  static String yearly(BuildContext context) => tr(context, 'Yearly', '年度');

  /// 充值标签。
  static String deposit(BuildContext context) => tr(context, 'Deposit', '充值');

  /// 提现标签。
  static String withdraw(BuildContext context) => tr(context, 'Withdraw', '提现');

  /// 当前受控选中状态。
  static String selected(BuildContext context, String label) =>
      tr(context, 'Selected: $label', '当前选中：$label');
}

/// 原长列表中保留的六种外观变体。
enum TabStyle {
  /// 主题默认颜色。
  theme,

  /// 原设计稿的三层背景。
  deposit,

  /// 渐变填充与底板描边。
  gradient,

  /// 纯色对照曲线。
  curve,

  /// 左右轮廓与分割线描边。
  outlines,

  /// 发光渐变分割线。
  glow,
}

/// 自己持有选择状态，重放重新挂载后自动演示一次切换。
class StyledTabs extends StatefulWidget {
  /// 创建某一种外观的交互预览。
  const StyledTabs({super.key, required this.style});

  /// 当前外观变体。
  final TabStyle style;

  /// 创建局部选择状态。
  @override
  State<StyledTabs> createState() => _StyledTabsState();
}

/// 将每张卡片的选择与过渡限制在其自身生命周期内。
class _StyledTabsState extends State<StyledTabs> {
  /// 当前选中侧。
  int _selected = 0;

  /// 首帧先显示左侧，再自动过渡到右侧。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) _select(1);
    });
  }

  /// 更新受控选择。
  void _select(int index) => setState(() => _selected = index);

  /// 构建保留原样式参数的标签栏与双语选中反馈。
  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final theme = style == TabStyle.theme;
    final deposit = style == TabStyle.deposit;
    final gradient = style == TabStyle.gradient;
    final curve = style == TabStyle.curve;
    final outlines = style == TabStyle.outlines;
    final glow = style == TabStyle.glow;
    final titles = theme
        ? [DemoCopy.monthly(context), DemoCopy.yearly(context)]
        : deposit || gradient
        ? [DemoCopy.deposit(context), DemoCopy.withdraw(context)]
        : [DemoCopy.left(context), DemoCopy.right(context)];
    final bar = CurvedDualTabBar(
      titles: titles,
      selectedIndex: _selected,
      onChanged: _select,
      safeArea: false,
      duration: demoTransition,
      animated: !MediaQuery.disableAnimationsOf(context),
      leanAmplitude: curve ? 0.22 : 0.1,
      unselectedTopInset: deposit
          ? 2
          : curve || outlines
          ? 0
          : 14,
      unselectedColor: theme ? null : DemoPalette.pale,
      unselectedBorderColor: gradient
          ? DemoPalette.outline
          : theme
          ? null
          : Colors.transparent,
      activeColor: theme
          ? null
          : deposit
          ? DemoPalette.cream
          : curve
          ? DemoPalette.purple
          : Colors.white,
      inactiveColor: curve ? DemoPalette.pale : Colors.transparent,
      activeGradient: gradient
          ? const LinearGradient(
              colors: [DemoPalette.purple, DemoPalette.lavender],
            )
          : null,
      inactiveGradient: gradient
          ? const LinearGradient(
              colors: [Colors.transparent, Colors.transparent],
            )
          : null,
      activeTextColor: theme
          ? null
          : curve || gradient
          ? Colors.white
          : DemoPalette.ink,
      inactiveTextColor: theme ? null : DemoPalette.mutedInk,
      indicatorColor: deposit ? DemoPalette.pink : null,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: outlines ? DemoPalette.purple : null,
      dividerWidth: _strokeWidth,
      activeBorderColor: outlines ? DemoPalette.pink : null,
      inactiveBorderColor: outlines ? DemoPalette.blue : null,
      splitBorderWidth: 2,
      dividerGradient: glow
          ? const LinearGradient(
              colors: [DemoPalette.pink, DemoPalette.purple, DemoPalette.blue],
            )
          : null,
      dividerCap: glow ? StrokeCap.round : StrokeCap.butt,
      dividerShadow: glow
          ? const BoxShadow(
              color: DemoPalette.glow,
              blurRadius: 10,
              spreadRadius: 1,
            )
          : null,
      topControlOffset: glow ? const Offset(16, 6) : Offset.zero,
      bottomControlOffset: glow ? const Offset(-16, -6) : Offset.zero,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deposit)
          ColoredBox(
            color: DemoPalette.ink,
            child: Padding(
              padding: const EdgeInsets.only(top: DemoTokens.smallGap),
              child: bar,
            ),
          )
        else
          bar,
        const SizedBox(height: DemoTokens.smallGap),
        Text(DemoCopy.selected(context, titles[_selected])),
      ],
    );
  }
}

/// 用默认控制器共享标签栏与内容页，亦可预览直接 appBar 接入。
class SharedTabs extends StatelessWidget {
  /// 创建共享控制器示例。
  const SharedTabs({super.key, this.asAppBar = false});

  /// 是否将标签栏直接放入局部 Scaffold.appBar。
  final bool asAppBar;

  /// 将控制器置于卡片内部，使重放同时重建控制器与滑动位置。
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: _tabCount,
    animationDuration: demoTransition,
    child: _SharedBody(asAppBar: asAppBar),
  );
}

/// 在默认控制器作用域内启动演示并构建内容。
class _SharedBody extends StatefulWidget {
  /// 创建默认控制器下的预览内容。
  const _SharedBody({required this.asAppBar});

  /// 是否使用 appBar 插槽。
  final bool asAppBar;

  /// 创建自动切换的生命周期。
  @override
  State<_SharedBody> createState() => _SharedBodyState();
}

/// 自动演示共享控制器，重放后从左侧重新开始。
class _SharedBodyState extends State<_SharedBody> {
  /// 首帧布局完成后启动一次控制器过渡。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        DefaultTabController.of(context).animateTo(1);
      }
    });
  }

  /// 省略 selectedIndex 与 onChanged，让控制器成为唯一状态来源。
  @override
  Widget build(BuildContext context) {
    final bar = CurvedDualTabBar(
      titles: [DemoCopy.monthly(context), DemoCopy.yearly(context)],
      safeArea: widget.asAppBar,
    );
    const panels = _TabPanels();
    if (widget.asAppBar) {
      return SizedBox(
        height: _barHeight + _panelHeight,
        child: Scaffold(appBar: bar, body: panels),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [bar, panels]);
  }
}

/// 保留独立曲线背景与原生 TabBar 的组合，并补齐滑动预览。
class NativeTabs extends StatefulWidget {
  /// 创建显式控制器示例。
  const NativeTabs({super.key});

  /// 创建局部控制器状态。
  @override
  State<NativeTabs> createState() => _NativeTabsState();
}

/// 显式控制器与背景动画共用生命周期，重放时一起释放重建。
class _NativeTabsState extends State<NativeTabs>
    with SingleTickerProviderStateMixin {
  /// 驱动原生标签、曲线与内容页的同一控制器。
  late final TabController _controller;

  /// 创建控制器并在首帧后开始一次切换。
  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: _tabCount,
      vsync: this,
      animationDuration: demoTransition,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        _controller.animateTo(1);
      }
    });
  }

  /// 释放此卡片独占的控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 缓存原生前景，用 progress 驱动纯背景绘制。
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CurvedTabBackground(
        selectedIndex: _controller.index,
        progress: _controller.animation,
        child: TabBar(
          controller: _controller,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: DemoCopy.monthly(context)),
            Tab(text: DemoCopy.yearly(context)),
          ],
        ),
      ),
      _TabPanels(controller: _controller),
    ],
  );
}

/// 为共享和显式控制器提供可横向滑动的双语内容。
class _TabPanels extends StatelessWidget {
  /// 创建内容区，空控制器时继承默认控制器。
  const _TabPanels({this.controller});

  /// 可选显式控制器。
  final TabController? controller;

  /// 构建两个易于识别的内容页。
  @override
  Widget build(BuildContext context) => SizedBox(
    height: _panelHeight,
    child: TabBarView(
      controller: controller,
      children: [
        Center(child: Text(tr(context, 'Monthly overview', '月度概览'))),
        Center(child: Text(tr(context, 'Yearly overview', '年度概览'))),
      ],
    ),
  );
}
