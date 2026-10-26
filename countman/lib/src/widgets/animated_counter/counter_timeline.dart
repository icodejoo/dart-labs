import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart';

import 'types.dart';

/// 两种动画计数器共享的不可变时间轴；非空字段覆盖同名平铺参数，空字段回退。
///
/// 示例：
/// ```dart
/// AnimatedCounter(
///   value: 12,
///   timeline: CounterTimeline(duration: Duration(milliseconds: 500)),
/// )
/// ```
@immutable
class CounterTimeline {
  /// 创建时间轴；各同名参数设置对应字段，省略表示回退到组件平铺参数。
  const CounterTimeline({
    this.duration,
    this.curve,
    this.reverseDuration,
    this.reverseCurve,
    this.startDelay,
    this.speedMultiplier,
    this.staggerDelay,
    this.staggerDirection,
    this.autoEaseThreshold,
    this.curveForDigit,
    this.interpolation,
    this.bounceOvershoot,
    this.fast,
  });

  /// 正向滚动时长。
  final Duration? duration;

  /// 滚动曲线。
  final Curve? curve;

  /// 递减时的滚动时长。
  final Duration? reverseDuration;

  /// 递减时的滚动曲线。
  final Curve? reverseCurve;

  /// 开始滚动前的延迟；同样受倍速影响。
  final Duration? startDelay;

  /// 播放倍速，必须大于零。
  final double? speedMultiplier;

  /// 相邻数位的启动间隔。
  final Duration? staggerDelay;

  /// 数位错峰的启动方向。
  final StaggerDirection? staggerDirection;

  /// 线性曲线自动转为缓动的数值跨度阈值。
  final double? autoEaseThreshold;

  /// 按从左到右的 digitIndex 返回逐位曲线；返回空时使用整体曲线。
  final Curve? Function(int digitIndex)? curveForDigit;

  /// 根据起点 from、终点 to 与曲线进度 t 计算数位值。
  final double Function(double from, double to, double t)? interpolation;

  /// 落位回弹幅度，必须非负；零表示关闭回弹。
  final double? bounceOvershoot;

  /// 是否让每个数位仅滚动一步。
  final bool? fast;

  /// 返回副本；同名非空参数替换字段，空参数保留原值。
  ///
  /// 示例：`timeline.copyWith(duration: Duration(seconds: 1))`。
  CounterTimeline copyWith({
    Duration? duration,
    Curve? curve,
    Duration? reverseDuration,
    Curve? reverseCurve,
    Duration? startDelay,
    double? speedMultiplier,
    Duration? staggerDelay,
    StaggerDirection? staggerDirection,
    double? autoEaseThreshold,
    Curve? Function(int digitIndex)? curveForDigit,
    double Function(double from, double to, double t)? interpolation,
    double? bounceOvershoot,
    bool? fast,
  }) =>
      CounterTimeline(
        duration: duration ?? this.duration,
        curve: curve ?? this.curve,
        reverseDuration: reverseDuration ?? this.reverseDuration,
        reverseCurve: reverseCurve ?? this.reverseCurve,
        startDelay: startDelay ?? this.startDelay,
        speedMultiplier: speedMultiplier ?? this.speedMultiplier,
        staggerDelay: staggerDelay ?? this.staggerDelay,
        staggerDirection: staggerDirection ?? this.staggerDirection,
        autoEaseThreshold: autoEaseThreshold ?? this.autoEaseThreshold,
        curveForDigit: curveForDigit ?? this.curveForDigit,
        interpolation: interpolation ?? this.interpolation,
        bounceOvershoot: bounceOvershoot ?? this.bounceOvershoot,
        fast: fast ?? this.fast,
      );

  /// 与 other 按字段值比较；函数字段按引用比较。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterTimeline &&
          runtimeType == other.runtimeType &&
          duration == other.duration &&
          curve == other.curve &&
          reverseDuration == other.reverseDuration &&
          reverseCurve == other.reverseCurve &&
          startDelay == other.startDelay &&
          speedMultiplier == other.speedMultiplier &&
          staggerDelay == other.staggerDelay &&
          staggerDirection == other.staggerDirection &&
          autoEaseThreshold == other.autoEaseThreshold &&
          identical(curveForDigit, other.curveForDigit) &&
          identical(interpolation, other.interpolation) &&
          bounceOvershoot == other.bounceOvershoot &&
          fast == other.fast;

  /// 与字段相等性一致的哈希值。
  @override
  int get hashCode => Object.hashAll([
        duration,
        curve,
        reverseDuration,
        reverseCurve,
        startDelay,
        speedMultiplier,
        staggerDelay,
        staggerDirection,
        autoEaseThreshold,
        curveForDigit == null ? null : identityHashCode(curveForDigit),
        interpolation == null ? null : identityHashCode(interpolation),
        bounceOvershoot,
        fast,
      ]);
}
