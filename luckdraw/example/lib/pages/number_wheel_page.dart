import 'package:flutter/material.dart';
import 'package:luckdraw/number_wheel.dart';

import '../demo_shell.dart';
import '../online/localized_config.dart';
import '../theme/demo_theme.dart';

/// 圆盘和小球反向旋转示例；例如 `const NumberWheelPage()`。
class NumberWheelPage extends StatefulWidget {
  /// 创建数字转盘页。
  const NumberWheelPage({super.key});

  /// 创建页面状态。
  @override
  State<NumberWheelPage> createState() => NumberWheelPageState();
}

/// 服务端按号码选奖的数字转盘状态。
class NumberWheelPageState extends State<NumberWheelPage> {
  /// 页面拥有的控制器；例如 `controller.lastNumber`。
  final NumberWheelController controller = NumberWheelController();

  /// 示例服务端号码。
  static const int targetNumber = 8;

  /// 一局期间不变的号码列表。
  static final NumberWheelConfig config = NumberWheelConfig.range(0, 12,
      palette: const [
        LuckyFill.color(DemoPalette.primary),
        LuckyFill.color(DemoPalette.ink),
        LuckyFill.color(DemoPalette.blue)
      ],
      style: const NumberWheelStyle(
          textColor: DemoPalette.ink,
          fontFamily: 'Roboto',
          background: LuckyFill.gradient(
              LinearGradient(colors: [DemoPalette.gold, DemoPalette.cream])),
          trackFill: LuckyFill.color(DemoPalette.ink),
          hubFill: LuckyFill.gradient(RadialGradient(
              colors: [DemoPalette.periwinkle, DemoPalette.primary])),
          ballFill: LuckyFill.color(DemoPalette.cream)),
      options: const NumberWheelOptions(motion: demoMotion));

  /// 结果文本。
  String _result = '';

  /// 展示数字环、刻度和落袋小球。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '数字转盘',
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
        controller.stopNumber(targetNumber);
      },
      game: LuckyNumberWheel(
          config: demoConfig(context, config),
          controller: controller,
          width: demoSide,
          height: demoSide,
          onStart: () {
            controller.play();
          },
          onEnd: (result) =>
              setState(() => _result = '号码：${result.prize?.number}')));

  /// 释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
