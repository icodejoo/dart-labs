import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/clock.dart';
import 'package:countman/src/core/types.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show internal;

import 'types.dart';
import '../core/fps.dart';

export 'package:countman/src/controllers/counter_value_controller.dart';

/// Returned by [Counter.add]. Allows the caller to retarget
/// or cancel the animation without holding a reference to the plugin.
class CounterHandle {
  CounterHandle._(this._id, this._plugin);

  final int _id;
  final Counter _plugin;

  /// 同步组件帧率配置；不重启任务或改变用户暂停状态。
  @internal
  set fps(double? value) {
    final task = _plugin.taskById(_id);
    if (task != null) _plugin.setTaskFps(task, value);
  }

  /// 由组件同步可见性；不触发暂停/恢复回调。
  @internal
  set muted(bool value) {
    final task = _plugin.taskById(_id);
    if (task != null) _plugin.setMuted(task, value);
  }

  /// 当前任务的静音状态，供插件迁移使用。
  @internal
  bool get muted => _plugin.taskById(_id)?.muted ?? false;

  /// 把存活任务迁移到新插件，保留进度、静音、暂停与一次性启动状态。
  @internal
  CounterHandle migrateTo(Counter next) => _plugin._migrate(_id, next);

  /// 读取当前真实插值位置，不投递显示回调；供隐藏期间控制器命令取快照。
  @internal
  double? get currentValue => _plugin._currentValue(_id);

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
  /// [fps] 为插件显示上限，null 继承全局；返回新插件。示例：`Counter(fps: 30)`。
  Counter({String? name, super.fps}) : super(name ?? 'counter');

  /// 限帧任务按单调钟差值推进；首次启用时沿用该帧 dt 衔接。
  void _advanceLimited(CounterTask task, int now, double dtMs) {
    final previous = task.frameClockMicros;
    task.accumMs += previous < 0 ? dtMs : (now - previous) / 1000.0;
    task.frameClockMicros = now;
  }

  /// 组件改上限时保留已推进时间，并令下一帧立即显示。
  @override
  @internal
  void setTaskFps(CounterTask task, double? value) {
    if (!task.muted && !task.paused && task.frameClockMicros >= 0) {
      _advanceLimited(task, CountmanClock.system.monotonicMicros(), 0);
    }
    task.nextAllowedMicros = -1;
    super.setTaskFps(task, value);
  }

  /// 把静音期间的真实流逝补到已用时间，暂停期间不补算。
  void _advanceMuted(CounterTask task, int now) {
    final start = task.muteStartMicros;
    if (start < 0 || task.paused) return;
    final durationMs = task.duration.inMicroseconds / 1000.0;
    task.accumMs = (task.accumMs + (now - start) / 1000.0)
        .clamp(0.0, durationMs > 0 ? durationMs : 0.0);
    task.muteStartMicros = now;
  }

  /// 静音只改显示调度；取消静音补算真实进度，下一帧统一执行回调。
  @override
  @internal
  void setMuted(CounterTask task, bool muted) {
    if (task.done || task.muted == muted) return;
    final now = CountmanClock.system.monotonicMicros();
    if (muted) {
      if (!task.paused && task.frameClockMicros >= 0) _advanceLimited(task, now, 0);
      task.frameClockMicros = -1;
      task.muteStartMicros = task.paused ? -1 : now;
    } else {
      _advanceMuted(task, now);
      task.muteStartMicros = -1;
      task.refreshAfterMute = true;
      task.frameClockMicros = !task.paused && frameIntervalOf(task) > 0 ? now : -1;
      task.nextAllowedMicros = -1;
      task.lastEmitMicros = -1;
    }
    super.setMuted(task, muted);
  }

