import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';

/// 独立运行 README 原始示例。
void main() => runApp(const MaterialApp(
      home: Scaffold(body: Center(child: SlotDemo())),
    ));

/// README 中可编译的 SlotDemo 示例。
class SlotDemo extends StatefulWidget {
  /// 创建 README 示例组件。
  const SlotDemo({super.key});

  /// 实现示例组件的生命周期契约。
  @override
  State<SlotDemo> createState() => _SlotDemoState();
}

/// README 中可编译的 _SlotDemoState 示例。
class _SlotDemoState extends State<SlotDemo> {
  /// 页面持有并释放的控制器。
  final _controller = SlotController();

  /// 与 README 一致的奖品配置。
  static const _config = SlotConfig(
    prizes: [
      SlotPrize(texts: [LuckyText('A')]),
      SlotPrize(texts: [LuckyText('B')]),
      SlotPrize(texts: [LuckyText('C')]),
    ],
    reels: [
      SlotReel(order: [0, 1, 2]),
      SlotReel(),
      SlotReel(direction: -1)
    ],
    options: SlotOptions(
        mode: SlotMode.vertical, colSpacing: 5, cellAspectRatio: 0.8),
  );

  /// 实现示例组件的生命周期契约。
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckySlotMachine(
              config: _config,
              controller: _controller,
              width: 300,
              height: 180,
              onEnd: (result) => debugPrint('Slots: $result')),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
                onPressed: () {
                  _controller.play();
                },
                child: const Text('Spin')),
            TextButton(
                onPressed: () {
                  _controller.stop(1);
                },
                child: const Text('Stop')),
          ]),
        ],
      );

  /// 实现示例组件的生命周期契约。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
