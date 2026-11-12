import 'package:countman/src/core/clock.dart';
import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:flutter/foundation.dart';

import 'types.dart';
import '../core/fps.dart';

export 'package:countman/src/controllers/countdown_controller.dart';

/// Returned by [Countdown.add].
class CountdownHandle {
  CountdownHandle._(this._id, this._plugin);

  final int _id;
  final Countdown _plugin;

  /// 同步组件帧率配置；不重启任务或改变用户暂停状态。
  @internal
  set fps(double? value) {
    final task = _plugin.task(_id);
    if (task != null) _plugin.setTaskFps(task, value);
  }

  /// 由组件同步可见性；不触发暂停/恢复回调。
  @internal
  set muted(bool value) {
    final task = _plugin.task(_id);
    if (task != null) _plugin.setMuted(task, value);
  }

  /// 当前任务的静音状态，供插件迁移使用。
  @internal
  bool get muted => _plugin.task(_id)?.muted ?? false;

  /// Freeze the countdown at its current remaining time.
  void pause() {
    final task = _plugin.task(_id);
    if (task == null || task.done || task.isPaused) return;
    task.pausedRemaining = _plugin.remainingOf(task);
    // 暂停会使当前帧计算失效，即使回调中马上恢复。
    task.revision++;
    task.onPause?.call();
  }

  /// Resume a paused countdown. Restarts the ticker if it had stopped.
  /// 恢复一律按单调钟重新锚定剩余时间（绝对截止的任务也转为相对计时）。
  void resume() {
    final task = _plugin.task(_id);
    if (task == null || task.done || !task.isPaused) return;
    _plugin.anchorRelative(task, task.pausedRemaining!);
    task.pausedRemaining = null;
    task.reanchor(); // next interval renders without consuming time
    task.onResume?.call();
    _plugin.requestFrame();
  }

  /// Reset remaining to [duration] (or the original duration if null),
  /// then resume. No-op if already completed. 重置按单调钟锚定总时长。
  void reset({Duration? duration}) {
    final task = _plugin.task(_id);
    if (task == null || task.done) return;
    if (duration != null) {
      task.restore = duration;
      // 显式给定的分母不随 reset 的新时长变化。
      if (!task.totalFixed) task.total = duration;
    }
    _plugin.anchorRelative(task, task.restore);
    task.pausedRemaining = null;
    task.reanchor();
    task.thresholdFired = false;
    _plugin.requestFrame();
  }

  /// Remove the task immediately.
  void cancel() => _plugin.removeTask(_id);

  /// Update only the threshold, preserving remaining time.
  /// 仅同步阈值，保留剩余时间和暂停状态。
  void updateThreshold(Duration? threshold) {
    final task = _plugin.task(_id);
    if (task == null) return;
    task.updateThreshold(threshold);
    // 休眠中的新阈值可能更早到达，需要重新计算唤醒时间。
    if (!task.done && !task.isPaused) _plugin.requestFrame();
  }

  /// 当前剩余时间（读取实时时钟）；已取消返回 [Duration.zero]。
  Duration get remaining {
    final task = _plugin.task(_id);
    return task == null ? Duration.zero : _plugin.remainingOf(task);
  }
  bool get isPaused => _plugin.task(_id)?.isPaused ?? false;
  bool get isDone => _plugin.task(_id)?.done ?? true;

  /// 仍按墙钟锚定（从未暂停或重置）的任务返回其绝对截止时间，否则返回 null。
  /// 由展示组件在迁移插件时调用，业务代码不要直接调用；例如迁移时保留
  /// “到 20:00 结束”这类截止语义。
  @internal
  DateTime? get absoluteDeadline {
    final task = _plugin.task(_id);
    if (task == null || task.done || !task.absolute) return null;
    return DateTime.fromMicrosecondsSinceEpoch(task.endMicros);
  }
}

/// Countdown engine — drives [Duration]-based timers on the shared ticker.
/// Each instance is an independent task queue (= a "group").
///
/// ## Interval
/// [interval] (milliseconds) controls how often a task's display is updated:
/// - `1000` (default) — whenever the remaining time crosses a whole second;
///   ideal for HH:mm:ss / mm:ss displays.
/// - `0` — every frame; use for sub-second precision.
///
/// 每个任务按**自己的剩余时间**跨过 interval 整数倍的时刻更新（桶边界），
/// 与任务何时加入无关；两次更新之间调度器休眠，不逐帧出帧。
/// 完成与阈值每帧检查，越过边界的那一帧触发。
///
/// The **first frame** of a newly added task always renders immediately,
/// regardless of the interval, to show the initial value without delay.
///
/// ## Clock anchors
/// - `CountdownOptions.duration` — anchored on the **monotonic** clock, so user
///   clock changes never make the countdown jump; deep sleep is compensated by
///   the clock's foreground-resume calibration.
/// - `CountdownOptions.deadline` — anchored on the **wall** clock, follows
///   system time changes (use for "ends at 20:00" style deadlines).
/// Pause/resume/reset always re-anchor on the monotonic clock.
///
/// ## Grouping
/// Create multiple [Countdown] instances to isolate groups:
/// ```dart
/// final precise = Countdown(name: 'ms', interval: 0);
/// Countman.use(precise);
/// CountdownBuilder(duration: ..., plugin: precise, builder: ...)
/// ```
/// 倒计时引擎：每帧共用时钟快照，完成与阈值不受显示间隔延迟。
class Countdown extends ClockPlugin<CountdownTask> {
  /// [name] 为诊断名称（不同实例请用唯一名称），[interval] 为显示间隔毫秒，
  /// [clock] 为时间源（默认 [CountmanClock.system]）；[fps] 为可空显示上限，null 继承全局。
  /// 例如 `Countdown(name: 'auction', interval: 100)`。
  Countdown({String? name, super.interval, super.clock, super.fps})
    : super(name ?? 'countdown');

