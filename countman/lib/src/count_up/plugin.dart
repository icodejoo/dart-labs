import 'package:flutter/animation.dart';
import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/core/types.dart';
import 'types.dart';

/// Returned by [Countup.add]. Allows the caller to retarget
/// or cancel the animation without holding a reference to the plugin.
class CountupHandle {
  CountupHandle._(this._id, this._plugin);

  final int _id;
  final Countup _plugin;

  /// Retarget to a new [to] value, continuing from the current position.
  void update({required double to, Duration? duration, Curve? curve}) =>
      _plugin._retarget(_id, to: to, duration: duration, curve: curve);

  void cancel() => _plugin._cancel(_id);
}

/// Count-up engine — drives number interpolation on the shared ticker.
/// Each instance is an independent task queue (= a "group").
class Countup implements CountmanPlugin {
  Countup({String? name}) : name = name ?? 'countup';

  @override
  final String name;

  late CountmanContext _ctx;
  final _tasks = <int, CountupTask>{};
  int _uid = 0;

  // ── CountmanPlugin ────────────────────────────────────────────────

  @override
  void onAttach(CountmanContext ctx) => _ctx = ctx;

  @override
  bool tick(Duration elapsed, Duration dt) {
    if (_tasks.isEmpty) return false;

    // Use dt accumulation rather than absolute elapsed.
    // elapsed goes through Flutter's epoch adjustment (first frame = Duration.zero),
    // making absolute-time math unreliable in tests. dt is always a clean delta.
    final dtMs = dt.inMicroseconds / 1000.0;
    var busy = false;
    final done = <int>[];

    for (final task in _tasks.values) {
      if (task.done) continue;

      if (!task.started) {
        task.started = true;
        // First active frame: render initial value without advancing time.
        task.value = task.from;
        task.onUpdate?.call(task.value);
        busy = true;
        continue;
      }

      task.accumMs += dtMs;
      final durationMs = task.duration.inMilliseconds.toDouble();
      final t = durationMs > 0
          ? (task.accumMs / durationMs).clamp(0.0, 1.0)
          : 1.0;

      final complete = t >= 1.0;
      task.value = complete
          ? task.to
          : task.from + (task.to - task.from) * task.curve.transform(t);
      task.onUpdate?.call(task.value);

      if (complete) {
        task.done = true;
        done.add(task.id);
        task.onDone?.call(task.value);
      } else {
        busy = true;
      }
    }

    for (final id in done) {
      _tasks.remove(id);
    }
    return busy;
  }

  @override
  void dispose() {
    _tasks.clear();
    // Reset the auto-bootstrap flag so countup() re-registers after destroy().
    if (identical(this, _default)) _registered = false;
  }

  // ── public API ────────────────────────────────────────────────────

  CountupHandle add(CountupOptions opts) {
    final id = _uid++;
    _tasks[id] = CountupTask(
      id: id,
      from: opts.from ?? 0,
      to: opts.to,
      duration: opts.duration,
      curve: opts.curve,
      onUpdate: opts.onUpdate,
      onDone: opts.onDone,
    );
    _ctx.requestFrame();
    return CountupHandle._(id, this);
  }

  // ── internal (called by CountupHandle) ───────────────────────────

  void _retarget(int id, {required double to, Duration? duration, Curve? curve}) {
    final task = _tasks[id];
    if (task == null || task.done) return;
    task.from = task.value;
    task.to = to;
    if (duration != null) task.duration = duration;
    if (curve != null) task.curve = curve;
    task.accumMs = 0;
    task.started = false;
    _ctx.requestFrame();
  }

  void _cancel(int id) => _tasks.remove(id);
}

// ── default instance + top-level function ─────────────────────────

final _default = Countup();
bool _registered = false;

/// Add a count-up animation using the default shared [Countup] instance.
/// Auto-registered with [Countman] on first call.
CountupHandle countup(CountupOptions opts) {
  if (!_registered) {
    _registered = true;
    Countman.use(_default);
  }
  return _default.add(opts);
}
