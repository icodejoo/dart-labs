import 'package:flutter/material.dart';
import 'package:luckdraw/grid.dart';

/// 独立运行 README 原始示例。
void main() => runApp(const MaterialApp(
      home: Scaffold(body: Center(child: GridDemo())),
    ));

/// README 中可编译的 GridDemo 示例。
class GridDemo extends StatefulWidget {
  /// 创建 README 示例组件。
  const GridDemo({super.key});

  /// 实现示例组件的生命周期契约。
  @override
  State<GridDemo> createState() => _GridDemoState();
}

/// README 中可编译的 _GridDemoState 示例。
class _GridDemoState extends State<GridDemo> {
  /// 页面持有并释放的控制器。
  final _controller = GridController();

  /// 与 README 一致的奖品配置。
  static const _config = GridConfig(
    rows: 3,
    cols: 3,
    prizes: [
      GridPrize(x: 0, y: 0, texts: [LuckyText('A')]),
      GridPrize(x: 1, y: 0, texts: [LuckyText('B')]),
      GridPrize(x: 2, y: 0, texts: [LuckyText('C')]),
      GridPrize(x: 2, y: 1, texts: [LuckyText('D')]),
      GridPrize(x: 2, y: 2, texts: [LuckyText('E')]),
      GridPrize(x: 1, y: 2, texts: [LuckyText('F')]),
      GridPrize(x: 0, y: 2, texts: [LuckyText('G')]),
      GridPrize(x: 0, y: 1, texts: [LuckyText('H')]),
    ],
    buttons: [
      GridButton(x: 1, y: 1, texts: [LuckyText('Spin')])
    ],
    activeStyle: LuckyCellStyle(background: LuckyFill.color(Color(0xFFFFCE98))),
  );

  /// 实现示例组件的生命周期契约。
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LuckyGrid(
              config: _config,
              controller: _controller,
              width: 300,
              height: 300,
              onStart: () {
                _controller.play();
              },
              onEnd: (result) => debugPrint('Grid: $result')),
          TextButton(
              onPressed: () {
                _controller.stop(1);
              },
              child: const Text('Stop')),
        ],
      );

  /// 实现示例组件的生命周期契约。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
