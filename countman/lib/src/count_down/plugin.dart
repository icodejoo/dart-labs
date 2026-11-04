import 'package:countman/src/core/clock.dart';
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
    if (duration != null) task.total = duration;
    _plugin.anchorRelative(task, task.total);
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
  /// [clock] 为时间源（默认 [CountmanClock.system]）。
  /// 例如 `Countdown(name: 'auction', interval: 100)`。
  Countdown({String? name, super.interval, super.clock})
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

  /// 进度分母：任务的初始总时长。
  @override
  Duration? totalOf(CountdownTask task) => task.total;

  /// 剩余为 0 即完成。
  @override
  bool isComplete(CountdownTask task) => valueMicrosOf(task) <= 0;

  /// 剩余降到当前桶下沿以下才会换桶：还需 `value - 桶 * 间隔 + 1` 微秒。
  @override
  int boundaryWake(int value, int intervalMicros) =>
      value - (value ~/ intervalMicros) * intervalMicros + 1;

  /// 剩余耗尽即完成。
  @override
  int completionWake(int value) => value;

  /// 剩余降到阈值（含）以下视为越过。
  @override
  int thresholdWake(int value, int thresholdMicros) => value - thresholdMicros;

  @override
  void onComplete(CountdownTask task) {
    // 最终更新及状态复核统一由基类完成。
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
  CountdownHandle add(CountdownOptions opts) {
    final id = nextId();
    final c = clock;
    final deadline = opts.deadline;
    final Duration total;
    final int endMicros;
    if (deadline != null) {
      endMicros = deadline.microsecondsSinceEpoch;
      final remaining = endMicros - c.wallMicros();
      total = Duration(microseconds: remaining < 0 ? 0 : remaining);
    } else {
      total = opts.duration!;
      endMicros = c.monotonicMicros() + total.inMicroseconds;
    }
    enqueue(
      CountdownTask(
        id: id,
        total: total,
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
      ),
    );
    return CountdownHandle._(id, this);
  }
}

// ── CountdownController ───────────────────────────────────────────

/// 倒计时展示组件的命令式控制器，结束后 reset 会请求组件重启。
///
/// Create once, pass to a widget via its `controller` parameter, then call
/// [pause], [resume], [reset], or [cancel] from any parent or business logic.
/// The controller attaches to the widget's internal [CountdownHandle] after
/// the first build.
class CountdownController {
  CountdownHandle? _handle;

  /// 保存展示组件提供的重启动作。
  void Function({Duration? duration})? _relaunch;

  /// 由展示组件调用，业务代码不要直接调用。
  /// 绑定 [handle] 和结束后使用的 [relaunch]，替换已有绑定；无返回值。
  /// 例如 `controller.attach(handle, relaunch: restart)`。
  @internal
  void attach(CountdownHandle handle,
      {void Function({Duration? duration})? relaunch}) {
    _handle = handle;
    _relaunch = relaunch;
  }

  /// 由展示组件调用，业务代码不要直接调用。
  /// [handle] 为空时无条件解绑，否则仅解绑相同实例，并清除重启动作；无返回值。
  /// 例如 `controller.detach(handle)`；旧式 `controller.detach()` 仍可用。
  @internal
  void detach([CountdownHandle? handle]) {
    if (handle != null && !identical(_handle, handle)) return;
    _handle = null;
    _relaunch = null;
  }

  void pause() => _handle?.pause();
  void resume() => _handle?.resume();

  /// 重置并恢复倒计时；[duration] 为空时存活任务沿用原时长，结束后采用组件配置。
  /// 已结束或取消时请求展示组件重启，未绑定时无操作；无返回值。
  /// 例如 `controller.reset(duration: Duration(seconds: 10))`。
  void reset({Duration? duration}) {
    final handle = _handle;
    if (handle != null && !handle.isDone) {
      handle.reset(duration: duration);
    } else {
      _relaunch?.call(duration: duration);
    }
  }

  void cancel() => _handle?.cancel();

  Duration get remaining => _handle?.remaining ?? Duration.zero;
  bool get isPaused => _handle?.isPaused ?? false;
  bool get isDone => _handle?.isDone ?? true;
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
