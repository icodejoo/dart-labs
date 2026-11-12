import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'sample_code.dart';

/// 计数器页面，合并重复的格式与动画变体。
class CounterPage extends StatefulWidget {
  /// 创建计数器页面。
  const CounterPage({super.key});

  /// 创建交互状态。
  @override
  State<CounterPage> createState() => _CounterPageState();
}

/// 管理当前目标值与重播代次。
class _CounterPageState extends State<CounterPage> {
  /// 每次交互增加的目标值。
  static const _step = 1234.5;

  /// 当前目标值。
  double _value = _step;

  /// 改变目标值，触发数字过渡。
  void _increment() => setState(() => _value += _step);

  /// 构建可重播的计数器卡片网格。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Counter', '计数器'),
    description: tr(
      context,
      'Change a value. Explore rolling digits, text and progress with the current options API.',
      '改变目标值，体验滚动数字、文本和进度；示例使用当前版本的配置对象。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Numbers in motion', '动态数字'),
        code: combineSampleCode([
          'counter',
          'text-counter',
          'odometer',
          'counter-progress',
        ]),
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                title: 'AnimatedCounter',
                description: tr(
                  context,
                  'CounterFormat + CounterTimeline. Try a new target.',
                  '用 CounterFormat 和 CounterTimeline 配置；试试新目标。',
                ),
                child: Column(
                  children: [
                    counterSample(_value),
                    FilledButton.icon(
                      onPressed: _increment,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(tr(context, 'Change value', '改变数值')),
                    ),
                  ],
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: 'TextCounter',
                description: tr(
                  context,
                  'Interpolate from zero using a style object.',
                  '从零平滑插值，用样式对象设置外观。',
                ),
                child: KeyedSubtree(
                  key: ValueKey(_value),
                  child: textCounterSample(_value),
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: 'OdometerCounter',
                description: tr(
                  context,
                  'Rolling digits without obsolete slot and fade controls.',
                  '滚动数字；不再使用已失效的槽位和淡出参数。',
                ),
                child: KeyedSubtree(
                  key: ValueKey(_value),
                  child: odometerSample(_value),
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                title: tr(context, 'Ring & bar', '环形与条形'),
                description: tr(
                  context,
                  'The same progress rendered in two shapes.',
                  '同样的进度，两种显示方式。',
                ),
                child: KeyedSubtree(
                  key: ValueKey(_value),
                  child: counterProgressSample(),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
