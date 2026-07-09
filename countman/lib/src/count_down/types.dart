/// Formatter function type for [CountdownWidget].
typedef DurationFormatter = String Function(Duration remaining);

/// Built-in duration formatters.
abstract final class CountdownFormat {
  /// HH:mm:ss — always shows hours (e.g. 01:23:45).
  static String hms(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// mm:ss — minutes may exceed 59 (e.g. 90:05 for 90 minutes).
  static String ms(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// mm:ss.f — tenths of a second (e.g. 01:05.3).
  static String msTenths(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final f = (d.inMilliseconds % 1000) ~/ 100;
    return '$m:$s.$f';
  }

  /// Picks the most compact format automatically:
  /// ≥1h → HH:mm:ss, <10s → mm:ss.f, else → mm:ss.
  static String auto(Duration d) {
    if (d.inHours >= 1) return hms(d);
    if (d.inSeconds < 10) return msTenths(d);
    return ms(d);
  }
}

/// Converts [to] to an absolute [DateTime] deadline.
///
/// Supported input types:
/// - [DateTime] — used as-is.
/// - [Duration] — resolved relative to [countdownClock] at call time.
/// - [int] — treated as milliseconds since Unix epoch.
/// - [String] — parsed as an ISO-8601 date string.
DateTime resolveDeadline(dynamic to) {
  if (to is DateTime) return to;
  if (to is Duration) return countdownClock().add(to);
  if (to is int) return DateTime.fromMillisecondsSinceEpoch(to);
  if (to is String) return DateTime.parse(to);
  throw ArgumentError(
    '`to` must be DateTime, Duration, int (ms epoch), or ISO-8601 String '
    '— got ${to.runtimeType}',
  );
}

/// Returns the remaining [Duration] until the deadline described by [to],
/// clamped to [Duration.zero] if already past.
Duration remainingUntil(dynamic to) {
  final d = resolveDeadline(to).difference(countdownClock());
  return d.isNegative ? Duration.zero : d;
}

/// Injectable clock — defaults to [DateTime.now] in production.
///
/// Override in tests to advance time without real delays:
/// ```dart
/// var fakeNow = DateTime(2024);
/// countdownClock = () => fakeNow;
/// fakeNow = fakeNow.add(const Duration(seconds: 3));
/// ```
// ignore: prefer_function_declarations_over_variables
DateTime Function() countdownClock = DateTime.now;

/// Options for a countdown task added via [Countdown.add] or [countdown].
class CountdownOptions {
  const CountdownOptions({
    required this.duration,
    this.onUpdate,
    this.onDone,
  });

  /// Total countdown duration (counts down to [Duration.zero]).
  final Duration duration;

  /// Called on each interval tick with the current remaining time.
  /// Update rate is controlled by [Countdown.interval].
  final void Function(Duration remaining)? onUpdate;

  /// Called once when [remaining] reaches [Duration.zero].
  final void Function()? onDone;
}

/// Internal task state.
class CountdownTask {
  CountdownTask({
    required this.id,
    required this.total,
    this.onUpdate,
    this.onDone,
  }) : endTime = countdownClock().add(total);

  final int id;

  /// Original duration; restored on [CountdownHandle.reset].
  Duration total;

  /// Wall-clock deadline. Remaining = endTime − countdownClock().
  DateTime endTime;

  /// Snapshot of remaining when paused; null means running.
  Duration? pausedRemaining;

  void Function(Duration)? onUpdate;
  void Function()? onDone;

  bool started = false;
  bool done = false;

  bool get isPaused => pausedRemaining != null;

  Duration get remaining {
    if (isPaused) return pausedRemaining!;
    final r = endTime.difference(countdownClock());
    return r.isNegative ? Duration.zero : r;
  }
}
