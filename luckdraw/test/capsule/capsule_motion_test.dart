import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/motion/capsule_motion.dart';

import '../support/capsule_fixtures.dart';

/// 仅实现默认成员探针，验证 LuckyMotion 的缺省时间上限契约。
final class _DefaultMotion extends LuckyMotion<CapsuleConfig, CapsuleLayout,
    CapsuleFrame, LuckyResult<CapsulePrize>> {
  /// 创建探针。
  _DefaultMotion();

  /// 未实现成员不应被调用。
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('仅验证基类缺省时间上限');
}

/// 按参考帧推进到指定阶段。
void advanceTo(CapsuleMotion m, CapsuleStage stage) {
  for (var i = 0; i < 1000 && m.frame.stage != stage; i++) {
    m.tick(0, kLuckyReferenceFrameMs);
  }
  expect(m.frame.stage, stage);
}

/// 推进到匀速。
void cruise(CapsuleMotion m) {
  expect(m.start(), isTrue);
  for (var i = 0; i < 60; i++) {
    m.tick(0, kLuckyReferenceFrameMs);
  }
  expect(m.phase, LuckyPhase.cruising);
}

/// 验证细分阶段、缓冲与时间边界。
void main() {
  late CapsuleMotion m;
  setUp(() {
    m = CapsuleMotion()..configure(capsuleConfig, capsuleLayout());
  });
  group('CapsuleMotion', () {
    test('mix intensity follows the swirl speed ratio', () {
      expect(m.start(), isTrue);
      m.tick(100, 100);
      final first = m.frame.swirlDeg;
      expect(m.frame.mix, closeTo(0.015625, 1e-12));
      m.tick(200, 100);
      expect(m.frame.mix, closeTo(0.0625, 1e-12));
      expect(m.frame.swirlDeg - first,
          closeTo(12 * 0.0625 * 100 / kLuckyReferenceFrameMs, 1e-9));
      for (var i = 0; i < 10; i++) {
        m.tick(0, 100);
      }
      expect(m.frame.mix, 1);
      expect(m.frame.knobDeg, m.frame.swirlDeg * 0.25);
    });
    test('deceleration starts at cruise speed without a jump', () {
      cruise(m);
      expect(m.requestStop(0), isTrue);
      m.tick(0, kLuckyReferenceFrameMs);
      final start = m.frame.swirlDeg;
      expect(m.frame.stage, CapsuleStage.settlingMix);
      m.tick(0, kLuckyReferenceFrameMs);
      expect(m.frame.swirlDeg - start, closeTo(12, 1e-9));
      expect(m.frame.mix, inInclusiveRange(0, 1));
    });
    test(
        'drop starts only after the swirl settles and follows the precomputed path',
        () {
      cruise(m);
      m.requestStop(0);
      advanceTo(m, CapsuleStage.dropping);
      expect(m.frame.mix, 0);
      expect(m.phase, LuckyPhase.decelerating);
      final l = capsuleLayout(), i = m.frame.droppedCapsule;
      expect(m.frame.x[i] + l.globeCenter.dx, closeTo(l.exit.dx, 1e-9));
      expect(m.frame.y[i] + l.globeCenter.dy, closeTo(l.exit.dy, 1e-9));
      m.tick(0, 100);
      final expected = l.dropPosition(1 / 36);
      expect(m.frame.dropProgress, closeTo(1 / 36, 1e-12));
      expect(m.frame.x[i] + l.globeCenter.dx, closeTo(expected.dx, 1e-9));
      expect(m.frame.y[i] + l.globeCenter.dy, closeTo(expected.dy, 1e-9));
      advanceTo(m, CapsuleStage.revealing);
      expect(m.frame.x[i] + l.globeCenter.dx, closeTo(l.tray.center.dx, 1e-9));
      expect(m.frame.y[i] + l.globeCenter.dy, closeTo(l.tray.center.dy, 1e-9));
    });
    test(
        'the dropped capsule belongs to the target prize and is the closest to the exit',
        () {
      cruise(m);
      m.requestStop(1);
      advanceTo(m, CapsuleStage.settlingMix);
      final l = capsuleLayout(), i = m.frame.droppedCapsule;
      expect(l.capsules[i], 1);
      final distance = (l.rest[i] + l.globeCenter - l.exit).distance;
      for (var j = 0; j < l.rest.length; j++) {
        if (l.capsules[j] == 1) {
          expect(distance,
              lessThanOrEqualTo((l.rest[j] + l.globeCenter - l.exit).distance));
        }
      }
    });
    test('reveal scales the card from 0 to 1 then settles', () {
      cruise(m);
      m.requestStop(1);
      advanceTo(m, CapsuleStage.revealing);
      expect(m.frame.revealProgress, 0);
      m.tick(0, 100);
      expect(m.frame.revealProgress, closeTo(0.578125, 1e-12));
      advanceTo(m, CapsuleStage.done);
      expect(m.frame.revealProgress, 1);
      expect(m.phase, LuckyPhase.settled);
      expect(m.takeResult()?.prize, capsuleConfig.prizes[1]);
      expect(m.takeResult(), isNull);
    });
    test('revealOnSettle false settles right after the drop', () {
      final c = capsuleConfig.copyWith(
          options: capsuleConfig.options.copyWith(revealOnSettle: false));
      m.configure(c, capsuleLayout(c));
      cruise(m);
      m.requestStop(0);
      advanceTo(m, CapsuleStage.done);
      expect(m.frame.revealProgress, 0);
      expect(m.frame.dropProgress, 1);
      expect(m.takeResult()?.index, 0);
    });
    test('capsule positions are written into reused Float64List buffers', () {
      final x = m.frame.x, y = m.frame.y, a = m.frame.angle;
      cruise(m);
      for (var i = 0; i < 20; i++) {
        final oldX = x.toList(), oldY = y.toList();
        m.tick(0, 1);
        expect(identical(x, m.frame.x), isTrue);
        expect(identical(y, m.frame.y), isTrue);
        expect(identical(a, m.frame.angle), isTrue);
        for (var j = 0; j < x.length; j++) {
          expect(
              math.sqrt(x[j] * x[j] + y[j] * y[j]),
              lessThanOrEqualTo(capsuleLayout().globeRadius -
                  capsuleLayout().capsuleRadius +
                  1e-9));
          expect(
              math.sqrt(
                  math.pow(x[j] - oldX[j], 2) + math.pow(y[j] - oldY[j], 2)),
              lessThan(10));
        }
      }
    });
    test('next play restores the dropped capsule to the pile', () {
      cruise(m);
      m.requestStop(0);
      advanceTo(m, CapsuleStage.done);
      expect(m.start(), isTrue);
      expect(m.frame.droppedCapsule, -1);
      expect(m.frame.dropProgress, 0);
      final l = capsuleLayout();
      for (var i = 0; i < l.rest.length; i++) {
        expect(m.frame.x[i], l.rest[i].dx);
        expect(m.frame.y[i], l.rest[i].dy);
      }
    });
    test('a 10 minute frame gap keeps positions finite and still settles', () {
      cruise(m);
      m.requestStop(0);
      m.tick(600000, 600000);
      expect(m.phase, LuckyPhase.decelerating);
      final values = [...m.frame.x, ...m.frame.y, ...m.frame.angle];
      for (final v in values) {
        expect(v.isFinite, isTrue);
      }
      advanceTo(m, CapsuleStage.done);
      expect(m.takeResult()?.index, 0);
    });
  });
  test(
      'CapsuleMotion edges > empty layouts zero speed fallback colors and frame timebase',
      () {
    final empty = CapsuleMotion();
    expect(empty.start(), isFalse);
    expect(empty.tick(0, 10), LuckyMotionEvents.none);
    expect(empty.idleSpin(), isFalse);
    empty.configure(capsuleConfig, null);
    empty.reset();
    expect(empty.frame.mix, 0);
    final config = capsuleConfig.copyWith(
        capsules: [0],
        options: capsuleConfig.options.copyWith(
            motion: capsuleConfig.options.motion
                .copyWith(speed: 0, timebase: LuckyTimebase.frame)));
    m.configure(config, capsuleLayout(config));
    m.configure(config, capsuleLayout(config));
    expect(m.start(), isTrue);
    expect(m.start(), isFalse);
    expect(m.idleSpin(), isFalse);
    m.tick(0, 0);
    expect(m.frame.mix, 0);
    for (var i = 0; i < 9; i++) {
      m.tick(0, 100);
    }
    expect(m.requestStop(3), isTrue);
    advanceTo(m, CapsuleStage.done);
    expect(m.takeResult()?.index, 1);
    expect(m.frame.droppedCapsule, 0);
    m.reset();
    expect(m.idleSpin(), isTrue);
    expect(m.idleSpin(), isFalse);
    expect(m.requestStop(0), isFalse);
    m.tick(0, 10);
    expect(m.frame.swirlDeg, greaterThan(0));
    expect(m.cancel(), isTrue);
    expect(m.takeResult(), isNull);
    expect(m.cancel(), isFalse);
    expect(m.requestStop(-1), isFalse);
    expect(m.start(), isTrue);
    expect(m.requestStop(null), isTrue);
    expect(m.takeResult()?.cancelled, isTrue);
  });
  test('CapsuleMotion edges > SPI defaults and detaching layout remain safe',
      () {
    expect(_DefaultMotion().maxFrameDelta, const Duration(milliseconds: 100));
    expect(m.passedReel, 0);
    expect(m.passedIndex, -1);
    m.configure(capsuleConfig, null);
    expect(m.start(), isFalse);
    expect(m.tick(0, 10), LuckyMotionEvents.none);
  });
  test(
      'CapsuleMotion edges > mixer packing compression boundary projection and repeatability obey contracts',
      () {
    final rest =
        packCirclesInCircle(count: 100, containerRadius: 100, bodyRadius: 60);
    expect(rest, hasLength(100));
    expect(rest,
        packCirclesInCircle(count: 100, containerRadius: 100, bodyRadius: 60));
    final a = LuckySwirlMixer(rest: rest, containerRadius: 100, bodyRadius: 60),
        b = LuckySwirlMixer(rest: rest, containerRadius: 100, bodyRadius: 60);
    final x = a.x, y = a.y, angle = a.angle;
    for (var t = 0; t < 720; t += 7) {
      a.update(t.toDouble(), 1);
      b.update(t.toDouble(), 1);
      expect(a.x, b.x);
      expect(a.y, b.y);
      expect(a.angle, b.angle);
      for (var i = 0; i < x.length; i++) {
        expect(
            math.sqrt(x[i] * x[i] + y[i] * y[i]), lessThanOrEqualTo(40 + 1e-9));
      }
    }
    expect(identical(a.x, x), isTrue);
    expect(identical(a.y, y), isTrue);
    expect(identical(a.angle, angle), isTrue);
  });
  test(
      'CapsuleMotion edges > frame cadence freezes during deceleration and resize preserves the drop',
      () {
    final config = capsuleConfig.copyWith(
        options: capsuleConfig.options.copyWith(
            motion: capsuleConfig.options.motion
                .copyWith(timebase: LuckyTimebase.frame)));
    m.configure(config, capsuleLayout(config));
    m.start();
    for (var i = 0; i < 45; i++) {
      m.tick(0, 20);
    }
    m.requestStop(1);
    m.tick(0, 20);
    final start = m.frame.swirlDeg;
    m.tick(0, 20);
    expect(m.frame.swirlDeg - start, closeTo(12, 1e-9));
    m.tick(0, 1);
    final easing = config.options.motion.decelerationEasing,
        decMs = config.options.motion.decelerationMs;
    final c = config.options.motion.speed / easing.easeOut(20, 0, 1, decMs);
    expect(m.frame.swirlDeg, easing.easeOut(21, start, c, decMs));
    advanceTo(m, CapsuleStage.dropping);
    m.tick(0, 100);
    final progress = m.frame.dropProgress;
    final l = capsuleLayout(config, const Size(150, 250));
    m.configure(config, l);
    expect(m.frame.dropProgress, progress);
    final point = l.dropPosition(progress), index = m.frame.droppedCapsule;
    expect(m.frame.x[index] + l.globeCenter.dx, closeTo(point.dx, 1e-9));
    expect(m.frame.y[index] + l.globeCenter.dy, closeTo(point.dy, 1e-9));
    advanceTo(m, CapsuleStage.revealing);
    final revealLayout = capsuleLayout(config, const Size(200, 330));
    m.configure(config, revealLayout);
    expect(m.frame.x[index] + revealLayout.globeCenter.dx,
        closeTo(revealLayout.tray.center.dx, 1e-9));
    expect(m.frame.y[index] + revealLayout.globeCenter.dy,
        closeTo(revealLayout.tray.center.dy, 1e-9));
    advanceTo(m, CapsuleStage.done);
    final doneLayout = capsuleLayout(config, const Size(225, 375));
    m.configure(config, doneLayout);
    expect(m.frame.stage, CapsuleStage.done);
    expect(m.frame.x[index] + doneLayout.globeCenter.dx,
        closeTo(doneLayout.tray.center.dx, 1e-9));
    expect(m.frame.y[index] + doneLayout.globeCenter.dy,
        closeTo(doneLayout.tray.center.dy, 1e-9));
    expect(m.takeResult()?.index, 1);
  });
}
