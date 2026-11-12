import 'dart:collection';

/// Read-only decomposition of a [Duration] into its calendar components,
/// shared per task: the owning countdown/elapsed task computes it **once**
/// per tick into a reused fixed-length backing list (zero per-frame
/// allocation), and every consumer of that task — formatters, progress
/// widgets, the flip-card's per-unit cells — reads the same instance instead
/// of each recomputing the `%`/`~/` math.
///
/// Isolation: one [TimeParts] per task. Different deadlines are different
/// tasks with different [TimeParts], so they never interfere.
///
/// Lifetime: the instance is mutated in place each tick. It is valid only
/// for the synchronous duration of the callback / build that receives it —
/// **do not retain it across frames** (store the component ints you need).
class TimeParts {
  TimeParts._(this._components, this._valueMicros, this._total);

  /// Fixed-length `[days, hours(0-23), minutes(0-59), seconds(0-59), millis(0-999)]`.
  final List<int> _components;
  /// 当前整数微秒；时钟热路径不构造 Duration。
  int _valueMicros;
  Duration? _total;

  /// Creates a standalone instance (owns its backing list). Used for a
  /// widget's initial value before the first tick; the engine reuses one
  /// per task via [TimeParts.zero] + [set].
  factory TimeParts.of(Duration value, [Duration? total]) =>
      (TimeParts._(List<int>.filled(5, 0), 0, null))..set(value, total);

  /// Creates a zeroed instance with its own reused backing list.
  factory TimeParts.zero() =>
      TimeParts._(List<int>.filled(5, 0), 0, null);

  // ── modulo components (direct reads, no allocation) ────────────────
  int get days => _components[0];
  int get hours => _components[1];
  int get minutes => _components[2];
  int get seconds => _components[3];
  int get millis => _components[4];

  // ── convenience totals (may exceed the modulo range) ───────────────
  int get totalHours => _valueMicros ~/ Duration.microsecondsPerHour;
  int get totalMinutes => _valueMicros ~/ Duration.microsecondsPerMinute;
  int get totalSeconds => _valueMicros ~/ Duration.microsecondsPerSecond;

  // ── Duration-style totals (mirror [Duration] for familiarity) ──────
  int get inDays => _valueMicros ~/ Duration.microsecondsPerDay;
  int get inHours => _valueMicros ~/ Duration.microsecondsPerHour;
  int get inMinutes => _valueMicros ~/ Duration.microsecondsPerMinute;
  int get inSeconds => _valueMicros ~/ Duration.microsecondsPerSecond;
  int get inMilliseconds => _valueMicros ~/ Duration.microsecondsPerMillisecond;
  int get inMicroseconds => _valueMicros;

  /// The raw value (remaining for countdown, elapsed for a stopwatch).
  Duration get value => Duration(microseconds: _valueMicros);

  /// The initial total (countdown only — the progress denominator). `null`
  /// for elapsed timers, which have no fixed total.
  Duration? get total => _total;

  /// Fraction complete in `[0, 1]` (countdown: value/total). 0 when [total]
  /// is null or non-positive.
  double get progress {
    final t = _total;
    if (t == null || t.inMicroseconds <= 0) return 0;
    return (_valueMicros / t.inMicroseconds).clamp(0.0, 1.0);
  }

  /// Live read-only view of the component list `[d, h, m, s, ms]`. Reflects
  /// in-place updates (it wraps the backing list by reference). Created once.
  late final List<int> parts = UnmodifiableListView(_components);

  /// Engine-internal: recompute the components in place from [value].
  /// Negative values clamp to zero.
  void set(Duration value, Duration? total) {
    setMicros(value.inMicroseconds, total);
  }

  /// 用整数微秒原地更新分量，负值钳零；供时钟热路径使用。
  void setMicros(int micros, Duration? total) {
    _valueMicros = micros < 0 ? 0 : micros;
    _total = total;
    final totalMs = inMilliseconds;
    _components[0] = totalMs ~/ Duration.millisecondsPerDay;
    _components[1] = (totalMs ~/ Duration.millisecondsPerHour) % Duration.hoursPerDay;
    _components[2] = (totalMs ~/ Duration.millisecondsPerMinute) % Duration.minutesPerHour;
    _components[3] = (totalMs ~/ Duration.millisecondsPerSecond) % Duration.secondsPerMinute;
    _components[4] = totalMs % Duration.millisecondsPerSecond;
  }
}
