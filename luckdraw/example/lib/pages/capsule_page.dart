import 'package:flutter/material.dart';
import 'package:luckdraw/capsule.dart';

import '../demo_shell.dart';
import '../theme/demo_theme.dart';

/// 旋钮、掉落和开蛋示例；例如 `const CapsulePage()`。
class CapsulePage extends StatefulWidget {
  /// 创建扭蛋机页。
  const CapsulePage({super.key});

  /// 创建页面状态。
  @override
  State<CapsulePage> createState() => CapsulePageState();
}

/// 展示服务端指定奖品的扭蛋机状态。
class CapsulePageState extends State<CapsulePage> {
  /// 页面拥有的控制器；例如 `controller.frame.stage`。
  final CapsuleController controller = CapsuleController();

  /// 固定胶囊奖品及开蛋时长。
  static const CapsuleConfig config = CapsuleConfig(
      prizes: [
        CapsulePrize(
            topFill: LuckyFill.color(DemoPalette.coral),
            bottomFill: LuckyFill.color(DemoPalette.cream),
            texts: [LuckyText('礼物')],
            weight: 1),
        CapsulePrize(
            topFill: LuckyFill.color(DemoPalette.blue),
            bottomFill: LuckyFill.color(DemoPalette.cream),
            texts: [LuckyText('大奖')],
            weight: 1),
        CapsulePrize(
            topFill: LuckyFill.color(DemoPalette.mint),
            bottomFill: LuckyFill.color(DemoPalette.cream),
            texts: [LuckyText('好运')],
            weight: 1),
        CapsulePrize(
            topFill: LuckyFill.color(DemoPalette.gold),
            bottomFill: LuckyFill.color(DemoPalette.cream),
            texts: [LuckyText('惊喜')],
            weight: 1),
      ],
      style: CapsuleStyle(
        globeFill: LuckyFill.gradient(LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE9F5FF), DemoPalette.periwinkle])),
        bodyFill: LuckyFill.gradient(LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DemoPalette.blue, DemoPalette.primary])),
        knobFill: LuckyFill.color(DemoPalette.gold),
        seamColor: DemoPalette.ink,
        card: LuckyCellStyle(
            background: LuckyFill.color(DemoPalette.cream), borderRadius: 18),
        text: LuckyTextDefaults(
            color: DemoPalette.ink,
            fontSize: 18,
            fontFamily: 'Roboto',
            fontFamilyFallback: demoFontFallback),
      ),
      options: CapsuleOptions(motion: demoMotion));

  /// 开启物理碰撞模式的配置：胶囊从顶部落下，与球壁、拨杆碰撞。
  static final CapsuleConfig physicsConfig = config.copyWith(
      options:
          const CapsuleOptions(motion: demoMotion, physics: LuckyPhysics()));

  /// 是否使用物理碰撞模式。
  bool _physics = false;

  /// 结果文本。
  String _result = '';

  /// 构建支持点击旋钮的画布。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '扭蛋机',
      phase: controller.phase,
      result: _result,
      extra: Row(children: [
        const Expanded(child: Text('物理碰撞（实验）')),
        Switch(
            key: physicsKey,
            value: _physics,
            onChanged: (value) => setState(() => _physics = value)),
      ]),
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
      game: LuckyCapsuleMachine(
          config: _physics ? physicsConfig : config,
          controller: controller,
          width: demoSide,
          height: demoTall,
          onStart: () {
            controller.play();
          },
          onEnd: (result) => setState(() => _result = '奖品：${result.index}')));

  /// 释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
