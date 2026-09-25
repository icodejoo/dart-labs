import 'trigger.dart';
import 'warm.dart';

/// Per-warm-up overrides for one [MovaSwapController.prepare] call.
///
/// The three knobs that legitimately differ *between two warm-ups on the same
/// engine*, and therefore cannot live in [MovaSwapConfig]: the same
/// [MovaSwapEngine] now warms content up behind an ad (lead-timed, keeps
/// rolling) and warms an ad up behind content (eager, must hold at frame
/// zero). Every field is nullable/defaulted, so `prepare(src)` with no plan
/// behaves exactly as it did in 0.4.0.
///
/// 单次 [MovaSwapController.prepare] 调用的预热参数覆盖。
///
/// 这三个旋钮会在*同一个引擎的两次预热之间*合理地取不同值，因此不能放进
/// [MovaSwapConfig]：同一个 [MovaSwapEngine] 现在既要在广告背后预热正片
/// （按提前量触发、一路播着），又要在正片背后预热广告（立即触发、必须停在
/// 第 0 帧）。每个字段都可空/有默认值，因此不带 plan 的 `prepare(src)` 与
/// 0.4.0 行为完全一致。
class MovaWarmPlan {
  /// Overrides [MovaSwapConfig.effectiveTrigger] for this warm-up; null keeps
  /// the configured one.
  ///
  /// 本次预热对 [MovaSwapConfig.effectiveTrigger] 的覆盖；null 表示沿用已配置的。
  final MovaWarmTrigger? trigger;

  /// Overrides [MovaSwapConfig.newReadyPolicy] for this warm-up; null keeps
  /// the configured one. The engine calls [MovaWarmPolicy.reset] on it before
  /// use, so one instance may safely drive successive warm-ups.
  ///
  /// 本次预热对 [MovaSwapConfig.newReadyPolicy] 的覆盖；null 表示沿用已配置的。
  /// 引擎在使用前会调用其 [MovaWarmPolicy.reset]，因此同一实例可安全驱动多次预热。
  final MovaWarmPolicy? policy;

  /// Whether the shadow pauses and rewinds to the warm-up target the moment it
  /// reports ready, so the swap starts playback from that exact frame.
  ///
  /// Required in both directions: a shadow warmed with `autoPlay: true` runs
  /// in real time while the visible engine shows something else, so by commit
  /// time it has drifted forward by the whole overlap window. For an ad that
  /// means an impression delivered with its head missing; for the content
  /// behind an ad it means the viewer silently loses that many seconds of the
  /// film (measured on device: a 2.8s hole).
  ///
  /// 影子引擎一报告就绪，是否立即暂停并回到预热目标点，使切换后从那一帧开始播。
  ///
  /// 两个方向都必须开：以 `autoPlay: true` 预热的影子在屏幕上放着别的东西时仍
  /// 按真实时间往前跑，到提交切换那一刻已经整整漂过一个重叠窗口。对广告，这是
  /// 交付出一条缺头的曝光；对广告背后的正片，这是让用户无声无息丢掉那么多秒
  /// 正片（真机实测 2.8 秒的缺口）。
  final bool pauseWhenReady;

  /// Creates a warm-up plan; all-defaults reproduces 0.4.0 behaviour.
  ///
  /// 创建一份预热计划；全默认即 0.4.0 行为。
  ///
  /// - [trigger]: per-call trigger override / 单次触发策略覆盖
  /// - [policy]: per-call readiness override / 单次就绪判据覆盖
  /// - [pauseWhenReady]: hold at the target frame once ready / 就绪后停在目标帧
  ///
  /// Example / 示例:
  /// ```dart
  /// await swap.prepare(ad.source, plan: const MovaWarmPlan(
  ///   trigger: MovaEagerWarm(), pauseWhenReady: true));
  /// ```
  const MovaWarmPlan({this.trigger, this.policy, this.pauseWhenReady = false});
}
