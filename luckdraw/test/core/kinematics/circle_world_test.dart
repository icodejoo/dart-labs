import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/kinematics/circle_world.dart';

/// 单球半径，与大乐透默认比例一致。
const double _r = 0.11;

/// 一帧六十赫兹。
const double _frame = 1 / 60;

/// 是否所有坐标与角度都是有限数。
bool _finite(LuckyCircleWorld w) =>
    [w.x, w.y, w.angle].every((list) => list.every((v) => v.isFinite));

/// 最大越界量：球心到圆心距离超出可达范围的部分。
double _outside(LuckyCircleWorld w) {
  var worst = 0.0;
  for (var i = 0; i < w.count; i++) {
    worst = math.max(
        worst, math.sqrt(w.x[i] * w.x[i] + w.y[i] * w.y[i]) - (1 - w.radius));
  }
  return worst;
}

/// 最大重叠量，单位为球半径。
double _overlap(LuckyCircleWorld w) {
  var worst = 0.0;
  for (var i = 0; i < w.count; i++) {
    for (var j = i + 1; j < w.count; j++) {
      final d = math
          .sqrt(math.pow(w.x[i] - w.x[j], 2) + math.pow(w.y[i] - w.y[j], 2));
      worst = math.max(worst, 2 * w.radius - d);
    }
  }
  return worst / w.radius;
}

/// 按六十赫兹推进到休眠或超时，返回用时秒数。
double _settle(LuckyCircleWorld w, {double limit = 15}) {
  var t = 0.0;
  while (w.isAwake && t < limit) {
    w.advance(_frame, stirAngle: 0);
    t += _frame;
  }
  return t;
}

/// 先搅拌 [seconds] 秒，返回累计拨杆指令角。
double _stir(LuckyCircleWorld w, double seconds, {double rate = 3.77}) {
  var angle = 0.0;
  for (var f = 0; f < (seconds / _frame).round(); f++) {
    angle += rate * _frame;
    w.advance(_frame, stirAngle: angle, engaged: 1);
  }
  return angle;
}

/// 球心到拨杆线段的距离。
double _armDistance(LuckyCircleWorld w, int i, int arm) {
  final a = w.armAngle + arm * 2 * math.pi / w.armCount;
  final ux = math.cos(a), uy = math.sin(a);
  final s = (w.x[i] * ux + w.y[i] * uy).clamp(0.15, 0.92);
  return math.sqrt(math.pow(w.x[i] - ux * s, 2) + math.pow(w.y[i] - uy * s, 2));
}

