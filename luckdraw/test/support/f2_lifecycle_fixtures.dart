import 'package:luckdraw/extend.dart';
import 'package:luckdraw/testing.dart';

/// 记录所有宿主事件，供释放后的回调边验证。
final class F2LifecycleHost<R extends LuckyResult<Object?>>
    implements LuckyControllerHost<R> {
  /// 创建独立时钟和计数器。
  F2LifecycleHost();

  /// 测试持有的手动时钟。
  @override
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 已接收的阶段、结果、条目与启动事件总数。
  int callbacks = 0;

  /// 记录结果事件。
  @override
  void handleResult(R result) {
    callbacks++;
  }

  /// 记录条目事件。
  @override
  void handleItemPassed(int reel, int index) {
    callbacks++;
  }

  /// 记录阶段事件。
  @override
  void handlePhaseChanged(LuckyPhase phase) {
    callbacks++;
  }

  /// 记录启动事件。
  @override
  void handleStarted() {
    callbacks++;
  }
}
