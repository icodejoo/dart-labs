import '../swap/trigger.dart';
import '../swap/warm.dart';

/// Configuration for seamless engine swapping.
///
/// Off by default: a swap costs a second decode session for the overlap
/// window, and many low-end Android SoCs only support one or two. With
/// [enabled] false every consumer falls back to today's plain `open()`
/// rebuild, so this whole feature is a pure opt-in increment.
///
/// 无缝引擎切换的配置。
///
/// 默认关闭：一次切换会在重叠窗口内多占一路解码 session，而很多中低端
/// Android SoC 只支持 1–2 路。[enabled] 为 false 时所有调用方都回落到今天
/// 的 `open()` 重建路径，因此整个特性是纯粹的可选增量。
class MovaSwapConfig {
  /// Master switch; no shadow engine is ever created when `false`.
  ///
  /// 总开关；为 `false` 时永不创建影子引擎。
  final bool enabled;

  /// How long before a predictable end the shadow engine starts warming up.
  ///
  /// 在可预测的结束时刻前多久开始预热影子引擎。
  final Duration leadTime;

  /// Clips shorter than this never warm up — the overlap window would be
  /// most of their length, so the double cost is not worth the saved blank.
  ///
  /// 短于此值的片段一律不预热——重叠窗口会占掉它大半时长，双份开销换不回
  /// 那一下黑屏。
  final Duration minWarmDuration;

  /// Gives up warming after this long and falls back to a plain `open()`.
  ///
  /// 超过此时长仍未就绪则放弃预热，回落到普通 `open()`。
  final Duration readyTimeout;

  /// Whether the shadow engine is muted while warming, so only one audio
  /// decode path is live until the swap commits.
  ///
  /// 预热期间是否静音影子引擎，使切换落定前只有一路音频解码在跑。
  final bool muteWhileWarm;

  /// Decides *when* warming starts; `null` uses [MovaLeadWarm] seeded from
  /// [leadTime]/[minWarmDuration].
  ///
  /// 决定*何时*开始预热；为 `null` 时使用由 [leadTime]/[minWarmDuration]
  /// 构造的 [MovaLeadWarm]。
  final MovaWarmTrigger? trigger;

  /// Decides *whether the shadow is ready*; `null` uses [MovaBufferWarm]
  /// seeded from [readyTimeout].
  ///
  /// 决定*影子引擎是否已就绪*；为 `null` 时使用由 [readyTimeout] 构造的
  /// [MovaBufferWarm]。
  final MovaWarmPolicy? readyPolicy;

  /// Creates a swap configuration; disabled by default.
  ///
  /// 创建一份切换配置；默认关闭。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [leadTime]: warm-up lead before a predictable end / 结束前的预热提前量
  /// - [minWarmDuration]: shortest clip worth warming for / 值得预热的最短片长
  /// - [readyTimeout]: give-up deadline / 放弃预热的期限
  /// - [muteWhileWarm]: mute the shadow while warming / 预热期间静音影子引擎
  /// - [trigger]: injectable warm-up trigger / 可注入的预热触发策略
  /// - [readyPolicy]: injectable readiness verdict / 可注入的就绪判据
  ///
  /// Example / 示例:
  /// ```dart
  /// const opts = MovaOpts(swap: MovaSwapConfig(enabled: true));
  /// ```
  const MovaSwapConfig({
    this.enabled = false,
    this.leadTime = const Duration(seconds: 2),
    this.minWarmDuration = const Duration(seconds: 5),
    this.readyTimeout = const Duration(seconds: 8),
    this.muteWhileWarm = true,
    this.trigger,
    this.readyPolicy,
  });

  /// The trigger actually in effect.
  ///
  /// 实际生效的预热触发策略。
  MovaWarmTrigger get effectiveTrigger =>
      trigger ?? MovaLeadWarm(lead: leadTime, minDuration: minWarmDuration);

  /// A fresh readiness policy instance; policies carry per-warm-up state, so
  /// each warm-up gets its own rather than sharing one across swaps.
  ///
  /// 新建一个就绪判据实例；判据带有每次预热的累积状态，因此每次预热各用一个，
  /// 不跨切换共享。
  MovaWarmPolicy newReadyPolicy() =>
      readyPolicy ?? MovaBufferWarm(timeout: readyTimeout);

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  MovaSwapConfig copyWith({
    bool? enabled,
    Duration? leadTime,
    Duration? minWarmDuration,
    Duration? readyTimeout,
    bool? muteWhileWarm,
    MovaWarmTrigger? trigger,
    MovaWarmPolicy? readyPolicy,
  }) {
    return MovaSwapConfig(
      enabled: enabled ?? this.enabled,
      leadTime: leadTime ?? this.leadTime,
      minWarmDuration: minWarmDuration ?? this.minWarmDuration,
      readyTimeout: readyTimeout ?? this.readyTimeout,
      muteWhileWarm: muteWhileWarm ?? this.muteWhileWarm,
      trigger: trigger ?? this.trigger,
      readyPolicy: readyPolicy ?? this.readyPolicy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaSwapConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          leadTime == other.leadTime &&
          minWarmDuration == other.minWarmDuration &&
          readyTimeout == other.readyTimeout &&
          muteWhileWarm == other.muteWhileWarm &&
          trigger == other.trigger &&
          readyPolicy == other.readyPolicy;

  @override
  int get hashCode => Object.hash(
      enabled, leadTime, minWarmDuration, readyTimeout, muteWhileWarm, trigger, readyPolicy);
}
