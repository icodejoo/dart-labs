import 'package:flutter/material.dart';

import 'demo_kit/demo_kit.dart';
import 'tab_demos.dart';

/// 外观页面与导航共用的英文名称。
const stylesPageEn = 'Colors & curves';

/// 外观页面与导航共用的中文名称。
const stylesPageZh = '配色与曲线';

/// 控制器页面与导航共用的中文名称。
const controllersPageZh = '控制器与滑动';

/// 三层配色与受控选择的可复制示例。
const _colorsCode = '''class ColorExample extends StatefulWidget {
  const ColorExample({super.key});
  @override
  State<ColorExample> createState() => _ColorExampleState();
}

class _ColorExampleState extends State<ColorExample> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => CurvedDualTabBar(
    titles: const ['Deposit', 'Withdraw'],
    selectedIndex: selected,
    onChanged: (index) => setState(() => selected = index),
    safeArea: false,
    unselectedTopInset: 2,
    unselectedBorderColor: const Color(0xFFB39DDB),
    activeGradient: const LinearGradient(
      colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
    ),
    activeTextColor: Colors.white,
    inactiveTextColor: const Color(0xFF2B2640),
  );
}''';

/// 分割线与两侧描边的可复制示例。
const _dividerCode = '''CurvedDualTabBar(
  titles: const ['Left', 'Right'],
  selectedIndex: selectedIndex,
  onChanged: (index) => setState(() => selectedIndex = index),
  safeArea: false,
  leanAmplitude: 0.22,
  unselectedTopInset: 0,
  dividerGradient: const LinearGradient(
    colors: [Colors.pink, Colors.purple, Colors.blue],
  ),
  dividerWidth: 3,
  dividerCap: StrokeCap.round,
  dividerShadow: const BoxShadow(
    color: Colors.black26, blurRadius: 10, spreadRadius: 1,
  ),
  topControlOffset: const Offset(16, 6),
  bottomControlOffset: const Offset(-16, -6),
  activeBorderColor: Colors.pink,
  inactiveBorderColor: Colors.blue,
  splitBorderWidth: 2,
)''';

/// 共享控制器同时驱动曲线与滑动内容的示例。
const _sharedCode = '''DefaultTabController(
  length: 2,
  child: Column(
    children: [
      const CurvedDualTabBar(
        titles: ['Monthly', 'Yearly'],
        safeArea: false,
      ),
      const SizedBox(
        height: 96,
        child: TabBarView(children: [
          Center(child: Text('Monthly')),
          Center(child: Text('Yearly')),
        ]),
      ),
    ],
  ),
)''';

/// 原生前景与独立背景共用动画的示例。
const _nativeCode = '''// Create in State with SingleTickerProviderStateMixin:
// controller = TabController(length: 2, vsync: this);
// Dispose controller in State.dispose().
Column(
  children: [
    CurvedTabBackground(
      selectedIndex: controller.index,
      progress: controller.animation,
      child: TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        tabs: const [Tab(text: 'Left'), Tab(text: 'Right')],
      ),
    ),
    SizedBox(
      height: 96,
      child: TabBarView(
        controller: controller,
        children: const [
          Center(child: Text('Left')),
          Center(child: Text('Right')),
        ],
      ),
    ),
  ],
)''';

/// 当前版本直接放入 appBar 的示例。
const _appBarCode = '''DefaultTabController(
  length: 2,
  child: Scaffold(
    appBar: const CurvedDualTabBar(
      titles: ['Deposit', 'Withdraw'],
      // PreferredSizeWidget; safeArea defaults to true.
    ),
    body: const TabBarView(children: [
      Center(child: Text('Deposit')),
      Center(child: Text('Withdraw')),
    ]),
  ),
)''';

/// 用紧凑网格保留原演示的全部六种外观。
class StylesPage extends StatelessWidget {
  /// 创建外观页面。
  const StylesPage({super.key});

