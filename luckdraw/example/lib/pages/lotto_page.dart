import 'package:flutter/material.dart';
import 'package:luckdraw/lotto.dart';

import '../demo_shell.dart';
import '../online/localized_config.dart';
import '../theme/demo_theme.dart';

/// 前五后二区的逐球开奖示例；例如 `const LottoPage()`。
class LottoPage extends StatefulWidget {
  /// 创建大乐透页。
  const LottoPage({super.key, this.initialPhysics = false});

  /// 初始是否开启实验性物理碰撞。
  final bool initialPhysics;

  /// 创建页面状态。
  @override
  State<LottoPage> createState() => LottoPageState();
}

/// 按服务端指定顺序出球的页面状态。
class LottoPageState extends State<LottoPage> {
  /// 页面拥有的控制器；例如 `controller.stopWith(serverDraw)`。
  final LottoController controller = LottoController();

  /// 未排序的服务端开奖顺序。
  static const LottoDraw serverDraw = LottoDraw([
    [7, 1, 18, 25, 35],
    [12, 3]
  ]);

  /// 默认大乐透号码池，保留服务端出球顺序。
  static final LottoConfig config = LottoConfig.superLotto(
      style: const LottoStyle(
          drumColor: DemoPalette.lavender,
          rimColor: DemoPalette.blue,
          slotColor: DemoPalette.periwinkle,
          buttonColor: DemoPalette.gold,
          buttonText: 'GO',
          buttonTextColor: DemoPalette.ink),
      options: const LottoOptions(sortResults: false, motion: demoMotion));

  /// 开启物理碰撞模式的配置：号码球从顶部落下，与容器、拨杆碰撞。
  static final LottoConfig physicsConfig = config.copyWith(
      options: const LottoOptions(
          sortResults: false, motion: demoMotion, physics: LuckyPhysics()));

  /// 是否使用物理碰撞模式。
  late bool _physics = widget.initialPhysics;

  /// 按实际回调记录的池及号码，测试可验证顺序。
  final List<(int, int)> drawn = [];

  /// 结果文本。
  String _result = '';

  /// 展示七球依次开奖及最终结果。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '大乐透',
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
        drawn.clear();
        setState(() => _result = '');
      },
      start: () {
        drawn.clear();
        controller.play();
      },
      serverResult: () {
        controller.stopWith(serverDraw);
      },
      game: LuckyLotto(
          config: demoConfig(context, _physics ? physicsConfig : config),
          controller: controller,
          width: demoSide,
          height: demoTall,
          onStart: () {
            drawn.clear();
            controller.play();
          },
          onBallDrawn: (pool, number) => drawn.add((pool, number)),
          onEnd: (result) =>
              setState(() => _result = '号码：${result.draw?.numbers}')));

  /// 释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
