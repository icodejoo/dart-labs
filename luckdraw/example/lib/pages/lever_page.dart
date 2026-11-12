import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';

import '../demo_shell.dart';
import '../online/localized_config.dart';
import 'slot_page.dart';

/// 拖动拉杆的错峰停轮示例；例如 `const LeverPage()`。
class LeverPage extends StatefulWidget {
  /// 创建拉霸机页。
  const LeverPage({super.key});

  /// 创建页面状态。
  @override
  State<LeverPage> createState() => LeverPageState();
}

/// 可观测逐轮停下过程的页面状态。
class LeverPageState extends State<LeverPage> {
  /// 本页拥有的控制器；例如 `controller.frame.scroll`。
  final SlotController controller = SlotController();

  /// 有效拉杆次数。
  int pulls = 0;

  /// 结算文本。
  String _result = '';

  /// 展示原生拉杆拖动交互。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '拉霸机',
      phase: controller.phase,
      result: _result,
      reset: () {
        controller.reset();
        setState(() {
          _result = '';
          pulls = 0;
        });
      },
      start: () {
        controller.play();
      },
      serverResult: () {
        controller.stopEach(SlotPageState.slotTargets);
      },
      game: LuckyLeverSlotMachine(
          config: demoConfig(context, SlotPageState.config),
          controller: controller,
          width: demoSide,
          height: 180,
          onPull: () => pulls++,
          onEnd: (result) => setState(() => _result = '奖品：${result.indices}')));

  /// 释放本页控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
