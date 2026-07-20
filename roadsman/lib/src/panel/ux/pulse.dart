/// 新格子插入后的呼吸光圈效果控制器。
///
/// 移植自 `src/panel/ux/pulse.ts`。TS 版本在 demo 层手写了一段独立的呼吸动画帧
/// 循环，直接在指令层叠加一个半透明描边圆；Flutter 版本把它简化成一个开关控制器
/// ——具体的光圈绘制交给消费方用 `AnimatedContainer`/`CustomPaint` 叠加层实现，
/// 这里只管"这个效果现在是否应该生效"这一件事，不重复实现动画采样。
library;

/// 呼吸光圈效果的选项。
class PulseOptions {
  /// 单次呼吸时长（ms），默认 2000ms。
  final int duration;

  /// 光圈颜色（ARGB），默认金色。
  final int color;

  const PulseOptions({this.duration = 2000, this.color = 0xFFFFD700});
}

/// 呼吸光圈效果控制器。
class PulseEffect {
  bool enabled;
  final PulseOptions options;

  PulseEffect({this.enabled = true, this.options = const PulseOptions()});

  /// 切换开关。
  void toggle(bool on) => enabled = on;
}

/// 创建呼吸光圈效果控制器（默认开启）。
PulseEffect createPulseEffect({PulseOptions options = const PulseOptions()}) =>
    PulseEffect(options: options);
