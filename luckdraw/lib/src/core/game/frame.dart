import '../motion/phase.dart';

/// 跨帧复用的可变帧快照，motion 应原地更新。
abstract class LuckyFrame {
  /// 创建初始帧。
  LuckyFrame();

  /// 当前运动阶段。
  LuckyPhase phase = LuckyPhase.idle;
}
