import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';

/// 拉霸机；拖动拉杆开始，再由外部命令错峰停轮。
class LeverDemo extends StatefulWidget {
  /// 创建拉霸机示例。
  const LeverDemo({super.key});

  /// 创建状态。
  @override
  State<LeverDemo> createState() => _LeverDemoState();
}

class _LeverDemoState extends State<LeverDemo> {
  final _controller = SlotController();
  static const _config = SlotConfig(
    prizes: [
      SlotPrize(texts: [LuckyText('7')]),
      SlotPrize(texts: [LuckyText('BAR')]),
      SlotPrize(texts: [LuckyText('★')]),
    ],
    reels: [SlotReel(), SlotReel(), SlotReel()],
  );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyLeverSlotMachine(
            config: _config,
            controller: _controller,
            width: 300,
            height: 180,
            onPull: () => debugPrint('Lever pulled'),
            onEnd: (result) => debugPrint('Lever: ${result.indices}'),
          ),
          TextButton(
            // 拉杆触发 play 后，由服务端结果决定每个转轴停在哪个奖品。
            onPressed: () {
              _controller.stopEach([0, 0, 0]);
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
