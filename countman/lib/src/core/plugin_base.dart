import 'package:flutter/foundation.dart';

import 'ticker.dart';
import 'time_parts.dart';
import 'types.dart';

/// Base state for a single task owned by a [TaskQueuePlugin].
///
/// Holds only what the shared tick skeleton needs:
/// [started] (has the first-frame render happened) and [done] (should the
/// task be evicted). Domain subclasses add their own value/anchor fields.
abstract class CountmanTask {
  CountmanTask(this.id, {this.onReady, this.onStart, this.onCancel});

  final int id;

  /// Set true after the task's first active frame renders its initial value.
  /// Cleared on re-anchor (e.g. counter retarget) so the next frame renders
  /// without advancing time; [onStart] does NOT re-fire (see [startFired]).
  ///
  /// 首帧渲染初值后置 true。重新锚定（如 counter 重定目标）时清除，使下一帧不推进
  /// 时间地渲染；[onStart] 不会再次触发（见 [startFired]）。
  bool started = false;

  /// Set true the first time [onStart] fires; keeps it once-per-task even
  /// across re-anchors that reset [started].
  ///
  /// [onStart] 首次触发后置 true；即使经过重置 [started] 的重新锚定，也保持每任务一次。
  bool startFired = false;

  /// Set true once the task has completed and should be removed.
  bool done = false;

  /// Re-anchor the task: make the next active frame render the current state
  /// WITHOUT advancing time (dt), and WITHOUT re-firing [onStart]. Used by
  /// retarget / resume / reset. The one named operation the plugins invoke
  /// instead of poking [started] directly — [startFired] keeps [onStart]
  /// once-per-task across every re-anchor.
  ///
  /// 重新锚定任务：使下一活动帧渲染当前状态，且不推进时间（dt）、不再次触发
  /// [onStart]。用于 retarget / resume / reset。这是插件调用的唯一具名操作，
  /// 取代直接改写 [started]——[startFired] 保证 [onStart] 跨每次重新锚定仍每任务一次。
  void reanchor() => started = false;

  /// Whether the task is frozen. Non-pausable tasks (counter) stay `false`.
  bool get isPaused => false;

  // ── lifecycle callbacks (fired by the base) ────────────────────────
  /// Fired synchronously when the task is enqueued (registration succeeded).
  VoidCallback? onReady;

  /// Fired once on the task's first rendered frame (timing begins).
  VoidCallback? onStart;

  /// Fired when the task is removed before it completes (handle.cancel /
  /// widget dispose). NOT fired on natural completion.
  VoidCallback? onCancel;
}

/// Shared boilerplate for every countman engine: task map, id allocator,
/// context wiring, add/remove/dispose plumbing, and the per-frame tick
/// skeleton (empty-check → first-frame render → per-task step → deferred
/// removal of completed tasks).
///
/// ## Concurrency safety (P0 guarantee)
/// User callbacks fired during [tick] (`onUpdate`/`onComplete`/`onThreshold`)
/// routinely call back into the plugin to add or cancel tasks — e.g.
/// `controller.repeat()` cancels then re-adds. Mutating [tasks] while the
/// tick loop iterates it would throw `ConcurrentModificationError`, so all
/// structural changes route through [enqueue]/[removeTask], which defer to
/// a pending buffer while [_ticking] and drain it after the loop. Value-only
/// mutations (retarget, pause/resume/reset) never touch map keys and are
/// always safe.
abstract class TaskQueuePlugin<T extends CountmanTask> implements CountmanPlugin {
  TaskQueuePlugin(this.name);

  @override
  final String name;

  @protected
  late CountmanContext ctx;

  /// True once [onAttach] has injected [ctx]. Used to lazily self-register a
  /// plugin the first time a task is added, so a user-created plugin passed
  /// straight to a widget (`plugin: Countdown(name: 'x', interval: 100)`)
  /// works without a manual `Countman.use(...)` call.
  ///
  /// [onAttach] 注入 [ctx] 后为 true。用于首次添加任务时惰性自注册，使用户直接传给
  /// 组件的自建插件（`plugin: Countdown(name: 'x', interval: 100)`）无需手动
  /// `Countman.use(...)` 即可工作。
  bool _attached = false;

  /// Live task map. Never mutate its key set directly from within a tick —
  /// use [enqueue]/[removeTask] so changes are deferred safely.
  @protected
  final Map<int, T> tasks = <int, T>{};

  int _uid = 0;
  bool _ticking = false;
  final List<T> _pendingAdd = <T>[];
  final List<int> _pendingRemove = <int>[];

