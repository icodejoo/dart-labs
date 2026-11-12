import 'package:flutter/material.dart';

/// 为单个动画演示提供独立的重放按钮。
class ReplayDemo extends StatefulWidget {
  /// 创建演示；[onReplay] 在重新挂载 [child] 前同步执行。
  const ReplayDemo({super.key, required this.child, this.onReplay});

  /// 需要从头播放的动画子树。
  final Widget child;

  /// 重挂载前的准备操作，例如清除该演示的图片缓存。
  final VoidCallback? onReplay;

  /// 展示页与控制页共用的双语按钮文案。
  static const label = '重放 / Replay';

  /// 保证重放按钮具有足够的触控面积。
  static const buttonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.square(48)),
  );

  /// 创建独立的重放状态。
  @override
  State<ReplayDemo> createState() => _ReplayDemoState();
}

/// 只重新挂载当前演示，不重置相邻动画。
class _ReplayDemoState extends State<ReplayDemo> {
  /// 当前演示的挂载代数。
  int _generation = 0;

  /// 完成准备操作后，通过新键重建动画子树。
  void _replay() {
    widget.onReplay?.call();
    setState(() => _generation++);
  }

  /// 在动画下方保留间距并放置原生按钮。
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      KeyedSubtree(key: ValueKey(_generation), child: widget.child),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _replay,
        style: ReplayDemo.buttonStyle,
        icon: const Icon(Icons.replay),
        label: const Text(ReplayDemo.label),
      ),
    ],
  );
}
