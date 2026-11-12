import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show internal;

import '../core/plugin_base.dart';

/// Options for a counter animation task.
class CounterOptions {
  const CounterOptions({
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.onUpdate,
    this.fps,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
  }) : assert(
         fps == null || (fps > 0 && fps < double.infinity),
         'fps 必须为有限正数',
       );

  /// 实例显示刷新上限（帧/秒），返回可空配置；null 继承插件再到全局。
  /// 仅限制显示，终值与事件不延迟。示例：`CounterOptions(to: 100, fps: 30)`。
  final double? fps;

  /// Start value. Defaults to 0, or the task's current value when retargeting.
  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default), emitted values are clamped to `>= 0` — the engine
  /// never reports a negative number. Set `true` to animate through / to
  /// negative values (e.g. temperatures, deltas).
  final bool allowNegative;

  /// Called every frame with the current interpolated value.
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  /// Fired when the task is enqueued (synchronous at [Counter.add]).
  final VoidCallback? onReady;

  /// Fired on the first rendered frame (timing begins).
  final VoidCallback? onStart;

  /// Fired if the task is cancelled before completing (handle.cancel / dispose).
  final VoidCallback? onCancel;
}

/// Internal task state.
class CounterTask extends CountmanTask {
  CounterTask({
    required int id,
    required this.from,
    required this.to,
    required this.duration,
    required this.curve,
    required this.allowNegative,
    required this.onUpdate,
    required this.onComplete,
    super.onReady,
    super.onStart,
    super.onCancel,
  }) : super(id);

  double from;
  double to;
  Duration duration;
  Curve curve;
  bool allowNegative;
  void Function(double)? onUpdate;
  void Function(double)? onComplete;

  double value = 0;
  /// 静音期间的单调钟起点；-1 表示当前不补算（可见或用户暂停）。
  @internal
  int muteStartMicros = -1;

  /// 取消静音后首帧只显示补算位置，不再重复累加该帧 dt。
  @internal
  bool refreshAfterMute = false;

  /// 限帧推进的单调钟快照；-1 表示仍用原 dt 路径。
  @internal
  int frameClockMicros = -1;

  double accumMs = 0; // accumulated dt since the task became active

  /// When true the task holds its current value and stops advancing until
  /// resumed. Mirrors the pause capability of countdown/elapsed tasks.
  ///
  /// 为 true 时任务保持当前值并停止推进，直到恢复。与倒计时/经过时间任务的暂停
  /// 能力对齐。
  bool paused = false;

  /// Reports the pause state to the base tick loop, which skips paused tasks
  /// and excludes them from "busy" — so a fully-paused group lets the shared
  /// ticker idle instead of spinning every frame. On resume the handle calls
  /// `requestFrame`, and the ticker's first post-restart frame has `dt == 0`
  /// (Countman resets `_hasLast`), so the animation continues from its frozen
  /// [accumMs] without a time jump.
  ///
  /// 向基类 tick 循环报告暂停态：循环会跳过暂停任务且不计入 busy——因此整组暂停时
  /// 共享 ticker 可 idle，而非每帧空转。恢复时 handle 调用 `requestFrame`，重启后
  /// 首帧 `dt == 0`（Countman 重置 `_hasLast`），故动画从冻结的 [accumMs] 无跳变
  /// 继续。
  @override
  bool get isPaused => paused;
}
