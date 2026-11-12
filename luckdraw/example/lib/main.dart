import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_kit/demo_kit.dart';
import 'online/playground_page.dart';
import 'theme/demo_theme.dart';

export 'native_main.dart' show LuckdrawExample;

/// 页头与应用标题共用的包名。
const _project = 'luckdraw';

/// 版本信息的唯一资产来源，构建时随包清单更新。
const packageManifest = '../pubspec.yaml';

/// pub.dev 包详情地址。
const packageUrl = 'https://pub.dev/packages/luckdraw';

/// 仓库地址与文档链接共用的根路径。
const repositoryUrl = 'https://github.com/icodejoo/dart-labs';

/// 包目录地址，与公开包清单保持一致。
const sourceUrl = '$repositoryUrl/tree/main/luckdraw';

/// 从打包的真实清单读取版本，不依赖 example 自身版本。
Future<String> loadPackageVersion() async {
  final manifest = await rootBundle.loadString(packageManifest);
  return RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(manifest)!
      .group(1)!;
}

/// 启动中英双语的线上演示。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final version = await loadPackageVersion();
  runApp(LuckdrawDemo(version: version));
}

/// 统一语言、主题与导航的线上演示宿主。
class LuckdrawDemo extends StatelessWidget {
  /// 创建演示应用；版本来自包清单，可注入语言和初始页面以验证导航。
  const LuckdrawDemo(
      {super.key, required this.version, this.locale, this.fragment});

  /// 包清单中的当前版本。
  final String version;

  /// 可选的外部语言状态。
  final DemoLocale? locale;

  /// 可选的初始页面片段。
  final String? fragment;

  /// 构建统一页头与三个主题页面。
  @override
  Widget build(BuildContext context) => DemoApp(
        title: _project,
        seedColor: DemoPalette.primary,
        locale: locale,
        home: Builder(
            builder: (context) => DemoShell(
                  project: _project,
                  version: version,
                  pubUrl: packageUrl,
                  githubUrl: sourceUrl,
                  readmeUrl:
                      '$repositoryUrl/blob/main/luckdraw/${tr(context, 'README.md', 'README.zh-CN.md')}',
                  initialFragment: fragment,
                  destinations: [
                    DemoDestination(
                        id: 'games',
                        en: 'Eight games',
                        zh: '八种玩法',
                        icon: Icons.casino_outlined,
                        builder: (_) =>
                            const PlaygroundPage(group: PlaygroundGroup.games)),
                    DemoDestination(
                        id: 'physics',
                        en: 'Physics',
                        zh: '物理碰撞',
                        icon: Icons.bubble_chart_outlined,
                        builder: (_) => const PlaygroundPage(
                            group: PlaygroundGroup.physics)),
                    DemoDestination(
                        id: 'integration',
                        en: 'Migration & overlays',
                        zh: '迁移与叠加',
                        icon: Icons.layers_outlined,
                        sectionEn: 'Integration',
                        sectionZh: '集成',
                        builder: (_) => const PlaygroundPage(
                            group: PlaygroundGroup.integration)),
                  ],
                )),
      );
}
