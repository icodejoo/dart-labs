import 'package:flutter/material.dart';
import 'package:luckdraw/lotto.dart';

/// 大乐透；多个号码池逐球摇出，可由服务端指定整组号码。
class LottoDemo extends StatefulWidget {
  /// 创建大乐透示例。
  const LottoDemo({super.key});

  /// 创建状态。
  @override
  State<LottoDemo> createState() => _LottoDemoState();
}

class _LottoDemoState extends State<LottoDemo> {
  final _controller = LottoController();
  // 5 + 2 的超级大乐透预设；options 里的 physics 打开碰撞模式。
  static final _config = LottoConfig.superLotto(
    options: const LottoOptions(physics: LuckyPhysics()),
  );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyLotto(
            config: _config,
            controller: _controller,
            width: 300,
            height: 400,
            onStart: () {
              _controller.play();
            },
            onBallDrawn: (pool, number) => debugPrint('Pool $pool: $number'),
            onEnd: (result) => debugPrint('Lotto: ${result.draw?.numbers}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stopWith(const LottoDraw([
                [7, 1, 18, 25, 35],
                [12, 3],
              ]));
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
