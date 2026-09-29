import '../report/error_policy.dart';
import '../report/session_id.dart';
import '../report/stall.dart';

/// Telemetry configuration: what mova computes on-device before handing
/// events to `MovaReporter`. Everything here is pure in-memory aggregation —
/// mova still never sends, batches, or schedules anything.
///
/// 埋点配置：mova 在把事件交给 `MovaReporter` 之前，在端上算哪些东西。
/// 这里的一切都是纯内存聚合——mova 依然从不发送、不攒批、不调度。
class MovaReportConfig {
  /// Master switch for the QoE layer (TTFF / rebuffer / session / fatal).
  /// Defaults to `false` per this project's opt-in convention for new
  /// capabilities. Not passing this parameter keeps the report event stream
  /// byte-for-byte identical to before this feature existed; explicitly
  /// passing `true` enables TTFF/rebuffer/session/fatal-error reporting.
  ///
  /// QoE 层（首帧/卡顿/会话/致命错误）的总开关。默认 `false`，遵循项目"新
  /// 功能默认关闭"的一贯约定；不传该参数时事件流与本功能落地前逐字节相同。
  /// 显式设为 `true` 才会启用 TTFF/卡顿/会话/致命错误四大指标。
  final bool qoe;

  /// Stalls shorter than this are swallowed as noise; mpv coalesces
  /// property-change notifications, so sub-frame flaps are not real stalls.
  ///
  /// 短于此值的卡顿按噪声吞掉；mpv 会合并属性变更通知，亚帧级翻转不是真卡顿。
  final Duration minStall;

  /// Emits a periodic `heartbeat` report when non-null. `null` (off) by
  /// default — long sessions that never end would otherwise be the only way
  /// to lose aggregates, and that is the host's call, not mova's.
  ///
  /// 非空时按周期发 `heartbeat` 上报。默认 `null`（关闭）——只有"长会话迟迟
  /// 不结束"才会丢掉汇总量，要不要为此付出一个常驻 Timer 是宿主的决定。
  final Duration? heartbeat;

  /// Injectable stall aggregator; `null` selects [MovaEdgeStall] seeded from
  /// [minStall].
  ///
  /// 可注入的卡顿聚合器；为 `null` 时选用由 [minStall] 构造的 [MovaEdgeStall]。
  final MovaStallPolicy? stallPolicy;

  /// Injectable fatal/code classifier; `null` selects [MovaPrefixError].
  ///
  /// 可注入的致命性/错误码判据；为 `null` 时选用 [MovaPrefixError]。
  final MovaErrorPolicy? errorPolicy;

  /// Injectable session-id factory; `null` selects [newMovaSessionId].
  ///
  /// 可注入的会话 ID 工厂；为 `null` 时选用 [newMovaSessionId]。
  final MovaSessionIdFactory? sessionId;

  /// Creates a telemetry config; every field defaults to off/default.
  ///
  /// 创建一份埋点配置；每个字段默认关闭/使用默认值。
  const MovaReportConfig({
    this.qoe = false,
    this.minStall = const Duration(milliseconds: 200),
    this.heartbeat,
    this.stallPolicy,
    this.errorPolicy,
    this.sessionId,
  });

  /// A fresh stall policy instance; policies carry per-session state, so a
  /// new one must be built for every new session.
  ///
  /// 新建一个卡顿策略实例；策略带有每会话的累积状态，每次新会话都必须新建。
  ///
  /// Example / 示例:
  /// ```dart
  /// final policy = config.newStallPolicy();
  /// ```
  MovaStallPolicy newStallPolicy() => stallPolicy ?? MovaEdgeStall(minStall: minStall);

  /// The error policy actually in effect.
  ///
  /// 实际生效的错误判据。
  MovaErrorPolicy get effectiveErrorPolicy => errorPolicy ?? const MovaPrefixError();

  /// The session-id factory actually in effect.
  ///
  /// 实际生效的会话 ID 工厂。
  MovaSessionIdFactory get effectiveSessionIdFactory => sessionId ?? newMovaSessionId;

  /// Returns a copy with the given fields replaced; omitted fields keep
  /// their current value.
  ///
  /// 返回一份替换了指定字段的拷贝；未指定的字段保持当前值。
  MovaReportConfig copyWith({
    bool? qoe,
    Duration? minStall,
    Duration? heartbeat,
    bool clearHeartbeat = false,
    MovaStallPolicy? stallPolicy,
    MovaErrorPolicy? errorPolicy,
    MovaSessionIdFactory? sessionId,
  }) {
    return MovaReportConfig(
      qoe: qoe ?? this.qoe,
      minStall: minStall ?? this.minStall,
      heartbeat: clearHeartbeat ? null : (heartbeat ?? this.heartbeat),
      stallPolicy: stallPolicy ?? this.stallPolicy,
      errorPolicy: errorPolicy ?? this.errorPolicy,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaReportConfig &&
          runtimeType == other.runtimeType &&
          qoe == other.qoe &&
          minStall == other.minStall &&
          heartbeat == other.heartbeat &&
          stallPolicy == other.stallPolicy &&
          errorPolicy == other.errorPolicy &&
          sessionId == other.sessionId;

  @override
  int get hashCode =>
      Object.hash(qoe, minStall, heartbeat, stallPolicy, errorPolicy, sessionId);
}
