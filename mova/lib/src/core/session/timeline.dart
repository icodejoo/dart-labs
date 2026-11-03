import '../model/ad.dart';

/// 返回 [items] 中首个满足 [predicate] 的元素；没有为 null。
/// 示例：`movaFirstWhere([1, 2], (n) => n > 1)` 返回 2。
T? movaFirstWhere<T>(Iterable<T> items, bool Function(T) predicate) {
  for (final item in items) {
    if (predicate(item)) return item;
  }
  return null;
}

/// 返回 [breaks] 中在 [position] 到期且不在 [played] 的首条中插；没有为 null。
/// 示例：`movaDueMidRoll(breaks, Duration(seconds: 30), {})`。
MovaAdBreak? movaDueMidRoll(
  List<MovaAdBreak> breaks,
  Duration position,
  Set<MovaAdBreak> played,
) {
  return movaFirstWhere(
    breaks,
    (b) =>
        b.kind == MovaAdBreakKind.mid &&
        !played.contains(b) &&
        b.offset <= position,
  );
}

/// 返回 [breaks] 中不晚于 [resumeAt] 且不在 [played] 的下一条中插；没有为 null。
/// 示例：`movaNextPodMid(breaks, {}, Duration(seconds: 31))`。
MovaAdBreak? movaNextPodMid(
  List<MovaAdBreak> breaks,
  Set<MovaAdBreak> played,
  Duration resumeAt,
) {
  return movaFirstWhere(
    breaks,
    (b) =>
        b.kind == MovaAdBreakKind.mid &&
        !played.contains(b) &&
        b.offset <= resumeAt,
  );
}

/// 返回 [breaks] 中不在 [played] 的首个 [kind] 广告位；没有为 null。
/// 示例：`movaFirstOfKind(breaks, {}, MovaAdBreakKind.pre)`。
MovaAdBreak? movaFirstOfKind(
  List<MovaAdBreak> breaks,
  Set<MovaAdBreak> played,
  MovaAdBreakKind kind,
) {
  return movaFirstWhere(breaks, (b) => b.kind == kind && !played.contains(b));
}

/// 返回 [breaks] 中 [b] 的 pod 成员；中插仅取不晚于 [resumeAt] 的同类广告。
/// 示例：`movaPodMembers(breaks, ad, Duration(seconds: 31)).toList()`。
Iterable<MovaAdBreak> movaPodMembers(
  List<MovaAdBreak> breaks,
  MovaAdBreak b,
  Duration resumeAt,
) sync* {
  for (final other in breaks) {
    if (other.kind != b.kind) continue;
    if (b.kind == MovaAdBreakKind.mid && other.offset > resumeAt) {
      continue;
    }
    yield other;
  }
}
