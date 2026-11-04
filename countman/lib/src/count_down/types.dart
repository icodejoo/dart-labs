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
/// - [Duration] — resolved relative to the wall clock of [clock]
///   (defaults to [CountmanClock.system]) at call time.
/// - [int] — treated as milliseconds since Unix epoch.
/// - [String] — parsed via [DateTime.parse] first, falling back to a more
///   lenient pattern for non-ISO strings (e.g. `2025/12/31` with slashes, or
///   a missing day/time). See [_parseDateString].
DateTime resolveDeadline(Object to, {CountmanClock? clock}) {
  if (to is DateTime) return to;
  if (to is Duration) {
    final wall = (clock ?? CountmanClock.system).wallMicros();
    return DateTime.fromMicrosecondsSinceEpoch(wall + to.inMicroseconds);
  }
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
/// clamped to [Duration.zero] if already past. A [Duration] is returned as-is
/// (relative lengths do not drift between two clock reads); other types are
/// resolved against the wall clock of [clock] (defaults to
/// [CountmanClock.system]).
Duration remainingUntil(Object to, {CountmanClock? clock}) {
  if (to is Duration) return to.isNegative ? Duration.zero : to;
  final source = clock ?? CountmanClock.system;
  final deadline = resolveDeadline(to, clock: source);
  final micros = deadline.microsecondsSinceEpoch - source.wallMicros();
  return micros <= 0 ? Duration.zero : Duration(microseconds: micros);
}

/// 把组件的 `to` 解析成 [CountdownOptions] 的锚点：[Duration] 走相对时长
/// （`duration`，单调钟锚定），其余类型解析为绝对截止（`deadline`，墙钟锚定）。
/// 返回的记录里 `duration` 与 `deadline` 恰有一个非空。
/// 例如 `countdownAnchorOf(Duration(minutes: 5))` 得到 `(duration: 5min, deadline: null)`。
({Duration? duration, DateTime? deadline}) countdownAnchorOf(
  Object to, {
  CountmanClock? clock,
}) => to is Duration
    ? (duration: to, deadline: null)
    : (duration: null, deadline: resolveDeadline(to, clock: clock));

/// Options for a countdown task added via [Countdown.add] or [countdown].
class CountdownOptions {
  /// 必须且只能给出 [duration]（相对时长）或 [deadline]（绝对截止）之一。
  /// 例如 `CountdownOptions(duration: Duration(minutes: 5))` 或
  /// `CountdownOptions(deadline: DateTime(2026, 12, 31))`。
  const CountdownOptions({
    this.duration,
    this.deadline,
    this.onUpdate,
    this.onComplete,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  }) : assert(
         (duration == null) != (deadline == null),
         'CountdownOptions: provide exactly one of duration or deadline.',
       );

  /// 相对时长（倒数到 [Duration.zero]），按单调钟锚定：用户改系统时间不影响它，
  /// 设备深睡期间的时长由时钟的前台恢复校准补上。与 [deadline] 二选一。
  final Duration? duration;

  /// 绝对截止时刻，按墙钟锚定：用户改系统时间会随之变化，适合“到点开售”这类
  /// 与真实时刻绑定的倒计时。与 [duration] 二选一。暂停、恢复后改为按单调钟计时。
  final DateTime? deadline;

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

/// 倒计时内部任务状态；锚点是整数微秒，热路径不构造对象。
class CountdownTask extends ClockTask {
  /// [total] 为进度分母，[endMicros] 为截止点微秒，[absolute] 为 true 时
  /// [endMicros] 在墙钟时间轴上，否则在单调钟时间轴上。
  CountdownTask({
    required int id,
    required this.total,
    required this.endMicros,
    required this.absolute,
    void Function(TimeParts)? onUpdate,
    this.onComplete,
    Duration? threshold,
    void Function()? onThreshold,
    super.onPause,
    super.onResume,
    super.onReady,
    super.onStart,
    super.onCancel,
  }) : super(
         id,
         onUpdate: onUpdate,
         threshold: threshold,
         onThreshold: onThreshold,
       );

  /// Original duration; restored on [CountdownHandle.reset].
  Duration total;

  /// 截止点的微秒；时间轴由 [absolute] 决定。
  int endMicros;

  /// true 表示按墙钟锚定（绝对截止）；暂停恢复或重置后一律变为 false（单调钟）。
  bool absolute;

  /// Snapshot of remaining when paused; null means running.
  Duration? pausedRemaining;

  void Function()? onComplete;

  @override
  bool get isPaused => pausedRemaining != null;
}
