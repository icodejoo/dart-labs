import 'package:curved_dual_tab_bar/curved_dual_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

void main() {
  runApp(const CurvedDualTabBarExampleApp());
}

class CurvedDualTabBarExampleApp extends StatelessWidget {
  const CurvedDualTabBarExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'curved_dual_tab_bar demo',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7C4DFF)),
      home: const CurvedDualTabBarDemoPage(),
    );
  }
}

/// Demo page for [CurvedDualTabBar]: showcases the DEPOSIT/WITHDRAW header
/// from the design mocks, plus a handful of other instances to confirm the
/// component isn't hardcoded to that one use case.
///
/// [CurvedDualTabBar] 的演示页：还原设计稿里的 DEPOSIT/WITHDRAW 头部，
/// 再加上几组不同配色/文案的实例，验证组件没有写死某个具体场景。
class CurvedDualTabBarDemoPage extends HookWidget {
  const CurvedDualTabBarDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final curveCheckSelected = useState(0);
    final dividerSelected = useState(0);
    final depositSelected = useState(0);
    final customSelected = useState(1);
    final gradientSelected = useState(0);

    final nativeTabController = useTabController(initialLength: 2);
    final nativeSelected = useState(0);
    useEffect(() {
      void listener() {
        if (!nativeTabController.indexIsChanging) {
          nativeSelected.value = nativeTabController.index;
        }
      }

      nativeTabController.addListener(listener);
      return () => nativeTabController.removeListener(listener);
    }, [nativeTabController]);

    return Scaffold(
      appBar: AppBar(title: const Text('CurvedDualTabBar Demo')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('曲线本身验证（两侧纯色对比，确认 S 曲线贯穿整个高度）'),
              const SizedBox(height: 8),
              CurvedDualTabBar(
                titles: const ['LEFT', 'RIGHT'],
                selectedIndex: curveCheckSelected.value,
                onChanged: (i) => curveCheckSelected.value = i,
                leanAmplitude: 0.22,
                activeColor: const Color(0xFF7C4DFF),
                inactiveColor: const Color(0xFFEDE7F6),
                unselectedColor: const Color(0xFFEDE7F6),
                unselectedBorderColor: Colors.transparent,
                unselectedTopInset: 0,
                activeTextColor: Colors.white,
                inactiveTextColor: const Color(0xFF4A3F72),
              ),
              const SizedBox(height: 24),
              const Text('还原设计稿配色（三层：底层透明 / 未选中底板 / 左右分割层）'),
              const SizedBox(height: 8),
              Container(
                color: const Color(0xFF2B2640),
                padding: const EdgeInsets.only(top: 16),
                child: CurvedDualTabBar(
                  titles: const ['DEPOSIT', 'WITHDRAW'],
                  selectedIndex: depositSelected.value,
                  onChanged: (i) => depositSelected.value = i,
                  unselectedTopInset: 2,
                  activeColor: const Color(0xFFF3EEFC),
                  activeTextColor: const Color(0xFF2B2640),
                  inactiveTextColor: const Color(0xFF8A82A0),
                  indicatorColor: const Color(0xFFEC4899),
                  indicatorSize: TabBarIndicatorSize.label,
                ),
              ),
              const SizedBox(height: 24),
              const Text('分割曲线描边 + 左右两侧各自不同颜色的描边'),
              const SizedBox(height: 8),
              CurvedDualTabBar(
                titles: const ['LEFT', 'RIGHT'],
                selectedIndex: dividerSelected.value,
                onChanged: (i) => dividerSelected.value = i,
                unselectedTopInset: 0,
                unselectedBorderColor: Colors.transparent,
                dividerColor: const Color(0xFF7C4DFF),
                dividerWidth: 3,
                activeBorderColor: const Color(0xFFEC4899),
                inactiveBorderColor: const Color(0xFF2196F3),
                splitBorderWidth: 2,
              ),
              const SizedBox(height: 24),
              const Text('主题默认配色'),
              const SizedBox(height: 8),
              CurvedDualTabBar(
                titles: const ['月度账单', '年度账单'],
                selectedIndex: customSelected.value,
                onChanged: (i) => customSelected.value = i,
              ),
              const SizedBox(height: 24),
              const Text('自定义分割层渐变 + 可见底板边框'),
              const SizedBox(height: 8),
              CurvedDualTabBar(
                titles: const ['充值', '提现'],
                selectedIndex: gradientSelected.value,
                onChanged: (i) => gradientSelected.value = i,
                unselectedBorderColor: const Color(0xFFB39DDB),
                activeGradient: const LinearGradient(
                  colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
                ),
                inactiveGradient: const LinearGradient(
                  colors: [Colors.transparent, Colors.transparent],
                ),
                activeTextColor: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                '结合原生 TabBar：曲线背景（CurvedTabBackground）作装饰，切换/滑动交给系统 TabBar',
              ),
              const SizedBox(height: 8),
              CurvedTabBackground(
                selectedIndex: nativeSelected.value,
                progress: nativeTabController.animation,
                activeColor: const Color(0xFFFFFFFF),
                unselectedColor: const Color(0xFFEDE7F6),
                unselectedBorderColor: Colors.transparent,
                // TabBar 不依赖 t，放进 child 缓存，动画帧不重建它。
                child: TabBar(
                  controller: nativeTabController,
                  indicatorColor: Colors.transparent,
                  dividerColor: Colors.transparent,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  labelColor: const Color(0xFF2B2640),
                  unselectedLabelColor: const Color(0xFF8A82A0),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(text: 'NATIVE LEFT'),
                    Tab(text: 'NATIVE RIGHT'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '当前选中：${depositSelected.value == 0 ? 'DEPOSIT' : 'WITHDRAW'} / '
                '${customSelected.value == 0 ? '月度账单' : '年度账单'} / '
                '${gradientSelected.value == 0 ? '充值' : '提现'}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
