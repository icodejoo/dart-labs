import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 构造上游等分转盘停止候选，保留 wheel.ts:453 的运算顺序。
LuckyStopProblem _wheel(
    {double speed = 20,
    double deceleration = 2500,
    double frame = 16,
    int n = 6,
    int target = 0,
    double start = 123.4,
    int direction = 1}) {
  final sweep = 360 / n;
  return LuckyStopProblem(
      start: start,
      candidate: (i) =>
          (360 * i - target * sweep - start - 0 + 0 - sweep / 2) * direction,
      cruiseSpeed: speed,
      frameMs: frame,
      decelerationMs: deceleration,
      easing: LuckyEasings.quad,
      selection: LuckyStopSelection.nearest,
      direction: direction);
}

/// 在测试内独立执行上游 while 循环，不调用被测求解器或缓动。
double _upstreamReference(LuckyStopProblem p) {
  var previousSpeed = 0.0;
  var previous = 0.0;
  for (var i = 1; i <= 100000; i++) {
    final candidate = p.candidate(i);
    final x = (p.frameMs >= p.decelerationMs ? p.decelerationMs : p.frameMs) /
        p.decelerationMs;
    final current =
        (-candidate * x * (x - 2) + p.start - p.start) * p.direction;
    if (current > p.cruiseSpeed) {
      return p.cruiseSpeed - previousSpeed > current - p.cruiseSpeed
          ? candidate
          : previous;
    }
    previous = candidate;
    previousSpeed = current;
  }
  throw StateError('测试输入应在上游循环内收敛');
}

/// 遍历任务卡要求的完整 #419 网格。
Iterable<LuckyStopProblem> _grid() sync* {
  for (final speed in [1.0, 5.0, 10.0, 20.0, 40.0]) {
    for (final duration in [150.0, 300.0, 1000.0, 2500.0]) {
      for (final frame in <double>[16.0, 1000 / 60, 8.33]) {
        for (final n in [2, 6, 12]) {
          for (final target in <int>[0, n - 1]) {
            for (final start in [0.0, 123.4, 359.9, 5000.0]) {
              yield _wheel(
                  speed: speed,
                  deceleration: duration,
                  frame: frame,
                  n: n,
                  target: target,
                  start: start);
            }
          }
        }
      }
    }
  }
}

/// 首帧恒定在起点，用于验证迭代耗尽。
final class _FlatEasing implements LuckyEasing {
  /// 返回起点。
  @override
  double easeIn(double t, double b, double c, double d) => b;

  /// 返回起点。
  @override
  double easeOut(double t, double b, double c, double d) => b;
}

