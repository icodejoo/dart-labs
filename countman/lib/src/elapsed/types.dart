import 'package:flutter/foundation.dart';

import '../core/plugin_base.dart';
import '../core/time_parts.dart';

export '../core/clock.dart' show elapsedClock;

/// Options for an elapsed-time task added via [Elapsed.add] or [elapsed].
///
/// Unlike [CountdownOptions] there's no fixed target — by default the task
/// counts up indefinitely from the moment it's added until
/// [ElapsedHandle.cancel] (or the owning widget is disposed). Give [limit] to
/// make it stop at an upper bound, and [since] / [initial] to start from a
/// non-zero elapsed time.
class ElapsedOptions {
  /// [since] 与 [initial] 互斥，最多给一个。
  /// 例如 `ElapsedOptions(since: orderTime, limit: Duration(minutes: 30))`。
  const ElapsedOptions({
    this.since,
    this.initial,
    this.limit,
    this.onComplete,
    this.onUpdate,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  }) : assert(
         since == null || initial == null,
         'ElapsedOptions: provide at most one of since or initial.',
       );

  /// 墙钟锚定的起点：已经过 = 当前墙钟 − [since]，例如“下单已 3 分钟”。
  /// 用户改系统时间会随之变化；暂停、恢复与 [ElapsedHandle.reset] 之后改为按单调钟
  /// 计时。起点在未来时按 0 显示。与 [initial] 互斥。
  final DateTime? since;

  /// 单调钟锚定的起始偏移，例如恢复上次的秒表 `initial: savedElapsed`。
  /// 不受系统改时间影响；负值按 0 处理。与 [since] 互斥。
  final Duration? initial;

  /// 上限：累计时间到达它时，发出值恰为 [limit] 的最后一次 [onUpdate]，触发
  /// [onComplete] 并结束任务。为空（默认）表示无上限。起点已超过上限时首帧即完成。
  final Duration? limit;

  /// 累计时间到达 [limit] 时调用一次；无上限的任务不会触发。
  final void Function()? onComplete;

  /// Called on each interval tick with the shared per-task [TimeParts]
  /// (pre-decomposed elapsed). Update rate is controlled by [Elapsed.interval].
  final void Function(TimeParts parts)? onUpdate;

  /// When elapsed time first reaches or exceeds this, [onThreshold] fires
  /// once. null (default) disables the check.
  final Duration? threshold;

  /// Called once when elapsed time crosses [threshold]. Fires again on a
  /// later crossing if [ElapsedHandle.reset] is called in between.
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
}

/// 正计时内部任务状态；以单调钟锚定起点，不受墙钟变化影响。
class ElapsedTask extends ClockTask {
  /// [startMicros] 为起点微秒，[absolute] 为 true 时在墙钟时间轴上，否则在单调钟上；
  /// [limitMicros] 为上限微秒，空表示无上限。
  ElapsedTask({
    required int id,
    required this.startMicros,
    this.absolute = false,
    this.limitMicros,
    this.onComplete,
    void Function(TimeParts)? onUpdate,
    Duration? threshold,
    void Function()? onThreshold,
    super.onPause,
    super.onResume,
    super.onReady,
    super.onStart,
    super.onCancel,
  }) : super(
         id,
         onUpdate: onUpdate,
         threshold: threshold,
         onThreshold: onThreshold,
       );

  /// 起点微秒；累计时间为当前时钟（由 [absolute] 决定）减去它。
  int startMicros;

  /// true 表示起点在墙钟时间轴上（来自 [ElapsedOptions.since]）；暂停恢复或重置后
  /// 一律变为 false（单调钟）。
  bool absolute;

  /// 上限微秒；空表示无上限。非负。
  int? limitMicros;

  /// 到达上限时的回调。
  void Function()? onComplete;

  /// Snapshot of elapsed when paused; null means running.
  Duration? pausedElapsed;

  @override
  bool get isPaused => pausedElapsed != null;
}
