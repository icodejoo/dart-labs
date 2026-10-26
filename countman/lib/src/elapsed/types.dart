import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/plugin_base.dart';
import '../core/time_parts.dart';

export '../core/clock.dart' show elapsedClock;

/// Options for an elapsed-time task added via [Elapsed.add] or [elapsed].
///
/// Unlike [CountdownOptions] there's no fixed target — the task counts up
/// indefinitely from the moment it's added until [ElapsedHandle.cancel] (or
/// the owning widget is disposed).
class ElapsedOptions {
  const ElapsedOptions({
    this.onUpdate,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

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

/// Internal task state.
///
/// 秒表以单调时间锚定起点，暂停和恢复时不受墙钟变化影响。
class ElapsedTask extends ClockTask {
  ElapsedTask({
    required int id,
    void Function(TimeParts)? onUpdate,
    Duration? threshold,
    void Function()? onThreshold,
    super.onPause,
    super.onResume,
    super.onReady,
    super.onStart,
    super.onCancel,
  })  : startTime = elapsedClock(),
        super(id, onUpdate: onUpdate, threshold: threshold, onThreshold: onThreshold);

  /// 单调时间起点；累计时间为当前单调时间减去起点。
  Duration startTime;

  /// Snapshot of elapsed when paused; null means running.
  Duration? pausedElapsed;

  @override
  bool get isPaused => pausedElapsed != null;

  Duration get elapsed => isPaused ? pausedElapsed! : elapsedClock() - startTime;
}
