import 'package:flutter/foundation.dart';

import 'clock.dart';
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
  // 回调内改锚点或暂停后，旧版本帧不能继续提交完成状态。
  int revision = 0;
  void reanchor() {
    revision++;
    started = false;
  }

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
/// 共享任务队列骨架，逐任务隔离回调异常并保证终态清理。
abstract class TaskQueuePlugin<T extends CountmanTask>
    implements CountmanPlugin {
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

  // 实例销毁后终身不可复用，调用方需创建新插件。
  bool _disposed = false;

  void _ensureUsable() {
    if (_disposed) {
      throw StateError(
        'countman: plugin "$name" is disposed; create a new instance.',
      );
    }
  }

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

  // 测试观测缓存持有量，验证排空后及时释放闭包。
  @visibleForTesting
  int get debugSnapshotTaskCount => _live.length;

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

  final _groupListeners = <Object, (VoidCallback?, VoidCallback?)>{};

  /// Subscribe independently of legacy callback fields; invoke to unsubscribe.
  /// 独立分组订阅，解除时只移除本次绑定，兼容原有单槽回调。
  VoidCallback addGroupListener({
    VoidCallback? onReady,
    VoidCallback? onDrained,
  }) {
    _ensureUsable();
    final key = Object();
    _groupListeners[key] = (onReady, onDrained);
    return () => _groupListeners.remove(key);
  }

  void _notifyGroup(bool ready) {
    final listeners = Map.of(_groupListeners);
    (ready ? onFirstEnqueued : onQueueDrained)?.call();
    for (final entry in listeners.entries) {
      if (_disposed) break;
      if (!_groupListeners.containsKey(entry.key)) continue;
      (ready ? entry.value.$1 : entry.value.$2)?.call();
    }
  }

  /// 注入调度上下文；已销毁的实例不能重新挂载。
  @override
  void onAttach(CountmanContext c) {
    _ensureUsable();
    ctx = c;
    _attached = true;
  }

  /// 标记为已注销；下一次添加任务会重新自注册。
  @override
  void onDetach() => _attached = false;

  /// Allocate a unique task id.
  @protected
  int nextId() => _uid++;

  /// Add [task] to the queue and request a frame. Safe to call from within a
  /// tick callback — the insert is deferred until the loop finishes.
  @protected
  void enqueue(T task) {
    _ensureUsable();
    if (!_attached) Countman.use(this);
    final wasIdle = tasks.isEmpty && _pendingAdd.isEmpty;
    if (_ticking) {
      _pendingAdd.add(task);
    } else {
      tasks[task.id] = task;
      _liveDirty = true;
    }
    if (wasIdle) _notifyGroup(true);
    // 分组回调可同步取消或销毁，后续通知只面向仍存活任务。
    if (!task.done && !_disposed) task.onReady?.call();
    if (!task.done && !_disposed) ctx.requestFrame();
  }

  /// Remove the task with [id]. Safe to call from within a tick callback —
  /// the removal is deferred until the loop finishes. Package-internal:
  /// handles (which are not subclasses) call this to cancel their task.
  @internal
  void removeTask(int id) {
    T? task = tasks[id];
    if (task == null) {
      for (final p in _pendingAdd) {
        if (p.id == id) {
          task = p;
          break;
        }
      }
    }
    if (task == null || task.done) return;
    // 终态先于回调提交，自身重入取消保持幂等。
    task.done = true;
    if (_ticking) {
      _pendingRemove.add(id);
    } else {
      final hadTasks = tasks.isNotEmpty;
      tasks.remove(id);
      _pendingAdd.removeWhere((t) => t.id == id);
      // 结构变化后立即释放旧快照，空闲组不依赖下一帧清理。
      _live.clear();
      _liveDirty = true;
      // 记录本次移除是否排空，兄弟任务的嵌套取消自行派发事件。
      final drained = hadTasks && tasks.isEmpty && _pendingAdd.isEmpty;
      task.onCancel?.call();
      if (drained && tasks.isEmpty && _pendingAdd.isEmpty && !_disposed) {
        _notifyGroup(false);
      }
      // 休眠期间取消最后一个任务：请求一帧，让调度器看到空闲并取消定时器。
      if (drained && tasks.isEmpty && _pendingAdd.isEmpty && !_disposed) {
        ctx.requestFrame();
      }
      return;
    }
    // 先标记终态、登记移除，再允许用户重入取消。
    task.onCancel?.call();
  }

  /// Look up a task by id (null if absent).
  @protected
  T? taskOf(int id) {
    final live = tasks[id];
    if (live != null) return live;
    // 刚返回的待入队 handle 同样支持暂停、重定目标和取消。
    for (final task in _pendingAdd) {
      if (task.id == id) return task;
    }
    return null;
  }

  // ── overridable hooks ─────────────────────────────────────────────

  /// 每帧在任务循环前调用一次，用于读取本帧共享的时钟快照等；默认无操作。
  /// [dtMs] 为本帧活动间隔（毫秒），休眠后的首帧为 0。
  @protected
  void beginFrame(double dtMs) {}

  /// Render a task's initial value on its first active frame (no time advance).
  @protected
  void renderInitial(T task);

  /// 推进一个活动任务；需要终结时置 `task.done = true`，循环结束后统一清理。
  /// 下次唤醒时间由 [nextWake] 另行给出，此处无返回值。
  /// [dtMs] 为本帧活动间隔（毫秒）。
  @protected
  void step(T task, double dtMs);

  /// 初值与首次启动回调完成后检查任务；默认无操作。
  /// 子类可在此完成首帧已到期任务，保留初值、启动、完成的回调顺序。
  @protected
  void afterInitial(T task) {}

  /// Extra teardown for subclasses (e.g. resetting a bootstrap flag).
  @protected
  void onDispose() {}

  // ── CountmanPlugin ────────────────────────────────────────────────

  /// 活动任务默认逐帧运行；时钟子类覆盖为自己的边界时间。
  @protected
  int nextWake(T task) => CountmanPlugin.nextFrame;

  /// 逐任务隔离回调异常并清理终态，返回最早唤醒微秒数。
  @override
  int tick(Duration elapsed, Duration dt) {
    // 已销毁插件不再接受帧驱动。
    if (_disposed) return CountmanPlugin.idle;
    if (tasks.isEmpty) return CountmanPlugin.idle;

    final dtMs = dt.inMicroseconds / 1000.0;
    beginFrame(dtMs);

    // Rebuild the live snapshot only if the set changed since last frame.
    //
    // 仅当任务集自上帧变化时才重建活动快照。
    if (_liveDirty) {
      _live
        ..clear()
        ..addAll(tasks.values);
      _liveDirty = false;
    }

    var wake = CountmanPlugin.idle;
    _ticking = true;
    try {
      for (var li = 0; li < _live.length; li++) {
        if (_disposed) break;
        final task = _live[li];
        if (task.done || task.isPaused) continue;

        try {
          if (!task.started) {
            task.started = true;
            final revision = task.revision;
            renderInitial(task);
            // 初值回调可取消、暂停或重定目标；不继续发送旧版本的 start。
            if (task.done ||
                task.isPaused ||
                revision != task.revision ||
                _disposed) {
              // 暂停中的初值不算已启动，恢复后仍需派发首次 start。
              if (!task.done && task.isPaused) task.started = false;
              continue;
            }
            if (!task.startFired) {
              task.startFired = true;
              task.onStart?.call(); // once per task, even across re-anchors
            }
            if (!task.done &&
                !task.isPaused &&
                revision == task.revision &&
                !_disposed) {
              afterInitial(task);
            }
            continue;
          }

          step(task, dtMs);
        } catch (error, stack) {
          _reportTaskError(task, error, stack, '回调');
          if (!task.done && !task.isPaused && !_disposed) {
            wake = CountmanPlugin.nextFrame;
          }
        } finally {
          if (task.done) _pendingRemove.add(task.id);
          if (!task.done && !task.isPaused && !_disposed) {
            final delay = task.started
                ? nextWake(task)
                : CountmanPlugin.nextFrame;
            if (wake == CountmanPlugin.idle || delay < wake) wake = delay;
          }
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
          // 同帧新增后取消的任务不得重新插回活动表。
          if (!t.done && !_disposed) tasks[t.id] = t;
        }
        _pendingAdd.clear();
        _liveDirty = true;
        if (tasks.isNotEmpty && !_disposed) wake = CountmanPlugin.nextFrame;
      }
      // Reached only when the group was non-empty this frame (empty groups
      // early-return above), so an empty map here means it just drained.
      // 丢弃含旧任务闭包的快照，下次活动帧再按需重建。
      if (_liveDirty || tasks.isEmpty || _disposed) _live.clear();
      if (tasks.isEmpty && !_disposed) _notifyGroup(false);
    }
    return _disposed ? CountmanPlugin.idle : wake;
  }

  /// 统一报告任务异常，保留插件、任务及回调阶段的上下文。
  void _reportTaskError(T task, Object error, StackTrace stack, String action) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'countman',
        context: ErrorDescription('插件 "$name" 的任务 ${task.id} $action异常'),
      ),
    );
  }

  /// 封闭队列并逐项报告取消异常；子类收尾始终执行。
  @override
  void dispose() {
    // 先封闭实例，避免销毁回调重新加入任务；重复销毁保持幂等。
    if (_disposed) return;
    _disposed = true;
    // 先摘除并终结全部任务，再通知；回调取消其他任务不会改变遍历集合。
    final cancelled = [
      ...tasks.values,
      ..._pendingAdd,
    ].where((t) => !t.done).toList();
    for (final task in cancelled) {
      task.done = true;
    }
    tasks.clear();
    _live.clear();
    _liveDirty = true;
    _pendingAdd.clear();
    _pendingRemove.clear();
    _groupListeners.clear();
    onFirstEnqueued = null;
    onQueueDrained = null;
    try {
      for (final task in cancelled) {
        try {
          task.onCancel?.call();
        } catch (error, stack) {
          _reportTaskError(task, error, stack, '取消回调');
        }
      }
    } finally {
      onDispose();
    }
  }
}