/// 验证逐位上游求解和单调方向约束。
void main() {
  final createUpstream = UpstreamStopSolver.new;
  final upstream = createUpstream();
  final createMonotonic = MonotonicStopSolver.new;
  final monotonic = createMonotonic();
  group('stop solver boundaries', () {
    test('firstExceeding skips a candidate exactly at cruise speed', () {
      const threshold = 100.0;
      const expectedCalls = 2;
      for (final solver in <LuckyStopSolver>[upstream, monotonic]) {
        final visited = <int>[];
        final problem = LuckyStopProblem(
            start: 0,
            candidate: (i) {
              visited.add(i);
              return threshold * i;
            },
            cruiseSpeed: threshold,
            frameMs: threshold,
            decelerationMs: threshold,
            easing: LuckyEasings.quad,
            selection: LuckyStopSelection.firstExceeding);
        expect(solver.solve(problem), threshold * expectedCalls);
        expect(visited, List<int>.generate(expectedCalls, (i) => i + 1));
      }
    });
    test('nearest searches past equal speed and uses the first finite fallback',
        () {
      const threshold = 100.0;
      const fallback = threshold / 2;
      for (final solver in <LuckyStopSolver>[upstream, monotonic]) {
        final visited = <int>[];
        final candidates = <double>[fallback, threshold, double.nan];
        final problem = LuckyStopProblem(
            start: 0,
            candidate: (i) {
              visited.add(i);
              return candidates[i - 1];
            },
            cruiseSpeed: threshold,
            frameMs: threshold,
            decelerationMs: threshold,
            easing: LuckyEasings.quad,
            selection: LuckyStopSelection.nearest);
        expect(solver.solve(problem), fallback);
        expect(visited, List<int>.generate(candidates.length, (i) => i + 1));
      }
    });
  });
  group('UpstreamStopSolver', () {
    test(
        'picks the first candidate whose first-frame speed exceeds cruise speed or the closer previous one',
        () {
      for (final p in _grid()) {
        expect(upstream.solve(p), _upstreamReference(p));
      }
      final first = LuckyStopProblem(
          start: 0,
          candidate: (i) => i * 100.0,
          cruiseSpeed: 80,
          frameMs: 100,
          decelerationMs: 100,
          easing: LuckyEasings.quad,
          selection: LuckyStopSelection.nearest);
      expect(upstream.solve(first), 100);
      final tied = LuckyStopProblem(
          start: 0,
          candidate: first.candidate,
          cruiseSpeed: 50,
          frameMs: 100,
          decelerationMs: 100,
          easing: LuckyEasings.quad,
          selection: LuckyStopSelection.nearest);
      expect(upstream.solve(tied), 0);
      expect(monotonic.solve(tied), 100);
    });
    test('reproduces negative displacement when deceleration is short (#419)',
        () {
      final p = _wheel(speed: 1, deceleration: 150, n: 2, target: 1);
      expect(upstream.solve(p), p.candidate(1));
      expect(upstream.solve(p), lessThan(0));
      expect(monotonic.solve(p), p.candidate(2));
    });
    test(
        'firstExceeding selection matches the upstream slot carve for both directions',
        () {
      final wrongDirection = LuckyStopProblem(
          start: 1000,
          candidate: (i) => 200 + (600 * i) - 1000,
          cruiseSpeed: 1,
          frameMs: 16,
          decelerationMs: 2500,
          easing: LuckyEasings.quad,
          selection: LuckyStopSelection.firstExceeding);
      expect(upstream.solve(wrongDirection), -200);
      expect(monotonic.solve(wrongDirection), 400);
      for (final direction in <int>[1, -1]) {
        for (final slotSpeed in <double>[20.0, -20.0]) {
          final p = LuckyStopProblem(
              start: 500,
              candidate: (i) => 100 * 2 + (600 * i * direction) - 500,
              cruiseSpeed: slotSpeed,
              frameMs: 16,
              decelerationMs: 2500,
              easing: LuckyEasings.quad,
              selection: LuckyStopSelection.firstExceeding,
              direction: direction);
          var i = 0;
          double candidate;
          double current;
          do {
            i++;
            candidate = 100 * 2 + (600 * i * direction) - 500;
            const x = 16 / 2500;
            current = -candidate * x * (x - 2) + 500 - 500;
          } while (!(current.abs() > slotSpeed));
          expect(upstream.solve(p), candidate);
          expect(monotonic.solve(p) * direction, greaterThan(0));
        }
      }
    });
  });
  group('MonotonicStopSolver', () {
    test('equals upstream whenever the upstream displacement is positive', () {
      var checked = 0;
      for (final p in _grid()) {
        final expected = _upstreamReference(p);
        if (expected > 0) {
          expect(monotonic.solve(p), expected);
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });
    test(
        'never returns a displacement against the direction across the parameter grid',
        () {
      for (final p in _grid()) {
        final forward = monotonic.solve(p);
        expect(forward, greaterThan(0));
        final reverse = LuckyStopProblem(
            start: -p.start,
            candidate: (i) => -p.candidate(i),
            cruiseSpeed: p.cruiseSpeed,
            frameMs: p.frameMs,
            decelerationMs: p.decelerationMs,
            easing: p.easing,
            selection: p.selection,
            direction: -1);
        final displacement = monotonic.solve(reverse);
        expect(displacement, -forward);
        for (var tick = 0; tick <= 10; tick++) {
          final t = p.decelerationMs * tick / 10;
          final position =
              p.easing.easeOut(t, p.start, forward, p.decelerationMs);
          if (tick > 0) {
            final previous = p.easing.easeOut(
                p.decelerationMs * (tick - 1) / 10,
                p.start,
                forward,
                p.decelerationMs);
            expect(position, greaterThanOrEqualTo(previous));
          }
        }
      }
    });
    test(
        'falls back after maxIterations with non-finite inputs instead of hanging',
        () {
      var calls = 0;
      final exhausted = LuckyStopProblem(
          start: 0,
          candidate: (i) {
            calls++;
            return i * 10.0;
          },
          cruiseSpeed: double.infinity,
          frameMs: 16,
          decelerationMs: 2500,
          easing: _FlatEasing(),
          selection: LuckyStopSelection.nearest);
      expect(monotonic.solve(exhausted), 10);
      expect(calls, 100000);
      final nonfinite = LuckyStopProblem(
          start: 0,
          candidate: (_) => double.nan,
          cruiseSpeed: 20,
          frameMs: 16,
          decelerationMs: 2500,
          easing: LuckyEasings.quad,
          selection: LuckyStopSelection.nearest);
      expect(monotonic.solve(nonfinite), 0);
      final lateInvalid = LuckyStopProblem(
          start: 0,
          candidate: (i) => i == 1 ? 10 : double.infinity,
          cruiseSpeed: 20,
          frameMs: 16,
          decelerationMs: 2500,
          easing: LuckyEasings.quad,
          selection: LuckyStopSelection.nearest);
      expect(monotonic.solve(lateInvalid), 10);
      final invalidRaw = LuckyStopProblem(
          start: double.nan,
          candidate: (_) => 15,
          cruiseSpeed: 20,
          frameMs: 16,
          decelerationMs: 2500,
          easing: LuckyEasings.quad,
          selection: LuckyStopSelection.nearest);
      expect(monotonic.solve(invalidRaw), 15);
      for (final badFrame in <double>[0.0, -1.0, double.nan, double.infinity]) {
        final p = LuckyStopProblem(
            start: 0,
            candidate: (i) => i * 360.0,
            cruiseSpeed: 20,
            frameMs: badFrame,
            decelerationMs: 2500,
            easing: LuckyEasings.quad,
            selection: LuckyStopSelection.nearest);
        final reference = LuckyStopProblem(
            start: 0,
            candidate: p.candidate,
            cruiseSpeed: 20,
            frameMs: 1000 / 60,
            decelerationMs: 2500,
            easing: LuckyEasings.quad,
            selection: LuckyStopSelection.nearest);
        expect(monotonic.solve(p), monotonic.solve(reference));
      }
    });
    test(
        'decel first-frame speed differs from cruise by at most half a period increment (#205)',
        () {
      var checked = 0;
      for (final p in _grid()) {
        // IMP-01 不接受负候选；半周期界只对无方向修正的最近候选成立。
        if (_upstreamReference(p) <= 0) continue;
        final displacement = monotonic.solve(p);
        final raw = p.easing
                .easeOut(p.frameMs, p.start, displacement, p.decelerationMs) -
            p.start;
        final increment = (p.easing.easeOut(
                    p.frameMs, p.start, p.candidate(2), p.decelerationMs) -
                p.start) -
            (p.easing.easeOut(
                    p.frameMs, p.start, p.candidate(1), p.decelerationMs) -
                p.start);
        expect((raw - p.cruiseSpeed).abs(),
            lessThanOrEqualTo(increment.abs() / 2 + 1e-9));
        checked++;
      }
      expect(checked, greaterThan(0));
    });
    test('direction constraint can exceed the half period speed bound', () {
      final p = _wheel(speed: 1, deceleration: 150, n: 2, target: 1);
      final x = p.frameMs / p.decelerationMs;
      final raw = -monotonic.solve(p) * x * (x - 2) + p.start - p.start;
      final increment = 360 * (2 * x - x * x);
      expect((raw - p.cruiseSpeed).abs(), greaterThan(increment / 2));
      expect(monotonic.solve(p), greaterThan(0));
    });
  });
}
