import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/core/types.dart';
import 'package:flutter/foundation.dart';

import 'types.dart';

/// Returned by [Elapsed.add].
/// 正计时句柄，终态后的暂停、恢复与重置均无操作。
class ElapsedHandle {
  ElapsedHandle._(this._id, this._plugin);

  final int _id;
  final Elapsed _plugin;

  /// 已记录的每圈时长；句柄持有，任务结束后仍可读取。
  final List<Duration> _laps = <Duration>[];

  /// 上一圈结束时的累计时间；0 表示尚未记圈。
  Duration _lastLap = Duration.zero;

  /// 暂停存活任务；已取消或已暂停时无操作。
  void pause() {
    final task = _plugin.task(_id);
    if (task == null || task.done || task.isPaused) return;
    task.pausedElapsed = _plugin.elapsedOf(task);
    // 回调内暂停后不再继续当前帧的旧计算。
    task.revision++;
    task.onPause?.call();
  }

  /// 恢复存活的暂停任务并唤醒帧循环；已取消时无操作。
  void resume() {
    final task = _plugin.task(_id);
    if (task == null || task.done || !task.isPaused) return;
    // 恢复时排除暂停期间经过的时间，并一律改按单调钟计时。
    task.startMicros =
        _plugin.clock.monotonicMicros() - task.pausedElapsed!.inMicroseconds;
    task.absolute = false;
    task.pausedElapsed = null;
    task.reanchor(); // next interval renders without consuming time
    task.onResume?.call();
    _plugin.requestFrame();
  }

  /// 将存活任务清零后恢复；已取消时无操作。
  void reset() {
    final task = _plugin.task(_id);
    if (task == null || task.done) return;
    // 重置只读取单调时间，不读取系统日期；since 任务也转为单调钟锚定。
    task.startMicros = _plugin.clock.monotonicMicros();
    task.absolute = false;
    task.pausedElapsed = null;
    task.reanchor();
    task.thresholdFired = false;
    _laps.clear();
    _lastLap = Duration.zero;
    _plugin.requestFrame();
  }

  /// 记录一圈并返回本圈时长（距上一圈，第一圈距起点）；暂停期间不计时。
  /// 任务已结束或取消时返回 [Duration.zero] 且不记录。
  /// 例如 `final split = handle.lap();`。
  Duration lap() {
    final task = _plugin.task(_id);
    if (task == null || task.done) return Duration.zero;
    final now = _plugin.elapsedOf(task);
    var split = now - _lastLap;
    if (split.isNegative) split = Duration.zero;
    _lastLap = now;
    _laps.add(split);
    return split;
  }

  /// 已记录的每圈时长快照（只读，按记录顺序）；[reset] 会清空。
  /// 例如 `handle.laps.last`。
  List<Duration> get laps => List<Duration>.unmodifiable(_laps);

  /// 动态调整上限，保留已累计的时间；传 null 取消上限。
  /// 新上限不超过当前累计时间时，下一帧即完成。
  void updateLimit(Duration? limit) {
    final task = _plugin.task(_id);
    if (task == null) return;
    task.limitMicros = Elapsed.limitMicrosOf(limit);
    task.revision++;
    if (!task.done && !task.isPaused) _plugin.requestFrame();
  }

  /// Remove the task immediately.
  void cancel() => _plugin.removeTask(_id);

  /// Update only the threshold, preserving elapsed time.
  /// 仅同步阈值，保留累计时间和暂停状态。
  void updateThreshold(Duration? threshold) {
    final task = _plugin.task(_id);
    if (task == null) return;
    task.updateThreshold(threshold);
    // 休眠中的新阈值可能更早到达，需要重新计算唤醒时间。
    if (!task.done && !task.isPaused) _plugin.requestFrame();
  }

  /// 当前累计时间（读取实时单调钟）；已取消返回 [Duration.zero]。
  Duration get elapsed {
    final task = _plugin.task(_id);
    return task == null ? Duration.zero : _plugin.elapsedOf(task);
  }
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
/// [interval] (milliseconds) controls how often a task's display is updated,
/// same semantics as [Countdown.interval]: `1000` (default) updates when the
/// elapsed time crosses a whole second, `0` updates every frame.
/// 每个任务按自己的累计时间跨过 interval 整数倍的时刻更新，调度器在两次更新之间休眠。
///
/// Tasks are anchored on the **monotonic** clock of [clock]; the default
/// [SystemClock] compensates deep sleep on foreground resume.
///
/// ## Grouping
/// Create multiple [Elapsed] instances to isolate groups, same as [Countdown]:
/// ```dart
/// final calls = Elapsed(name: 'call-durations');
/// Countman.use(calls);
/// TextElapsed(plugin: calls)
/// ```
/// 正计时引擎，每帧共享单调时钟快照并独立检查阈值。
class Elapsed extends ClockPlugin<ElapsedTask> {
  /// [name] 为诊断名称（不同实例请用唯一名称），[interval] 为显示间隔毫秒，
  /// [clock] 为时间源（默认 [CountmanClock.system]）。
  /// 例如 `Elapsed(name: 'call-durations', interval: 100)`。
  Elapsed({String? name, super.interval, super.clock})
    : super(name ?? 'elapsed');

