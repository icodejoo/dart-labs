import 'package:flutter/widgets.dart';
import 'package:layerman/layerman.dart';
import 'demo_kit/demo_kit.dart';

/// 为运行时事件提供中文文案，英文保留对应 API 枚举名。
String demoEventLabel(BuildContext context, OverlayEvent event) =>
    '${event.id}: ${event.reason == null ? tr(context, event.type.name, switch (event.type) {
            OverlayEventType.queued => '已入队',
            OverlayEventType.shown => '已展示',
            OverlayEventType.ended => '已结束',
          }) : demoEndReason(context, event.reason!)}';

/// 翻译全部公开结束原因，代码示例中的 API 名称保持原样。
String demoEndReason(BuildContext context, OverlayEndReason reason) =>
    tr(context, reason.name, switch (reason) {
      OverlayEndReason.closed => '主动关闭',
      OverlayEndReason.dismissedByBackend => '后端关闭',
      OverlayEndReason.expired => '展示到期',
      OverlayEndReason.replaced => '已被抢占',
      OverlayEndReason.superseded => '同名取代',
      OverlayEndReason.removed => '已移除',
      OverlayEndReason.unmet => '条件失效',
      OverlayEndReason.skipped => '已跳过',
      OverlayEndReason.dropped => '未获准展示',
      OverlayEndReason.capped => '已达次数上限',
      OverlayEndReason.suppressed => '已抑制',
      OverlayEndReason.gated => '准入拒绝',
      OverlayEndReason.queueFull => '队列已满',
      OverlayEndReason.queueExpired => '排队过期',
      OverlayEndReason.failed => '展示失败',
      OverlayEndReason.disposed => '已销毁',
    });