  /// 构建两组外观演示与折叠代码。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, stylesPageEn, stylesPageZh),
    description: tr(
      context,
      'Tap either tab. Replay restarts each transition.',
      '点击任一标签；重放可重新观察每张卡片的过渡。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Colors & layers', '配色与图层'),
        code: _colorsCode,
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('theme'),
                title: tr(context, 'Theme defaults', '主题默认配色'),
                description: tr(
                  context,
                  'Uses the current color scheme.',
                  '随当前亮暗主题调整配色。',
                ),
                child: const StyledTabs(style: TabStyle.theme),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('deposit'),
                title: tr(context, 'Deposit / Withdraw', '充值与提现'),
                description: tr(
                  context,
                  'Base, resting pill and active fill.',
                  '底色、未选底板与选中填充三层叠加。',
                ),
                child: const StyledTabs(style: TabStyle.deposit),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('gradient'),
                title: tr(context, 'Gradient fill', '渐变填充'),
                description: tr(
                  context,
                  'Gradient fill over an outlined pill.',
                  '渐变分割层搭配可见底板边框。',
                ),
                child: const StyledTabs(style: TabStyle.gradient),
              ),
            ),
          ],
        ),
      ),
      DemoSection(
        title: tr(context, 'Curve & borders', '曲线与描边'),
        code: _dividerCode,
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('curve'),
                title: tr(context, 'Full-height S-curve', '贯穿高度的 S 曲线'),
                description: tr(
                  context,
                  'Two solid fills make the shape clear.',
                  '纯色对比展示曲线，倾斜幅度 0.22。',
                ),
                child: const StyledTabs(style: TabStyle.curve),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('outlines'),
                title: tr(context, 'Separate outlines', '独立轮廓描边'),
                description: tr(
                  context,
                  'Divider and each side have their own stroke.',
                  '分割线与左右两侧各有独立描边。',
                ),
                child: const StyledTabs(style: TabStyle.outlines),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('glow'),
                title: tr(context, 'Divider details', '分割线细节'),
                description: tr(
                  context,
                  'Gradient, round caps, glow and control offsets.',
                  '渐变、圆头线帽、发光与控制点偏移。',
                ),
                child: const StyledTabs(style: TabStyle.glow),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Exactly two tabs; tap a card heading for full details.',
          '仅支持两个标签；点击卡片标题可查看完整说明。',
        ),
      ),
    ],
  );
}

/// 展示共享控制器、原生背景组合和直接 appBar 三种接入方式。
class ControllersPage extends StatelessWidget {
  /// 创建控制器页面。
  const ControllersPage({super.key});

  /// 构建控制器卡片和当前 API 的代码。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Controllers', controllersPageZh),
    description: tr(
      context,
      'Tap or swipe; the curve follows.',
      '点击标签或滑动内容，曲线跟随同一个控制器。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Shared selection', '统一选中状态'),
        code: _sharedCode,
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('shared'),
                title: tr(context, 'Shared controller', '共享控制器'),
                description: tr(
                  context,
                  'DefaultTabController owns selection.',
                  '由 DefaultTabController 统一管理选中态。',
                ),
                child: const SharedTabs(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('native'),
                title: tr(context, 'Native TabBar', '原生 TabBar'),
                description: tr(
                  context,
                  'CurvedTabBackground follows controller.animation.',
                  '独立背景通过 progress 跟随原生动画。',
                ),
                child: const NativeTabs(),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                key: const ValueKey('appbar'),
                title: tr(context, 'Direct appBar', '直接作为 appBar'),
                description: tr(
                  context,
                  'PreferredSizeWidget with top SafeArea.',
                  '实现 PreferredSizeWidget，默认避开顶部安全区。',
                ),
                child: const SharedTabs(asAppBar: true),
              ),
            ),
          ],
        ),
      ),
      DemoSection(
        title: tr(context, 'Native background composition', '原生背景组合'),
        code: _nativeCode,
        child: InfoNote(
          text: tr(
            context,
            'Keep the native TabBar in child so animation frames reuse it.',
            '将原生 TabBar 放在 child 中，让动画帧复用前景。',
          ),
        ),
      ),
      DemoSection(
        title: tr(context, 'Scaffold integration', '接入 Scaffold'),
        code: _appBarCode,
        child: InfoNote(
          text: tr(
            context,
            'With a shared controller, omit selectedIndex and onChanged. Use safeArea: false for inline bars.',
            '共享控制器时省略 selectedIndex 和 onChanged；内嵌标签栏用 safeArea: false。',
          ),
        ),
      ),
    ],
  );
}
