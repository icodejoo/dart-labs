import 'package:flutter/animation.dart';

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
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
  });

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
  double accumMs = 0; // accumulated dt since the task became active

  /// When true the task holds its current value and stops advancing until
  /// resumed. Mirrors the pause capability of countdown/elapsed tasks.
  ///
  /// 为 true 时任务保持当前值并停止推进，直到恢复。与倒计时/经过时间任务的暂停
  /// 能力对齐。
  bool paused = false;
}
