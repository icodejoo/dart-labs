import 'package:meta/meta.dart';

import '../model/quality.dart';

/// 内核加载理由；仅用于引擎内部，不从包入口导出。
enum LoadReason {
  /// 接受新源，含公开 reload。
  open,

  /// 在当前地址重试。
  retry,

  /// 切到备选地址。
  failover,

  /// 同一源切换清晰度。
  quality,

  /// 按固定落后量打开时移地址。
  timeshift,

  /// 回直播边缘或唤醒重开。
  liveEdge,
}

/// 一次实际内核加载的不可变规格；不拥有会话或尝试生命周期。
///
/// 示例：`LoadSpec(sourceIndex: 0, uri: source.uri, reason: LoadReason.open)`。
@immutable
class LoadSpec {
  /// 地址在源的主备列表中的下标。
  final int sourceIndex;

  /// 本次传给内核的有效地址。
  final String uri;

  /// 当前选定档位；新源及故障切换时为空。
  final MovaQuality? quality;

  /// 时移地址的固定落后量；非时移加载为空。
  final Duration? timeshiftBehind;

  /// 本次加载待落地后应用的续播目标。
  final Duration? resumeAt;

  /// 本次加载的显式理由。
  final LoadReason reason;

  /// 用 [sourceIndex]、[uri] 和 [reason] 创建加载快照。
  /// [quality] 为档位，[timeshiftBehind] 为时移量，[resumeAt] 为续播点。
  /// 返回不可变规格；示例：`LoadSpec(sourceIndex: 0, uri: 'a.mp4', reason: LoadReason.open)`。
  const LoadSpec({
    required this.sourceIndex,
    required this.uri,
    required this.reason,
    this.quality,
    this.timeshiftBehind,
    this.resumeAt,
  });
}
