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
    // 暂停会使当前帧计算失效，即使回调中马上恢复。
    task.revision++;
    task.onPause?.call();
  }

  /// Resume a paused countdown. Restarts the ticker if it had stopped.
  void resume() {
    final task = _plugin.task(_id);
    if (task == null || task.done || !task.isPaused) return;
    task.endTime = countdownClock().add(task.pausedRemaining!);
    task.pausedRemaining = null;
    task.reanchor(); // next interval renders without consuming time
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
    task.reanchor();
    task.thresholdFired = false;
    _plugin.requestFrame();
  }

  /// Remove the task immediately.
  void cancel() => _plugin.removeTask(_id);

  /// Update only the threshold, preserving remaining time.
  /// 仅同步阈值，保留剩余时间和暂停状态。
  void updateThreshold(Duration? threshold) =>
      _plugin.task(_id)?.updateThreshold(threshold);

  Duration get remaining => _plugin.task(_id)?.remaining ?? Duration.zero;
  bool get isPaused => _plugin.task(_id)?.isPaused ?? false;
  bool get isDone => _plugin.task(_id)?.done ?? true;
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
  // 直接转发父类间隔参数，保留默认值与调用方式。
  Countdown({String? name, super.interval}) : super(name ?? 'countdown');

  // ── ClockPlugin domain hooks ──────────────────────────────────────

  @override
  Duration valueOf(CountdownTask task) => task.remaining;

  @override
  Duration? totalOf(CountdownTask task) => task.total;

  @override
  bool isComplete(CountdownTask task) => task.remaining <= Duration.zero;

  @override
  bool thresholdCrossed(CountdownTask task) =>
      task.remaining <= task.threshold!;

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
