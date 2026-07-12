import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show internal;

import 'types.dart';

/// Returned by [Counter.add]. Allows the caller to retarget
/// or cancel the animation without holding a reference to the plugin.
class CounterHandle {
  CounterHandle._(this._id, this._plugin);

  final int _id;
  final Counter _plugin;

  /// Retarget to a new [to] value, continuing from the current position.
  void update({required double to, Duration? duration, Curve? curve}) =>
      _plugin._retarget(_id, to: to, duration: duration, curve: curve);

  /// Freeze the animation at its current value. No-op if done.
  ///
  /// 将动画冻结在当前值。已完成则无操作。
  void pause() => _plugin._setPaused(_id, true);

  /// Resume a paused animation from where it froze. No-op if not paused.
  ///
  /// 从冻结处恢复动画。未暂停则无操作。
  void resume() => _plugin._setPaused(_id, false);

  void cancel() => _plugin.removeTask(_id);

  /// True while the task exists, is not done, and is not paused.
  ///
  /// 任务存在、未完成且未暂停时为 true。
  bool get isAnimating {
    final t = _plugin.taskById(_id);
    return t != null && !t.done && !t.paused;
  }

  /// True when the task is currently frozen via [pause].
  ///
  /// 任务当前经 [pause] 冻结时为 true。
  bool get isPaused => _plugin.taskById(_id)?.paused ?? false;

  /// True once the task has completed (or no longer exists).
  ///
  /// 任务已完成（或不再存在）时为 true。
  bool get isDone => _plugin.taskById(_id)?.done ?? true;
}

/// Counter engine — drives number interpolation on the shared ticker.
/// Each instance is an independent task queue (= a "group").
class Counter extends TaskQueuePlugin<CounterTask> {
  Counter({String? name}) : super(name ?? 'counter');

  // Runs every frame (no interval) for smooth interpolation, so the default
  // [beginFrame] (always-true) from the base is exactly right.

  @override
  void renderInitial(CounterTask task) {
    // First active frame: render initial value without advancing time.
    task.value = _clamp(task, task.from);
    task.onUpdate?.call(task.value);
  }

  @override
  bool step(CounterTask task, double dtMs, bool shouldProcess) {
    // Paused tasks are skipped by the base tick loop (via `isPaused`) and never
    // reach here, so no explicit pause guard is needed.
    //
    // 暂停任务由基类 tick 循环（经 `isPaused`）跳过，不会到达此处，故无需显式暂停判断。
    task.accumMs += dtMs;
    final durationMs = task.duration.inMilliseconds.toDouble();
    final t = durationMs > 0 ? (task.accumMs / durationMs).clamp(0.0, 1.0) : 1.0;

    final complete = t >= 1.0;
    final raw = complete
        ? task.to
        : task.from + (task.to - task.from) * task.curve.transform(t);
    task.value = _clamp(task, raw);
    task.onUpdate?.call(task.value);

    if (complete) {
      task.done = true;
      task.onComplete?.call(task.value);
      return false;
    }
    return true;
  }

  static double _clamp(CounterTask task, double v) =>
      (!task.allowNegative && v < 0) ? 0 : v;

  // ── public API ────────────────────────────────────────────────────

  CounterHandle add(CounterOptions opts) {
    final id = nextId();
    enqueue(CounterTask(
      id: id,
      from: opts.from ?? 0,
      to: opts.to,
      duration: opts.duration,
      curve: opts.curve,
      allowNegative: opts.allowNegative,
      onUpdate: opts.onUpdate,
      onComplete: opts.onComplete,
      onReady: opts.onReady,
      onStart: opts.onStart,
      onCancel: opts.onCancel,
    ));
    return CounterHandle._(id, this);
  }

  // ── internal (called by CounterHandle) ───────────────────────────

  /// Same-library task lookup for [CounterHandle] (which is not a subclass and
  /// so can't touch the protected [taskOf] directly). Mirrors
  /// `Countdown.task` / `Elapsed.task`.
  ///
  /// 供 [CounterHandle] 使用的同库任务查找（它不是子类，无法直接访问受保护的
  /// [taskOf]）。与 `Countdown.task` / `Elapsed.task` 一致。
  @internal
  CounterTask? taskById(int id) => taskOf(id);

  void _retarget(int id, {required double to, Duration? duration, Curve? curve}) {
    final task = taskOf(id);
    if (task == null || task.done) return;
    task.from = task.value;
    task.to = to;
    if (duration != null) task.duration = duration;
    if (curve != null) task.curve = curve;
    task.accumMs = 0;
    task.started = false;
    ctx.requestFrame();
  }

  /// Sets the paused state of task [id]; requests a frame on resume so the
  /// ticker picks the task back up. Called by [CounterHandle.pause]/[resume].
  ///
  /// 设置任务 [id] 的暂停状态；恢复时请求一帧使 ticker 重新拾取任务。由
  /// [CounterHandle.pause]/[resume] 调用。
  void _setPaused(int id, bool paused) {
    final task = taskOf(id);
    if (task == null || task.done || task.paused == paused) return;
    task.paused = paused;
    if (!paused) ctx.requestFrame();
  }
}

// ── CounterValueController ─────────────────────────────────────────────

/// Imperative controller for counter display widgets.
///
/// Create once, pass to a widget via its `controller` parameter, then call
/// [update] to retarget, [cancel] to remove, or read [value] for the current
/// animated number. The controller attaches to the widget's internal
/// [CounterHandle] after the first build; mirrors [CountdownController].
class CounterValueController {
  CounterHandle? _handle;
  double _value = 0;

  // Called by counter display widgets in initState / didUpdateWidget / dispose.
  // Not part of the end-user API.
  // ignore: use_setters_to_change_properties
  void attach(CounterHandle h) => _handle = h;
  void detach() => _handle = null;

  /// Pushed by the owning widget on every frame — not user-facing.
  @internal
  set latestValue(double v) => _value = v;

  /// Retarget the animation to [to], continuing from the current value.
  void update({required double to, Duration? duration, Curve? curve}) =>
      _handle?.update(to: to, duration: duration, curve: curve);

  /// Freeze the animation at its current value.
  ///
  /// 将动画冻结在当前值。
  void pause() => _handle?.pause();

  /// Resume a paused animation.
  ///
  /// 恢复已暂停的动画。
  void resume() => _handle?.resume();

  /// Remove the underlying task immediately.
  void cancel() => _handle?.cancel();

  /// The most recent animated value reported by the widget (0 before start).
  double get value => _value;

  /// True while the animation is running (not paused, not done).
  ///
  /// 动画运行中（未暂停、未完成）时为 true。
  bool get isAnimating => _handle?.isAnimating ?? false;

  /// True when the animation is currently paused.
  ///
  /// 动画当前暂停时为 true。
  bool get isPaused => _handle?.isPaused ?? false;

  /// True once the animation has completed (or before attach).
  ///
  /// 动画已完成（或尚未 attach）时为 true。
  bool get isDone => _handle?.isDone ?? true;
}

// ── default instance + top-level function ─────────────────────────

final _defaultCounter = LazyDefault<Counter>(() => Counter());

/// The default shared [Counter] instance. Auto-registered with [Countman]
/// on first access.
Counter get defaultCounter => _defaultCounter.instance;

/// Add a counter animation using the default shared [Counter] instance.
/// Auto-registered with [Countman] on first call.
CounterHandle counter(CounterOptions opts) => defaultCounter.add(opts);
