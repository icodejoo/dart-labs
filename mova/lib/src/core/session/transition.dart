import '../cutover/plan.dart';
import '../cutover/trigger.dart';
import '../options/ad_config.dart';

/// 广告方向沿用宿主计划，未指定倍速时补 1x。
MovaWarmPlan movaAdWarmPlan(MovaAdConfig cfg) {
  final plan = cfg.effectiveWarmPlan;
  return MovaWarmPlan(
    trigger: plan.trigger,
    policy: plan.policy,
    pauseWhenReady: plan.pauseWhenReady,
    rate: plan.rate ?? 1.0,
  );
}

/// 正片停在续播点，并继承广告前的倍速。
MovaWarmPlan movaContentWarmPlan(double rate) =>
    MovaWarmPlan(pauseWhenReady: true, rate: rate);

/// 提示同时考虑素材和广告位；未知长度忽略，已到期长度夹到零。
MovaWarmCue movaContentWarmCue({
  required Duration mediaDuration,
  required Duration adPosition,
  Duration? slotRemaining,
  Duration? slotLength,
}) {
  Duration? remaining = mediaDuration > Duration.zero
      ? mediaDuration - adPosition
      : null;
  if (slotRemaining != null && (remaining == null || slotRemaining < remaining)) {
    remaining = slotRemaining;
  }
  if (remaining != null && remaining < Duration.zero) remaining = Duration.zero;
  Duration? total = mediaDuration > Duration.zero ? mediaDuration : null;
  if (slotLength != null && (total == null || slotLength < total)) {
    total = slotLength;
  }
  return MovaWarmCue(remaining: remaining, total: total);
}
