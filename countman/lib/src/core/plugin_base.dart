import 'package:flutter/foundation.dart';

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
  bool started = false;

  /// Set true once the task has completed and should be removed.
  bool done = false;

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

  /// Live task map. Never mutate its key set directly from within a tick —
  /// use [enqueue]/[removeTask] so changes are deferred safely.
  @protected
  final Map<int, T> tasks = <int, T>{};

  int _uid = 0;
  bool _ticking = false;
  final List<T> _pendingAdd = <T>[];
  final List<int> _pendingRemove = <int>[];

  // ── group-level lifecycle (used by providers) ─────────────────────
  /// Fired when a task is enqueued into a previously empty group (the group
  /// transitions idle → active). Surfaced to providers as `onGroupReady`.
  VoidCallback? onFirstEnqueued;

  /// Fired when the last task leaves the group (the group transitions
  /// active → idle). Surfaced to providers as `onAllComplete`.
  VoidCallback? onQueueDrained;

  @override
  void onAttach(CountmanContext c) => ctx = c;

  /// Allocate a unique task id.
  @protected
  int nextId() => _uid++;

  /// Add [task] to the queue and request a frame. Safe to call from within a
  /// tick callback — the insert is deferred until the loop finishes.
  @protected
  void enqueue(T task) {
    final wasIdle = tasks.isEmpty && _pendingAdd.isEmpty;
    if (_ticking) {
      _pendingAdd.add(task);
    } else {
      tasks[task.id] = task;
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
    final task = tasks[id] ?? _pendingAdd.cast<T?>().firstWhere(
          (t) => t?.id == id,
          orElse: () => null,
        );
    if (task != null && !task.done) task.onCancel?.call();
    if (_ticking) {
      _pendingRemove.add(id);
    } else {
      final hadTasks = tasks.isNotEmpty;
      tasks.remove(id);
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

    var busy = false;
    _ticking = true;
    try {
      for (final task in tasks.values) {
        if (task.done || task.isPaused) continue;

        if (!task.started) {
          task.started = true;
          renderInitial(task);
          task.onStart?.call(); // timing begins on the first rendered frame
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
      }
      if (_pendingAdd.isNotEmpty) {
        for (final t in _pendingAdd) {
          tasks[t.id] = t;
        }
        _pendingAdd.clear();
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
