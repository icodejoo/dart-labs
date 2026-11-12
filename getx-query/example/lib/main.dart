import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_support.dart';
import 'pages/query_page.dart';
import 'pages/mutation_page.dart';
import 'pages/infinite_page.dart';
import 'pages/queries_page.dart';
import 'pages/viewmodel_page.dart';

/// 项目在包管理器中的名称。
const demoProject = 'getx_query';

/// 当前包版本资源，由 example 的资产声明指向父级 pubspec。
const demoPubspecAsset = '../pubspec.yaml';

/// 从打包资源读取当前版本，避免手工维护版本 chip。
Future<String> loadDemoVersion() async {
  final yaml = await rootBundle.loadString(demoPubspecAsset);
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(yaml);
  if (match == null) throw StateError('Missing package version');
  return match.group(1)!;
}

/// 启动独立的双语查询演示应用。
void main() => runApp(const GetxQueryDemoApp());

/// 当前公开 API 的统一演示入口。
class GetxQueryDemoApp extends StatefulWidget {
  /// 支持测试注入语言与初始 hash。
  const GetxQueryDemoApp({super.key, this.locale, this.initialFragment});

  /// 外部管理的可选语言状态。
  final DemoLocale? locale;

  /// 初始导航标识。
  final String? initialFragment;

  /// 创建版本资源加载状态。
  @override
  State<GetxQueryDemoApp> createState() => _GetxQueryDemoAppState();
}

/// 仅加载一次版本资源，语言或主题切换不会重新读取。
class _GetxQueryDemoAppState extends State<GetxQueryDemoApp> {
  /// 包版本读取任务。
  late final Future<String> _version = loadDemoVersion();

  /// 构建五类 API 导航与统一页头。
  @override
  Widget build(BuildContext context) => DemoApp(
    title: demoProject,
    seedColor: Colors.orange,
    locale: widget.locale,
    home: FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) => DemoShell(
        project: demoProject,
        version: snapshot.data ?? demoPending,
        pubUrl: 'https://pub.dev/packages/$demoProject',
        githubUrl: 'https://github.com/icodejoo/dart-labs/tree/main/getx-query',
        readmeUrl:
            'https://github.com/icodejoo/dart-labs/blob/main/getx-query/README.md',
        initialFragment: widget.initialFragment,
        destinations: [
          DemoDestination(
            id: 'query',
            en: 'Queries',
            zh: '查询',
            icon: Icons.cloud_download_outlined,
            builder: (_) => const QueryPage(),
          ),
          DemoDestination(
            id: 'mutation',
            en: 'Mutations',
            zh: '数据变更',
            icon: Icons.edit_outlined,
            builder: (_) => const MutationPage(),
          ),
          DemoDestination(
            id: 'infinite',
            en: 'Pagination',
            zh: '分页加载',
            icon: Icons.expand_more_rounded,
            builder: (_) => const InfinitePage(),
          ),
          DemoDestination(
            id: 'queries',
            en: 'Parallel queries',
            zh: '并行查询',
            icon: Icons.widgets_outlined,
            builder: (_) => const QueriesPage(),
          ),
          DemoDestination(
            id: 'viewmodel',
            en: 'Lifecycle',
            zh: '生命周期',
            icon: Icons.architecture_outlined,
            builder: (_) => const ViewModelPage(),
          ),
        ],
      ),
    ),
  );
}
