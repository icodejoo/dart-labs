import 'package:flutter/material.dart';
import 'package:luckdraw/number_wheel.dart';

/// 数字转盘；按号码而不是下标停下。
class NumberWheelDemo extends StatefulWidget {
  /// 创建数字转盘示例。
  const NumberWheelDemo({super.key});

  /// 创建状态。
  @override
  State<NumberWheelDemo> createState() => _NumberWheelDemoState();
}

class _NumberWheelDemoState extends State<NumberWheelDemo> {
  final _controller = NumberWheelController();
  // 0 到 12 共 13 个号码袋。
  static final _config = NumberWheelConfig.range(0, 12);

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyNumberWheel(
            config: _config,
            controller: _controller,
            width: 300,
            height: 300,
            onStart: () {
              _controller.play();
            },
            onEnd: (result) => debugPrint('Number: ${result.prize?.number}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stopNumber(8);
            },
            child: const Text('Server result'),
          ),
        ],
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
