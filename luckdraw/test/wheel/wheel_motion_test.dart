import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/wheel/motion/wheel_motion.dart';
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';
import 'wheel_test_support.dart';

/// 记录求解输入，实际结果仍使用指定的生产求解器。
final class _Solver implements LuckyStopSolver {
  /// 指定内部策略。
  _Solver([this.inner = const UpstreamStopSolver()]);

  /// 内部求解策略。
  final LuckyStopSolver inner;

  /// 最近求解问题。
  late LuckyStopProblem problem;

  /// 返回的位移。
  double displacement = 0;

  /// 求解次数。
  int calls = 0;

  /// 记录并转发求解。
  @override
  double solve(LuckyStopProblem problem) {
    this.problem = problem;
    calls++;
    return displacement = inner.solve(problem);
  }
}

/// 使用默认配置或指定运动选项构造可确定重放的 motion。
WheelMotion _motion(
    {LuckyMotionOptions? options,
    WheelConfig? config,
    SequenceRandom? random}) {
  final motion = WheelMotion(
      random: random ?? SequenceRandom([0.75]),
      picker: const WeightedPrizePicker());
  motion.configure(
      config ??
          kLuckyWheelFixture.copyWith(
              options: WheelOptions(
                  motion: options ??
                      const LuckyMotionOptions(
                          timebase: LuckyTimebase.frame,
                          stopSolver: UpstreamStopSolver()))),
      null);
  return motion;
}

/// 直接以 double 毫秒驱动 motion，不引入 Duration 微秒量化。
void _ticks(WheelMotion motion, double end,
    {double step = 16, double from = 0}) {
  for (var t = from; t <= end; t += step) {
    motion.tick(t, t == 0 ? 0 : step);
  }
}

