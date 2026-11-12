import 'package:flutter/material.dart';

import 'demo_kit/demo_kit.dart';
import 'demo_pages.dart';
import 'demo_palette.dart';

/// 包名与线上演示的统一标识。
const demoProject = 'curved_dual_tab_bar';

/// 与包 pubspec.yaml 同步，并由 widget 测试校验的当前版本。
const demoVersion = '0.2.4';

/// 包源码目录的外链。
const demoGithubUrl =
    'https://github.com/icodejoo/dart-labs/tree/main/$demoProject';

/// 包文档的外链。
const demoReadmeUrl =
    'https://github.com/icodejoo/dart-labs/blob/main/$demoProject/README.md';

/// 包发布页的外链。
const demoPubUrl = 'https://pub.dev/packages/$demoProject';

/// 启动使用统一演示骨架的应用。
void main() => runApp(const CurvedDualTabBarExampleApp());

/// 展示当前 API 的双语响应式演示应用。
class CurvedDualTabBarExampleApp extends StatelessWidget {
  /// 创建应用，可注入语言和页面路径以便验证。
  const CurvedDualTabBarExampleApp({
    super.key,
    this.locale,
    this.initialFragment,
  });

  /// 可选外部管理的语言状态。
  final DemoLocale? locale;

  /// 可选初始页面路径。
  final String? initialFragment;

  /// 构建统一页头、主题和两组演示。
  @override
  Widget build(BuildContext context) => DemoApp(
    title: demoProject,
    seedColor: DemoPalette.purple,
    locale: locale,
    home: DemoShell(
      project: demoProject,
      version: demoVersion,
      pubUrl: demoPubUrl,
      githubUrl: demoGithubUrl,
      readmeUrl: demoReadmeUrl,
      initialFragment: initialFragment,
      destinations: [
        DemoDestination(
          id: 'styles',
          en: stylesPageEn,
          zh: stylesPageZh,
          icon: Icons.palette_outlined,
          builder: (_) => const StylesPage(),
        ),
        DemoDestination(
          id: 'controllers',
          en: 'Controllers & swipes',
          zh: controllersPageZh,
          icon: Icons.swipe_outlined,
          builder: (_) => const ControllersPage(),
        ),
      ],
    ),
  );
}
