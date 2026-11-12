import 'package:flutter/material.dart';
import 'package:luckdraw/capsule.dart';

/// 扭蛋机；点击旋钮开始，服务端结果到达后掉出指定胶囊。
class CapsuleDemo extends StatefulWidget {
  /// 创建扭蛋机示例。
  const CapsuleDemo({super.key});

  /// 创建状态。
  @override
  State<CapsuleDemo> createState() => _CapsuleDemoState();
}

class _CapsuleDemoState extends State<CapsuleDemo> {
  final _controller = CapsuleController();
  static const _config = CapsuleConfig(
    prizes: [
      CapsulePrize(
        topFill: LuckyFill.color(Color(0xFFFF8A65)),
        bottomFill: LuckyFill.color(Color(0xFFFFF3E0)),
        texts: [LuckyText('Gift')],
        weight: 1,
      ),
      CapsulePrize(
        topFill: LuckyFill.color(Color(0xFF64B5F6)),
        bottomFill: LuckyFill.color(Color(0xFFFFF3E0)),
        texts: [LuckyText('Grand')],
        weight: 1,
      ),
    ],
    // 打开碰撞模式：胶囊从顶部落下，与球壁、拨杆碰撞；删掉这行即为确定性动画。
    options: CapsuleOptions(physics: LuckyPhysics()),
  );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyCapsuleMachine(
            config: _config,
            controller: _controller,
            width: 300,
            height: 400,
            onStart: () {
              _controller.play();
            },
            onEnd: (result) => debugPrint('Capsule: ${result.index}'),
          ),
          TextButton(
            onPressed: () {
              _controller.stop(1);
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