  // Reusable snapshot of live tasks for the per-frame loop — avoids allocating
  // a fresh `tasks.values` iterator every frame. Rebuilt only when the task set
  // structurally changes (add/remove/drain); steady-state animation reuses it.
  //
  // 逐帧循环用的活动任务复用快照——避免每帧新建 `tasks.values` 迭代器。仅当任务集
  // 结构变化（增/删/排空）时重建；稳态动画复用它。
  final List<T> _live = <T>[];
  bool _liveDirty = true;

  /// Number of live tasks in this group, including ones queued mid-tick.
  /// Drops to 0 once every task completes and is auto-removed — handy for
  /// observing the group going idle (the ticker then auto-stops).
  ///
  /// 本组存活任务数（含 tick 中排队的）。所有任务完成并被自动移除后归 0——
  /// 便于观察组转空闲（此后 ticker 自动停止）。
  int get activeTaskCount => tasks.length + _pendingAdd.length;

  // ── group-level lifecycle (used by providers) ─────────────────────
  /// Fired when a task is enqueued into a previously empty group (the group
  /// transitions idle → active). Surfaced to providers as `onGroupReady`.
  VoidCallback? onFirstEnqueued;

  /// Fired when the last task leaves the group (the group transitions
  /// active → idle). Surfaced to providers as `onAllComplete`.
  VoidCallback? onQueueDrained;

  @override
  void onAttach(CountmanContext c) {
    ctx = c;
    _attached = true;
  }

  /// Allocate a unique task id.
  @protected
  int nextId() => _uid++;

  /// Add [task] to the queue and request a frame. Safe to call from within a
  /// tick callback — the insert is deferred until the loop finishes.
  @protected
  void enqueue(T task) {
    // Lazily self-register on first use so a user-created plugin handed to a
    // widget attaches without a manual Countman.use(). Idempotent by name; a
    // name clash with an already-registered DIFFERENT instance leaves us
    // unattached — surface that as a clear error instead of a cryptic
    // LateInitializationError on [ctx].
    //
    // 首次使用时惰性自注册，使用户直接传给组件的插件无需手动 Countman.use() 即可挂载。
    // 按名幂等；若与已注册的“另一个”同名实例冲突则仍未挂载——此时抛出清晰错误，
    // 而非 [ctx] 上晦涩的 LateInitializationError。
    if (!_attached) {
      Countman.use(this);
      if (!_attached) {
        throw StateError(
          'countman: plugin "$name" is not attached because a different plugin '
          'with the same name is already registered. Give this plugin a unique '
          'name (e.g. Countdown(name: "my-group", ...)).',
        );
      }
    }
    final wasIdle = tasks.isEmpty && _pendingAdd.isEmpty;
    if (_ticking) {
      _pendingAdd.add(task);
    } else {
      tasks[task.id] = task;
      _liveDirty = true;
    }
    if (wasIdle) onFirstEnqueued?.call(); // group went idle → active
    task.onReady?.call(); // registration succeeded (synchronous at add)
    ctx.requestFrame();
  }

  /// Remove the task with [id]. Safe to call from within a tick callback —
  /// the removal is deferred until the loop finishes. Package-internal:
  /// handles (which are not subclasses) call this to cancel their task.
  @internal
  void removeTask(int id) {
    T? task = tasks[id];
    if (task == null) {
      for (final p in _pendingAdd) {
        if (p.id == id) { task = p; break; }
      }
    }
    if (task != null && !task.done) {
      task.onCancel?.call();
      // Mark done so a second removeTask in the same tick (e.g. cancel() called
      // twice) doesn't fire onCancel again; the loop also evicts done tasks.
      //
      // 标记 done，使同一 tick 内二次 removeTask（如 cancel() 被调两次）不再触发
      // onCancel；循环也会驱逐 done 任务。
      task.done = true;
    }
    if (_ticking) {
      _pendingRemove.add(id);
    } else {
      final hadTasks = tasks.isNotEmpty;
      tasks.remove(id);
      _liveDirty = true;
      if (hadTasks && tasks.isEmpty && _pendingAdd.isEmpty) {
        onQueueDrained?.call(); // group went active → idle
      }
    }
  }

  /// Look up a task by id (null if absent).
  @protected
  T? taskOf(int id) => tasks[id];

  // ── overridable hooks ─────────────────────────────────────────────

