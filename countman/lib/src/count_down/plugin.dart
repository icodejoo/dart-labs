import 'package:countman/src/core/ticker.dart';
import 'package:countman/src/core/types.dart';
import 'types.dart';

/// Returned by [Countdown.add].
class CountdownHandle {
  CountdownHandle._(this._id, this._plugin);

  final int _id;
  final Countdown _plugin;

  /// Freeze the countdown at its current remaining time.
  void pause() {
    final task = _plugin._tasks[_id];
    if (task == null || task.done || task.isPaused) return;
    task.pausedRemaining = task.remaining;
  }

  /// Resume a paused countdown. Restarts the ticker if it had stopped.
  void resume() {
    final task = _plugin._tasks[_id];
    if (task == null || task.done || !task.isPaused) return;
    task.endTime = countdownClock().add(task.pausedRemaining!);
    task.pausedRemaining = null;
    task.started = false; // re-anchor: next interval renders without consuming time
    _plugin._ctx.requestFrame();
  }

  /// Reset remaining to [duration] (or the original duration if null),
  /// then resume. No-op if already completed.
  void reset({Duration? duration}) {
    final task = _plugin._tasks[_id];
    if (task == null || task.done) return;
    if (duration != null) task.total = duration;
    task.endTime = countdownClock().add(task.total);
    task.pausedRemaining = null;
    task.started = false;
    _plugin._ctx.requestFrame();
  }

  /// Remove the task immediately.
  void cancel() => _plugin._tasks.remove(_id);

  Duration get remaining => _plugin._tasks[_id]?.remaining ?? Duration.zero;
  bool get isPaused      => _plugin._tasks[_id]?.isPaused ?? false;
  bool get isDone        => _plugin._tasks[_id]?.done ?? true;
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
class Countdown implements CountmanPlugin {
  Countdown({String? name, this.interval = 1000})
      : name = name ?? 'countdown';

  @override
  final String name;

  /// Processing interval in milliseconds. 0 = every frame.
  final int interval;

  late CountmanContext _ctx;
  final _tasks = <int, CountdownTask>{};
  int _uid = 0;
  double _accumMs = 0;

  // ── CountmanPlugin ────────────────────────────────────────────────

  @override
  void onAttach(CountmanContext ctx) => _ctx = ctx;

  @override
  bool tick(Duration elapsed, Duration dt) {
    if (_tasks.isEmpty) return false;

    _accumMs += dt.inMicroseconds / 1000.0;
    final shouldProcess = interval <= 0 || _accumMs >= interval;
    if (shouldProcess) {
      if (interval > 0) {
        _accumMs -= interval; // carry remainder for next cycle
      } else {
        _accumMs = 0; // prevent unbounded growth at interval=0
      }
    }

    var busy = false;
    final done = <int>[];

    for (final task in _tasks.values) {
      if (task.done || task.isPaused) continue;

      if (!task.started) {
        // First appearance: render initial remaining immediately, skip interval.
        task.started = true;
        task.onUpdate?.call(task.remaining);
        busy = true;
        continue;
      }

      if (!shouldProcess) {
        busy = true; // active but interval not reached yet
        continue;
      }

      final remaining = task.remaining;
      if (remaining <= Duration.zero) {
        task.done = true;
        task.onUpdate?.call(Duration.zero);
        done.add(task.id);
        task.onDone?.call();
        // task is done — do NOT set busy for it
      } else {
        task.onUpdate?.call(remaining);
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
    _accumMs = 0;
    if (identical(this, _default)) _registered = false;
  }

  // ── public API ────────────────────────────────────────────────────

  CountdownHandle add(CountdownOptions opts) {
    final id = _uid++;
    _tasks[id] = CountdownTask(
      id: id,
      total: opts.duration,
      onUpdate: opts.onUpdate,
      onDone: opts.onDone,
    );
    _ctx.requestFrame();
    return CountdownHandle._(id, this);
  }
}

// ── CountdownController ───────────────────────────────────────────

/// Imperative controller for countdown display widgets.
///
/// Create once, pass to a widget via its `controller` parameter, then call
/// [pause], [resume], [reset], or [cancel] from any parent or business logic.
/// The controller attaches to the widget's internal [CountdownHandle] after
/// the first build.
class CountdownController {
  CountdownHandle? _handle;

  // Called by countdown display widgets in initState / didUpdateWidget / dispose.
  // Not part of the end-user API.
  // ignore: use_setters_to_change_properties
  void attach(CountdownHandle h) => _handle = h;
  void detach() => _handle = null;

  void pause()                     => _handle?.pause();
  void resume()                    => _handle?.resume();
  void reset({Duration? duration}) => _handle?.reset(duration: duration);
  void cancel()                    => _handle?.cancel();

  Duration get remaining => _handle?.remaining ?? Duration.zero;
  bool get isPaused      => _handle?.isPaused ?? false;
  bool get isDone        => _handle?.isDone ?? true;
}

// ── default instance + top-level function ─────────────────────────

final _default = Countdown(); // interval = 1000ms
bool _registered = false;

/// The default [Countdown] instance (interval = 1 s) used by [CountdownWidget]
/// when no [plugin] is provided. Auto-registered with [Countman] on first access.
Countdown get defaultCountdown {
  if (!_registered) {
    _registered = true;
    Countman.use(_default);
  }
  return _default;
}

/// Add a countdown using the default shared [Countdown] instance.
CountdownHandle countdown(CountdownOptions opts) =>
    defaultCountdown.add(opts);
