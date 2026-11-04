import 'package:flutter/foundation.dart';

/// 条目为什么结束，或为什么没有出场。
enum OverlayEndReason {
  /// 管理器主动关闭。
  closed,

  /// 后端自行关闭，例如用户点击或返回。
  dismissedByBackend,

  /// 展示时长到期。
  expired,

  /// 被 replace 条目抢占。
  replaced,

  /// 被同 id 的新提交取代。
  superseded,

  /// 被 remove、clear 或 clearWhere 移除。
  removed,

  /// 展示条件不再满足。
  unmet,

  /// 解析返回空值、抛出异常或超时。
  skipped,

  /// overlap 当前不满足条件或冷却要求。
  dropped,

  /// session 或 total 永久上限已耗尽。
  capped,

  /// 槽位排队已满，被挤出队尾。
  queueFull,

  /// 排队时间超过 expireAfter。
  queueExpired,

  /// 展示后端抛出异常。
  failed,

  /// 管理器已销毁。
  disposed,
}

/// 单次提交首次结束时的值与原因。
@immutable
class OverlayOutcome<T> {
  /// 保存可空的 [value] 与结束 [reason]。
  const OverlayOutcome(this.value, this.reason);

  /// 关闭结果；没有结果时为 null。
  final T? value;

  /// 第一次结束的原因，之后不再改变。
  final OverlayEndReason reason;
}

/// 条目生命周期中的事件种类。
enum OverlayEventType {
  /// 提交进入管理器。
  queued,

  /// 后端成功展示。
  shown,

  /// 首次结束。
  ended,
}

/// 异步广播的条目生命周期事件。
@immutable
class OverlayEvent {
  /// 保存事件类型、条目标识与槽位；[reason] 仅 ended 时有值。
  const OverlayEvent({
    required this.type,
    required this.id,
    required this.slot,
    this.reason,
  });

  /// 生命周期事件类型。
  final OverlayEventType type;

  /// 条目的标识，同 id 的不同提交各自发出事件。
  final String id;

  /// 条目所属槽位。
  final String slot;

  /// ended 事件的原因；其他事件为 null。
  final OverlayEndReason? reason;
}

/// 单个槽位的可选配置，未提供的字段使用全局默认行为。
@immutable
class OverlaySlotOptions {
  /// [gap] 覆盖全局间隔；[maxQueued] 限制未激活条目数，必须大于零。
  const OverlaySlotOptions({this.gap, this.maxQueued});

  /// 该槽位关闭一个条目后等待的间隔。
  final Duration? gap;

  /// 排队数量上限，不包含已激活的条目。
  final int? maxQueued;
}

/// 指定冷却配置在当前时刻的资格快照。
@immutable
class OverlayCooldownStatus {
  /// [canShow] 表示全部上限通过；永久受阻或等待读取时 [wait] 为 null。
  const OverlayCooldownStatus(
      {required this.canShow,
      required this.permanentlyBlocked,
      required this.wait});

  /// 当前所有上限是否通过。
  final bool canShow;

  /// session 或 total 已耗尽，时间流逝不会解除。
  final bool permanentlyBlocked;

  /// 时间上限的最长剩余等待；可展示时为 Duration.zero。
  final Duration? wait;
}