/// 由时钟锚点驱动的任务，按自己的显示桶边界更新。
/// 倒计时（截止点在前）与正计时（起点在后）共用。
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

  /// 上次发出显示更新时的桶编号（`值微秒 ~/ interval 微秒`）。
  /// 只由 [ClockPlugin] 维护；桶变化才触发下一次 `onUpdate`。
  int lastBucket = 0;

  /// Update the threshold without resetting the clock anchor.
  /// 阈值独立同步，不重置计时；阈值改变后允许新阈值触发一次。
  void updateThreshold(Duration? value) {
    if (threshold == value) return;
    threshold = value;
    thresholdFired = false;
    revision++;
  }

  /// Fired when the task is paused / resumed via its handle.
  VoidCallback? onPause;
  VoidCallback? onResume;

  /// Per-task reused decomposition — mutated in place each tick, read by every
  /// consumer of this task.
  final TimeParts parts = TimeParts.zero();
}

/// 时钟类引擎（倒计时、正计时）的基类。
///
/// 每帧只读一次时钟快照（墙钟与单调钟微秒，按需惰性读取），任务内部全部用整数
/// 微秒运算。显示更新按**每个任务自己的桶边界**触发：桶 = `值微秒 ~/ interval 微秒`，
/// 桶变化才发 `onUpdate`；完成与阈值每帧检查，不被显示间隔延迟。[tick] 返回所有活动
/// 任务中最早的唤醒时间，调度器据此休眠，不再逐 vsync 出帧。
///
/// 子类提供领域钩子：[valueMicrosOf]、[totalOf]、[isComplete]、[thresholdWake]、
/// [boundaryWake]、[completionWake]、[onComplete]。
abstract class ClockPlugin<T extends ClockTask> extends TaskQueuePlugin<T> {
  /// [interval] 为显示更新间隔（毫秒，0 或负数表示每帧）；[clock] 为时间源，
  /// 为空时使用 [CountmanClock.system]（每次读取时解析，便于测试整体替换）。
  /// 例如 `Countdown(name: 'ms', interval: 0, clock: ManualCountmanClock())`。
  ClockPlugin(super.name, {this.interval = 1000, CountmanClock? clock})
    : _clock = clock,
      _intervalMicros = interval * Duration.microsecondsPerMillisecond;