  /// 可见动画按显示节拍与终点唤醒；静音动画只为终点安排一次唤醒。
  @override
  int nextWake(CounterTask task) {
    if (!task.muted) {
      final period = frameIntervalOf(task);
      if (period == 0) return CountmanPlugin.nextFrame;
      final now = CountmanClock.system.monotonicMicros();
      final allowed = allowedFrameMicros(task, period);
      final display = allowed - frameToleranceMicros - now;
      final remaining = task.duration.inMicroseconds - (task.accumMs * 1000).round();
      return display <= 0 || remaining <= 0 ? CountmanPlugin.nextFrame
          : (display < remaining ? display : remaining);
    }
    final remaining = task.duration.inMicroseconds -
        (task.accumMs * 1000).round() -
        (CountmanClock.system.monotonicMicros() - task.muteStartMicros);
    return remaining <= 0 ? CountmanPlugin.nextFrame : remaining;
  }

  /// 首帧保留现有进度，迁移或取消静音时不会倒回起点。
  @override
  void renderInitial(CounterTask task) {
    task.value = _clamp(task, task.from);
    if (task.refreshAfterMute) task.value = _valueAt(task);
    final period = frameIntervalOf(task);
    if (period > 0) {
      final now = CountmanClock.system.monotonicMicros();
      task.frameClockMicros = now;
      recordFrameEmit(task, now, period);
    }
    task.onUpdate?.call(task.value);
  }

  /// 静音任务仍初始化 started，并在首帧检查是否已越过终点。
  @override
  void afterInitial(CounterTask task) {
    if (task.muted) {
      step(task, 0);
    } else if (task.refreshAfterMute) {
      task.refreshAfterMute = false;
      if (task.accumMs * 1000 >= task.duration.inMicroseconds) {
        task.done = true;
        task.onComplete?.call(task.value);
      }
    }
  }

  /// 按已用时间计算当前位置，不分配对象，也不触发任何回调。
  double _valueAt(CounterTask task) {
    final durationMs = task.duration.inMicroseconds / 1000.0;
    final t = durationMs > 0 ? (task.accumMs / durationMs).clamp(0.0, 1.0) : 1.0;
    return _clamp(
      task,
      t >= 1 ? task.to : task.from + (task.to - task.from) * task.curve.transform(t),
    );
  }

  /// 读取静音期间实时进度，供命令取快照；完成事件留到 tick 内处理。
  double? _currentValue(int id) {
    final task = taskOf(id);
    if (task == null || task.done) return null;
    if (task.muted) {
      _advanceMuted(task, CountmanClock.system.monotonicMicros());
    } else if (task.frameClockMicros >= 0 && !task.paused) {
      _advanceLimited(task, CountmanClock.system.monotonicMicros(), 0);
    }
    return _valueAt(task);
  }

  /// 插值与完成回调始终处于基类逐任务异常边界内，静音不投递 onUpdate。
  @override
  void step(CounterTask task, double dtMs) {
    final period = task.muted ? 0 : frameIntervalOf(task);
    var now = 0;
    if (task.muted) {
      _advanceMuted(task, CountmanClock.system.monotonicMicros());
    } else if (period > 0 || task.frameClockMicros >= 0) {
      now = CountmanClock.system.monotonicMicros();
      _advanceLimited(task, now, task.refreshAfterMute ? 0 : dtMs);
      if (period == 0) task.frameClockMicros = -1;
    } else if (!task.refreshAfterMute) {
      task.accumMs += dtMs;
    }
    final refresh = task.refreshAfterMute;
    task.refreshAfterMute = false;
    final complete = task.accumMs * 1000 >= task.duration.inMicroseconds;
    task.value = _valueAt(task);
    final revision = task.revision;
    final allowed = allowedFrameMicros(task, period);
    if (!task.muted && (complete || refresh || task.lastEmitMicros < 0 || period == 0 || now >= allowed - frameToleranceMicros)) {
      if (period > 0) recordFrameEmit(task, now, period);
      task.onUpdate?.call(task.value);
    }
    if (task.done || task.isPaused || revision != task.revision) return;
    if (complete) {
      task.done = true;
      task.onComplete?.call(task.value);
    }
  }

  static double _clamp(CounterTask task, double v) =>
      (!task.allowNegative && v < 0) ? 0 : v;

  // ── public API ────────────────────────────────────────────────────

