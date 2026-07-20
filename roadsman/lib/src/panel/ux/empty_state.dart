/// 空态文案覆盖层：结果为空时在面板中央显示提示文案。
///
/// 移植自 `src/panel/ux/empty-state.ts`；Flutter 版本是一个纯 widget，直接
/// `Stack` 叠在 `RoadPanel` 上即可，不需要像 TS 那样手动增删 DOM 节点。
library;

import 'package:flutter/material.dart';

/// 空态覆盖层：`message` 为空字符串时不渲染任何内容。
class EmptyStateOverlay extends StatelessWidget {
  /// 提示文案，默认"等待开局"。
  final String message;

  /// 文字颜色。
  final Color color;

  const EmptyStateOverlay({super.key, this.message = '等待开局', this.color = Colors.white70});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(child: Text(message, style: TextStyle(color: color, fontSize: 14))),
  );
}
