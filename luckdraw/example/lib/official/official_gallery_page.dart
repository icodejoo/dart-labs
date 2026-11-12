import 'package:flutter/material.dart';

import 'grid_demos.dart';
import 'more_demos.dart';
import 'official_demo.dart';
import 'slot_demos.dart';
import 'wheel_demos.dart';

/// 官方示例站（100px.net）基础示例与完整示例的 1:1 复刻页，用于对照验证 luckdraw。
///
/// 每个条目左侧是官方截图，右侧是 luckdraw 的实时渲染；例如 `const OfficialGalleryPage()`。
class OfficialGalleryPage extends StatelessWidget {
  /// 创建对照页。
  const OfficialGalleryPage({super.key});

  /// 官方站的四个分区：基础示例三页 + 完整示例。
  static final List<OfficialSection> sections = [
    OfficialSection('大转盘', wheelDemos),
    OfficialSection('九宫格', gridDemos),
    OfficialSection('老虎机', slotDemos),
    OfficialSection('完整示例', moreDemos),
  ];

  /// 构建分区标签与条目列表。
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: sections.length,
      child: Scaffold(
          appBar: AppBar(
              title: const Text('官方示例对照'),
              bottom: TabBar(tabs: [
                for (final s in sections)
                  Tab(text: '${s.title}(${s.demos.length})')
              ])),
          body: TabBarView(children: [
            for (final s in sections) _SectionList(section: s),
          ])));
}

/// 单个分区的滚动列表。
class _SectionList extends StatelessWidget {
  /// 创建列表。
  const _SectionList({required this.section});

  /// 要展示的分区。
  final OfficialSection section;

  /// 构建条目卡片列表。
  @override
  Widget build(BuildContext context) => ListView.separated(
      key: PageStorageKey<String>(section.title),
      padding: const EdgeInsets.all(12),
      itemCount: section.demos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) =>
          _DemoCard(index: i + 1, demo: section.demos[i]));
}

/// 单个条目的对照卡片。
class _DemoCard extends StatelessWidget {
  /// 创建卡片；[index] 从 1 起，与官方页面顺序一致。
  const _DemoCard({required this.index, required this.demo});

  /// 官方页面上的序号。
  final int index;

  /// 条目。
  final OfficialDemo demo;

  /// 宽屏左右对照，窄屏上下对照。
  @override
  Widget build(BuildContext context) {
    final official = _Labeled(
        label: '官方截图',
        child: Image.asset('assets/official_ref/${demo.refAsset}.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('无截图')));
    final ours = _Labeled(label: 'luckdraw', child: demo.builder(context));
    return Card(
        key: ValueKey('official-${demo.id}'),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$index. ${demo.title}',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              LayoutBuilder(
                  builder: (_, c) => c.maxWidth >= 560
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(child: official),
                              const SizedBox(width: 12),
                              Expanded(child: ours),
                            ])
                      : Column(children: [
                          official,
                          const SizedBox(height: 12),
                          ours
                        ])),
            ])));
  }
}

/// 带小标题的容器。
class _Labeled extends StatelessWidget {
  /// 创建容器。
  const _Labeled({required this.label, required this.child});

  /// 小标题。
  final String label;

  /// 内容。
  final Widget child;

  /// 小标题在上，内容居中。
  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).hintColor)),
        const SizedBox(height: 4),
        child,
      ]);
}
