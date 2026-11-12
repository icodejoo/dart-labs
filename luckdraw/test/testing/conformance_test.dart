import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/testing.dart';
import 'package:luckdraw/wheel.dart';

import '../support/fixtures.dart';
import '../support/grid_fixtures.dart';
import '../support/lots_fixtures.dart';
import '../support/slot_fixtures.dart';

/// 同时用于加减速的合法过冲曲线。
const LuckyEasing _back = CurveEasing(Curves.easeOutBack);

/// 错误缓动的端点偏移量。
const double _endpointOffset = 120;

/// 结果下标的错误原因。
const String _resultMismatch = 'result.index 不一致';

/// 实际画面停点的错误原因。
const String _landingMismatch = '画面最终落点不一致';

/// 用错误端点或 NaN 破坏缓动契约。
final class _BrokenEasing implements LuckyEasing {
  /// 选择非有限值或端点偏移。
  const _BrokenEasing({this.nonFinite = false, this.offset = _endpointOffset});

  /// 是否返回 NaN。
  final bool nonFinite;

  /// 故意偏离端点的量；不改变采样序列本身的单调性。
  final double offset;

  /// 返回故意错误的值。
  @override
  double easeIn(double t, double b, double c, double d) =>
      nonFinite ? double.nan : b + c * (t / d).clamp(0.0, 1.0) + offset;

  /// 对减速施加相同错误。
  @override
  double easeOut(double t, double b, double c, double d) => easeIn(t, b, c, d);
}

/// 使老虎机停在两格之间的错误求解器。
final class _ShiftedSolver implements LuckyStopSolver {
  /// 创建无状态测试求解器。
  const _ShiftedSolver();

  /// 在正确停点上额外偏移四分之一像素。
  @override
  double solve(LuckyStopProblem problem) =>
      const MonotonicStopSolver().solve(problem) + 0.25;
}

/// 将过冲缓动注入给定运动配置。
LuckyMotionOptions _backMotion(LuckyMotionOptions motion) =>
    motion.copyWith(accelerationEasing: _back, decelerationEasing: _back);

