import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/src/core/kinematics/body_driver.dart';
import 'package:luckdraw/src/core/kinematics/physics_options.dart';
import 'package:luckdraw/src/core/kinematics/swirl_mixer.dart';

/// 容器像素半径。
const double _radius = 100;

/// 球像素半径，比例零点一一。
const double _body = 11;

/// 创建物理驱动。
LuckyPhysicsDriver _driver(
        {int count = 6,
        LuckyPhysics physics = const LuckyPhysics(),
        double container = _radius}) =>
    LuckyPhysicsDriver(
        physics: physics,
        count: count,
        containerRadius: container,
        bodyRadius: container * 0.11);

/// 推进若干六十赫兹帧。
void _run(LuckyPhysicsDriver d, int frames,
    {double swirl = 0, double mix = 0, List<bool>? excluded}) {
  final flags = excluded ?? List.filled(d.world.count, false);
  for (var f = 0; f < frames; f++) {
    d.advance(1000 / 60, swirl, mix, flags);
  }
}

/// 验证驱动抽象对参数化与物理两种实现的契约。
void main() {
  test('参数化驱动与混合器共用缓冲并逐帧一致，且恒不休眠', () {
    final rest = packCirclesInCircle(
        count: 5, containerRadius: _radius, bodyRadius: _body);
    final mixer = LuckySwirlMixer(
        rest: rest, containerRadius: _radius, bodyRadius: _body);
    final reference = LuckySwirlMixer(
        rest: rest, containerRadius: _radius, bodyRadius: _body);
    final driver = LuckySwirlDriver(mixer);
    expect(identical(driver.x, mixer.x), isTrue);
    expect(identical(driver.y, mixer.y), isTrue);
    expect(identical(driver.angle, mixer.angle), isTrue);
    final excluded = [false, true, false, false, false];
    driver.advance(16, 90, 0.7, excluded);
    reference.update(90, 0.7, excluded: excluded);
    expect(driver.x, reference.x);
    expect(driver.y, reference.y);
    expect(driver.angle, reference.angle);
    expect(driver.isAwake, isFalse);
    driver.reset();
    expect(driver.x, reference.x);
  });

  test('物理驱动输出等于归一化世界乘以容器像素半径', () {
    final d = _driver();
    _run(d, 30);
    for (var i = 0; i < d.world.count; i++) {
      expect(d.x[i], closeTo(d.world.x[i] * _radius, 1e-9));
      expect(d.y[i], closeTo(d.world.y[i] * _radius, 1e-9));
      expect(d.angle[i], d.world.angle[i]);
    }
    expect(d.isAwake, isTrue);
  });

  test('缩放只改换算比例不重置世界，兼容性按球数、半径比与参数判定', () {
    final d = _driver();
    _run(d, 20);
    final before = [for (var i = 0; i < 6; i++) Offset(d.x[i], d.y[i])];
    d.rescale(200);
    for (var i = 0; i < 6; i++) {
      expect(d.x[i], closeTo(before[i].dx * 2, 1e-9));
      expect(d.y[i], closeTo(before[i].dy * 2, 1e-9));
    }
    d.rescale(_radius);
    bool compatible(
            {int count = 6,
            double body = _body,
            double container = _radius,
            LuckyPhysics physics = const LuckyPhysics()}) =>
        d.isCompatible(
            count: count,
            bodyRadius: body,
            containerRadius: container,
            physics: physics);
    expect(compatible(), isTrue);
    expect(compatible(container: 200, body: 22), isTrue);
    expect(compatible(count: 7), isFalse);
    expect(compatible(body: 20), isFalse);
    expect(compatible(physics: const LuckyPhysics(gravity: 5)), isFalse);
  });

  test('被接管的球保持原值并退出模拟，取消接管后重新参与', () {
    final d = _driver();
    _run(d, 20);
    final excluded = List.filled(6, false);
    excluded[2] = true;
    d.x[2] = 12.5;
    d.y[2] = -7.5;
    _run(d, 30, excluded: excluded);
    expect(d.world.isActive(2), isFalse);
    expect(d.x[2], 12.5);
    expect(d.y[2], -7.5);
    _run(d, 1);
    expect(d.world.isActive(2), isTrue);
  });

  test('搅拌角回退时忘记旧指令，拨杆不会因重置而倒转', () {
    final d = _driver();
    _run(d, 5, swirl: 10, mix: 1);
    var swirl = 10.0;
    for (var f = 0; f < 10; f++) {
      swirl += 20;
      d.advance(1000 / 60, swirl, 1, List.filled(6, false));
    }
    final armed = d.armDeg;
    expect(armed, greaterThan(0));
    d.advance(1000 / 60, 0, 0, List.filled(6, false));
    expect(d.armDeg, closeTo(armed, 1e-9));
    d.advance(1000 / 60, 5, 1, List.filled(6, false));
    expect(d.armDeg, closeTo(armed + 5 * 0.3, 1e-9));
  });

  test('导引把目标限制在球心可达范围内并使球趋向目标', () {
    final d = _driver(count: 3);
    _run(d, 10);
    d.guide(0, 0, 500, 1);
    _run(d, 90);
    final distance = math.sqrt(d.x[0] * d.x[0] + d.y[0] * d.y[0]);
    expect(distance, lessThanOrEqualTo(_radius - _body + 1e-6));
    expect(d.y[0], closeTo(_radius - _body, 1));
    d.guide(1, 10, 20, 1);
    _run(d, 90);
    expect(d.x[1], closeTo(10, 1));
    expect(d.y[1], closeTo(20, 1));
  });

  test('重置后重新落入并唤醒，拨杆角换算为度', () {
    final d = _driver();
    for (var f = 0; f < 600 && d.isAwake; f++) {
      d.advance(1000 / 60, 0, 0, List.filled(6, false));
    }
    expect(d.isAwake, isFalse);
    d.reset();
    expect(d.isAwake, isTrue);
    expect(d.y.reduce(math.min), lessThan(-_radius * 0.3));
    _run(d, 3, swirl: 30, mix: 1);
    _run(d, 1, swirl: 60, mix: 1);
    expect(d.armDeg, closeTo(30 * 0.3, 1e-9));
  });
}
