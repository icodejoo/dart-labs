import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'scenario_page.dart';
import 'scenarios.dart';

/// 当前包版本，与上级 pubspec.yaml 保持一致并由测试校验。
const demoVersion = '0.8.2';

/// 启动离线可用的线上演示。
void main() => runApp(const DiomanDemoApp());

/// 使用统一骨架展示当前管线 API。
class DiomanDemoApp extends StatelessWidget {
  /// 创建应用，允许测试注入语言和初始页面。
  const DiomanDemoApp({super.key, this.locale, this.initialFragment});

  /// 外部管理的语言状态。
  final DemoLocale? locale;

  /// 初始导航片段。
  final String? initialFragment;

  /// 构建响应式导航、主题和四个场景分组。
  @override
  Widget build(BuildContext context) => DemoApp(
        title: 'dioman',
        seedColor: const Color(0xFF4263EB),
        locale: locale,
        home: DemoShell(
          project: 'dioman',
          version: demoVersion,
          pubUrl: 'https://pub.dev/packages/dioman',
          githubUrl: 'https://github.com/icodejoo/dart-labs/tree/main/dioman',
          readmeUrl:
              'https://github.com/icodejoo/dart-labs/blob/main/dioman/README.md',
          initialFragment: initialFragment,
          destinations: [
            for (final group in demoGroups)
              DemoDestination(
                id: group.id,
                en: group.title.en,
                zh: group.title.zh,
                icon: group.icon,
                builder: (_) => ScenarioPage(group: group),
              ),
          ],
        ),
      );
}
