import 'package:flutter/material.dart';
import 'package:luckdraw/wheel.dart';

import '../demo_shell.dart';
import '../theme/demo_theme.dart';
import '../theme/prize_art.dart';

/// 转盘示例；例如 `const WheelPage()`。
class WheelPage extends StatefulWidget {
  /// 创建独立控制器的转盘页。
  const WheelPage({super.key});

  /// 创建页面状态。
  @override
  State<WheelPage> createState() => WheelPageState();
}

/// 转盘页状态，集成测试可观测公开的只读帧。
class WheelPageState extends State<WheelPage> {
  /// 由本页面释放的控制器；例如 `controller.frame.rotateDeg`。
  final WheelController controller = WheelController();

  /// 固定的示例奖品，服务端下标在整局期间稳定。
  static const WheelConfig config = WheelConfig(
      blocks: [
        WheelBlock(
            padding: 14,
            background: LuckyFill.gradient(LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DemoPalette.blue, DemoPalette.primary]))),
        WheelBlock(padding: 3, background: LuckyFill.color(DemoPalette.gold)),
        WheelBlock(padding: 3, background: LuckyFill.color(DemoPalette.cream)),
      ],
      prizes: [
        WheelPrize(
            texts: [
              LuckyText('谢谢参与',
                  top: LuckyLength.percent(8),
                  fontSize: 12,
                  color: DemoPalette.ink)
            ],
            weight: 3,
            painter: paintWheelPrize,
            background: LuckyFill.color(DemoPalette.lavender)),
        WheelPrize(
            texts: [
              LuckyText('一等奖',
                  top: LuckyLength.percent(8),
                  fontSize: 12,
                  color: DemoPalette.ink)
            ],
            weight: 1,
            painter: paintWheelPrize,
            background: LuckyFill.color(DemoPalette.periwinkle)),
        WheelPrize(
            texts: [
              LuckyText('惊喜礼盒',
                  top: LuckyLength.percent(8),
                  fontSize: 12,
                  color: DemoPalette.ink)
            ],
            weight: 1,
            painter: paintWheelPrize,
            background: LuckyFill.color(DemoPalette.lavender)),
        WheelPrize(
            texts: [
              LuckyText('好运星',
                  top: LuckyLength.percent(8),
                  fontSize: 12,
                  color: DemoPalette.ink)
            ],
            weight: 1,
            painter: paintWheelPrize,
            background: LuckyFill.color(DemoPalette.periwinkle)),
        WheelPrize(
            texts: [
              LuckyText('幸运好礼',
                  top: LuckyLength.percent(8),
                  fontSize: 12,
                  color: DemoPalette.ink)
            ],
            weight: 1,
            painter: paintWheelPrize,
            background: LuckyFill.color(DemoPalette.lavender)),
        WheelPrize(
            texts: [
              LuckyText('元气礼包',
                  top: LuckyLength.percent(8),
                  fontSize: 12,
                  color: DemoPalette.ink)
            ],
            weight: 1,
            painter: paintWheelPrize,
            background: LuckyFill.color(DemoPalette.periwinkle)),
      ],
      buttons: [
        WheelButton(
            radius: LuckyLength.percent(34),
            background: LuckyFill.color(DemoPalette.gold)),
        WheelButton(
            radius: LuckyLength.percent(30),
            pointer: true,
            texts: [
              LuckyText('开始',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  top: LuckyLength.px(-10))
            ],
            background: LuckyFill.gradient(LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [DemoPalette.primary, DemoPalette.ink])))
      ],
      style: WheelStyle(
          text: LuckyTextDefaults(
              fontFamily: 'Roboto', fontFamilyFallback: demoFontFallback)),
      options: WheelOptions(motion: demoMotion));

  /// 本局结算显示。
  String _result = '';

  /// 提供真实画布、开始与模拟服务端返回按钮。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '转盘',
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
      game: LayoutBuilder(builder: (_, constraints) {
        final side = constraints.maxWidth.clamp(0.0, demoSide);
        return LuckyWheel(
            config: config,
            controller: controller,
            width: side,
            height: side,
            onStart: () {
              controller.play();
            },
            onEnd: (result) => setState(() => _result = '奖品：${result.index}'));
      }));

  /// 页面离开时释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