  /// Processing interval in milliseconds. 0 = every frame.
  final int interval;

  /// 显示间隔的微秒数；非正数表示每帧更新。
  final int _intervalMicros;

  /// 构造时显式指定的时钟；null 表示跟随 [CountmanClock.system]。
  final CountmanClock? _clock;

  /// 当前生效的时钟。
  CountmanClock get clock => _clock ?? CountmanClock.system;

  /// 本帧墙钟快照。
  int _frameWall = 0;

  /// 本帧墙钟快照是否已读取；false 表示尚未读取。
  bool _wallRead = false;

  /// 本帧单调钟快照。
  int _frameMono = 0;

  /// 本帧单调钟快照是否已读取；false 表示尚未读取。
  bool _monoRead = false;

  /// 本帧的墙钟微秒快照，同一帧内多次读取返回同一个值。
  @protected
  int get frameWallMicros {
    if (!_wallRead) {
      _frameWall = clock.wallMicros();
      _wallRead = true;
    }
    return _frameWall;
  }

  /// 本帧的单调钟微秒快照，同一帧内多次读取返回同一个值。
  @protected
  int get frameMonotonicMicros {
    if (!_monoRead) {
      _frameMono = clock.monotonicMicros();
      _monoRead = true;
    }
    return _frameMono;
  }

