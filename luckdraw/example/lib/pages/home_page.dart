import 'package:flutter/material.dart';

import '../theme/demo_theme.dart';

/// 演示入口卡片网格；[pages] 保持调用方提供的全部路由。
class DemoHomePage extends StatelessWidget {
  /// 创建首页；例如 `DemoHomePage(pages: [('转盘', () => WheelPage())])`。
  const DemoHomePage({super.key, required this.pages});

  /// 可见标题与页面工厂；未归类的路由仍显示在最后一组。
  final List<(String, Widget Function())> pages;

  /// 官方三玩法的稳定标题。
  static const _upstream = ['转盘', '九宫格', '老虎机'];

  /// 新增玩法的稳定标题。
  static const _extra = ['拉霸机', '扭蛋机', '数字转盘', '抽签', '大乐透'];

  /// 构建按主题切换的单一滚动页面。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('luckdraw 示例'), actions: [
        Padding(
            padding: const EdgeInsets.only(right: DemoSpace.xl),
            child: Icon(Icons.auto_awesome_rounded,
                color: scheme.primary, size: 20)),
      ]),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            DemoSpace.xl, DemoSpace.md, DemoSpace.xl, DemoSpace.xxl),
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: DemoSpace.maxWidth),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(DemoSpace.xl),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [DemoPalette.ink, DemoPalette.primary]),
                          borderRadius:
                              BorderRadius.circular(DemoSpace.stageRadius),
                        ),
                        child: Stack(children: [
                          Positioned(
                              right: -18,
                              top: 0,
                              child: Transform.rotate(
                                  angle: -.2,
                                  child: Icon(Icons.card_giftcard_rounded,
                                      size: 124,
                                      color: DemoPalette.periwinkle
                                          .withAlpha(45)))),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('LUCKDRAW / PLAYGROUND',
                                    style: TextStyle(
                                        color: DemoPalette.periwinkle,
                                        fontSize: 10,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: DemoSpace.lg),
                                const Text('今天，也有\n好手气。',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        height: 1.2,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(height: DemoSpace.md),
                                Text('挑一个喜欢的玩法，开启小小惊喜',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: DemoPalette.lavender)),
                              ]),
                        ]),
                      ),
                      _group(
                          context,
                          '上游三玩法',
                          'CLASSICS',
                          pages
                              .where((page) => _upstream.contains(page.$1))
                              .toList()),
                      _group(
                          context,
                          '新增玩法',
                          'MORE TO EXPLORE',
                          pages
                              .where((page) => _extra.contains(page.$1))
                              .toList()),
                      _group(
                          context,
                          '迁移与叠加',
                          'BUILD YOUR OWN',
                          pages
                              .where((page) =>
                                  !_upstream.contains(page.$1) &&
                                  !_extra.contains(page.$1))
                              .toList()),
                      const SizedBox(height: DemoSpace.xl),
                      Text('用一点点期待，点亮平常的一天',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ]))),
      )),
    );
  }

  /// 按可用宽度排列两列卡片，窄窗口仍保留完整可见标题。
  Widget _group(BuildContext context, String title, String caption,
          List<(String, Widget Function())> entries) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: DemoSpace.xl),
        Row(children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(caption,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 9,
                  letterSpacing: .7)),
        ]),
        const SizedBox(height: DemoSpace.md),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth < 280 ? 1 : 2;
          return Wrap(
              spacing: DemoSpace.md,
              runSpacing: DemoSpace.md,
              children: [
                for (final entry in entries)
                  SizedBox(
                      width: (constraints.maxWidth -
                              DemoSpace.md * (columns - 1)) /
                          columns,
                      child: _tile(context, entry)),
              ]);
        }),
      ]);

  /// 每个入口保留原路由可见文本及原导航方式。
  Widget _tile(BuildContext context, (String, Widget Function()) entry) {
    final scheme = Theme.of(context).colorScheme;
    final (description, icon) = demoDescription(entry.$1);
    return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DemoSpace.radius),
          onTap: () => Navigator.of(context)
              .push<void>(MaterialPageRoute(builder: (_) => entry.$2())),
          child: DemoCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(DemoSpace.sm),
                      decoration: BoxDecoration(
                          color: scheme.primary.withAlpha(18),
                          borderRadius: BorderRadius.circular(DemoSpace.md)),
                      child: Icon(icon, color: scheme.primary, size: 24)),
                  const Spacer(),
                  Icon(Icons.arrow_outward_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                ]),
                const SizedBox(height: DemoSpace.md),
                Text(entry.$1,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: DemoSpace.xs),
                Text(description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant, height: 1.5)),
              ])),
        ));
  }
}