/// 核对无头一致性检查的报告与故障诊断。
void main() {
  test('default fixtures settle at every enabled prize and hit its center', () {
    final reports = [
      LuckyConformance.checkWheel(kLuckyWheelFixture),
      LuckyConformance.checkGrid(gridFixture),
      LuckyConformance.checkSlot(slotTestConfig, size: slotTestSize),
      LuckyConformance.checkLots(lotsFixture),
    ];
    for (final report in reports) {
      expect(report.isOk, isTrue, reason: '$report');
      expect(report.problems, isEmpty);
      expect('$report', 'LuckyConformanceReport(OK)');
      expect(() => report.problems.clear(), throwsUnsupportedError);
    }
  });

  test('standard easing passes with a nondefault duration', () {
    final report =
        LuckyConformance.checkEasing(LuckyEasings.quad, duration: 240);
    expect(report.isOk, isTrue);
    expect(report.problems, isEmpty);
    for (final duration in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => LuckyConformance.checkEasing(_back, duration: duration),
          throwsArgumentError);
    }
  });

  test('back easing warns for both methods without failing the report', () {
    final report = LuckyConformance.checkEasing(_back);
    expect(report.isOk, isTrue, reason: '$report');
    expect(report.problems, hasLength(2));
    expect(report.problems.map((problem) => problem.game),
        ['easing.easeIn', 'easing.easeOut']);
    for (final problem in report.problems) {
      expect(problem.severity, LuckyConformanceSeverity.warning);
      expect(problem.index, inInclusiveRange(1, 100));
      expect(problem.expected, startsWith('>= '));
      expect(problem.actual, isNotEmpty);
      expect(problem.reason, contains('可能影响停止求解'));
      expect('$problem', contains('warning ${problem.game}[${problem.index}]'));
    }
    expect('$report', startsWith('LuckyConformanceReport(OK)\nwarning'));
  });

  test('back easing actually settles consistently for all four fixtures', () {
    final reports = [
      LuckyConformance.checkWheel(kLuckyWheelFixture.copyWith(
          options: kLuckyWheelFixture.options.copyWith(
              motion: _backMotion(kLuckyWheelFixture.options.motion)))),
      LuckyConformance.checkGrid(gridFixture.copyWith(
          options: gridFixture.options
              .copyWith(motion: _backMotion(gridFixture.options.motion)))),
      LuckyConformance.checkSlot(slotTestConfig.copyWith(
          options: slotTestConfig.options
              .copyWith(motion: _backMotion(slotTestConfig.options.motion)))),
      LuckyConformance.checkLots(lotsFixture.copyWith(
          options: lotsFixture.options
              .copyWith(motion: _backMotion(lotsFixture.options.motion)))),
    ];
    for (final report in reports) {
      expect(report.isOk, isTrue, reason: '$report');
      expect(report.problems, isEmpty);
    }
  });

  test('wrong endpoints and nonfinite values are errors with readable details',
      () {
    for (final easing in [
      const _BrokenEasing(),
      const _BrokenEasing(offset: -_endpointOffset),
      const _BrokenEasing(nonFinite: true),
    ]) {
      final report = LuckyConformance.checkEasing(easing);
      expect(report.isOk, isFalse);
      expect(
          report.problems.every(
              (problem) => problem.severity == LuckyConformanceSeverity.error),
          isTrue,
          reason: '$report');
      expect(report.problems.where((problem) => problem.reason == '端点不精确'),
          hasLength(4));
      expect('$report', startsWith('LuckyConformanceReport(FAIL)\nerror'));
      expect('$report', contains('expected=2.0, actual='));
      final wheel = LuckyConformance.checkWheel(
          kLuckyWheelFixture.copyWith(
              options: kLuckyWheelFixture.options.copyWith(
                  motion: kLuckyWheelFixture.options.motion.copyWith(
                      accelerationEasing: easing, decelerationEasing: easing))),
          indices: [1]);
      expect(wheel.isOk, isFalse, reason: '$wheel');
      expect(wheel.problems.single.game, 'wheel');
      expect(wheel.problems.single.index, 1);
    }
    final nonFinite =
        LuckyConformance.checkEasing(const _BrokenEasing(nonFinite: true));
    expect(nonFinite.problems.where((problem) => problem.reason == '采样值非有限'),
        hasLength(2));
  });

  test('a long motion times out with target and phase diagnostics', () {
    final config = gridFixture.copyWith(
        options: gridFixture.options.copyWith(
            motion: gridFixture.options.motion
                .copyWith(accelerationTime: const Duration(days: 1))));
    final report = LuckyConformance.checkGrid(config, indices: [2]);
    expect(report.isOk, isFalse);
    final problem = report.problems.single;
    expect(problem.index, 2);
    expect(problem.expected, 'settled');
    expect(problem.actual, 'accelerating');
    expect(problem.reason, '超过 10000 步仍未结算');
  });

  test('disabled prizes are skipped by default and with explicit indices', () {
    const bad =
        LuckyMotionOptions(accelerationEasing: _BrokenEasing(nonFinite: true));
    final reports = [
      LuckyConformance.checkWheel(const WheelConfig(
          prizes: [WheelPrize(disabled: true)],
          options: WheelOptions(motion: bad))),
      LuckyConformance.checkGrid(
          const GridConfig(
              prizes: [GridPrize(x: 0, y: 0, disabled: true)],
              options: GridOptions(motion: bad)),
          indices: [0]),
      LuckyConformance.checkSlot(const SlotConfig(
          prizes: [SlotPrize(disabled: true)],
          reels: [SlotReel()],
          options: SlotOptions(motion: bad))),
      LuckyConformance.checkLots(const LotsConfig(
          sticks: [LotsStick(label: 'disabled', disabled: true)],
          options: LotsOptions(motion: bad))),
      LuckyConformance.checkWheel(const WheelConfig()),
      LuckyConformance.checkGrid(gridFixture, indices: []),
    ];
    for (final report in reports) {
      expect(report.isOk, isTrue, reason: '$report');
      expect(report.problems, isEmpty);
    }
    final enabled = LuckyConformance.checkWheel(const WheelConfig(
        prizes: [WheelPrize()], options: WheelOptions(motion: bad)));
    expect(enabled.isOk, isFalse, reason: '$enabled');
  });

  test('invalid indices and rejected play produce errors', () {
    final invalid = LuckyConformance.checkWheel(kLuckyWheelFixture,
        indices: [-1, kLuckyWheelFixture.prizes.length]);
    expect(invalid.problems.map((problem) => problem.index), [-1, 6]);
    expect(invalid.problems.every((problem) => problem.reason == '目标下标越界'),
        isTrue);
    final empty =
        LuckyConformance.checkGrid(gridFixture, size: Size.zero, indices: [0]);
    expect(empty.isOk, isFalse);
    expect(empty.problems.single.reason, 'play/stop 未接受');
    expect(empty.problems.single.actual, 'false');
  });

  test('grid button covering a prize reports the wrong center hit', () {
    final config = gridFixture.copyWith(buttons: [
      const GridButton(x: 0, y: 0),
    ]);
    final report = LuckyConformance.checkGrid(config, indices: [0]);
    expect(report.isOk, isFalse);
    expect(report.problems.single.reason, '奖品几何中心未命中目标');
    expect(report.problems.single.expected, 'item(0)');
    expect(report.problems.single.actual, '[button(0)]');
  });

  test('lots checks the rotated raised stick even with reveal disabled', () {
    final report = LuckyConformance.checkLots(
        lotsFixture.copyWith(
            options: lotsFixture.options.copyWith(revealOnSettle: false)),
        size: const Size(240, 400),
        indices: [1, 2]);
    expect(report.isOk, isTrue, reason: '$report');
    expect(report.problems, isEmpty);
  });

  test('slot checks shuffled reverse reels against actual scroll positions',
      () {
    final report = LuckyConformance.checkSlot(slotTestConfig.copyWith(reels: [
      const SlotReel(order: [2, 0, 1], direction: -1),
      const SlotReel(order: [1, 2, 0]),
      const SlotReel(order: [0, 1, 2], stopDelay: Duration(milliseconds: 32)),
    ]));
    expect(report.isOk, isTrue, reason: '$report');
    expect(report.problems, isEmpty);
  });

  test('slot reports custom result mismatch and absent or fractional stops',
      () {
    final result = LuckyConformance.checkSlot(
        slotTestConfig.copyWith(winPredicate: (indices, config) => null),
        indices: [1]);
    expect(result.isOk, isFalse);
    expect(result.problems.single.reason, _resultMismatch);
    expect(result.problems.single.actual, 'null');
    final missing = LuckyConformance.checkSlot(
        slotTestConfig.copyWith(reels: [
          const SlotReel(order: [0, 2])
        ]),
        indices: [1]);
    expect(missing.problems.map((problem) => problem.reason),
        [_resultMismatch, _landingMismatch]);
    expect(missing.problems.last.actual, '[2]');
    final fractional = LuckyConformance.checkSlot(
        slotTestConfig.copyWith(
            options: slotTestConfig.options.copyWith(
                motion: slotTestMotion.copyWith(
                    stopSolver: const _ShiftedSolver()))),
        indices: [1]);
    expect(fractional.isOk, isFalse);
    expect(fractional.problems.single.reason, _landingMismatch);
    expect(fractional.problems.single.actual, '[-1, -1, -1]');
  });
}
