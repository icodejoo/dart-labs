import 'package:flutter/foundation.dart';

import '../easing/easing.dart';
import '../foundation/constants.dart';

/// 返回第 i 个停止候选位移；i 从一开始。
typedef LuckyStopCandidate = double Function(int i);

/// 停止候选的选择方式。
enum LuckyStopSelection {
  /// 首个超速者与前一个候选中选速度差较小者，相同差时选前一个候选。
  nearest,

  /// 选首个首帧位移绝对值大于阈值的候选。
  firstExceeding,
}

/// 一次停止求解的输入；例如传给 `solver.solve(problem)`。
@immutable
final class LuckyStopProblem {
  /// 创建求解输入；[direction] 应为 +1 或 −1，其余值单位须一致。
  const LuckyStopProblem(
      {required this.start,
      required this.candidate,
      required this.cruiseSpeed,
      required this.frameMs,
      required this.decelerationMs,
      required this.easing,
      required this.selection,
      this.direction = 1});

  /// 当前位置 b。
  final double start;

  /// 按上游顺序计算的候选位移函数。
  final LuckyStopCandidate candidate;

  /// 匀速阶段的每帧速度；老虎机保留配置速度的符号。
  final double cruiseSpeed;

  /// 首帧时长；非有限或非正时使用参考帧。
  final double frameMs;

  /// 正的减速时长，单位为毫秒。
  final double decelerationMs;

  /// 减速缓动。
  final LuckyEasing easing;

  /// 候选选择规则。
  final LuckyStopSelection selection;

  /// 运动方向，+1 或 −1。
  final int direction;
}

/// 停止求解策略，可由调用方显式传入。
abstract interface class LuckyStopSolver {
  /// 返回 [problem] 的减速变化量 c；无法求解时返回有限兜底或零。
  double solve(LuckyStopProblem problem);
}

/// 复刻上游离散停止求解，包括负位移；例如 `const UpstreamStopSolver()`。
final class UpstreamStopSolver implements LuckyStopSolver {
  /// 创建无状态求解器。
  const UpstreamStopSolver();

  /// 按上游规则返回位移，异常输入有有限兜底与迭代上限。
  @override
  double solve(LuckyStopProblem problem) =>
      _solveStop(problem, monotonic: false);
}

/// 默认停止求解器，只接受沿运动方向的位移；例如 `const MonotonicStopSolver()`。
final class MonotonicStopSolver implements LuckyStopSolver {
  /// 创建无状态求解器。
  const MonotonicStopSolver();

  /// 返回方向正确的位移；异常输入有有限兜底与迭代上限。
  @override
  double solve(LuckyStopProblem problem) =>
      _solveStop(problem, monotonic: true);
}

/// 共享上游搜索顺序，仅在 monotonic 模式额外限制方向。
double _solveStop(LuckyStopProblem p, {required bool monotonic}) {
  final frameMs =
      p.frameMs.isFinite && p.frameMs > 0 ? p.frameMs : kLuckyReferenceFrameMs;
  var prevSpeed = 0.0;
  var prevDeg = 0.0;
  var fallback = 0.0;
  for (var i = 1; i <= kLuckyMaxSolverIterations; i++) {
    final cand = p.candidate(i);
    if (!cand.isFinite) return fallback;
    if (fallback == 0 && cand * p.direction > 0) fallback = cand;
    final raw =
        p.easing.easeOut(frameMs, p.start, cand, p.decelerationMs) - p.start;
    if (!raw.isFinite) return fallback;
    if (p.selection == LuckyStopSelection.firstExceeding) {
      // 上游 slot.ts:473-478：速度阈值不取绝对值。
      if (raw.abs() > p.cruiseSpeed && (!monotonic || cand * p.direction > 0)) {
        return cand;
      }
    } else {
      // 上游 wheel.ts:451-461；乘 direction 仅用于泛化反向运动。
      final currSpeed = raw * p.direction;
      if (currSpeed > p.cruiseSpeed) {
        final chosen = p.cruiseSpeed - prevSpeed > currSpeed - p.cruiseSpeed
            ? cand
            : prevDeg;
        if (!monotonic || chosen * p.direction > 0) return chosen;
        if (cand * p.direction > 0) return cand;
      }
      prevDeg = cand;
      prevSpeed = currSpeed;
    }
  }
  return fallback;
}
