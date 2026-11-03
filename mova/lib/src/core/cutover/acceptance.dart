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

/// 包内预热凭据；空槽仍保留操作代际，以识别 prepare 期间的宿主抢源。
final class MovaWarmTicket {
  MovaWarmTicket(this.slot, this.operation, {this.rejected = false});
  final Object? slot;
  final int operation;
  final bool rejected;
}

/// 包内提交结果：未就绪允许回落，被取代必须让位。
enum MovaWarmCommit { committed, notReady, superseded }

/// 在原接受能力上扩展凭据提交，公开 MovaCutover 不增加成员。
abstract interface class MovaWarmOwner implements MovaCutoverAcceptance {
  Future<MovaWarmTicket?> prepareOwned(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
    bool? play,
  });
  Future<MovaWarmCommit> commitOwned(
    MovaWarmTicket ticket, {
    bool waitForReady = false,
  });
}
