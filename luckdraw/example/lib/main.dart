import 'package:flutter/material.dart';

import 'official/official_gallery_page.dart';
import 'pages/capsule_page.dart';
import 'pages/compat_page.dart';
import 'pages/grid_page.dart';
import 'pages/home_page.dart';
import 'pages/lever_page.dart';
import 'pages/lots_page.dart';
import 'pages/lotto_page.dart';
import 'pages/number_wheel_page.dart';
import 'pages/overlay_page.dart';
import 'pages/slot_page.dart';
import 'pages/wheel_page.dart';
import 'readme_snippets.dart';
import 'theme/demo_theme.dart';

/// 启动全玩法示例。
void main() => runApp(const LuckdrawExample());

/// 全玩法入口；例如 `runApp(const LuckdrawExample())`。
class LuckdrawExample extends StatelessWidget {
  /// 创建带独立页面路由的示例应用。
  const LuckdrawExample({super.key});

  /// 构建应用主题和首页。
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'luckdraw',
        debugShowCheckedModeBanner: false,
        theme: demoTheme(Brightness.light),
        darkTheme: demoTheme(Brightness.dark),
        home: const _HomePage(),
      );
}

/// 展示全部示例入口。
class _HomePage extends StatelessWidget {
  /// 创建首页。
  const _HomePage();

  /// 路由名称与创建函数。
  static final List<(String, Widget Function())> _pages = [
    ('官方示例对照', () => const OfficialGalleryPage()),
    ('转盘', () => const WheelPage()),
    ('九宫格', () => const GridPage()),
    ('老虎机', () => const SlotPage()),
    ('拉霸机', () => const LeverPage()),
    ('扭蛋机', () => const CapsulePage()),
    ('数字转盘', () => const NumberWheelPage()),
    ('抽签', () => const LotsPage()),
    ('大乐透', () => const LottoPage()),
    ('compat 迁移', () => const CompatPage()),
    ('Widget 叠加层', () => const OverlayPage()),
    ('README 代码片段', () => const ReadmeSnippetsPage()),
  ];

  /// 构建可滚动菜单。
  @override
  Widget build(BuildContext context) => DemoHomePage(pages: _pages);
}
