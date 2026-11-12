import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../motion/phase.dart';

/// 绘制钩子，收到当前画布与逻辑盒子尺寸。
typedef LuckyDrawHook = void Function(Canvas canvas, Size size);

/// 按钮点击回调，下标从零开始，并提供点击时的阶段。
typedef LuckyButtonTapCallback = void Function(int index, LuckyPhase phase);

/// 生命周期与绘制钩子；例如 `LuckyHooks(afterStart: playSound)`。
@immutable
final class LuckyHooks {
  /// 创建钩子集合；未提供的钩子不触发。
  const LuckyHooks(
      {this.beforeInit,
      this.afterInit,
      this.beforeDraw,
      this.afterDraw,
      this.afterStart,
      this.beforeResize,
      this.afterResize});

  /// 宿主开始初始化。
  final VoidCallback? beforeInit;

  /// 每轮图片请求均有结论，初始化完成。
  final VoidCallback? afterInit;

  /// 全部绘制内容之前。
  final LuckyDrawHook? beforeDraw;

  /// 全部绘制内容之后。
  final LuckyDrawHook? afterDraw;

  /// play 被接受之后。
  final VoidCallback? afterStart;

  /// 尺寸变化引起布局重算之前。
  final VoidCallback? beforeResize;

  /// 尺寸变化引起布局重算之后。
  final VoidCallback? afterResize;
}
