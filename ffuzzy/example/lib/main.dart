// ffuzzy API showcase: one demo card per public FuzzyCorpus method (~50
// cards across 6 tabs), plus a live code snippet on every card.
//
// ffuzzy API 全展示：FuzzyCorpus 每个公开方法对应一张 demo 卡片（6 个 Tab
// 共约 50 张），每张卡都附带对应的实时代码片段。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import 'tabs/async_tab.dart';
import 'tabs/mutation_tab.dart';
import 'tabs/raws_specs.dart';
import 'tabs/search_modes_specs.dart';
import 'tabs/shared_query_tab.dart';
import 'tabs/static_tab.dart';
import 'tabs/utility_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: load the locally-built WASM engine (copied into web/ from
  // wasm/dist/ffuzzy.mjs) instead of the CDN — the published npm package
  // predates today's fixes, and jsdelivr@0.7.0/dist/ffz.mjs no longer
  // resolves (the dist filename changed). On native this call is a no-op.
  //
  // Web 端：从本地构建产物加载 WASM 引擎（从 wasm/dist/ffuzzy.mjs 拷贝到
  // web/ 下），而不是走 CDN —— 已发布的 npm 包还没有今天的修复，且
  // jsdelivr@0.7.0/dist/ffz.mjs 已经找不到了（dist 文件名变了）。
  // native 端这个调用是空操作。
  await ffuzzyInit(webUrl: './ffuzzy.mjs');
  runApp(const FuzzyDemoApp());
}

class FuzzyDemoApp extends StatelessWidget {
  const FuzzyDemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ffuzzy API showcase',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const _ShowcasePage(),
      );
}

class _ShowcasePage extends StatelessWidget {
  const _ShowcasePage();

  static const _tabs = [
    Tab(text: 'Search modes (12)'),
    Tab(text: 'Raws variants (8)'),
    Tab(text: 'Mutation (9)'),
    Tab(text: 'Static ctors (3)'),
    Tab(text: 'Async mirrors (20)'),
    Tab(text: 'Utilities (1)'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ffuzzy API showcase'),
          bottom: const TabBar(isScrollable: true, tabs: _tabs),
        ),
        body: TabBarView(
          children: [
            SharedQueryTab(tabId: 1, specs: searchModeSpecs),
            SharedQueryTab(tabId: 2, specs: rawsSpecs),
            const MutationTab(),
            const StaticTab(),
            const AsyncTab(),
            const UtilityTab(),
          ],
        ),
      ),
    );
  }
}
