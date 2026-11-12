import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_support.dart';
import 'pages/basic_page.dart';
import 'pages/ttl_page.dart';
import 'pages/batch_page.dart';
import 'pages/namespace_page.dart';
import 'pages/advanced_page.dart';
import 'pages/async_page.dart';
import 'pages/hub_page.dart';
import 'pages/types_page.dart';

/// 启动自包含的当前版本演示。
void main() => runApp(const CachemanDemoApp());

/// 提供双语、明暗主题与地址导航的演示应用。
class CachemanDemoApp extends StatelessWidget {
  /// 创建应用，可注入语言及初始页面供测试使用。
  const CachemanDemoApp({super.key, this.locale, this.initialFragment});

  /// 由调用者管理生命周期的语言状态。
  final DemoLocale? locale;

  /// 可选的初始页面地址。
  final String? initialFragment;

  /// 构建当前公开 API 的八个功能入口。
  @override
  Widget build(BuildContext context) => DemoApp(
    title: demoProject,
    seedColor: Colors.teal,
    locale: locale,
    home: DemoShell(
      project: demoProject,
      version: '0.7.1',
      pubUrl: demoPubUrl,
      githubUrl: 'https://github.com/icodejoo/dart-labs/tree/main/cacheman',
      readmeUrl:
          'https://github.com/icodejoo/dart-labs/blob/main/cacheman/README.md',
      initialFragment: initialFragment,
      destinations: [
        DemoDestination(
          id: 'basic',
          en: DemoCopy.basic.en,
          zh: DemoCopy.basic.zh,
          icon: Icons.storage_rounded,
          builder: (_) => const BasicPage(),
        ),
        DemoDestination(
          id: 'ttl',
          en: DemoCopy.ttl.en,
          zh: DemoCopy.ttl.zh,
          icon: Icons.timer_outlined,
          builder: (_) => const TtlPage(),
        ),
        DemoDestination(
          id: 'batch',
          en: DemoCopy.batch.en,
          zh: DemoCopy.batch.zh,
          icon: Icons.list_alt_rounded,
          builder: (_) => const BatchPage(),
        ),
        DemoDestination(
          id: 'namespace',
          en: DemoCopy.namespace.en,
          zh: DemoCopy.namespace.zh,
          icon: Icons.folder_outlined,
          builder: (_) => const NamespacePage(),
        ),
        DemoDestination(
          id: 'advanced',
          en: DemoCopy.advanced.en,
          zh: DemoCopy.advanced.zh,
          icon: Icons.data_object_rounded,
          builder: (_) => const AdvancedPage(),
        ),
        DemoDestination(
          id: 'async',
          en: DemoCopy.async.en,
          zh: DemoCopy.async.zh,
          icon: Icons.layers_outlined,
          builder: (_) => const AsyncPage(),
        ),
        DemoDestination(
          id: 'hub',
          en: DemoCopy.hub.en,
          zh: DemoCopy.hub.zh,
          icon: Icons.sync_rounded,
          builder: (_) => const HubPage(),
        ),
        DemoDestination(
          id: 'types',
          en: DemoCopy.types.en,
          zh: DemoCopy.types.zh,
          icon: Icons.rule_rounded,
          builder: (_) => const TypesPage(),
        ),
      ],
    ),
  );
}