  /// Called once per frame before the task loop. Return whether tasks should
  /// be processed this frame. Default: always (every-frame engines). Interval
  /// engines override to gate on accumulated time.
  @protected
  bool beginFrame(double dtMs) => true;

  /// Render a task's initial value on its first active frame (no time advance).
  @protected
  void renderInitial(T task);

  /// Advance one active task. Return whether it is still busy (wants more
  /// frames). Set `task.done = true` to have it evicted after the loop.
  /// [shouldProcess] is the result of [beginFrame] for this frame.
  @protected
  bool step(T task, double dtMs, bool shouldProcess);

  /// Extra teardown for subclasses (e.g. resetting a bootstrap flag).
  @protected
  void onDispose() {}

  // ── CountmanPlugin ────────────────────────────────────────────────

  @override
  bool tick(Duration elapsed, Duration dt) {
    if (tasks.isEmpty) return false;

    final dtMs = dt.inMicroseconds / 1000.0;
    final shouldProcess = beginFrame(dtMs);

    // Rebuild the live snapshot only if the set changed since last frame.
    //
    // 仅当任务集自上帧变化时才重建活动快照。
    if (_liveDirty) {
      _live..clear()..addAll(tasks.values);
      _liveDirty = false;
    }

    var busy = false;
    _ticking = true;
    try {
      for (var li = 0; li < _live.length; li++) {
        final task = _live[li];
        if (task.done || task.isPaused) continue;

        if (!task.started) {
          task.started = true;
          renderInitial(task);
          if (!task.startFired) {
            task.startFired = true;
            task.onStart?.call(); // once per task, even across re-anchors
          }
          busy = true;
          continue;
        }

        final stillBusy = step(task, dtMs, shouldProcess);
        if (task.done) {
          _pendingRemove.add(task.id);
        } else if (stillBusy) {
          busy = true;
        }
      }
    } finally {
      _ticking = false;
      if (_pendingRemove.isNotEmpty) {
        for (final id in _pendingRemove) {
          tasks.remove(id);
        }
        _pendingRemove.clear();
        _liveDirty = true;
      }
      if (_pendingAdd.isNotEmpty) {
        for (final t in _pendingAdd) {
          tasks[t.id] = t;
        }
        _pendingAdd.clear();
        _liveDirty = true;
        busy = true; // freshly added tasks need a frame to render
      }
      // Reached only when the group was non-empty this frame (empty groups
      // early-return above), so an empty map here means it just drained.
      if (tasks.isEmpty) onQueueDrained?.call();
    }
    return busy;
  }

  @override
  void dispose() {
    for (final task in tasks.values) {
      if (!task.done) task.onCancel?.call(); // teardown cancels live tasks
    }
    tasks.clear();
    _pendingAdd.clear();
    _pendingRemove.clear();
    onDispose();
  }
}

/// A [CountmanTask] driven by a wall-clock anchor, processed on an interval.
/// Shared by countdown (deadline ahead of now) and elapsed (start behind now).
abstract class ClockTask extends CountmanTask {
  ClockTask(
    super.id, {
    this.onUpdate,
    this.threshold,
    this.onThreshold,
    this.onPause,
    this.onResume,
    super.onReady,
    super.onStart,
    super.onCancel,
  });

  /// Called each processed tick with this task's shared [TimeParts] (decomposed
  /// once per tick, reused — do not retain across frames).
  void Function(TimeParts parts)? onUpdate;
  Duration? threshold;
  void Function()? onThreshold;
  bool thresholdFired = false;

  /// Fired when the task is paused / resumed via its handle.
  VoidCallback? onPause;
  VoidCallback? onResume;

  /// Per-task reused decomposition — mutated in place each tick, read by every
  /// consumer of this task.
  final TimeParts parts = TimeParts.zero();
}

/// Base for interval-gated, wall-clock timer engines (countdown, elapsed).
///
/// Adds to [TaskQueuePlugin]: plugin-level interval accumulation ([interval]
/// ms; `0` = every frame) and once-only threshold dispatch. Subclasses supply
/// the four domain hooks: [valueOf], [isComplete], [thresholdCrossed],
/// [onComplete].
abstract class ClockPlugin<T extends ClockTask> extends TaskQueuePlugin<T> {
  ClockPlugin(super.name, {this.interval = 1000});

  /// Processing interval in milliseconds. 0 = every frame.
  final int interval;

  double _accumMs = 0;

