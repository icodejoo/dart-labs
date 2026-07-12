import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/plugin_base.dart';
import '../core/time_parts.dart';

export '../core/clock.dart' show countdownClock;
export '../core/time_parts.dart' show TimeParts;

/// Formatter function type for [CountdownWidget] / [TextElapsed]. Receives the
/// shared per-task [TimeParts] (pre-decomposed d/h/m/s/ms) rather than a raw
/// [Duration], so a formatter reads components directly with no `%` math.
typedef DurationFormatter = String Function(TimeParts parts);

/// Built-in duration formatters.
abstract final class CountdownFormat {
  /// HH:mm:ss — always shows hours (e.g. 01:23:45).
  static String hms(TimeParts t) {
    final h = t.totalHours.toString().padLeft(2, '0');
    final m = t.minutes.toString().padLeft(2, '0');
    final s = t.seconds.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// mm:ss — minutes may exceed 59 (e.g. 90:05 for 90 minutes).
  static String ms(TimeParts t) {
    final m = t.totalMinutes.toString().padLeft(2, '0');
    final s = t.seconds.toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// mm:ss.f — tenths of a second (e.g. 01:05.3).
  static String msTenths(TimeParts t) {
    final m = t.totalMinutes.toString().padLeft(2, '0');
    final s = t.seconds.toString().padLeft(2, '0');
    final f = t.millis ~/ 100;
    return '$m:$s.$f';
  }

  /// mm:ss.SSS — full millisecond precision (e.g. 01:05.327).
  /// Pair with [defaultCountdownMs] / [countdownMs] for sub-second updates.
  static String msMillis(TimeParts t) {
    final m = t.totalMinutes.toString().padLeft(2, '0');
    final s = t.seconds.toString().padLeft(2, '0');
    final ms = t.millis.toString().padLeft(3, '0');
    return '$m:$s.$ms';
  }

  /// Dd HH:mm:ss — shows whole days when ≥1 day remains (e.g. `2d 03:04:05`),
  /// otherwise falls back to [hms]. Ideal for multi-day event/sale countdowns
  /// where [hms] would render an unwieldy `72:00:00`.
  ///
  /// Dd HH:mm:ss——剩余 ≥1 天时显示整数天（如 `2d 03:04:05`），否则回退到 [hms]。
  /// 适合多天活动/大促倒计时；此时 [hms] 会显示笨重的 `72:00:00`。
  static String dhms(TimeParts t) {
    if (t.days <= 0) return hms(t);
    final h = t.hours.toString().padLeft(2, '0');
    final m = t.minutes.toString().padLeft(2, '0');
    final s = t.seconds.toString().padLeft(2, '0');
    return '${t.days}d $h:$m:$s';
  }

  /// Dd HH:mm — days + hours + minutes, dropping seconds (e.g. `2d 03:04`).
  /// Falls back to [hms] when under a day.
  ///
  /// Dd HH:mm——天 + 时 + 分，省去秒（如 `2d 03:04`）。不足一天时回退到 [hms]。
  static String dhm(TimeParts t) {
    if (t.days <= 0) return hms(t);
    final h = t.hours.toString().padLeft(2, '0');
    final m = t.minutes.toString().padLeft(2, '0');
    return '${t.days}d $h:$m';
  }

  /// Picks the most compact format automatically:
  /// ≥1d → Dd HH:mm:ss, ≥1h → HH:mm:ss, <10s → mm:ss.f, else → mm:ss.
  static String auto(TimeParts t) {
    if (t.days >= 1) return dhms(t);
    if (t.totalHours >= 1) return hms(t);
    if (t.totalSeconds < 10) return msTenths(t);
    return ms(t);
  }
}

/// Converts [to] to an absolute [DateTime] deadline.
///
/// Supported input types:
/// - [DateTime] — used as-is.
/// - [Duration] — resolved relative to [countdownClock] at call time.
/// - [int] — treated as milliseconds since Unix epoch.
/// - [String] — parsed via [DateTime.parse] first, falling back to a more
///   lenient pattern for non-ISO strings (e.g. `2025/12/31` with slashes, or
///   a missing day/time). See [_parseDateString].
DateTime resolveDeadline(Object to) {
  if (to is DateTime) return to;
  if (to is Duration) return countdownClock().add(to);
  if (to is int) return DateTime.fromMillisecondsSinceEpoch(to);
  if (to is String) return _parseDateString(to);
  throw ArgumentError(
    '`to` must be DateTime, Duration, int (ms epoch), or ISO-8601 String '
    '— got ${to.runtimeType}',
  );
}

// year, month?, day?, hour?, minute?, second?, fraction?
// month/day/hour/minute/second are optional and default to the first
// valid value (month=1, day=1) or zero (hour/minute/second) when absent —
// same defaulting DateTime.parse itself applies to a date-only ISO string.
final RegExp _lenientDatePattern =
    RegExp(r'^(\d{4})[-/]?(\d{1,2})?[-/]?(\d{0,2})[Tt\s]*(\d{1,2})?:?(\d{1,2})?:?(\d{1,2})?[.:]?(\d+)?$');

/// [DateTime.parse] is tried first — it's Dart's native single-pass ISO-8601
/// scanner, faster than walking a [RegExp] for the common well-formed case.
/// [_lenientDatePattern] only runs as a fallback for strings [DateTime.parse]
/// rejects (e.g. `/`-separated dates, or a date with no time component at
/// all) — a genuinely malformed string fails both and throws.
///
/// The fallback mirrors dayjs's own reference parser (`Utils.u`/`REGEX_PARSE`
/// dispatch in `dayjs/src/index.js`) for one specific quirk: the fraction
/// capture is *not* zero-padded — only its first 3 characters are read as
/// the raw millisecond value, so `.5` becomes 5ms (not 500ms) the same way
/// `(d[7] || '0').substring(0, 3)` behaves in dayjs. Sloppy for sub-3-digit
/// fractions, but faithful to the reference behavior.
///
/// dayjs also skips its regex for strings ending in `Z`/`z`, but that guard
/// only matters given dayjs's order (regex first, native `Date` as the last
/// resort on the hot path — the guard cheaply skips a `Z`-suffixed string
/// before spending a full capture-group match on it). Here [DateTime.parse]
/// runs first, so this fallback only executes on the already-cold error
/// path, and [_lenientDatePattern] can never match a `Z`-suffixed string
/// anyway (nothing in the pattern consumes `Z`, and it's anchored with `$`)
/// — so there's nothing to guard against and no such check here.
DateTime _parseDateString(String s) {
  try {
    return DateTime.parse(s);
  } catch (_) {
    final m = _lenientDatePattern.firstMatch(s);
    if (m != null) {
      try {
        int intOf(int group, [int fallback = 0]) {
          final v = m.group(group);
          return (v == null || v.isEmpty) ? fallback : int.parse(v);
        }

        final fraction = m.group(7);
        final milliseconds = fraction == null
            ? 0
            : int.parse(fraction.length > 3 ? fraction.substring(0, 3) : fraction);

        return DateTime(
          intOf(1),
          intOf(2, 1),
          intOf(3, 1),
          intOf(4),
          intOf(5),
          intOf(6),
          milliseconds,
        );
      } catch (_) {
        // DateTime()'s constructor normalizes out-of-range components
        // rather than throwing (month 13 rolls into next January, etc.), so
        // this only guards against something genuinely unexpected — fall
        // through to the same error as a non-matching string.
      }
    }
    throw FormatException('Unable to parse date string "$s" as a countdown deadline '
        '(tried DateTime.parse and a lenient fallback pattern)');
  }
}

/// Returns the remaining [Duration] until the deadline described by [to],
/// clamped to [Duration.zero] if already past.
Duration remainingUntil(Object to) {
  final d = resolveDeadline(to).difference(countdownClock());
  return d.isNegative ? Duration.zero : d;
}

/// Options for a countdown task added via [Countdown.add] or [countdown].
class CountdownOptions {
  const CountdownOptions({
    required this.duration,
    this.onUpdate,
    this.onComplete,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Total countdown duration (counts down to [Duration.zero]).
  final Duration duration;

  /// Called on each interval tick with the shared per-task [TimeParts]
  /// (pre-decomposed remaining). Update rate is controlled by [Countdown.interval].
  final void Function(TimeParts parts)? onUpdate;

  /// Called once when [remaining] reaches [Duration.zero].
  final void Function()? onComplete;

  /// When [remaining] first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check entirely.
  final Duration? threshold;

  /// Called once when [remaining] crosses [threshold]. Fires again on a
  /// later crossing if [CountdownHandle.reset] is called in between (e.g.
  /// to drive a "final minute" color/pulse change).
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
}

/// Internal task state.
class CountdownTask extends ClockTask {
  CountdownTask({
    required int id,
    required this.total,
    void Function(TimeParts)? onUpdate,
    this.onComplete,
    Duration? threshold,
    void Function()? onThreshold,
    super.onPause,
    super.onResume,
    super.onReady,
    super.onStart,
    super.onCancel,
  })  : endTime = countdownClock().add(total),
        super(id, onUpdate: onUpdate, threshold: threshold, onThreshold: onThreshold);

  /// Original duration; restored on [CountdownHandle.reset].
  Duration total;

  /// Wall-clock deadline. Remaining = endTime − countdownClock().
  DateTime endTime;

  /// Snapshot of remaining when paused; null means running.
  Duration? pausedRemaining;

  void Function()? onComplete;

  @override
  bool get isPaused => pausedRemaining != null;

  Duration get remaining {
    if (isPaused) return pausedRemaining!;
    final r = endTime.difference(countdownClock());
    return r.isNegative ? Duration.zero : r;
  }
}
