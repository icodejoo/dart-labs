import 'package:countman/src/core/plugin_base.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:flutter/animation.dart';

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

  void cancel() => _plugin.removeTask(_id);
}

/// Count-up engine — drives number interpolation on the shared ticker.
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

  @override
  void onDispose() {
    // Reset the auto-bootstrap flag so counter() re-registers after destroy().
    if (identical(this, _default)) _registered = false;
  }

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
}

// ── default instance + top-level function ─────────────────────────

final _default = Counter();
bool _registered = false;

/// The default shared [Counter] instance. Auto-registered with [Countman]
/// on first access.
Counter get defaultCounter {
  if (!_registered) {
    _registered = true;
    Countman.use(_default);
  }
  return _default;
}

/// Add a count-up animation using the default shared [Counter] instance.
/// Auto-registered with [Countman] on first call.
CounterHandle counter(CounterOptions opts) => defaultCounter.add(opts);
