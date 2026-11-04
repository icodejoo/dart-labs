import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:flutter/foundation.dart';

import 'types.dart';

/// Returned by [Elapsed.add].
class ElapsedHandle {
  ElapsedHandle._(this._id, this._plugin);

  final int _id;
  final Elapsed _plugin;

  /// Freeze the timer at its current elapsed time.
  void pause() {
    final task = _plugin.task(_id);
    if (task == null || task.isPaused) return;
    task.pausedElapsed = task.elapsed;
    // 回调内暂停后不再继续当前帧的旧计算。
    task.revision++;
    task.onPause?.call();
  }

  /// Resume a paused timer. Restarts the ticker if it had stopped.
  void resume() {
    final task = _plugin.task(_id);
    if (task == null || !task.isPaused) return;
    // 恢复时排除暂停期间经过的单调时间。
    task.startTime = elapsedClock() - task.pausedElapsed!;
    task.pausedElapsed = null;
    task.reanchor(); // next interval renders without consuming time
    task.onResume?.call();
    _plugin.requestFrame();
  }

  /// Reset elapsed time back to zero, then resume.
  void reset() {
    final task = _plugin.task(_id);
    if (task == null) return;
    // 重置只读取单调时间，不读取系统日期。
    task.startTime = elapsedClock();
    task.pausedElapsed = null;
    task.reanchor();
    task.thresholdFired = false;
    _plugin.requestFrame();
  }

  /// Remove the task immediately.
  void cancel() => _plugin.removeTask(_id);

  /// Update only the threshold, preserving elapsed time.
  /// 仅同步阈值，保留累计时间和暂停状态。
  void updateThreshold(Duration? threshold) =>
      _plugin.task(_id)?.updateThreshold(threshold);

  Duration get elapsed => _plugin.task(_id)?.elapsed ?? Duration.zero;
  bool get isPaused => _plugin.task(_id)?.isPaused ?? false;

  /// 返回任务是否已完成或不存在；例如取消后 `handle.isDone` 为 true。
  bool get isDone => _plugin.task(_id)?.done ?? true;
}

/// Elapsed-time engine — drives open-ended "stopwatch" timers on the shared
/// ticker. Each instance is an independent task queue (= a "group").
///
/// Unlike [Countdown], a task never completes on its own — it counts up
/// indefinitely until [ElapsedHandle.cancel] or disposal. Named `Elapsed`
/// rather than `Stopwatch` to avoid shadowing `dart:core`'s [Stopwatch].
///
/// ## Interval
/// [interval] (milliseconds) controls how often tasks are processed, same
/// semantics as [Countdown.interval]: `1000` (default) for HH:mm:ss / mm:ss
/// displays, `0` for every-frame sub-second precision.
///
/// ## Grouping
/// Create multiple [Elapsed] instances to isolate groups, same as [Countdown]:
/// ```dart
/// final calls = Elapsed(name: 'call-durations');
/// Countman.use(calls);
/// TextElapsed(plugin: calls)
/// ```
class Elapsed extends ClockPlugin<ElapsedTask> {
  // 直接转发父类间隔参数，保留上一批计时修复。
  Elapsed({String? name, super.interval}) : super(name ?? 'elapsed');

  // ── ClockPlugin domain hooks ──────────────────────────────────────

  @override
  Duration valueOf(ElapsedTask task) => task.elapsed;

  @override
  Duration? totalOf(ElapsedTask task) => null; // open-ended, no total

  @override
  bool isComplete(ElapsedTask task) => false; // never done on its own

  @override
  bool thresholdCrossed(ElapsedTask task) => task.elapsed >= task.threshold!;

  @override
  void onComplete(
      ElapsedTask task) {} // unreachable: isComplete is always false

  // ── internal accessors for handles (same library) ─────────────────

  @internal
  ElapsedTask? task(int id) => taskOf(id);
  @internal
  void requestFrame() => ctx.requestFrame();

  // ── public API ────────────────────────────────────────────────────

  ElapsedHandle add(ElapsedOptions opts) {
    final id = nextId();
    enqueue(ElapsedTask(
      id: id,
      onUpdate: opts.onUpdate,
      threshold: opts.threshold,
      onThreshold: opts.onThreshold,
      onReady: opts.onReady,
      onStart: opts.onStart,
      onCancel: opts.onCancel,
      onPause: opts.onPause,
      onResume: opts.onResume,
    ));
    return ElapsedHandle._(id, this);
  }
}

// ── ElapsedController ──────────────────────────────────────────────

/// 正计时展示组件的命令式控制器，取消后 reset 会请求组件重启。
///
/// Create once, pass to a widget via its `controller` parameter, then call
/// [pause], [resume], [reset], or [cancel] from any parent or business logic.
/// The controller attaches to the widget's internal [ElapsedHandle] after
/// the first build.
class ElapsedController {
  ElapsedHandle? _handle;

  /// 保存展示组件提供的重启动作。
  VoidCallback? _relaunch;

  /// 由展示组件调用，业务代码不要直接调用。
  /// 绑定 [handle] 和结束后使用的 [relaunch]，替换已有绑定；无返回值。
  /// 例如 `controller.attach(handle, relaunch: restart)`。
  @internal
  void attach(ElapsedHandle handle, {VoidCallback? relaunch}) {
    _handle = handle;
    _relaunch = relaunch;
  }

  /// 由展示组件调用，业务代码不要直接调用。
  /// [handle] 为空时无条件解绑，否则仅解绑相同实例，并清除重启动作；无返回值。
  /// 例如 `controller.detach(handle)`；旧式 `controller.detach()` 仍可用。
  @internal
  void detach([ElapsedHandle? handle]) {
    if (handle != null && !identical(_handle, handle)) return;
    _handle = null;
    _relaunch = null;
  }

  void pause() => _handle?.pause();
  void resume() => _handle?.resume();

  /// 清零并恢复计时；已取消时请求展示组件从零新建任务，未绑定时无操作。
  /// 无参数、无返回值；例如 `controller.reset()`。
  void reset() {
    final handle = _handle;
    if (handle != null && !handle.isDone) {
      handle.reset();
    } else {
      _relaunch?.call();
    }
  }

  void cancel() => _handle?.cancel();

  Duration get elapsed => _handle?.elapsed ?? Duration.zero;
  bool get isPaused => _handle?.isPaused ?? false;
}

// ── default instance + top-level function ─────────────────────────

final _defaultElapsed =
    LazyDefault<Elapsed>(() => Elapsed()); // interval = 1000ms

/// The default [Elapsed] instance (interval = 1 s) used by [TextElapsed]
/// when no [plugin] is provided. Auto-registered with [Countman] on first access.
Elapsed get defaultElapsed => _defaultElapsed.instance;

/// Add an elapsed-time timer using the default shared [Elapsed] instance.
ElapsedHandle elapsed(ElapsedOptions opts) => defaultElapsed.add(opts);

final _defaultElapsedMs =
    LazyDefault<Elapsed>(() => Elapsed(name: 'elapsed-ms', interval: 0));

/// The default **precise** [Elapsed] instance (`interval: 0` — processes every
/// frame) used by widgets with `precise: true` when no [plugin] is given.
/// Auto-registered with [Countman] on first access.
///
/// 默认的**精确** [Elapsed] 实例（`interval: 0`——每帧处理），当未传 [plugin] 时
/// 供 `precise: true` 的组件使用。首次访问时自动向 [Countman] 注册。
Elapsed get defaultElapsedMs => _defaultElapsedMs.instance;
