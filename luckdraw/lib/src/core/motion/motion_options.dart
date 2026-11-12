import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../easing/easing.dart';
import '../foundation/constants.dart';
import '../foundation/duration_ms.dart';
import 'stop_solver.dart';
import 'timebase.dart';

/// 动画配置；默认按有效时间推进并使用单调停止求解。
///
/// 例如 `const LuckyMotionOptions(speed: 10)`；非正时长由 motion.configure 断言，
/// 毫秒访问器始终至少返回 1，避免运行期除零。
@immutable
final class LuckyMotionOptions {
  /// 创建不可变配置；时长应为正，maxFrameDelta 应非负。
  const LuckyMotionOptions(
      {this.speed = kLuckyDefaultSpeed,
      this.accelerationTime = kLuckyDefaultAccelerationTime,
      this.decelerationTime = kLuckyDefaultDecelerationTime,
      this.accelerationEasing = LuckyEasings.quad,
      this.decelerationEasing = LuckyEasings.quad,
      this.timebase = LuckyTimebase.time,
      this.stopSolver = const MonotonicStopSolver(),
      this.maxFrameDelta = kLuckyDefaultMaxFrameDelta,
      this.idleSpinSpeed = kLuckyDefaultIdleSpinSpeed});

  /// 匀速阶段每参考帧的速度。
  final double speed;

  /// 加速时长，应为正。
  final Duration accelerationTime;

  /// 减速时长，应为正。
  final Duration decelerationTime;

  /// 加速缓动。
  final LuckyEasing accelerationEasing;

  /// 减速缓动。
  final LuckyEasing decelerationEasing;

  /// 位移时间基准。
  final LuckyTimebase timebase;

  /// 停止求解策略。
  final LuckyStopSolver stopSolver;

  /// 有效时间轴单帧最大推进量。
  final Duration maxFrameDelta;

  /// 待机慢转每参考帧的速度。
  final double idleSpinSpeed;

  /// 至少一毫秒的加速时长。
  double get accelerationMs => math.max(1, luckyMs(accelerationTime));

  /// 至少一毫秒的减速时长。
  double get decelerationMs => math.max(1, luckyMs(decelerationTime));

  /// 返回只替换非 null 参数的副本；例如 `options.copyWith(speed: 30)`。
  LuckyMotionOptions copyWith(
          {double? speed,
          Duration? accelerationTime,
          Duration? decelerationTime,
          LuckyEasing? accelerationEasing,
          LuckyEasing? decelerationEasing,
          LuckyTimebase? timebase,
          LuckyStopSolver? stopSolver,
          Duration? maxFrameDelta,
          double? idleSpinSpeed}) =>
      LuckyMotionOptions(
          speed: speed ?? this.speed,
          accelerationTime: accelerationTime ?? this.accelerationTime,
          decelerationTime: decelerationTime ?? this.decelerationTime,
          accelerationEasing: accelerationEasing ?? this.accelerationEasing,
          decelerationEasing: decelerationEasing ?? this.decelerationEasing,
          timebase: timebase ?? this.timebase,
          stopSolver: stopSolver ?? this.stopSolver,
          maxFrameDelta: maxFrameDelta ?? this.maxFrameDelta,
          idleSpinSpeed: idleSpinSpeed ?? this.idleSpinSpeed);

  /// 按全部字段比较配置值。
  @override
  bool operator ==(Object other) =>
      other is LuckyMotionOptions &&
      other.speed == speed &&
      other.accelerationTime == accelerationTime &&
      other.decelerationTime == decelerationTime &&
      other.accelerationEasing == accelerationEasing &&
      other.decelerationEasing == decelerationEasing &&
      other.timebase == timebase &&
      other.stopSolver == stopSolver &&
      other.maxFrameDelta == maxFrameDelta &&
      other.idleSpinSpeed == idleSpinSpeed;

  /// 与值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      speed,
      accelerationTime,
      decelerationTime,
      accelerationEasing,
      decelerationEasing,
      timebase,
      stopSolver,
      maxFrameDelta,
      idleSpinSpeed);
}
