import 'package:flutter/material.dart';
import 'package:luckdraw/lots.dart';

import '../demo_shell.dart';
import '../theme/demo_theme.dart';

/// 摇签、升签和展示签文示例；例如 `const LotsPage()`。
class LotsPage extends StatefulWidget {
  /// 创建抽签页。
  const LotsPage({super.key});

  /// 创建页面状态。
  @override
  State<LotsPage> createState() => LotsPageState();
}

/// 按固定下标抽签的页面状态。
class LotsPageState extends State<LotsPage> {
  /// 页面拥有的控制器；例如 `controller.lastResult`。
  final LotsController controller = LotsController();

  /// 服务端下标对应的签文列表。
  static const LotsConfig config = LotsConfig(
      sticks: [
        LotsStick(label: '吉', weight: 1, texts: [LuckyText('平安顺遂')]),
        LotsStick(label: '上上签', weight: 1, texts: [LuckyText('心愿可期')]),
        LotsStick(label: '大吉', weight: 1, texts: [LuckyText('一路生花')]),
      ],
      style: LotsStyle(
          background: LuckyFill.color(DemoPalette.lavender),
          cylinderFill: LuckyFill.gradient(
              LinearGradient(colors: [DemoPalette.blue, DemoPalette.primary])),
          backFill: LuckyFill.color(DemoPalette.ink),
          stickFill: LuckyFill.color(DemoPalette.gold),
          cardFill: LuckyFill.color(DemoPalette.cream),
          textColor: DemoPalette.ink,
          fontFamily: 'Microsoft YaHei'),
      options: LotsOptions(motion: demoMotion));

  /// 结果文本。
  String _result = '';

  /// 构建可点按签筒的抽签画布。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '抽签',
      phase: controller.phase,
      result: _result,
      reset: () {
        controller.reset();
        setState(() => _result = '');
      },
      start: () {
        controller.play();
      },
      serverResult: () {
        controller.stop(demoTarget);
      },
      game: LuckyLots(
          config: config,
          controller: controller,
          width: demoSide,
          height: demoTall,
          onStart: () {
            controller.play();
          },
          onEnd: (result) =>
              setState(() => _result = '签文：${result.prize?.label}')));

  /// 释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
