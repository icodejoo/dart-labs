import 'package:flutter/foundation.dart';

/// 实验性（可能调整）：物理模式的减少动效策略，例如 `LuckyPhysicsReduceMotion.always`。
enum LuckyPhysicsReduceMotion {
  /// 跟随 MediaQuery.disableAnimations；没有 MediaQuery 时视为 false。
  system,

  /// 始终回退到参数化轨迹。
  always,

  /// 忽略系统减少动效设置，始终使用物理模拟。
  never,
}

/// 实验性（可能调整）：物理碰撞模式参数；长度单位为容器半径，时间单位为秒。
///
/// 传给扭蛋机或大乐透的 options 即开启，例如
/// `const LuckyPhysics(stirArms: 3, restitution: 0.4)`。
@immutable
final class LuckyPhysics {
  /// 创建参数；数值范围由 [validate] 检查。
  const LuckyPhysics({
    this.gravity = 9,
    this.restitution = 0.3,
    this.friction = 0.25,
    this.linearDamping = 0.2,
    this.stirArms = 2,
    this.stirRatio = 0.3,
    this.dropIn = true,
    this.guideLead = const Duration(milliseconds: 350),
    this.seed = 1,
    this.maxBodies = 128,
    this.reduceMotion = LuckyPhysicsReduceMotion.system,
  });

  /// 重力加速度，单位为容器半径每二次方秒，方向为屏幕向下；必须有限且非负。
  final double gravity;

  /// 球与球、球与容器壁的恢复系数，范围零到一。
  final double restitution;

  /// 库仑摩擦系数，驱动球的自转；必须有限且非负。
  final double friction;

  /// 线性阻尼，单位每秒，防止球永不停止；必须有限且非负。
  final double linearDamping;

  /// 拨杆数量，零表示没有拨杆，只有落入与堆叠。
  final int stirArms;

  /// 拨杆角相对搅拌角的比例，拨杆角等于搅拌角乘以该值；必须有限且非负。
  final double stirRatio;

  /// 首次布局与重置后，球是否从容器顶部落入；关闭则直接静止堆积。
  final bool dropIn;

  /// 目标球在起飞前提前多久开始受导引力；必须非负。
  final Duration guideLead;

  /// 初始落入位置的确定性抖动种子，相同种子得到相同初始摆放。
  final int seed;

  /// 物理模拟的球数上限，超出则整体回退到参数化轨迹；必须为正。
  final int maxBodies;

  /// 减少动效策略，默认跟随系统。
  final LuckyPhysicsReduceMotion reduceMotion;

  /// 校验参数范围；非法时抛出 ArgumentError，例如 `const LuckyPhysics().validate()`。
  void validate() {
    final finiteNonNegative = [gravity, friction, linearDamping, stirRatio]
        .every((v) => v.isFinite && v >= 0);
    if (!finiteNonNegative ||
        !(restitution >= 0 && restitution <= 1) ||
        stirArms < 0 ||
        guideLead.isNegative ||
        maxBodies <= 0) {
      throw ArgumentError.value(this, 'physics', '物理参数范围无效');
    }
  }

  /// 返回替换非空参数的副本，例如 `physics.copyWith(stirArms: 3)`。
  LuckyPhysics copyWith(
          {double? gravity,
          double? restitution,
          double? friction,
          double? linearDamping,
          int? stirArms,
          double? stirRatio,
          bool? dropIn,
          Duration? guideLead,
          int? seed,
          int? maxBodies,
          LuckyPhysicsReduceMotion? reduceMotion}) =>
      LuckyPhysics(
          gravity: gravity ?? this.gravity,
          restitution: restitution ?? this.restitution,
          friction: friction ?? this.friction,
          linearDamping: linearDamping ?? this.linearDamping,
          stirArms: stirArms ?? this.stirArms,
          stirRatio: stirRatio ?? this.stirRatio,
          dropIn: dropIn ?? this.dropIn,
          guideLead: guideLead ?? this.guideLead,
          seed: seed ?? this.seed,
          maxBodies: maxBodies ?? this.maxBodies,
          reduceMotion: reduceMotion ?? this.reduceMotion);

  /// 按所有参数比较。
  @override
  bool operator ==(Object other) =>
      other is LuckyPhysics &&
      other.gravity == gravity &&
      other.restitution == restitution &&
      other.friction == friction &&
      other.linearDamping == linearDamping &&
      other.stirArms == stirArms &&
      other.stirRatio == stirRatio &&
      other.dropIn == dropIn &&
      other.guideLead == guideLead &&
      other.seed == seed &&
      other.maxBodies == maxBodies &&
      other.reduceMotion == reduceMotion;

  /// 与相等性一致的哈希。
  @override
  int get hashCode => Object.hash(gravity, restitution, friction, linearDamping,
      stirArms, stirRatio, dropIn, guideLead, seed, maxBodies, reduceMotion);
}
