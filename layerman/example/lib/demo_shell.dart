import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'pages/catalog_page.dart';
import 'pages/presenters_page.dart';
import 'pages/setup_page.dart';
import 'scenarios.dart';

/// 包名及网页标题。
const demoProject = 'layerman';

/// 与包 pubspec.yaml 同步的版本，由 widget 测试校验。
const demoVersion = '1.0.4';

/// 当前包的代码目录，与 pubspec.yaml 的主页一致。
const demoRepository =
    'https://github.com/icodejoo/dart-labs/tree/layerman/layerman';

/// 当前包的英文文档地址。
const demoReadme =
    'https://github.com/icodejoo/dart-labs/blob/layerman/layerman/README.md';

/// 使用统一页头和 hash 导航的功能入口。
class LayermanDemoShell extends StatelessWidget {
  /// 创建入口，可指定初始页面。
  const LayermanDemoShell({super.key, this.initialFragment});

  /// 初始页面路径。
  final String? initialFragment;

  /// 按主题生成稳定的双语导航。
  @override
  Widget build(BuildContext context) => DemoShell(
    project: demoProject,
    version: demoVersion,
    pubUrl: 'https://pub.dev/packages/$demoProject',
    githubUrl: demoRepository,
    readmeUrl: demoReadme,
    initialFragment: initialFragment,
    destinations: [
      for (final group in demoGroups)
        DemoDestination(
          id: group.id,
          en: group.en,
          zh: group.zh,
          icon: group.icon,
          builder: (_) => CatalogPage(group: group),
        ),
      DemoDestination(
        id: 'presenters',
        en: 'UI backends',
        zh: 'UI 后端',
        icon: Icons.open_in_new_rounded,
        builder: (_) => const PresentersPage(),
      ),
      DemoDestination(
        id: 'setup',
        en: 'Setup',
        zh: '接入说明',
        icon: Icons.settings_outlined,
        builder: (_) => const SetupPage(),
      ),
      DemoDestination(
        id: 'diagnostics',
        en: 'Queue diagnostics',
        zh: '队列诊断',
        sectionEn: 'Benchmarks',
        sectionZh: '压测',
        icon: Icons.monitor_heart_outlined,
        builder: (_) => const CatalogPage(group: diagnosticsGroup),
      ),
    ],
  );
}
