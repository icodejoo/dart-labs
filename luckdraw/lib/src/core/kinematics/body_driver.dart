import 'dart:math' as math;
import 'dart:typed_data';

import '../foundation/angles.dart';
import '../foundation/constants.dart';
import '../render/perf_trace.dart';
import 'circle_world.dart';
import 'physics_options.dart';
import 'swirl_mixer.dart';

/// 导引目标可达的最远圆心距，单位为容器半径，受球半径限制后取更小者。
const double _maxReach = 1;

/// 球半径比的比较容差。
const double _ratioTolerance = 1e-9;

/// 容器内一组同半径球的位置驱动：参数化轨迹或物理模拟，对外是同一组复用缓冲。
///
/// 坐标与角度缓冲在构造时分配并长期复用，调用方只读；坐标相对容器圆心，单位同布局。
abstract interface class LuckyBodyDriver {
  /// 球心横坐标缓冲。
  Float64List get x;

  /// 球心纵坐标缓冲。
  Float64List get y;

  /// 球自转角缓冲，单位弧度。
  Float64List get angle;

  /// 物理模拟是否仍未休眠；参数化轨迹恒为 false。
  bool get isAwake;

  /// 推进到当前帧。
  ///
  /// [dtMs] 为本帧有效毫秒，[swirlDeg] 为累计搅拌角，[mix] 为零到一的搅拌强度，
  /// [excluded] 为 true 的球保持原值（由调用方接管其位置）。
  void advance(double dtMs, double swirlDeg, double mix, List<bool> excluded);

  /// 回到初始状态：物理模拟重新摆放并落入，参数化轨迹无需操作。
  void reset();
}

/// 参数化搅拌驱动，包装 [LuckySwirlMixer]，行为与原先直接使用混合器一致。
final class LuckySwirlDriver implements LuckyBodyDriver {
  /// 包装已构造的混合器。
  LuckySwirlDriver(this._mixer);

  /// 被包装的混合器。
  final LuckySwirlMixer _mixer;

  /// 横坐标缓冲，与混合器共用。
  @override
  Float64List get x => _mixer.x;

  /// 纵坐标缓冲，与混合器共用。
  @override
  Float64List get y => _mixer.y;

  /// 自转角缓冲，与混合器共用。
  @override
  Float64List get angle => _mixer.angle;

  /// 参数化轨迹没有休眠概念，恒为 false。
  @override
  bool get isAwake => false;

  /// 忽略 [dtMs]，按累计搅拌角与强度直接计算位置。
  @override
  void advance(double dtMs, double swirlDeg, double mix, List<bool> excluded) =>
      _mixer.update(swirlDeg, mix, excluded: excluded);

  /// 无状态，无需操作。
  @override
  void reset() {}
}

/// 物理模拟驱动，把 [LuckyCircleWorld] 的归一化结果换算到布局像素坐标。
///
/// 例如 `LuckyPhysicsDriver(physics: const LuckyPhysics(), count: 12,
/// containerRadius: 100, bodyRadius: 12)`，之后每帧调用 [advance]。
final class LuckyPhysicsDriver implements LuckyBodyDriver {
  /// 创建驱动与世界；[bodyRadius] 与 [containerRadius] 之比须在零到零点五之间。
  LuckyPhysicsDriver(
      {required this.physics,
      required int count,
      required double containerRadius,
      required double bodyRadius})
      : _scale = containerRadius,
        _ratio = bodyRadius / containerRadius,
        world = LuckyCircleWorld(
            count: count,
            radius: bodyRadius / containerRadius,
            gravity: physics.gravity,
            restitution: physics.restitution,
            friction: physics.friction,
            linearDamping: physics.linearDamping,
            armCount: physics.stirArms,
            seed: physics.seed,
            dropIn: physics.dropIn),
        x = Float64List(count),
        y = Float64List(count),
        angle = Float64List(count) {
    _copy(const []);
  }

  /// 创建所用的物理参数。
  final LuckyPhysics physics;

  /// 归一化物理世界。
  final LuckyCircleWorld world;

  /// 球心横坐标缓冲，单位同布局。
  @override
  final Float64List x;

  /// 球心纵坐标缓冲，单位同布局。
  @override
  final Float64List y;

  /// 球自转角缓冲，单位弧度。
  @override
  final Float64List angle;

  /// 容器半径，归一化到布局像素的比例。
  double _scale;

  /// 球半径与容器半径之比。
  final double _ratio;

  /// 上一次的累计搅拌角，用于识别重置造成的回退。
  double _lastSwirl = 0;

  /// 物理模拟是否仍未休眠。
  @override
  bool get isAwake => world.isAwake;

  /// 拨杆当前角度，单位度，供绘制与碰撞保持一致。
  double get armDeg => world.armAngle * kLuckyHalfTurnDeg / math.pi;

  /// 是否可沿用现有世界：球数、半径比与物理参数都未变化，只需 [rescale]。
  bool isCompatible(
          {required int count,
          required double bodyRadius,
          required double containerRadius,
          required LuckyPhysics physics}) =>
      count == world.count &&
      physics == this.physics &&
      (bodyRadius / containerRadius - _ratio).abs() < _ratioTolerance;

  /// 容器像素半径变化时只改换算比例，不重置世界。
  void rescale(double containerRadius) {
    _scale = containerRadius;
    _copy(const []);
  }

  /// 同步移出标记、推进世界并把结果写入像素缓冲。
  @override
  void advance(double dtMs, double swirlDeg, double mix, List<bool> excluded) {
    luckyTraceStart('luckdraw.physics.step');
    try {
      for (var i = 0; i < world.count; i++) {
        if (excluded[i] == world.isActive(i)) {
          world.setActive(i, active: !excluded[i]);
        }
      }
      if (swirlDeg < _lastSwirl) world.resetStir();
      _lastSwirl = swirlDeg;
      world.advance(dtMs / Duration.millisecondsPerSecond,
          stirAngle: luckyDegToRad(swirlDeg) * physics.stirRatio, engaged: mix);
      _copy(excluded);
    } finally {
      luckyTraceEnd();
    }
  }

  /// 让球 [i] 趋向容器内的像素坐标 ([tx], [ty])，[strength] 在零到一；零取消导引。
  ///
  /// 目标被限制在球心可达范围内，避免弹簧与容器壁互相对抗。
  void guide(int i, double tx, double ty, double strength) {
    final reach = math.min(_maxReach, 1 - _ratio);
    var nx = tx / _scale, ny = ty / _scale;
    final d = math.sqrt(nx * nx + ny * ny);
    if (d > reach) {
      nx *= reach / d;
      ny *= reach / d;
    }
    world.setGuide(i, nx, ny, strength);
  }

  /// 重新摆放并落入，回到初始状态。
  @override
  void reset() {
    world.reset(dropIn: physics.dropIn);
    _lastSwirl = 0;
    _copy(const []);
  }

  /// 把世界缓冲换算到像素缓冲；[excluded] 为 true 的球由调用方接管，保持不变。
  void _copy(List<bool> excluded) {
    for (var i = 0; i < world.count; i++) {
      if (i < excluded.length && excluded[i]) continue;
      x[i] = world.x[i] * _scale;
      y[i] = world.y[i] * _scale;
      angle[i] = world.angle[i];
    }
  }
}
