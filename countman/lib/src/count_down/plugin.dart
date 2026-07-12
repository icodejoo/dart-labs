import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:flutter/foundation.dart';

import 'types.dart';

/// Returned by [Countdown.add].
class CountdownHandle {
  CountdownHandle._(this._id, this._plugin);

  final int _id;
  final Countdown _plugin;

  /// Freeze the countdown at its current remaining time.
  void pause() {
    final task = _plugin.task(_id);
    if (task == null || task.done || task.isPaused) return;
    task.pausedRemaining = task.remaining;
    task.onPause?.call();
  }

  /// Resume a paused countdown. Restarts the ticker if it had stopped.
  void resume() {
    final task = _plugin.task(_id);
    if (task == null || task.done || !task.isPaused) return;
    task.endTime = countdownClock().add(task.pausedRemaining!);
    task.pausedRemaining = null;
    task.started = false; // re-anchor: next interval renders without consuming time
    task.onResume?.call();
    _plugin.requestFrame();
  }

  /// Reset remaining to [duration] (or the original duration if null),
  /// then resume. No-op if already completed.
  void reset({Duration? duration}) {
    final task = _plugin.task(_id);
    if (task == null || task.done) return;
    if (duration != null) task.total = duration;
    task.endTime = countdownClock().add(task.total);
    task.pausedRemaining = null;
    task.started = false;
    task.thresholdFired = false;
    _plugin.requestFrame();
  }

  /// Remove the task immediately.
  void cancel() => _plugin.removeTask(_id);

  Duration get remaining => _plugin.task(_id)?.remaining ?? Duration.zero;
  bool get isPaused      => _plugin.task(_id)?.isPaused ?? false;
  bool get isDone        => _plugin.task(_id)?.done ?? true;
}

/// Countdown engine — drives [Duration]-based timers on the shared ticker.
/// Each instance is an independent task queue (= a "group").
///
/// ## Interval
/// [interval] (milliseconds) controls how often tasks are processed:
/// - `1000` (default) — once per second; ideal for HH:mm:ss / mm:ss displays.
/// - `0` — every frame; use for sub-second precision.
///
/// The plugin accumulates elapsed time via `dt` each frame and processes tasks
/// only when `accumMs >= interval`. The remainder carries forward so timing
/// stays accurate across frames.
///
/// The **first frame** of a newly added task always renders immediately,
/// regardless of the interval, to show the initial value without delay.
///
/// ## Real-clock deadline
/// Each task records `endTime = countdownClock().add(duration)`.
/// Remaining = `endTime − countdownClock()`, so app-background pauses and
/// frame drops never cause drift.
///
/// ## Grouping
/// Create multiple [Countdown] instances to isolate groups:
/// ```dart
/// final precise = Countdown(name: 'ms', interval: 0);
/// Countman.use(precise);
/// CountdownWidget(duration: ..., plugin: precise, builder: ...)
/// ```
class Countdown extends ClockPlugin<CountdownTask> {
  Countdown({String? name, int interval = 1000})
      : super(name ?? 'countdown', interval: interval);

  // ── ClockPlugin domain hooks ──────────────────────────────────────

  @override
  Duration valueOf(CountdownTask task) => task.remaining;

  @override
  Duration? totalOf(CountdownTask task) => task.total;

  @override
  bool isComplete(CountdownTask task) => task.remaining <= Duration.zero;

  @override
  bool thresholdCrossed(CountdownTask task) => task.remaining <= task.threshold!;

  @override
  void onComplete(CountdownTask task) {
    task.parts.set(Duration.zero, task.total);
    task.onUpdate?.call(task.parts);
    task.onComplete?.call();
  }

  @override
  void onDispose() {
    super.onDispose();
    if (identical(this, _default)) _registered = false;
    // Drop the cached precise instance so defaultCountdownMs re-creates and
    // re-registers a live one after Countman.destroy().
    //
    // 丢弃缓存的精确实例，使 Countman.destroy() 后 defaultCountdownMs 重新创建并
    // 注册一个存活实例。
    if (identical(this, _defaultMs)) _defaultMs = null;
  }

  // ── internal accessors for handles (same library) ─────────────────

  @internal
  CountdownTask? task(int id) => taskOf(id);
  @internal
  void requestFrame() => ctx.requestFrame();

  // ── public API ────────────────────────────────────────────────────

  CountdownHandle add(CountdownOptions opts) {
    final id = nextId();
    enqueue(CountdownTask(
      id: id,
      total: opts.duration,
      onUpdate: opts.onUpdate,
      onComplete: opts.onComplete,
      threshold: opts.threshold,
      onThreshold: opts.onThreshold,
      onReady: opts.onReady,
      onStart: opts.onStart,
      onCancel: opts.onCancel,
      onPause: opts.onPause,
      onResume: opts.onResume,
    ));
    return CountdownHandle._(id, this);
  }
}

// ── CountdownController ───────────────────────────────────────────

/// Imperative controller for countdown display widgets.
///
/// Create once, pass to a widget via its `controller` parameter, then call
/// [pause], [resume], [reset], or [cancel] from any parent or business logic.
/// The controller attaches to the widget's internal [CountdownHandle] after
/// the first build.
class CountdownController {
  CountdownHandle? _handle;

  // Called by countdown display widgets in initState / didUpdateWidget / dispose.
  // Not part of the end-user API.
  // ignore: use_setters_to_change_properties
  void attach(CountdownHandle h) => _handle = h;
  void detach() => _handle = null;

  void pause()                     => _handle?.pause();
  void resume()                    => _handle?.resume();
  void reset({Duration? duration}) => _handle?.reset(duration: duration);
  void cancel()                    => _handle?.cancel();

  Duration get remaining => _handle?.remaining ?? Duration.zero;
  bool get isPaused      => _handle?.isPaused ?? false;
  bool get isDone        => _handle?.isDone ?? true;
}

// ── default instance + top-level function ─────────────────────────

final _default = Countdown(); // interval = 1000ms
bool _registered = false;

/// The default [Countdown] instance (interval = 1 s) used by [CountdownWidget]
/// when no [plugin] is provided. Auto-registered with [Countman] on first access.
Countdown get defaultCountdown {
  if (!_registered) {
    _registered = true;
    Countman.use(_default);
  }
  return _default;
}

/// Add a countdown using the default shared [Countdown] instance.
CountdownHandle countdown(CountdownOptions opts) =>
    defaultCountdown.add(opts);

Countdown? _defaultMs;

/// The default **precise** [Countdown] instance (`interval: 0` — processes
/// every frame) used by widgets with `precise: true` when no [plugin] is
/// given. Lets sub-second formatters ([CountdownFormat.msTenths] /
/// [CountdownFormat.msMillis]) update smoothly without hand-wiring a group.
/// Auto-registered with [Countman] on first access.
///
/// 默认的**精确** [Countdown] 实例（`interval: 0`——每帧处理），当未传 [plugin]
/// 时供 `precise: true` 的组件使用。让亚秒格式化器（[CountdownFormat.msTenths] /
/// [CountdownFormat.msMillis]）平滑更新，无需手动接线分组。首次访问时自动向
/// [Countman] 注册。
Countdown get defaultCountdownMs {
  final existing = _defaultMs;
  if (existing != null) return existing;
  final p = Countdown(name: 'countdown-ms', interval: 0);
  Countman.use(p);
  _defaultMs = p;
  return p;
}
