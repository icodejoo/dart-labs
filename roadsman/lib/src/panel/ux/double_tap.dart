/// 双击回尾部效果控制器。
///
/// 移植自 `src/panel/ux/double-tap.ts`。`RoadPanel` 已经内建了双击手势处理
/// （见 `road_panel.dart` 的 `onDoubleTap`），这个控制器只是给不想直接用
/// `RoadPanel.onDoubleTap` 参数、而是想按 TS 版本"独立开关效果"这套 API 风格
/// 接入的调用方一个等价选择。
library;

/// 双击回尾部效果控制器。
class DoubleTapToTailEffect {
  bool enabled;
  final void Function() onDoubleTap;

  DoubleTapToTailEffect({required this.onDoubleTap, this.enabled = true});

  /// 切换开关。
  void toggle(bool on) => enabled = on;

  /// 触发一次双击回尾（仅在 [enabled] 时生效）。
  void handleDoubleTap() {
    if (enabled) onDoubleTap();
  }
}

/// 创建双击回尾部效果控制器。
DoubleTapToTailEffect createDoubleTapToTail(void Function() onDoubleTap) =>
    DoubleTapToTailEffect(onDoubleTap: onDoubleTap);