  /// 把用户给的上限换算成非负微秒；null 表示无上限。
  @internal
  static int? limitMicrosOf(Duration? limit) => limit == null
      ? null
      : (limit.inMicroseconds < 0 ? 0 : limit.inMicroseconds);

  /// 把累计微秒钳到 [0, 上限]；无上限时只钳下界。
  int _clamped(ElapsedTask task, int us) {
    if (us < 0) return 0;
    final limit = task.limitMicros;
    return limit != null && us > limit ? limit : us;
  }

  /// 累计微秒：暂停时取冻结值，否则用本帧时钟快照（墙钟或单调钟）减去起点，
  /// 并钳到 [0, limit]。
  @override
  int valueMicrosOf(ElapsedTask task) {
    final paused = task.pausedElapsed;
    if (paused != null) return _clamped(task, paused.inMicroseconds);
    final now = task.absolute ? frameWallMicros : frameMonotonicMicros;
    return _clamped(task, now - task.startMicros);
  }

  /// 正计时没有固定总时长，进度分母恒为空。
  @override
  Duration? totalOf(ElapsedTask task) => null;

  /// 仅当设置了 limit 且累计到达它时完成；无上限的正计时不会自行完成。
  @override
  bool isComplete(ElapsedTask task) {
    final limit = task.limitMicros;
    return limit != null && valueMicrosOf(task) >= limit;
  }

  /// 累计到下一个间隔整数倍还需的微秒数。
  @override
  int boundaryWake(ElapsedTask task, int value, int intervalMicros) =>
      (value ~/ intervalMicros + 1) * intervalMicros - value;

  /// 距到达 limit 的微秒数；无上限返回 [CountmanPlugin.idle]。
  @override
  int completionWake(ElapsedTask task, int value) {
    final limit = task.limitMicros;
    return limit == null ? CountmanPlugin.idle : limit - value;
  }

  /// 累计达到阈值（含）视为越过。
  @override
  int thresholdWake(int value, int thresholdMicros) => thresholdMicros - value;

  /// 到达 limit：触发完成回调；最后一次 limit 值的更新已由基类先行发出。
  @override
  void onComplete(ElapsedTask task) => task.onComplete?.call();

  // ── internal accessors for handles (same library) ─────────────────

  @internal
  ElapsedTask? task(int id) => taskOf(id);
  @internal
  void requestFrame() => ctx.requestFrame();

  /// 读取实时时钟得到 [task] 的累计时间（钳到 [0, limit]），供句柄与控制器使用。
  @internal
  Duration elapsedOf(ElapsedTask task) {
    final paused = task.pausedElapsed;
    if (paused != null) {
      return Duration(microseconds: _clamped(task, paused.inMicroseconds));
    }
    final c = clock;
    final now = task.absolute ? c.wallMicros() : c.monotonicMicros();
    final us = _clamped(task, now - task.startMicros);
    return us <= 0 ? Duration.zero : Duration(microseconds: us);
  }

  // ── public API ────────────────────────────────────────────────────

  /// 添加一个正计时并返回句柄。起点：`opts.since` 按墙钟锚定；`opts.initial`
  /// 按单调钟锚定为已有该偏移；都没给则从当前单调钟起算（从零开始）。
  ElapsedHandle add(ElapsedOptions opts) {
    final id = nextId();
    final since = opts.since;
    final initialMicros = opts.initial?.inMicroseconds ?? 0;
    enqueue(
      ElapsedTask(
        id: id,
        startMicros: since != null
            ? since.microsecondsSinceEpoch
            : clock.monotonicMicros() - (initialMicros < 0 ? 0 : initialMicros),
        absolute: since != null,
        limitMicros: limitMicrosOf(opts.limit),
        onComplete: opts.onComplete,
        onUpdate: opts.onUpdate,
        threshold: opts.threshold,
        onThreshold: opts.onThreshold,
        onReady: opts.onReady,
        onStart: opts.onStart,
        onCancel: opts.onCancel,
        onPause: opts.onPause,
        onResume: opts.onResume,
      ),
    );
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

  /// 记录一圈并返回本圈时长；未绑定或任务已结束时返回 [Duration.zero]。
  /// 例如 `final split = controller.lap();`。
  Duration lap() => _handle?.lap() ?? Duration.zero;

  /// 已记录的每圈时长（只读快照）；未绑定时为空列表。
  List<Duration> get laps => _handle?.laps ?? const <Duration>[];

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
