import 'package:flutter/material.dart';
import 'package:luckdraw/wheel.dart';

/// 独立运行 README 原始示例。
void main() => runApp(const MaterialApp(
      home: Scaffold(body: Center(child: WheelDemo())),
    ));

/// README 中可编译的 WheelDemo 示例。
class WheelDemo extends StatefulWidget {
  /// 创建 README 示例组件。
  const WheelDemo({super.key});

  /// 实现示例组件的生命周期契约。
  @override
  State<WheelDemo> createState() => _WheelDemoState();
}

/// README 中可编译的 _WheelDemoState 示例。
class _WheelDemoState extends State<WheelDemo> {
  /// 页面持有并释放的控制器。
  final _controller = WheelController();

  /// 与 README 一致的奖品配置。
  static const _config = WheelConfig(
    prizes: [
      WheelPrize(
          background: LuckyFill.color(Color(0xFFE9E8FE)),
          texts: [LuckyText('Try again')],
          weight: 3),
      WheelPrize(
          background: LuckyFill.color(Color(0xFFB8C5F2)),
          texts: [LuckyText('Gift')],
          weight: 1),
    ],
    buttons: [
      WheelButton(
          radius: LuckyLength.percent(30),
          pointer: true,
          background: LuckyFill.color(Color(0xFF617DF2)),
          texts: [LuckyText('Spin', top: LuckyLength.px(-10))]),
    ],
  );

  /// 实现示例组件的生命周期契约。
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyWheel(
              config: _config,
              controller: _controller,
              width: 300,
              height: 300,
              onStart: () {
                _controller.play();
              },
              onEnd: (result) => debugPrint('Wheel: $result')),
          TextButton(
              onPressed: () {
                _controller.stop(1);
              },
              child: const Text('Stop')),
        ],
      );

  /// 请求服务端下标，异常时作废并继续抛出。
  Future<void> drawFromServer(Future<int> Function() requestIndex) async {
    if (!_controller.play()) return;
    try {
      final index = await requestIndex();
      if (!mounted) return;
      _controller.stop(index);
    } catch (_) {
      if (mounted) _controller.cancel();
      rethrow;
    }
  }

  /// 在给定观察期内订阅阶段，结束时取消订阅。
  Future<void> observePhases(Future<void> untilDone) async {
    final subscription = _controller.phaseChanges.listen((phase) {
      debugPrint('Phase: $phase');
    });
    try {
      await untilDone;
    } finally {
      await subscription.cancel();
    }
  }

  /// 实现示例组件的生命周期契约。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
