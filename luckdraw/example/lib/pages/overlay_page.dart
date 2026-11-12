import 'package:flutter/material.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/wheel.dart';

import '../demo_shell.dart';
import '../online/localized_config.dart';
import '../theme/demo_theme.dart';
import 'wheel_page.dart';

/// 奖品使用动画 Widget 的叠加示例；例如 `const OverlayPage()`。
class OverlayPage extends StatefulWidget {
  /// 创建叠加层页。
  const OverlayPage({super.key});

  /// 创建页面状态。
  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

/// 转盘控制与 Widget 内容独立动画。
class _OverlayPageState extends State<OverlayPage> {
  /// 页面控制器。
  final WheelController _controller = WheelController();

  /// 结算结果。
  String _result = '';

  /// 通过公开渲染 SPI 叠加奖品 Widget。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: 'Widget 叠加层',
      phase: _controller.phase,
      result: _result,
      reset: () {
        _controller.reset();
        setState(() => _result = '');
      },
      start: () {
        _controller.play();
      },
      serverResult: () {
        _controller.stop(demoTarget);
      },
      game: LuckyWheel(
          config: demoConfig(context, WheelPageState.config),
          controller: _controller,
          renderer: const _OverlayRenderer(),
          width: demoSide,
          height: demoSide,
          onStart: () {
            _controller.play();
          },
          onEnd: (result) => setState(() => _result = '奖品：${result.index}')));

  /// 页面离开时释放控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// 在默认 Canvas 后端上组合一个奖品叠加层。
class _OverlayRenderer extends LuckyRenderer<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>> {
  /// 创建无状态组合策略。
  const _OverlayRenderer();

  /// 使用宿主实际布局与帧通知，尺寸变化自动跟随。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) =>
      Stack(children: [
        const WheelCanvasRenderer().buildSurface(context, data),
        IgnorePointer(
            child: LuckyItemOverlay(
          geometry: const WheelGame().itemGeometry,
          layout: data.layout,
          frame: data.frame,
          frameListenable: data.frameListenable,
          children: [
            for (var i = 0; i < data.config.prizes.length; i++)
              const _SpinningGift()
          ],
        )),
      ]);
}

/// 可替代动图的自转奖品，动画资源由自身 State 释放。
class _SpinningGift extends StatefulWidget {
  /// 创建独立奖品 Widget。
  const _SpinningGift();

  /// 创建动画所有者。
  @override
  State<_SpinningGift> createState() => _SpinningGiftState();
}

/// 管理奖品的自转动画。
class _SpinningGiftState extends State<_SpinningGift>
    with SingleTickerProviderStateMixin {
  /// 可复用的自转控制器。
  late final AnimationController _turns =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  /// 固定子树由旋转过渡绘制，不需要逐帧重建。
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: RotationTransition(
          turns: _turns,
          child: const Icon(Icons.card_giftcard,
              size: 20, color: DemoPalette.primary)));

  /// 释放独立自转 Ticker。
  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }
}
