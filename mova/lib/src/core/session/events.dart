import 'timeline.dart';

/// 独立于引擎事件的会话事件；示例：`session.events.listen((e) => print(e.epoch));`。
sealed class MovaSessionEvent {
  /// 以加载纪元 [epoch] 创建事件。示例：`MovaItemChange(1, 0)`。
  const MovaSessionEvent(this.epoch);

  /// 返回事件所属加载纪元。示例：`event.epoch`。
  final int epoch;
}

/// 节点开始事件；示例：`event is MovaNodeStart`。
final class MovaNodeStart extends MovaSessionEvent {
  /// 以纪元 [epoch] 和身份 [node] 创建开始事件，返回新事件。
  /// 示例：`MovaNodeStart(1, MovaNodeId(0, MovaNodeKind.content, 0))`。
  const MovaNodeStart(super.epoch, this.node);

  /// 返回开始的节点身份。示例：`event.node.ordinal`。
  final MovaNodeId node;
}

/// 节点结束事件；示例：`event is MovaNodeEnd`。
final class MovaNodeEnd extends MovaSessionEvent {
  /// 以纪元 [epoch]、身份 [node] 和原因 [reason] 创建结束事件，返回新事件。
  /// 示例：`MovaNodeEnd(1, id, MovaNodeEndReason.completed)`。
  const MovaNodeEnd(super.epoch, this.node, this.reason);

  /// 返回结束的节点身份。示例：`event.node.kind`。
  final MovaNodeId node;

  /// 返回结束原因。示例：`event.reason == MovaNodeEndReason.skipped`。
  final MovaNodeEndReason reason;
}

/// 已接受条目变化；示例：`event is MovaItemChange`。
final class MovaItemChange extends MovaSessionEvent {
  /// 以纪元 [epoch]、新下标 [index] 创建条目事件，返回新事件。
  /// 示例：`MovaItemChange(2, 1)`。
  const MovaItemChange(super.epoch, this.index);

  /// 返回已接受的条目下标。示例：`event.index`。
  final int index;
}

/// 节点结束原因；示例：`MovaNodeEndReason.completed`。
enum MovaNodeEndReason {
  /// 自然结束或足额计时。
  completed,

  /// 用户跳过。
  skipped,

  /// 播放失败或请求被拒。
  failed,

  /// 被新加载取代。
  superseded,
}
