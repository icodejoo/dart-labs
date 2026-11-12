import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'sample_code.dart';

/// 展示聚合 Provider 与当前推荐的主题扩展。
class ProviderPage extends StatefulWidget {
  /// 创建作用域与主题页面。
  const ProviderPage({super.key});

  /// 创建重播状态。
  @override
  State<ProviderPage> createState() => _ProviderPageState();
}

/// 维护作用域示例的重播代次。
class _ProviderPageState extends State<ProviderPage> {
  /// 重播代次。
  int _generation = 0;

  /// 重新挂载分组示例。
  void _restart() => setState(() => _generation++);

  /// 构建主题与作用域网格。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Providers & theme', '作用域与主题'),
    description: tr(
      context,
      'Share plugin groups with providers and visual defaults with CountmanTheme. Widget styles take priority.',
      '用 Provider 共享插件分组，用 CountmanTheme 统一默认外观；组件自身的样式优先。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Scope and style', '分组与外观'),
        code: combineSampleCode(['providers', 'theme']),
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: 'CountmanProvider',
                description: tr(
                  context,
                  'One scope for counter, countdown and elapsed families.',
                  '一个作用域聚合计数器、倒计时和正计时。',
                ),
                child: Column(
                  children: [
                    KeyedSubtree(
                      key: ValueKey(_generation),
                      child: providerSample(),
                    ),
                    TextButton(
                      onPressed: _restart,
                      child: Text(tr(context, 'Replay group', '重播分组')),
                    ),
                  ],
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: 'CountmanTheme',
                description: tr(
                  context,
                  'Use ThemeData.extensions for visual defaults.',
                  '通过 ThemeData.extensions 设置默认样式。',
                ),
                child: Center(child: themeSample(context)),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        kind: InfoNoteKind.deprecated,
        text: tr(
          context,
          'Provider-level *Style arguments are deprecated. Move visual defaults into CountmanTheme; keep providers for grouping and behavior.',
          'Provider 上的 *Style 参数已弃用。将默认外观迁入 CountmanTheme，Provider 继续负责分组和行为。',
        ),
      ),
    ],
  );
}
