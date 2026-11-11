import 'package:flutter/material.dart';
import 'package:luckdraw/lots.dart';

import '../demo_shell.dart';
import '../theme/demo_theme.dart';
import '../theme/lots_art.dart';

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

  /// 服务端下标对应的签文：签级、签诗；前三项与历史示例保持一致。
  static const List<(String, String)> _lots = [
    ('吉', '平安顺遂\n万事安康'),
    ('上上签', '心愿可期\n福至心灵'),
    ('大吉', '一路生花\n步步高升'),
    ('中吉', '稳中有进\n守得云开'),
    ('小吉', '静待花开\n来日方长'),
    ('上吉', '好运临门\n喜事将近'),
  ];

  /// 签筒、签与签文卡全部由示例自绘，库只提供自定义入口（见 lots_art.dart）。
  static final LotsConfig config = LotsConfig(
      sticks: [
        for (final (grade, poem) in _lots)
          LotsStick(
              label: grade,
              weight: 1,
              painter: lotsCardPainter(grade: grade, poem: poem)),
      ],
      style: const LotsStyle(
          background: LuckyFill.color(Color(0x00000000)),
          cylinderFill: LuckyFill.color(Color(0x00000000)),
          backFill: LuckyFill.color(Color(0x00000000)),
          cardFill: LuckyFill.color(Color(0x00000000)),
          backgroundPainter: paintLotsScene,
          cylinderBackPainter: paintLotsCylinderBack,
          cylinderFrontPainter: paintLotsCylinderFront,
          stickPainter: paintLotsStick,
          textColor: DemoPalette.ink,
          fontFamily: 'Microsoft YaHei'),
      options: const LotsOptions(
          motion: demoMotion,
          riseEasing: lotsSpringEasing,
          revealEasing: lotsSpringEasing,
          shakeWaveform: lotsRattleWaveform,
          layoutAdjuster: adjustLotsLayout));

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
