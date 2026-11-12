import 'timeline.dart';
import 'package:meta/meta.dart';

/// 会话阶段；示例：`session.cursor.phase == MovaSessionPhase.content`。
enum MovaSessionPhase {
  /// 未加载或全部结束。
  idle,

  /// 中插待播，正片继续。
  pending,

  /// 广告在屏。
  ad,

  /// 正在回正片。
  toContent,

  /// 正片在屏。
  content,
}

/// 会话只读游标；示例：`session.cursor.item` 返回已接受的集下标。
@immutable
class MovaCursor {
  /// 以加载纪元 [epoch]、条目 [item]、阶段 [phase] 和续播点 [contentResumeAt]
  /// 和可选身份 [node] 创建快照，返回新游标。示例：`MovaCursor(epoch: 1, item: 0,
  /// phase: MovaSessionPhase.content, contentResumeAt: Duration.zero)`。
  const MovaCursor({
    this.node,
    required this.epoch,
    required this.item,
    required this.phase,
    required this.contentResumeAt,
  });

  /// 返回待播或在屏节点，无节点则 null。示例：`cursor.node?.kind`。
  final MovaNodeId? node;

  /// 返回加载纪元；load/jumpTo/dispose 推进。示例：`cursor.epoch`。
  final int epoch;

  /// 返回已接受条目下标，无列表为 0。示例：`cursor.item`。
  final int item;

  /// 返回当前阶段。示例：`cursor.phase`。
  final MovaSessionPhase phase;

  /// 返回正片续播点。示例：`cursor.contentResumeAt.inSeconds`。
  final Duration contentResumeAt;
}
