import '../model/source.dart';
import 'plan.dart';
import 'trigger.dart';

/// 包内可选能力：把宿主拒绝与无缝切换失败分开，不扩展公开切换接口。
abstract interface class MovaCutoverAcceptance {
  /// 预热并报告宿主是否未拒绝；未触发预热也视为未拒绝。
  Future<bool> prepareAccepted(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
  });

  /// 返回本次调用的无缝结果与接受结果，避免并发调用串读全局状态。
  Future<({bool seamless, bool accepted})> cutoverToAccepted(
    MovaSource source, {
    Duration at = Duration.zero,
    double? rate,
    bool? play,
  });
}