  /// 新帧开始：作废上一帧的时钟快照，首次使用时再读取。
  @override
  @protected
  void beginFrame(double dtMs) {
    _wallRead = false;
    _monoRead = false;
  }

  /// 返回 [task] 当前值所在的显示桶；每帧更新（间隔非正）时恒为 0。
  int _bucketOf(int valueMicros) =>
      _intervalMicros > 0 ? valueMicros ~/ _intervalMicros : 0;

  /// Decompose [valueMicrosOf] into the task's reused [TimeParts] and notify.
  /// 同时记录发出时的显示桶。
  @protected
  void emit(T task) {
    final value = valueMicrosOf(task);
    task.lastBucket = _bucketOf(value);
    task.parts.setMicros(value, totalOf(task));
    task.onUpdate?.call(task.parts);
  }

  /// 首帧先发初值，保持初值更新在 onStart 之前。
  @override
  @protected
  void renderInitial(T task) => emit(task);

  /// 初值与 onStart 后立即检查到期和阈值，不重复发初值。
  @override
  @protected
  void afterInitial(T task) => _process(task, true);

  /// 每帧检查阈值与完成；只有显示桶变化（或每帧模式）才发普通更新。
  @override
  @protected
  void step(T task, double dtMs) => _process(task, false);

  /// 共用逐帧判定；initial 表示首帧已发过当前快照的最终初值。
  void _process(T task, bool initial) {
    final revision = task.revision;
    if (!task.thresholdFired &&
        task.threshold != null &&
        thresholdWake(valueMicrosOf(task), task.threshold!.inMicroseconds) <=
            0) {
      task.thresholdFired = true;
      task.onThreshold?.call();
    }

    // 阈值回调可能取消、暂停或重置，旧帧不再更新或完成。
    if (task.done || task.isPaused || revision != task.revision) return;

    if (isComplete(task)) {
      if (!initial) emit(task);
      if (task.done || task.isPaused || revision != task.revision) return;
      task.done = true;
      onComplete(task);
      return;
    }

    if (initial) return;
    if (_intervalMicros <= 0 ||
        _bucketOf(valueMicrosOf(task)) != task.lastBucket) {
      emit(task);
    }
  }

  /// 单个任务距下次需要处理的微秒数：显示桶边界、完成时刻、阈值时刻取最早。
  /// 每帧更新模式或桶与上次不一致时返回下一帧。
  @override
  @protected
  int nextWake(T task) {
    if (_intervalMicros <= 0) return CountmanPlugin.nextFrame;
    final value = valueMicrosOf(task);
    if (_bucketOf(value) != task.lastBucket) return CountmanPlugin.nextFrame;
    var wake = boundaryWake(value, _intervalMicros);
    final complete = completionWake(value);
    if (complete != CountmanPlugin.idle && complete < wake) wake = complete;
    final threshold = task.threshold;
    if (threshold != null && !task.thresholdFired) {
      final crossing = thresholdWake(value, threshold.inMicroseconds);
      if (crossing <= 0) return CountmanPlugin.nextFrame;
      if (crossing < wake) wake = crossing;
    }
    return wake <= 0 ? CountmanPlugin.nextFrame : wake;
  }

  // ── domain hooks ──────────────────────────────────────────────────

  /// 任务当前值的整数微秒（倒计时为剩余并钳零，正计时为已过）。
  /// 必须基于本帧快照 [frameWallMicros]/[frameMonotonicMicros]，且不分配对象。
  @protected
  int valueMicrosOf(T task);

  /// The task's fixed total for progress (countdown: initial duration).
  /// `null` when there is none (elapsed).
  @protected
  Duration? totalOf(T task);

  /// Whether the task has finished (countdown reached zero; elapsed: never).
  @protected
  bool isComplete(T task);

  /// 距显示桶下一次变化的微秒数，要求结果为正；[value] 为当前值微秒，
  /// [intervalMicros] 为显示间隔微秒。
  @protected
  int boundaryWake(int value, int intervalMicros);

  /// 距任务完成的微秒数；不会自行完成的引擎返回 [CountmanPlugin.idle]。
  @protected
  int completionWake(int value) => CountmanPlugin.idle;

  /// 距阈值被越过的微秒数；小于等于 0 表示已越过。
  /// [thresholdMicros] 为阈值微秒（倒计时：剩余降到阈值；正计时：已过达到阈值）。
  @protected
  int thresholdWake(int value, int thresholdMicros);

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

  /// Forget only the default that owns this instance.
  /// 局部注销默认实例后，下次访问重建，其他默认组保持原样。
  static void resetInstance(CountmanPlugin plugin) {
    for (final d in _all) {
      if (identical(d._instance, plugin)) d.reset();
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