  /// 剩余微秒：暂停时取冻结值，否则用本帧快照；负值钳为 0。
  /// 不用 `clamp(0, int 最大值)`，那个 64 位字面量在 Web 上无法精确表示，会让 dart2js 编译失败。
  @override
  int valueMicrosOf(CountdownTask task) {
    final paused = task.pausedRemaining;
    if (paused != null) return paused.inMicroseconds;
    final now = task.absolute ? frameWallMicros : frameMonotonicMicros;
    final us = task.endMicros - now;
    return us < 0 ? 0 : us;
  }

  /// 显示值：按任务的取整方式和插件间隔取整（默认向下，即原样）。
  @override
  int displayMicrosOf(CountdownTask task, int value) =>
      task.rounding.apply(value, interval);

  /// 进度分母：显式给定的 total，否则为任务创建时（或 reset 指定）的时长。
  @override
  Duration? totalOf(CountdownTask task) => task.total;

  /// 剩余为 0 即完成。
  @override
  bool isComplete(CountdownTask task) => valueMicrosOf(task) <= 0;

  /// 距显示换档的微秒数。向下取整：剩余降到当前桶下沿以下才换桶，还需
  /// `value - 桶 * 间隔 + 1`；向上取整：剩余降到上一档整数倍（含）就换档，
  /// 还需 `value - (档 - 1) * 间隔`，其中 `档 = ceil(value / 间隔)`。
  @override
  int boundaryWake(CountdownTask task, int value, int intervalMicros) {
    if (task.rounding == CountdownRounding.ceil) {
      return value - ((value - 1) ~/ intervalMicros) * intervalMicros;
    }
    return value - (value ~/ intervalMicros) * intervalMicros + 1;
  }

  /// 剩余耗尽即完成。
  @override
  int completionWake(CountdownTask task, int value) => value;

  /// 剩余降到阈值（含）以下视为越过。
  @override
  int thresholdWake(int value, int thresholdMicros) => value - thresholdMicros;

  /// 触发完成回调；最终的 0 值更新及状态复核已由基类完成。
  @override
  void onComplete(CountdownTask task) {
    task.onComplete?.call();
  }

  // ── internal accessors for handles (same library) ─────────────────

  @internal
  CountdownTask? task(int id) => taskOf(id);
  @internal
  void requestFrame() => ctx.requestFrame();

  /// 读取实时时钟得到 [task] 的剩余时间（负值钳零），供句柄与控制器使用。
  @internal
  Duration remainingOf(CountdownTask task) {
    final paused = task.pausedRemaining;
    if (paused != null) return paused;
    final c = clock;
    final now = task.absolute ? c.wallMicros() : c.monotonicMicros();
    final us = task.endMicros - now;
    return us <= 0 ? Duration.zero : Duration(microseconds: us);
  }

  /// 把 [task] 改为按单调钟锚定，剩余 [remaining]。
  @internal
  void anchorRelative(CountdownTask task, Duration remaining) {
    task.endMicros = clock.monotonicMicros() + remaining.inMicroseconds;
    task.absolute = false;
  }

  // ── public API ────────────────────────────────────────────────────

  /// 添加一个倒计时并返回句柄；`opts.duration` 按单调钟锚定，
  /// `opts.deadline` 按墙钟锚定。
  CountdownHandle add(CountdownOptions opts) => addMuted(opts);

  /// 以指定静音状态直接入队，避免隐藏组件首帧投递显示回调。
  @internal
  CountdownHandle addMuted(CountdownOptions opts, {bool muted = false}) {
    final id = nextId();
    final c = clock;
    final deadline = opts.deadline;
    final Duration initial;
    final int endMicros;
    if (deadline != null) {
      endMicros = deadline.microsecondsSinceEpoch;
      final remaining = endMicros - c.wallMicros();
      initial = Duration(microseconds: remaining < 0 ? 0 : remaining);
    } else {
      initial = opts.duration!;
      endMicros = c.monotonicMicros() + initial.inMicroseconds;
    }
    enqueue(
      CountdownTask(
        id: id,
        total: opts.total ?? initial,
        restore: initial,
        totalFixed: opts.total != null,
        rounding: opts.rounding,
        endMicros: endMicros,
        absolute: deadline != null,
        onUpdate: opts.onUpdate,
        onComplete: opts.onComplete,
        threshold: opts.threshold,
        onThreshold: opts.onThreshold,
        onReady: opts.onReady,
        onStart: opts.onStart,
        onCancel: opts.onCancel,
        onPause: opts.onPause,
        onResume: opts.onResume,
      )..fps = validFps(opts.fps)
      ..muted = muted,
    );
    return CountdownHandle._(id, this);
  }
}

// ── default instance + top-level function ─────────────────────────

final _defaultCountdown =
    LazyDefault<Countdown>(() => Countdown()); // interval = 1000ms

/// The default [Countdown] instance (interval = 1 s) used by [CountdownWidget]
/// when no [plugin] is provided. Auto-registered with [Countman] on first access.
Countdown get defaultCountdown => _defaultCountdown.instance;

/// Add a countdown using the default shared [Countdown] instance.
CountdownHandle countdown(CountdownOptions opts) => defaultCountdown.add(opts);

final _defaultCountdownMs =
    LazyDefault<Countdown>(() => Countdown(name: 'countdown-ms', interval: 0));

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
Countdown get defaultCountdownMs => _defaultCountdownMs.instance;