/// 验证圆形刚体世界的数值契约。
void main() {
  test('构造与复位后坐标有限、全部在容器内且落入初始互不重叠', () {
    for (final count in [0, 1, 12, 35]) {
      for (final dropIn in [true, false]) {
        final w = LuckyCircleWorld(count: count, radius: _r, dropIn: dropIn);
        expect(_finite(w), isTrue, reason: 'n=$count drop=$dropIn');
        expect(_outside(w), lessThanOrEqualTo(1e-9));
        if (dropIn) expect(_overlap(w), lessThanOrEqualTo(1e-9));
      }
    }
  });

  test('球数超出容器容量时收缩落入间距仍能摆放且不越界', () {
    final w = LuckyCircleWorld(count: 100, radius: _r);
    expect(_finite(w), isTrue);
    expect(_outside(w), lessThanOrEqualTo(1e-9));
    expect(w.isAwake, isTrue);
  });

  test('单球自由落体与解析解一致并最终静止在容器底部', () {
    final w = LuckyCircleWorld(count: 1, radius: _r, linearDamping: 0);
    w.place(0, 0, -0.5);
    for (var f = 0; f < 18; f++) {
      w.advance(_frame, stirAngle: 0);
    }
    const t = 18 * _frame;
    expect(w.y[0], closeTo(-0.5 + 0.5 * 9 * t * t, 0.03));
    expect(w.x[0], closeTo(0, 1e-9));
    expect(_settle(w), lessThan(15));
    expect(w.isAwake, isFalse);
    expect(w.y[0], closeTo(1 - _r, 0.005));
    expect(w.x[0], closeTo(0, 0.005));
  });

  test('堆叠落定后休眠，残余重叠不超过球半径的百分之五', () {
    for (final count in [12, 35]) {
      final w = LuckyCircleWorld(count: count, radius: _r);
      expect(_settle(w), lessThan(15), reason: 'n=$count');
      expect(w.isAwake, isFalse);
      expect(_overlap(w), lessThanOrEqualTo(0.05), reason: 'n=$count');
      expect(_outside(w), lessThanOrEqualTo(1e-9));
    }
  });

  test('dropIn 为假时直接预演到静止堆积并已休眠', () {
    final w = LuckyCircleWorld(count: 20, radius: _r, dropIn: false);
    expect(w.isAwake, isFalse);
    expect(_overlap(w), lessThanOrEqualTo(0.05));
    expect(w.y.reduce(math.max), closeTo(1 - _r, 0.02));
  });

  test('无阻尼对心碰撞交换速度并守恒动能', () {
    final w = LuckyCircleWorld(
        count: 2,
        radius: _r,
        gravity: 0,
        restitution: 1,
        friction: 0,
        linearDamping: 0,
        armCount: 0);
    w.place(0, -0.3, 0, vx: 1);
    w.place(1, 0.3, 0, vx: -1);
    expect(w.energy, closeTo(1, 1e-9));
    for (var f = 0; f < 36; f++) {
      w.advance(_frame, stirAngle: 0);
    }
    expect(w.x[0], lessThan(-0.45));
    expect(w.x[1], greaterThan(0.45));
    expect(w.energy, closeTo(1, 0.05));
  });

  test('有阻尼无拨杆时机械能单调不增并最终归零', () {
    final w = LuckyCircleWorld(count: 20, radius: _r, armCount: 0);
    double mechanical() {
      var potential = 0.0;
      for (var i = 0; i < w.count; i++) {
        potential += w.gravity * -w.y[i];
      }
      return w.energy + potential;
    }

    final start = mechanical();
    var previous = start;
    var worstRise = 0.0;
    for (var f = 0; f < 600 && w.isAwake; f++) {
      w.advance(_frame, stirAngle: 0);
      final now = mechanical();
      worstRise = math.max(worstRise, now - previous);
      previous = now;
    }
    expect(worstRise, lessThan(0.5));
    expect(previous, lessThan(start - 50));
    expect(w.isAwake, isFalse);
    expect(w.energy, 0);
  });

  test('斜向接触产生与切向一致的自转', () {
    for (final direction in [1.0, -1.0]) {
      final w = LuckyCircleWorld(count: 1, radius: _r);
      w.place(0, 0, 1 - _r, vx: direction);
      for (var f = 0; f < 6; f++) {
        w.advance(_frame, stirAngle: 0);
      }
      expect(w.angle[0] * direction, greaterThan(0.01),
          reason: 'direction=$direction');
    }
  });

  test('拨杆搅拌让球运动且球心不会陷入拨杆内部', () {
    final w = LuckyCircleWorld(count: 20, radius: _r, dropIn: false);
    var angle = 0.0;
    var peak = 0.0;
    var closest = double.infinity;
    for (var f = 0; f < 240; f++) {
      angle += 3.77 * _frame;
      w.advance(_frame, stirAngle: angle, engaged: 1);
      peak = math.max(peak, w.energy);
      for (var i = 0; i < w.count; i++) {
        for (var arm = 0; arm < w.armCount; arm++) {
          closest = math.min(closest, _armDistance(w, i, arm));
        }
      }
    }
    expect(peak, greaterThan(0.5));
    expect(closest, greaterThan(0.5 * _r));
    expect(_finite(w), isTrue);
    expect(_outside(w), lessThanOrEqualTo(1e-9));
  });

  test('拨杆啮合度按比例缩小半宽，零啮合时拨杆不参与碰撞', () {
    final off = LuckyCircleWorld(count: 1, radius: _r, gravity: 0, armCount: 2);
    off.place(0, 0.5, 0);
    off.advance(_frame, stirAngle: 0);
    expect(off.x[0], 0.5);
    expect(off.y[0], 0);
    final half = LuckyCircleWorld(count: 1, radius: _r, gravity: 0);
    half.place(0, 0.5, 0.05);
    half.advance(_frame, stirAngle: 0, engaged: 0.5);
    expect(half.y[0], greaterThan(0.05));
  });

  test('拨杆指令角突变被限制为尖端每子步位移不超过半个球半径', () {
    final w = LuckyCircleWorld(count: 5, radius: _r);
    w.advance(_frame, stirAngle: 0, engaged: 1);
    w.advance(_frame, stirAngle: 100, engaged: 1);
    final maxDelta = 8 * 0.5 * _r / 0.92;
    expect(w.armAngle, closeTo(maxDelta, 1e-9));
    w.advance(_frame, stirAngle: -100, engaged: 1);
    expect(w.armAngle, closeTo(0, 1e-9));
  });

  test('没有拨杆的世界忽略拨杆指令且不会因此唤醒', () {
    final w = LuckyCircleWorld(count: 6, radius: _r, armCount: 0);
    _settle(w);
    expect(w.isAwake, isFalse);
    w.advance(_frame, stirAngle: 5, engaged: 1);
    w.advance(_frame, stirAngle: 10, engaged: 1);
    expect(w.isAwake, isFalse);
  });

  test('休眠后不再积分，放置、导引、移出、拨杆与复位都会唤醒', () {
    final w = LuckyCircleWorld(count: 4, radius: _r);
    _settle(w);
    final frozen = List<double>.of(w.y);
    expect(w.isAwake, isFalse);
    w.advance(_frame, stirAngle: 0);
    expect(w.y, frozen);
    w.place(0, 0, -0.3);
    expect(w.isAwake, isTrue);
    _settle(w);
    w.setGuide(1, 0, 0, 0);
    expect(w.isAwake, isFalse);
    w.setGuide(1, 0, 0, 0.2);
    expect(w.isAwake, isTrue);
    w.setGuide(1, 0, 0, 0);
    _settle(w);
    w.setActive(2, active: false);
    expect(w.isAwake, isTrue);
    _settle(w);
    w.advance(_frame, stirAngle: 0, engaged: 1);
    w.advance(_frame, stirAngle: 0.2, engaged: 1);
    expect(w.isAwake, isTrue);
    _settle(w);
    w.reset(dropIn: true);
    expect(w.isAwake, isTrue);
  });

  test('球数为零的世界始终休眠且所有操作安全', () {
    final w = LuckyCircleWorld(count: 0, radius: _r);
    expect(w.isAwake, isFalse);
    w.wake();
    w.advance(_frame, stirAngle: 1, engaged: 1);
    expect(w.isAwake, isFalse);
    expect(w.energy, 0);
    w.reset(dropIn: false);
    expect(w.isAwake, isFalse);
  });

  test('帧长非正时不推进，且超长帧由子步封顶后仍稳定', () {
    final w = LuckyCircleWorld(count: 10, radius: _r);
    final before = List<double>.of(w.y);
    w.advance(0, stirAngle: 0);
    w.advance(-1, stirAngle: 0);
    expect(w.y, before);
    for (var f = 0; f < 30; f++) {
      w.advance(1, stirAngle: f.toDouble(), engaged: 1);
    }
    expect(_finite(w), isTrue);
    expect(_outside(w), lessThanOrEqualTo(1e-9));
  });

  test('相同种子与帧序列逐位一致，不同种子初始摆放不同', () {
    LuckyCircleWorld run(int seed) {
      final w = LuckyCircleWorld(count: 20, radius: _r, seed: seed);
      var angle = 0.0;
      for (var f = 0; f < 120; f++) {
        angle += 0.05;
        w.advance(f.isEven ? _frame : 0.02,
            stirAngle: angle, engaged: f < 90 ? 1 : 0);
      }
      return w;
    }

    final a = run(1), b = run(1), c = run(2);
    expect(a.x, b.x);
    expect(a.y, b.y);
    expect(a.angle, b.angle);
    expect(a.armAngle, b.armAngle);
    expect(LuckyCircleWorld(count: 20, radius: _r, seed: 1).x,
        isNot(LuckyCircleWorld(count: 20, radius: _r, seed: 2).x));
    expect(c.x, isNot(a.x));
  });

  test('八十三十三一百毫秒混合帧长与拨杆导引下保持稳定', () {
    final w = LuckyCircleWorld(count: 30, radius: _r);
    final dts = [0.008, 0.016, 0.033, 0.1];
    var angle = 0.0;
    for (var f = 0; f < 400; f++) {
      final dt = dts[f % dts.length];
      angle += 3.77 * dt;
      if (f == 150) w.setGuide(3, 0, 1 - _r, 1);
      w.advance(dt, stirAngle: angle, engaged: f < 300 ? 1 : 0);
      expect(_finite(w), isTrue, reason: 'frame $f');
      expect(_outside(w), lessThanOrEqualTo(1e-9), reason: 'frame $f');
    }
  });

  test('导引球在搅拌中与静止堆里都能到达出口，其余球不越界', () {
    for (final stirring in [true, false]) {
      for (var seed = 1; seed <= 12; seed++) {
        final w = LuckyCircleWorld(
            count: 30, radius: _r, seed: seed, dropIn: stirring);
        var angle = stirring ? _stir(w, 1.5) : 0.0;
        final k = (seed * 7) % 30;
        var arrived = false;
        for (var f = 0; f < 60; f++) {
          w.setGuide(k, 0, 1 - _r, math.min(1, f * _frame / 0.35));
          angle += 0.04;
          w.advance(_frame, stirAngle: angle, engaged: stirring ? 0.6 : 0);
          final d =
              math.sqrt(math.pow(w.x[k], 2) + math.pow(w.y[k] - (1 - _r), 2));
          if (d < 0.05) arrived = true;
          expect(_outside(w), lessThanOrEqualTo(1e-9));
        }
        expect(arrived, isTrue, reason: 'stirring=$stirring seed=$seed');
      }
    }
  });

  test('幽灵球不被其他球与拨杆阻挡但仍受容器壁约束', () {
    final w = LuckyCircleWorld(count: 2, radius: _r, gravity: 0);
    w.place(0, 0.5, 0);
    w.place(1, 0.5, 0);
    w.setGuide(1, 0.5, 0, 1);
    for (var f = 0; f < 5; f++) {
      w.advance(_frame, stirAngle: f * 0.1, engaged: 1);
    }
    expect(w.x[1], closeTo(0.5, 1e-9));
    expect(w.y[1], closeTo(0, 1e-9));
    w.setGuide(1, 5, 5, 1);
    for (var f = 0; f < 120; f++) {
      w.advance(_frame, stirAngle: 0);
    }
    expect(_outside(w), lessThanOrEqualTo(1e-9));
  });

  test('移出的球不参与碰撞也不被积分，且不计入动能', () {
    final w = LuckyCircleWorld(count: 2, radius: _r);
    w.place(0, 0, 0.2);
    w.place(1, 0.05, 0.2);
    w.setActive(1, active: false);
    expect(w.isActive(1), isFalse);
    expect(w.isActive(0), isTrue);
    final fixed = (w.x[1], w.y[1]);
    for (var f = 0; f < 120; f++) {
      w.advance(_frame, stirAngle: 0);
    }
    expect((w.x[1], w.y[1]), fixed);
    expect(w.y[0], greaterThan(0.2));
    w.setActive(1, active: true);
    expect(w.isActive(1), isTrue);
  });

  test('球心重合或恰在拨杆中线上时方向确定且不产生非有限数', () {
    final pair = LuckyCircleWorld(count: 2, radius: _r, gravity: 0);
    pair.place(0, 0.1, 0.1);
    pair.place(1, 0.1, 0.1);
    pair.advance(_frame, stirAngle: 0);
    expect(_finite(pair), isTrue);
    expect(pair.x[0], lessThan(pair.x[1]));
    final arm = LuckyCircleWorld(count: 1, radius: _r, gravity: 0);
    arm.place(0, 0.5, 0);
    arm.advance(_frame, stirAngle: 0, engaged: 1);
    expect(_finite(arm), isTrue);
    expect(arm.y[0], greaterThan(0));
  });

  test('复位清除导引、移出标记与拨杆角并重新落入', () {
    final w = LuckyCircleWorld(count: 5, radius: _r);
    w.setGuide(0, 0, 0, 1);
    w.setActive(1, active: false);
    w.advance(_frame, stirAngle: 0, engaged: 1);
    w.advance(_frame, stirAngle: 0.3, engaged: 1);
    expect(w.armAngle, closeTo(0.3, 1e-9));
    w.reset(dropIn: true);
    expect(w.armAngle, 0);
    expect(w.isActive(1), isTrue);
    expect(w.isAwake, isTrue);
    expect(_overlap(w), lessThanOrEqualTo(1e-9));
    for (var f = 0; f < 5; f++) {
      w.advance(_frame, stirAngle: 0);
    }
    expect(w.y[0], greaterThan(-1));
  });

  test('邻近对超过容量上限时丢弃多余的对，仍保持有限坐标且不越界', () {
    final w = LuckyCircleWorld(
        count: 60, radius: 0.05, gravity: 0, armCount: 0, dropIn: false);
    for (var i = 0; i < 60; i++) {
      w.place(i, 0.01 * (i % 3), 0.01 * (i % 5));
    }
    for (var f = 0; f < 5; f++) {
      w.advance(_frame, stirAngle: 0);
    }
    expect(_finite(w), isTrue);
    expect(_outside(w), lessThanOrEqualTo(1e-9));
  });
}
