import '../events/events.dart';
import 'report.dart';

/// Pure mapping from a [MovaEvent] to its [MovaReportEvent], or `null` when
/// [event] isn't in the reportable whitelist.
///
/// This is the single, centralized place that decides which [MovaEvent]
/// variants are worth reporting — call sites in `MovaEngine`/`MovaSwapEngine`
/// must never sprinkle ad-hoc `reporter.onReport(...)` calls of their own.
///
/// Deliberately excluded (and why): [MovaBufferChange]/[MovaTimeShiftChange]
/// (flap several times per second while stalled/timeshifting),
/// [MovaDurationChange]/[MovaSizeChange]/[MovaQualityListChange] (decoder
/// metadata, not a user-facing action), [MovaVolumeChange]/[MovaBrightChange]/
/// [MovaZoomChange]/[MovaRateChange]/[MovaLockChange]/[MovaOrientationChange]
/// (fire once per pixel of a drag gesture), [MovaReady] (fires on every
/// successful open right alongside [MovaSourceChange], redundant),
/// [MovaSwapChange] (internal seamless-swap implementation detail),
/// [MovaPreviewBlock]/[MovaSttBlock] (internal refusal diagnostics, not
/// analytics-worthy business events).
///
/// [event] 到其 [MovaReportEvent] 的纯映射；[event] 不在可上报白名单内时
/// 返回 `null`。
///
/// 这是唯一、集中判断哪些 [MovaEvent] 子类型值得上报的一处——`MovaEngine`/
/// `MovaSwapEngine` 的调用方绝不应该自行散落插入零星的 `reporter.onReport(...)`
/// 调用。
///
/// 刻意排除（及理由）：[MovaBufferChange]/[MovaTimeShiftChange]（卡顿/时移期间
/// 每秒可能翻转数次）、[MovaDurationChange]/[MovaSizeChange]/
/// [MovaQualityListChange]（解码器元数据，非用户可感知动作）、
/// [MovaVolumeChange]/[MovaBrightChange]/[MovaZoomChange]/[MovaRateChange]/
/// [MovaLockChange]/[MovaOrientationChange]（拖动手势每个像素都会触发一次）、
/// [MovaReady]（与 [MovaSourceChange] 几乎同时触发，信息冗余）、
/// [MovaSwapChange]（无缝切换的内部实现细节）、[MovaPreviewBlock]/
/// [MovaSttBlock]（内部拒绝诊断，非业务分析事件）。
MovaReportEvent? translateMovaEvent(MovaEvent event, {DateTime Function() now = DateTime.now}) {
  switch (event) {
    case MovaSourceChange():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.sourceChange,
        params: {'uri': event.source.uri},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaPlay():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.play,
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaPause():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.pause,
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaSeek():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.seek,
        params: {'targetMs': event.target.inMilliseconds},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaSeeked():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.seeked,
        params: {'positionMs': event.position.inMilliseconds},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    // Playback completion is business-critical (e.g. drives "did the user
    // finish this content" funnels) — hint immediate delivery.
    //
    // 播放完成是业务关键事件（例如驱动"用户是否看完"漏斗分析）——提示立即发送。
    case MovaDone():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.done,
        priority: MovaReportPriority.immediate,
        at: now(),
      );
    // Errors are handled entirely by MovaQoeCollector (Task 8): fatal/code
    // classification needs "has the first frame landed yet" session state
    // this pure function does not have, so MovaErrorEvent is deliberately
    // excluded here — never null-checked by a caller that forgot this.
    //
    // 错误完全由 MovaQoeCollector 处理（Task 8）：fatal/code 判定需要"首帧是否
    // 已落地"这一会话状态，这个纯函数并不持有，因此 MovaErrorEvent 在此被刻意
    // 排除——不存在遗忘这一点的调用方。
    case MovaErrorEvent():
      return null;
    case MovaQualityChange():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.qualityChange,
        params: {'quality': event.quality.label},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaAbrDownShift():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.abrDownShift,
        params: {'from': event.from.label, 'to': event.to.label},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaFullScreenChange():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.fullScreenChange,
        params: {'value': event.value},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaPipChange():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.pipChange,
        params: {'value': event.value},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaMiniChange():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.miniChange,
        params: {'mini': event.mini},
        priority: MovaReportPriority.batched,
        at: now(),
      );
    case MovaLiveEdgeReach():
      return MovaReportEvent(
        kind: MovaReportKind.event,
        name: MovaReportName.liveEdgeReach,
        priority: MovaReportPriority.batched,
        at: now(),
      );
    default:
      return null;
  }
}
