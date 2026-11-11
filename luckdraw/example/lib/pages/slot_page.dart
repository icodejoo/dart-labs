import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';

import '../demo_shell.dart';
import '../theme/demo_theme.dart';
import '../theme/prize_art.dart';

/// 三轮老虎机示例；例如 `const SlotPage()`。
class SlotPage extends StatefulWidget {
  /// 创建老虎机页。
  const SlotPage({super.key});

  /// 创建页面状态。
  @override
  State<SlotPage> createState() => SlotPageState();
}

/// 独立停止各轮的页面状态。
class SlotPageState extends State<SlotPage> {
  /// 页面拥有的控制器；例如 `controller.stopEach(slotTargets)`。
  final SlotController controller = SlotController();

  /// 三轮分别由服务端指定的奖品下标。
  static const List<int> slotTargets = [0, 1, 2];

  /// 三轮三奖品配置，也用于拉霸机演示。
  static const SlotConfig config = SlotConfig(
      blocks: [
        LuckyBoxBlock(
            padding: LuckyEdgeInsets.all(10),
            borderRadius: 22,
            background: LuckyFill.gradient(LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [DemoPalette.blue, DemoPalette.primary]))),
        LuckyBoxBlock(
            padding: LuckyEdgeInsets.all(5),
            borderRadius: 14,
            background: LuckyFill.color(DemoPalette.gold)),
        LuckyBoxBlock(
            padding: LuckyEdgeInsets.all(5),
            borderRadius: 10,
            background: LuckyFill.color(DemoPalette.ink)),
      ],
      prizes: [
        SlotPrize(
            painter: paintSlotPrize,
            texts: [LuckyText('A · 礼盒', top: LuckyLength.percent(70))]),
        SlotPrize(
            painter: paintSlotPrize,
            texts: [LuckyText('B · 宝石', top: LuckyLength.percent(70))]),
        SlotPrize(
            painter: paintSlotPrize,
            texts: [LuckyText('C · 星章', top: LuckyLength.percent(70))]),
      ],
      reels: [
        SlotReel(),
        SlotReel(direction: -1),
        SlotReel()
      ],
      style: SlotStyle(
          cell: LuckyCellStyle(
              background: LuckyFill.color(DemoPalette.cream), borderRadius: 8),
          text: LuckyTextDefaults(
              fontSize: 12,
              color: DemoPalette.ink,
              fontFamily: 'Roboto',
              fontFamilyFallback: demoFontFallback)),
      options: SlotOptions(colSpacing: 5, rowSpacing: 8, motion: demoMotion));

  /// 结算文本。
  String _result = '';

  /// 展示外部控制按钮和三个轮。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '老虎机',
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
        controller.stopEach(slotTargets);
      },
      game: LuckySlotMachine(
          config: config,
          controller: controller,
          width: demoSide,
          height: 180,
          onEnd: (result) => setState(() => _result = '奖品：${result.indices}')));

  /// 离开页面释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
