import 'package:flutter/widgets.dart';
import 'package:luckdraw/wheel.dart';

/// 转盘探针的有界边长。
const double _side = 240;

/// 只保留默认 quad 转盘与 stop 调用，不引用其它玩法。
void main() {
  runApp(const _WheelProbe());
}

/// 拥有并释放探针控制器的宿主。
class _WheelProbe extends StatefulWidget {
  /// 创建转盘探针。
  const _WheelProbe();

  /// 创建控制器宿主状态。
  @override
  State<_WheelProbe> createState() => _WheelProbeState();
}

/// 通过可见按钮使 play/stop 保持可达。
class _WheelProbeState extends State<_WheelProbe> {
  /// 本探针专用的控制器。
  final WheelController _controller = WheelController();

  /// 释放探针拥有的控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 让转盘和停止回调进入产物。
  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          LuckyWheel(
              config: const WheelConfig(prizes: [WheelPrize()]),
              controller: _controller,
              width: _side,
              height: _side),
          GestureDetector(
              onTap: () {
                _controller.play();
                _controller.stop(0);
              },
              child: const Text('play / stop')),
        ]),
      );
}