  CounterHandle add(CounterOptions opts) => addMuted(opts);

  /// 以指定静音状态直接入队，避免隐藏组件首帧投递显示回调。
  @internal
  CounterHandle addMuted(CounterOptions opts, {bool muted = false}) {
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
    )..fps = validFps(opts.fps)
      ..muted = muted
      ..muteStartMicros = muted ? CountmanClock.system.monotonicMicros() : -1);
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

  /// 由展示组件调用，业务代码不要直接调用。
  /// 返回一个不对应任何任务的句柄（`isDone` 恒为 true），用于组件当前没有动画任务
  /// （如 animateOnce 跳过入场）时仍能绑定控制器；不会入队、不触发分组回调、不请求帧。
  /// 例如 `controller.attach(plugin.detachedHandle(), relaunch: restart)`。
  @internal
  CounterHandle detachedHandle() => CounterHandle._(nextId(), this);

  /// 复制活动任务状态后静默移除旧任务；集合变更仍经延迟队列。
  CounterHandle _migrate(int id, Counter next) {
    final old = taskOf(id);
    if (old == null || old.done) return next.detachedHandle();
    final task = CounterTask(
      id: next.nextId(),
      from: old.from,
      to: old.to,
      duration: old.duration,
      curve: old.curve,
      allowNegative: old.allowNegative,
      onUpdate: old.onUpdate,
      onComplete: old.onComplete,
      onStart: old.onStart,
      onCancel: old.onCancel,
    )
      ..fps = old.fps
      ..lastEmitMicros = old.lastEmitMicros
      ..frameClockMicros = old.frameClockMicros
      ..nextAllowedMicros = old.nextAllowedMicros
      ..framePeriodMicros = old.framePeriodMicros
      ..value = old.value
      ..accumMs = old.accumMs
      ..started = old.started
      ..startFired = old.startFired
      ..paused = old.paused
      ..muted = old.muted
      ..muteStartMicros = old.muteStartMicros
      ..refreshAfterMute = old.refreshAfterMute;
    old.onCancel = null;
    removeTask(id);
    next.enqueue(task);
    return CounterHandle._(task.id, next);
  }

  void _retarget(int id,
      {required double to, Duration? duration, Curve? curve}) {
    final task = taskOf(id);
    if (task == null || task.done) return;
    // 隐藏期间重定目标也从真实推进位置衔接。
    task.from = task.muted || task.frameClockMicros >= 0 ? _currentValue(id)! : task.value;
    task.value = task.from;
    task.to = to;
    if (duration != null) task.duration = duration;
    if (curve != null) task.curve = curve;
    task.accumMs = 0;
    task.frameClockMicros = -1;
    task.nextAllowedMicros = -1;
    task.refreshAfterMute = false;
    if (task.muted && !task.paused) {
      task.muteStartMicros = CountmanClock.system.monotonicMicros();
    }
    task.reanchor();
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
    if (task.muted) {
      final now = CountmanClock.system.monotonicMicros();
      if (paused) _advanceMuted(task, now);
      task.muteStartMicros = paused ? -1 : now;
    }
    if (!task.muted && (task.frameClockMicros >= 0 || frameIntervalOf(task) > 0)) {
      final now = CountmanClock.system.monotonicMicros();
      if (paused && task.frameClockMicros >= 0) _advanceLimited(task, now, 0);
      task.frameClockMicros = paused ? -1 : now;
    }
    task.paused = paused;
    // 同帧暂停再恢复也必须使旧计算失效。
    task.revision++;
    ctx.requestFrame();
  }
}

// ── default instance + top-level function ─────────────────────────

final _defaultCounter = LazyDefault<Counter>(() => Counter());

/// The default shared [Counter] instance. Auto-registered with [Countman]
/// on first access.
Counter get defaultCounter => _defaultCounter.instance;

/// Add a counter animation using the default shared [Counter] instance.
/// Auto-registered with [Countman] on first call.
CounterHandle counter(CounterOptions opts) => defaultCounter.add(opts);
