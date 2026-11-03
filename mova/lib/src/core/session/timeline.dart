import 'package:meta/meta.dart';
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

/// 节点类型；示例：`MovaNodeKind.mid` 表示中插。
enum MovaNodeKind {
  /// 前贴片。
  pre,

  /// 正片。
  content,

  /// 中插。
  mid,

  /// 后贴片。
  post,
}

/// 时间线节点身份；负序号表示运行时插播。示例：`MovaNodeId(0, MovaNodeKind.pre, 1)`。
@immutable
class MovaNodeId {
  /// 以条目 [item]、类型 [kind]、同类型排期序号 [ordinal] 创建身份并返回新值。
  /// 示例：`const MovaNodeId(0, MovaNodeKind.content, 0)`。
  const MovaNodeId(this.item, this.kind, this.ordinal);

  /// 返回条目下标。示例：`id.item`。
  final int item;

  /// 返回节点类型。示例：`id.kind`。
  final MovaNodeKind kind;

  /// 返回同类型原始顺序，0 起；负数为本集插播计数。示例：`id.ordinal`。
  final int ordinal;

  /// 比较 [other] 的三个身份分量，返回是否相等。示例：`id == other`。
  @override
  bool operator ==(Object other) =>
      other is MovaNodeId &&
      item == other.item &&
      kind == other.kind &&
      ordinal == other.ordinal;

  /// 返回身份哈希。示例：`{id}.contains(id)` 使用此值。
  @override
  int get hashCode => Object.hash(item, kind, ordinal);
}

/// 包内排期节点，正片没有广告对象。
class MovaTimelineNode {
  /// 绑定身份、广告对象与插入点。
  const MovaTimelineNode(this.id, this.adBreak, this.offset);

  /// 稳定节点身份。
  final MovaNodeId id;

  /// 原始广告对象，正片为 null。
  final MovaAdBreak? adBreak;

  /// 排期插入点。
  final Duration offset;
}

/// 将 [breaks] 按原顺序为 [item] 编号，并添加一个正片节点。
List<MovaTimelineNode> movaBuildNodes(int item, List<MovaAdBreak> breaks) {
  final counts = <MovaNodeKind, int>{};
  final nodes = <MovaTimelineNode>[];
  for (final b in breaks) {
    final kind = switch (b.kind) {
      MovaAdBreakKind.pre => MovaNodeKind.pre,
      MovaAdBreakKind.mid => MovaNodeKind.mid,
      MovaAdBreakKind.post => MovaNodeKind.post,
    };
    final ordinal = counts.update(kind, (n) => n + 1, ifAbsent: () => 0);
    nodes.add(MovaTimelineNode(MovaNodeId(item, kind, ordinal), b, b.offset));
  }
  nodes.add(
    MovaTimelineNode(
      MovaNodeId(item, MovaNodeKind.content, 0),
      null,
      Duration.zero,
    ),
  );
  return nodes;
}

/// 返回 [nodes] 中在 [position] 到期且不在 [played] 的首条中插。
MovaTimelineNode? movaDueMid(
  List<MovaTimelineNode> nodes,
  Duration position,
  Set<MovaNodeId> played,
) => movaFirstWhere(
  nodes,
  (n) =>
      n.id.kind == MovaNodeKind.mid &&
      !played.contains(n.id) &&
      n.offset <= position,
);