  @override
  @protected
  bool beginFrame(double dtMs) {
    _accumMs += dtMs;
    final shouldProcess = interval <= 0 || _accumMs >= interval;
    if (shouldProcess) {
      if (interval > 0) {
        // Modulo (not subtract-one) so a dt spike — e.g. the app returning
        // from background with a multi-second dt — drops the whole backlog in
        // one frame instead of firing a burst of catch-up ticks over the next
        // N frames. Values come from the wall clock, so no drift results.
        _accumMs %= interval;
      } else {
        _accumMs = 0; // prevent unbounded growth at interval=0
      }
    }
    return shouldProcess;
  }

  /// Decompose [valueOf] into the task's reused [TimeParts] and notify.
  @protected
  void emit(T task) {
    task.parts.set(valueOf(task), totalOf(task));
    task.onUpdate?.call(task.parts);
  }

  @override
  @protected
  void renderInitial(T task) => emit(task);

  @override
  @protected
  bool step(T task, double dtMs, bool shouldProcess) {
    if (!shouldProcess) return true; // active, waiting for the interval

    if (!task.thresholdFired &&
        task.threshold != null &&
        thresholdCrossed(task)) {
      task.thresholdFired = true;
      task.onThreshold?.call();
    }

    if (isComplete(task)) {
      task.done = true;
      onComplete(task);
      return false;
    }

    emit(task);
    return true;
  }

  @override
  @protected
  void onDispose() => _accumMs = 0;

  // ── domain hooks ──────────────────────────────────────────────────

  /// Current value to report to `onUpdate` (remaining, or elapsed).
  @protected
  Duration valueOf(T task);

  /// The task's fixed total for progress (countdown: initial duration).
  /// `null` when there is none (elapsed).
  @protected
  Duration? totalOf(T task);

  /// Whether the task has finished (countdown reached zero; elapsed: never).
  @protected
  bool isComplete(T task);

  /// Whether [threshold] has been crossed in the counting direction
  /// (countdown: remaining ≤ threshold; elapsed: elapsed ≥ threshold).
  /// Only called when `task.threshold != null`.
  @protected
  bool thresholdCrossed(T task);

  /// Fire terminal callbacks when [isComplete] first returns true.
  @protected
  void onComplete(T task);
}

/// Holds a lazily-created, auto-registered default plugin instance. Replaces
/// the per-engine `_default` / `_registered` bootstrap and the matching
/// `Countman.destroy()` reset boilerplate.
///
/// 持有惰性创建、自动注册的默认插件实例。取代各引擎的 `_default` / `_registered`
/// 引导及对应的 `Countman.destroy()` 重置样板。
class LazyDefault<T extends CountmanPlugin> {
  /// Creates a lazy default from a [factory] invoked on first access, and
  /// registers it so [Countman.destroy] can reset every default centrally.
  ///
  /// 由首次访问时调用的 [factory] 创建惰性默认值，并登记自身，使 [Countman.destroy]
  /// 能集中重置所有默认值。
  LazyDefault(this._factory) {
    _all.add(this);
  }

  /// Every [LazyDefault] ever constructed. [Countman.destroy] resets them all
  /// via [resetAll], so plugins no longer each reset their own in `onDispose`.
  ///
  /// 所有已构造的 [LazyDefault]。[Countman.destroy] 经 [resetAll] 统一重置，
  /// 插件不再各自在 `onDispose` 里重置。
  static final List<LazyDefault<CountmanPlugin>> _all = [];

  /// Forgets every default instance so the next access rebuilds + re-registers.
  /// Called by [Countman.destroy] after clearing the plugin set.
  ///
  /// 忘记所有默认实例，使下次访问重建并重新注册。由 [Countman.destroy] 在清空
  /// 插件集后调用。
  static void resetAll() {
    for (final d in _all) {
      d.reset();
    }
  }

  final T Function() _factory;
  T? _instance;

  /// The instance — created lazily on first access, then reused. Registration
  /// is left to [TaskQueuePlugin.enqueue]'s self-register on the first added
  /// task (the single registration point for both default and user plugins),
  /// so a bare `defaultX` access that never adds a task costs nothing.
  ///
  /// 实例——首次访问时惰性创建，此后复用。注册交由 [TaskQueuePlugin.enqueue] 在首个
  /// 任务加入时自注册（默认插件与用户插件共用的唯一注册点），故仅访问 `defaultX`
  /// 而不加任务时零开销。
  T get instance => _instance ??= _factory();

  /// Forget the instance so the next [instance] access rebuilds + re-registers.
  ///
  /// 忘记实例，使下次 [instance] 访问重建并重新注册。
  void reset() => _instance = null;
}
