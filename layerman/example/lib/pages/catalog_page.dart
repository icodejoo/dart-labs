import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../scenarios.dart';
import '../widgets/scenario_demo.dart';

/// 将同一主题的真实引擎示例排列为紧凑网格。
class CatalogPage extends StatelessWidget {
  /// 创建由目录数据驱动的页面。
  const CatalogPage({super.key, required this.group});

  /// 当前主题的双语目录。
  final DemoGroup group;

  /// 构建演示及占满整行的可复制代码。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, group.en, group.zh),
    description: tr(context, group.descriptionEn, group.descriptionZh),
    sections: [
      DemoSection(
        title: tr(context, 'Try the API', '动手试试'),
        code: group.scenarios.map((scenario) => scenario.code).join('\n\n'),
        child: DemoGrid(
          children: [
            for (final scenario in group.scenarios)
              DemoGridItem(
                child: DemoCard(
                  key: ValueKey(scenario.name),
                  title: tr(context, scenario.en, scenario.zh),
                  description: tr(
                    context,
                    scenario.descriptionEn,
                    scenario.descriptionZh,
                  ),
                  child: ScenarioDemo(scenario: scenario),
                ),
              ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Each card owns its manager. Replay restores its queue, timers, data and cooldowns. The preview is a real present backend; UI libraries are on the UI backends page.',
          '每张卡片独立运行 manager；重放会恢复队列、计时、数据和冷却。预览通过真实 present 后端绘制；UI 库见「UI 后端」页。',
        ),
      ),
    ],
  );
}
