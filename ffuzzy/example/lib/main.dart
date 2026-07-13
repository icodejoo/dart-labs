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
  // Web: load the WASM engine from the published npm package.
  // On native this is a no-op, so it's safe to always call.
  //
  // Web 端：从已发布的 npm 包加载 WASM 引擎；native 端这是空操作，
  // 所以随时调用都安全。
  await ffuzzyInit(
    webUrl: 'https://cdn.jsdelivr.net/npm/@codejoo/ffuzzy@0.7.0/dist/ffz.mjs',
  );
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
    Tab(text: '搜索模式 (9)'),
    Tab(text: 'Raws变体 (8)'),
    Tab(text: '增删改 (9)'),
    Tab(text: '静态构造 (3)'),
    Tab(text: 'Async镜像 (20)'),
    Tab(text: '工具函数 (1)'),
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
