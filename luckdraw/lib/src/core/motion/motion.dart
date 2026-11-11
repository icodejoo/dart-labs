import 'package:flutter/foundation.dart';

import '../foundation/constants.dart';

import '../game/frame.dart';
import '../game/layout.dart';
import 'phase.dart';
import 'result.dart';

/// tick 和命令返回的事件位，允许同时表达多个事件。
abstract final class LuckyMotionEvents {
  /// 没有事件。
  static const int none = 0;

  /// 阶段发生变化。
  static const int phaseChanged = 1 << 0;

  /// 本局正常结束。
  static const int settled = 1 << 1;

  /// 本局作废。
  static const int cancelled = 1 << 2;

  /// 跨过一个条目。
  static const int itemPassed = 1 << 3;

  /// 需要重新绘制。
  static const int repaint = 1 << 4;
}

/// 帧通知器，通知不会触发宿主 Widget 构建。
final class LuckyFrameNotifier extends ChangeNotifier {
  /// 创建帧通知器。
  LuckyFrameNotifier();

  /// 通知所有绘制监听者。
  void notify() => notifyListeners();
}

/// 无 Widget、Canvas、Ticker 依赖的玩法状态机。
abstract class LuckyMotion<C extends Object, L extends LuckyLayout,
    F extends LuckyFrame, R extends LuckyResult<Object?>> {
  /// 创建状态机。
  LuckyMotion();

  /// 时间轴单帧上限；玩法覆写为当前已应用的 motion 配置值。
  Duration get maxFrameDelta => kLuckyDefaultMaxFrameDelta;

  /// 跨帧复用的快照。
  F get frame;

  /// 当前阶段。
  LuckyPhase get phase;

  /// 阶段不在运动、但物理模拟仍未休眠时为真，宿主据此保持时钟运行；默认没有模拟。
  bool get isSimulating => false;

  /// 最近跨过条目的列，非多列玩法为零。
  int get passedReel;

  /// 最近跨过条目的下标。
  int get passedIndex;

  /// 应用配置和可选布局；缺必要布局时保持静止。
  void configure(C config, L? layout);

  /// 开始抽奖；返回是否接受。
  bool start();

  /// 开始待机慢转；返回是否接受。
  bool idleSpin();

  /// 作废当前局；返回是否接受。
  bool cancel();

  /// 回到初始状态。
  void reset();

  /// 按有效毫秒时间推进，返回 LuckyMotionEvents 位。
  int tick(double tMs, double dtMs);

  /// 取走一次性结果，无结果时返回 null。
  R? takeResult();
}
