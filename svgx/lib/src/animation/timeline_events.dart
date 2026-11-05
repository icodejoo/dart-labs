import 'smil_animation.dart';
import 'svg_document_parser.dart';

/// An active interval's beginning, ending, or repetition.
///
/// 活动区间的开始、结束或重复。
enum SvgxTimelineEventKind {
  /// The active interval begins.
  ///
  /// 活动区间开始。
  begin,

  /// A finite active interval ends, independently of fill mode.
  ///
  /// 有限活动区间结束，不受填充模式影响。
  end,

  /// Another iteration begins inside the active interval.
  ///
  /// 活动区间内开始下一次迭代。
  repeat,
}

/// An immutable event on an identified animation's document timeline.
///
/// 有 id 动画在文档时间线上的不可变事件。
final class SvgxTimelineEvent {
  /// Creates an event; [iteration] is zero for begin/end and positive for repeat.
  ///
  /// 创建事件；begin/end 的 [iteration] 为零，repeat 为正数。
  const SvgxTimelineEvent({
    required this.elementId,
    required this.kind,
    required this.time,
    required this.iteration,
  });

  /// The animation element's own nonempty id.
  ///
  /// 动画元素自身的非空 id。
  final String elementId;

  /// The event kind.
  ///
  /// 事件类型。
  final SvgxTimelineEventKind kind;

  /// Absolute event time on the document timeline.
  ///
  /// 事件在文档时间线上的绝对时刻。
  final Duration time;

  /// SMIL repeatEvent detail: the zero-based iteration now beginning; the
  /// first iteration emits no repeat, so observed repeat values start at 1.
  /// Begin/end use zero; each new active interval resets the repeat sequence.
  ///
  /// 对齐 SMIL repeatEvent 的 detail：即将开始的迭代的零基序号；首轮不发
  /// repeat，因此可观察的 repeat 从 1 开始。begin/end 为零，新活动区间重新计数。
  final int iteration;
}

/// Returns identified animation events in `(from, to]`, ordered by time and
/// then document order. Returns an empty list when [from] >= [to]. For reverse
/// playback, callers swap endpoints and reverse the returned list.
///
/// 返回 `(from, to]` 内有 id 动画的事件，按时刻及文档顺序稳定排列；
/// [from] >= [to] 时返回空列表。倒放由调用方交换端点并逆序返回结果。
List<SvgxTimelineEvent> timelineEventsBetween(
  SvgDocument document,
  Duration from,
  Duration to,
) {
  if (from >= to) return const [];
  final fromMicros = from.inMicroseconds;
  final toMicros = to.inMicroseconds;
  // Expansion is a monotonic cache only: repeated and historical queries
  // produce the same events without replaying past intervals.
  // 展开只更新单调缓存，重复及历史查询无需重放过去的区间。
  for (final timeline in document.timelines) {
    timeline.extendIntervalsThrough(to);
  }
  final events = <(SvgxTimelineEvent, int)>[];
  for (final timeline in document.timelines) {
    final id = timeline.elementId;
    if (id == null || id.isEmpty || timeline.begin == kSmilNeverBegins) {
      continue;
    }
    final intervals = timeline.intervals;
    if (intervals == null) {
      _appendIntervalEvents(
        events,
        timeline,
        id,
        timeline.begin.inMicroseconds,
        timeline.repeatCount.indefinite
            ? null
            : timeline.begin.inMicroseconds +
                  smilActiveDurationMicroseconds(
                    timeline.duration,
                    timeline.repeatCount,
                  ),
        fromMicros,
        toMicros,
      );
      continue;
    }
    // Skip historical intervals by their ordered ends.
    // 按有序结束时刻二分，跳过历史区间。
    var low = 0;
    var high = intervals.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (intervals[mid].end <= from) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (var i = low; i < intervals.length; i++) {
      final interval = intervals[i];
      if (interval.begin > to) break;
      _appendIntervalEvents(
        events,
        timeline,
        id,
        interval.begin.inMicroseconds,
        interval.end == kSmilNeverBegins ? null : interval.end.inMicroseconds,
        fromMicros,
        toMicros,
      );
    }
  }
  if (events.isEmpty) return const [];
  events.sort((a, b) {
    final order = a.$1.time.compareTo(b.$1.time);
    return order != 0 ? order : a.$2.compareTo(b.$2);
  });
  return [for (final event in events) event.$1];
}

/// Appends only events inside the query; repeat bounds use integer arithmetic.
///
/// 只追加查询区间内的事件；重复序号边界通过整数运算直接求出。
void _appendIntervalEvents(
  List<(SvgxTimelineEvent, int)> events,
  SmilTimeline timeline,
  String id,
  int begin,
  int? end,
  int from,
  int to,
) {
  if (begin > to || (end != null && end <= from)) return;
  if (begin > from) {
    _appendEvent(events, id, SvgxTimelineEventKind.begin, begin, 0);
  }
  final duration = timeline.duration.inMicroseconds;
  if (duration > 0) {
    final fromLocal = from - begin;
    final first = fromLocal < 0 ? 1 : fromLocal ~/ duration + 1;
    var upper = to;
    if (end != null && upper >= end) {
      upper = end - 1;
    }
    // A minimum active duration may hold the finite animation's final value;
    // that frozen tail does not start additional repeat iterations.
    // min 延长的有限动画尾段保持末值，不会开始新的重复迭代。
    if (!timeline.repeatCount.indefinite) {
      final naturalEnd =
          begin +
          smilActiveDurationMicroseconds(
            timeline.duration,
            timeline.repeatCount,
          );
      if (upper >= naturalEnd) upper = naturalEnd - 1;
    }
    final last = (upper - begin) ~/ duration;
    for (var k = first; k <= last; k++) {
      _appendEvent(
        events,
        id,
        SvgxTimelineEventKind.repeat,
        begin + k * duration,
        k,
      );
    }
  }
  if (end != null && end > from && end <= to) {
    _appendEvent(events, id, SvgxTimelineEventKind.end, end, 0);
  }
}

/// Allocates an event and its stable sequence only after finding a match.
///
/// 仅在找到匹配事件后分配事件及稳定序号。
void _appendEvent(
  List<(SvgxTimelineEvent, int)> events,
  String id,
  SvgxTimelineEventKind kind,
  int time,
  int iteration,
) {
  events.add((
    SvgxTimelineEvent(
      elementId: id,
      kind: kind,
      time: Duration(microseconds: time),
      iteration: iteration,
    ),
    events.length,
  ));
}
