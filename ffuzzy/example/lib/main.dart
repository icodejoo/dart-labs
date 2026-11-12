import 'package:ffuzzy/ffuzzy.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'package_version.dart';
import 'search_page.dart';
import 'lifecycle_page.dart';
import 'constructors_page.dart';

/// 项目名称与链接路径中的包名。
const projectName = 'ffuzzy';

/// 当前包的源码主页。
const repositoryUrl =
    'https://github.com/icodejoo/dart-labs/tree/main/$projectName';

/// 初始化配套的本地 WASM 引擎并启动演示。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ffuzzyInit(webUrl: './ffuzzy.mjs');
  runApp(const FuzzyDemoApp());
}

/// 使用统一骨架展示当前公开 API。
class FuzzyDemoApp extends StatelessWidget {
  /// 创建应用；可注入语言和页面 hash 以供测试。
  const FuzzyDemoApp({super.key, this.locale, this.initialFragment});

  /// 外部可控的演示语言。
  final DemoLocale? locale;

  /// 初始页面 hash。
  final String? initialFragment;

  /// 构建双语页面导航与统一页头。
  @override
  Widget build(BuildContext context) => DemoApp(
        title: projectName,
        seedColor: const Color(0xFF4263EB),
        locale: locale,
        home: DemoShell(
          project: projectName,
          version: packageVersion,
          pubUrl: 'https://pub.dev/packages/$projectName',
          githubUrl: repositoryUrl,
          readmeUrl:
              'https://github.com/icodejoo/dart-labs/blob/main/$projectName/README.md',
          initialFragment: initialFragment,
          destinations: [
            DemoDestination(
                id: 'search',
                en: 'Search',
                zh: '搜索',
                icon: Icons.search_rounded,
                builder: (_) => const SearchPage()),
            DemoDestination(
                id: 'lifecycle',
                en: 'Corpus lifecycle',
                zh: '语料生命周期',
                icon: Icons.storage_rounded,
                builder: (_) => const LifecyclePage()),
            DemoDestination(
                id: 'constructors',
                en: 'Constructors & highlights',
                zh: '构造与高亮',
                icon: Icons.data_object_rounded,
                builder: (_) => const ConstructorsPage()),
            DemoDestination(
                id: 'benchmark',
                en: 'Async build',
                zh: '异步构建',
                sectionEn: 'Benchmarks',
                sectionZh: '压测',
                icon: Icons.speed_rounded,
                builder: (_) => const BuildBenchmarkPage()),
          ],
        ),
      );
}