/// 验证逐帧移植、时间模式及边界行为。
void main() {
  group('WheelMotion frame timebase', () {
    test('first tick after play has zero interval and does not move', () {
      final motion = _motion();
      expect(motion.start(), isTrue);
      motion.tick(123, 16);
      expect(motion.frame.rotateDeg, 0);
      expect(motion.phase, LuckyPhase.accelerating);
    });
    test('acceleration adds easeIn(startInterval) remainder 360 per tick', () {
      final motion = _motion();
      motion.start();
      motion.tick(0, 0);
      var expected = 0.0;
      for (var t = 16.0; t <= 2560; t += 16) {
        expected += LuckyEasings.quad.easeIn(t, 0, 20, 2500).remainder(360);
        motion.tick(t, 16);
        expect(motion.frame.rotateDeg, expected);
      }
    });
    test('measures fps as startInterval / frame count after the first tick',
        () {
      final solver = _Solver();
      final motion = _motion(
          options: LuckyMotionOptions(
              timebase: LuckyTimebase.frame, stopSolver: solver));
      motion.start();
      _ticks(motion, 2520, step: 20);
      motion.requestStop(2);
      motion.tick(2540, 20);
      motion.tick(2560, 20);
      expect(solver.problem.frameMs, 20);
      expect(solver.calls, 1);
    });
    test('enters cruising after accelerationTime and adds speed per tick', () {
      final motion = _motion();
      motion.start();
      _ticks(motion, 2512);
      expect(motion.phase, LuckyPhase.cruising);
      final before = motion.frame.rotateDeg;
      motion.tick(2528, 16);
      expect(motion.frame.rotateDeg, before + 20);
    });
    test('stop during acceleration keeps accelerating until accelerationTime',
        () {
      final motion = _motion();
      motion.start();
      _ticks(motion, 480);
      expect(motion.requestStop(4), isTrue);
      expect(motion.phase, LuckyPhase.accelerating);
      _ticks(motion, 2496, from: 496);
      expect(motion.phase, LuckyPhase.accelerating);
      motion.tick(2512, 16);
      expect(motion.phase, LuckyPhase.decelerating);
    });
    test('deceleration follows easeOut from stopDeg by endDeg', () {
      final solver = _Solver();
      final motion = _motion(
          options: LuckyMotionOptions(
              timebase: LuckyTimebase.frame, stopSolver: solver));
      motion.start();
      _ticks(motion, 2528);
      motion.requestStop(2);
      motion.tick(2544, 16);
      motion.tick(2560, 16);
      for (var t = 2576.0; t <= 5072; t += 16) {
        motion.tick(t, 16);
        expect(
            motion.frame.rotateDeg,
            LuckyEasings.quad.easeOut(
                t - 2560, solver.problem.start, solver.displacement, 2500));
      }
      expect(motion.phase, LuckyPhase.settled);
    });
    test(
        'final angle puts the target sector middle under the pointer plus stopRange',
        () {
      final config = kLuckyWheelFixture.copyWith(
          options: const WheelOptions(
              offsetDegree: 30,
              stopRange: 0.8,
              motion: LuckyMotionOptions(timebase: LuckyTimebase.frame)));
      final motion = _motion(config: config);
      motion.start();
      motion.requestStop(2);
      _ticks(motion, 5200);
      expect(motion.phase, LuckyPhase.settled);
      final targetMiddle =
          (motion.frame.rotateDeg + 30 + 2 * 60 + 30).remainder(360);
      expect(targetMiddle, closeTo((0.75 * 60 - 30) * 0.8, 1e-10));
      expect(motion.takeResult()!.index, 2);
      expect(motion.takeResult(), isNull);
    });
    test('stopRange draws exactly one random number per stop in upstream order',
        () {
      final random = SequenceRandom([0.5, 0.75, 0.125]);
      final motion = _motion(random: random);
      motion.start();
      motion.requestStop(null);
      expect(motion.frame.targetIndex, 2);
      _ticks(motion, 5200);
      expect(motion.phase, LuckyPhase.settled);
      expect(random.nextDouble(), 0.125);
    });
    test('index beyond prize count wraps modulo prize count', () {
      final motion = _motion();
      motion.start();
      expect(motion.requestStop(14), isTrue);
      expect(motion.frame.targetIndex, 2);
    });
    test(
        'upstream baseline w01 through w06 matches every numeric frame bit for bit',
        () {
      for (var number = 1; number <= 6; number++) {
        final id = 'w0$number';
        final spec =
            jsonDecode(File('tool/parity/cases/$id.json').readAsStringSync())
                as Map<String, Object?>;
        final rawConfig = spec['config']! as Map<String, Object?>;
        final defaults =
            rawConfig['defaultConfig'] as Map<String, Object?>? ?? {};
        final prizes = rawConfig['prizes']! as List<Object?>;
        final config = WheelConfig(
            prizes: [
              for (final p in prizes)
                WheelPrize(
                    weight: ((p! as Map<String, Object?>)['range'] as num?)
                        ?.toDouble())
            ],
            options: WheelOptions(
                offsetDegree:
                    (defaults['offsetDegree'] as num?)?.toDouble() ?? 0,
                stopRange: (defaults['stopRange'] as num?)?.toDouble() ?? 0,
                motion: LuckyMotionOptions(
                    timebase: LuckyTimebase.frame,
                    stopSolver: const UpstreamStopSolver(),
                    speed: (defaults['speed'] as num?)?.toDouble() ?? 20,
                    decelerationTime: Duration(
                        milliseconds:
                            (defaults['decelerationTime'] as num?)?.toInt() ??
                                2500))));
        final random = SequenceRandom((spec['random']! as List<Object?>)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList());
        final motion = _motion(config: config, random: random);
        final baseline = jsonDecode(
            File('test/parity/baselines/$id/frames.json')
                .readAsStringSync()) as Map<String, Object?>;
        final frames = baseline['frames']! as List<Object?>;
        final actions =
            (spec['script']! as List<Object?>).cast<Map<String, Object?>>();
        for (var i = 0; i < frames.length; i++) {
          for (final action in actions.where((a) => a['frame'] == i)) {
            if (action['action'] == 'play') {
              motion.start();
            } else {
              motion.requestStop(action['index'] as int?);
            }
          }
          motion.tick(i * 16.0, i == 0 ? 0 : 16);
          final expected = frames[i]! as Map<String, Object?>;
          expect(motion.frame.rotateDeg,
              (expected['rotateDeg']! as num).toDouble(),
              reason: '$id frame $i');
        }
        expect(
            random.nextDouble(),
            (spec['random']!
                as List<Object?>)[baseline['randomConsumed']! as int]);
      }
    });
  });
  group('WheelMotion time timebase', () {
    test(
        'right endpoint integration retains the documented intermediate sampling difference',
        () {
      final positions = <double>[];
      for (var hz = 60; hz <= 120; hz += 60) {
        final motion = _motion(options: const LuckyMotionOptions());
        motion.start();
        final count = (2.5 * hz).toInt();
        for (var i = 0; i <= count; i++) {
          motion.tick(i * 1000 / hz, i == 0 ? 0 : 1000 / hz);
        }
        final expected =
            20 * (count + 1) * (2 * count + 1) / (6 * count) * 60 / hz;
        expect(motion.frame.rotateDeg, closeTo(expected, 1e-9));
        positions.add(motion.frame.rotateDeg);
      }
      expect((positions.first - positions.last).abs(),
          closeTo(5.0166666666667, 1e-9));
    });
    test('covers the same angle at 60Hz and 120Hz within 0.5 degrees', () {
      final angles = <double>[];
      for (final hz in [60, 120]) {
        final motion = _motion(options: const LuckyMotionOptions());
        motion.start();
        motion.requestStop(3);
        for (var i = 0; i <= hz * 6; i++) {
          motion.tick(i * 1000 / hz, i == 0 ? 0 : 1000 / hz);
        }
        expect(motion.phase, LuckyPhase.settled);
        angles.add(motion.frame.rotateDeg);
      }
      expect((angles.first - angles.last).abs(), lessThanOrEqualTo(0.5));
    });
    test('matches frame timebase within 1e-6 degrees at 1000/60 ms steps', () {
      final time = _motion(options: const LuckyMotionOptions());
      final frame = _motion(
          options: const LuckyMotionOptions(timebase: LuckyTimebase.frame));
      time.start();
      frame.start();
      time.requestStop(2);
      frame.requestStop(2);
      for (var i = 0; i < 350; i++) {
        final t = i * kLuckyReferenceFrameMs;
        time.tick(t, i == 0 ? 0 : kLuckyReferenceFrameMs);
        frame.tick(t, i == 0 ? 0 : kLuckyReferenceFrameMs);
        expect(time.frame.rotateDeg, closeTo(frame.frame.rotateDeg, 1e-6));
      }
    });
  });
  group('WheelMotion edges', () {
    test(
        'weighted sectors settle under the pointer with offset and random stopRange',
        () {
      const config = WheelConfig(
          prizes: [
            WheelPrize(),
            WheelPrize(sectorWeight: 3),
            WheelPrize(sectorWeight: 2)
          ],
          options: WheelOptions(
              offsetDegree: -37, stopRange: 0.8, motion: kWheelTestMotion));
      for (var i = 0; i < config.prizes.length; i++) {
        final motion = _motion(config: config);
        motion.start();
        motion.requestStop(i);
        _ticks(motion, 240);
        expect(motion.phase, LuckyPhase.settled);
        expect(motion.frame.pointerIndex, i);
        expect(motion.takeResult()!.index, i);
      }
    });
    test('upstream zero sentinel settles without claiming pointer alignment',
        () {
      final solver = _Solver();
      final motion = _motion(
          config: wheelTestConfig(
              motion: kWheelTestMotion.copyWith(
                  speed: 1,
                  timebase: LuckyTimebase.frame,
                  stopSolver: solver)));
      motion.start();
      motion.requestStop(2);
      _ticks(motion, 240);
      expect(solver.displacement, 0);
      expect(solver.calls, 1);
      expect(motion.phase, LuckyPhase.settled);
      expect(motion.frame.pointerIndex, isNot(2));
      expect(motion.takeResult()!.index, 2);
    });
    test('monotonic solver never rotates backwards on the #419 grid', () {
      var comparedPositive = 0;
      for (final speed in [1.0, 5.0, 10.0, 20.0]) {
        for (final duration in [64, 200, 600, 1200, 2500]) {
          for (final offset in [0.0, 60.0, 180.0, 300.0]) {
            final solver = _Solver(const MonotonicStopSolver());
            final config = wheelTestConfig(
                motion: LuckyMotionOptions(
                    speed: speed,
                    accelerationTime: const Duration(milliseconds: 64),
                    decelerationTime: Duration(milliseconds: duration),
                    timebase: LuckyTimebase.frame,
                    stopSolver: solver));
            final motion = _motion(
                config: config.copyWith(
                    options: config.options.copyWith(offsetDegree: offset)));
            motion.start();
            motion.requestStop(2);
            var previous = 0.0;
            for (var i = 0; i <= (duration + 160) / 16; i++) {
              motion.tick(i * 16.0, i == 0 ? 0 : 16);
              expect(motion.frame.rotateDeg, greaterThanOrEqualTo(previous));
              previous = motion.frame.rotateDeg;
            }
            expect(motion.phase, LuckyPhase.settled);
            final upstream = const UpstreamStopSolver().solve(solver.problem);
            if (upstream > 0) {
              expect(solver.displacement, upstream);
              comparedPositive++;
            }
          }
        }
      }
      expect(comparedPositive, greaterThan(0));
    });
    test('upstream solver reproduces backward rotation on the #419 grid', () {
      var backwards = 0;
      final speeds = [1.0, 5.0, 10.0];
      final durations = [64, 200, 600, 1200];
      for (final speed in speeds) {
        for (final duration in durations) {
          final baseConfig = wheelTestConfig(
              motion: LuckyMotionOptions(
                  speed: speed,
                  accelerationTime: const Duration(milliseconds: 64),
                  decelerationTime: Duration(milliseconds: duration),
                  timebase: LuckyTimebase.frame,
                  stopSolver: const UpstreamStopSolver()));
          final motion = _motion(
              config: baseConfig.copyWith(
                  options: baseConfig.options.copyWith(offsetDegree: 300)));
          motion.start();
          motion.requestStop(2);
          var previous = 0.0;
          for (var i = 0; i <= (duration + 160) / 16; i++) {
            motion.tick(i * 16.0, i == 0 ? 0 : 16);
            if (motion.frame.rotateDeg < previous) backwards++;
            previous = motion.frame.rotateDeg;
          }
        }
      }
      expect(backwards, greaterThan(0));
    });
    test('upstream solver with zero displacement still settles (DEV-07)', () {
      final solver = _Solver();
      final options = kWheelTestMotion.copyWith(
          speed: 1, timebase: LuckyTimebase.frame, stopSolver: solver);
      final config = wheelTestConfig(motion: options);
      final motion = _motion(config: config);
      motion.start();
      _ticks(motion, 64);
      // 下个匀速 tick 后目标中线恰在指针；候选 i=1 为零。
      final offset = 360 - 2 * 60 - (motion.frame.rotateDeg + 1) - 30;
      motion.configure(
          config.copyWith(
              options: config.options.copyWith(offsetDegree: offset)),
          null);
      motion.requestStop(2);
      _ticks(motion, 224, from: 80);
      expect(solver.displacement, 0);
      expect(solver.calls, 1);
      expect(motion.phase, LuckyPhase.settled);
      expect(motion.frame.pointerIndex, 2);
    });
    test('idle spin rotates at idleSpinSpeed and play accelerates from it', () {
      final motion = _motion();
      expect(motion.idleSpin(), isTrue);
      motion.tick(0, 0);
      motion.tick(16, 16);
      expect(motion.frame.rotateDeg, 4);
      expect(motion.idleSpin(), isFalse);
      expect(motion.start(), isTrue);
      motion.tick(32, 16);
      expect(motion.frame.rotateDeg, 6);
      expect(motion.phase, LuckyPhase.accelerating);
      expect(motion.cancel(), isTrue);
      expect(motion.takeResult()!.cancelled, isTrue);
      motion.reset();
      expect(motion.frame.rotateDeg, 0);
    });
    test('zero prizes refuses to play', () {
      final motion = _motion(config: const WheelConfig());
      expect(motion.start(), isFalse);
      expect(motion.phase, LuckyPhase.idle);
    });
    test(
        'structural config change during deceleration is deferred until settled',
        () {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      controller.play();
      controller.stop(4);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.decelerating);
      controller.configure(const WheelConfig(prizes: [WheelPrize()]), null,
          structural: true);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
      expect(controller.lastResult!.index, 4);
      expect(controller.lastResult!.prize, kLuckyWheelFixture.prizes[4]);
      controller.play();
      controller.stop(4);
      expect(controller.frame.targetIndex, 0);
    });
    test(
        'a 10 minute frame gap keeps the angle finite and still settles (#308)',
        () {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      controller.play();
      controller.stop(2);
      host.clock.advanceFrames(2, step: const Duration(minutes: 10));
      expect(controller.rotateDeg.isFinite, isTrue);
      wheelAdvanceTo(controller, host.clock, LuckyPhase.settled);
      expect(controller.lastResult!.index, 2);
    });
    test('onSectorPassed fires once per boundary crossing', () {
      final host = WheelTestHost();
      final controller = wheelTestController(host);
      controller.play();
      host.clock.advanceFrames(1);
      var previous = controller.frame.pointerIndex;
      var crossings = host.passed.length;
      for (var i = 0; i < 100; i++) {
        host.clock.advanceFrames(1);
        if (controller.frame.pointerIndex != previous) crossings++;
        previous = controller.frame.pointerIndex;
      }
      expect(host.passed.length, crossings);
      expect(crossings, greaterThan(5));
    });
    test('extra revolutions add whole turns to the final angle', () {
      final normal = _motion();
      final extra = _motion();
      normal.start();
      extra.start();
      normal.requestStop(2);
      extra.requestStop(2, extraRevolutions: 3);
      _ticks(normal, 5200);
      _ticks(extra, 5200);
      expect(extra.frame.rotateDeg - normal.frame.rotateDeg, 1080);
      expect(extra.frame.pointerIndex, normal.frame.pointerIndex);
      expect(() {
        normal.start();
        normal.requestStop(2, extraRevolutions: -1);
      }, throwsArgumentError);
    });
  });
}
