import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/src/grid/motion/grid_motion.dart' show GridMotion;
import 'package:luckdraw/testing.dart';

import '../support/grid_fixtures.dart';
import 'grid_controller_test.dart' show gridHost;

/// 默认巡航速度。
const double _defaultSpeed = 20;

/// 三次换格每秒对应的 speed。
const double _reducedSpeed = 2;

/// 比系统限制宽松的显式上限。
const double _looseLimit = 6;

/// 比系统限制严格的显式上限。
const double _strictLimit = 1.5;

/// 宽松显式上限对应的 speed。
const double _looseSpeed = 4;

/// 严格显式上限对应的 speed。
const double _strictSpeed = 1;

/// 已低于所有上限的速度。
const double _slowSpeed = 0.5;

/// 测试画布的逻辑边长。
const double _side = 300;

/// 指定的停止目标。
const int _target = 4;

/// 约 60Hz 的测试帧长。
const Duration _frame = Duration(microseconds: 16667);

/// 两秒内的参考帧数。
const int _twoSecondFrames = 120;

/// 只在测试中暴露控制器真正应用的配置。
final class _GridController extends GridController {
  /// 当前状态机配置，供解析与引用断言。
  GridConfig get appliedConfig => (motion as GridMotion).config;
}

/// 挂载真实宿主；null 表示没有 MediaQuery。
Future<_GridController> _mount(WidgetTester tester, GridConfig config,
    {bool? disableAnimations}) async {
  final controller = _GridController();
  final grid = LuckyGrid(
      config: config, controller: controller, width: _side, height: _side);
  await tester.pumpWidget(gridHost(disableAnimations == null
      ? grid
      : MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: grid)));
  return controller;
}

/// 读取控制器实际使用的配置，并释放宿主。
Future<GridConfig> _resolve(WidgetTester tester,
    {GridOptions options = const GridOptions(),
    bool? disableAnimations}) async {
  final controller = await _mount(
      tester, gridFixture.copyWith(options: options),
      disableAnimations: disableAnimations);
  final applied = controller.appliedConfig;
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  return applied;
}

/// 逐帧计数实际 activeIndex 变更；包含启动后的第一个高亮。
Future<int> _changes(WidgetTester tester,
    {required bool disableAnimations}) async {
  final controller =
      await _mount(tester, gridFixture, disableAnimations: disableAnimations);
  var previous = controller.frame.activeIndex;
  var changes = 0;
  expect(controller.play(), isTrue);
  await tester.pump();
  for (var frame = 0; frame < _twoSecondFrames; frame++) {
    await tester.pump(_frame);
    final current = controller.frame.activeIndex;
    if (current != previous) changes++;
    previous = current;
  }
  expect(controller.phase.value.isMoving, isTrue);
  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  return changes;
}

/// 九宫格减少动效的解析、实际频率与落点契约。
void main() {
  test('新选项默认值、副本、相等性和哈希包含限速策略', () {
    const original = GridOptions();
    expect(original.maxStepsPerSecond, isNull);
    expect(original.reduceMotion, GridReduceMotion.system);
    expect(kLuckyReducedStepsPerSecond, 3);
    final capped = original.copyWith(maxStepsPerSecond: _looseLimit);
    final reduced = original.copyWith(reduceMotion: GridReduceMotion.always);
    expect(capped, isNot(original));
    expect(reduced, isNot(original));
    expect(capped.hashCode, isNot(original.hashCode));
    expect(reduced.hashCode, isNot(original.hashCode));
    expect(capped.copyWith(), capped);
    expect(capped.copyWith().hashCode, capped.hashCode);
    expect(reduced.copyWith(), reduced);
    expect(reduced.copyWith().hashCode, reduced.hashCode);
  });

  testWidgets('system 无 MediaQuery 时原样传递配置引用', (tester) async {
    final controller = await _mount(tester, gridFixture);
    expect(controller.appliedConfig, same(gridFixture));
    expect(controller.appliedConfig.options.motion.speed, _defaultSpeed);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('system 且 disableAnimations 为 false 时不限速', (tester) async {
    final controller =
        await _mount(tester, gridFixture, disableAnimations: false);
    expect(controller.appliedConfig, same(gridFixture));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('system 且 disableAnimations 为 true 时封顶', (tester) async {
    final applied = await _resolve(tester, disableAnimations: true);
    expect(applied.options.motion.speed, _reducedSpeed);
    expect(applied.options.maxStepsPerSecond, kLuckyReducedStepsPerSecond);
  });

  testWidgets('always 且 disableAnimations 为 false 时封顶', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(reduceMotion: GridReduceMotion.always),
        disableAnimations: false);
    expect(applied.options.motion.speed, _reducedSpeed);
  });

  testWidgets('always 且 disableAnimations 为 true 时封顶', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(reduceMotion: GridReduceMotion.always),
        disableAnimations: true);
    expect(applied.options.motion.speed, _reducedSpeed);
  });

  testWidgets('never 且 disableAnimations 为 false 时不限速', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(reduceMotion: GridReduceMotion.never),
        disableAnimations: false);
    expect(applied.options.motion.speed, _defaultSpeed);
  });

  testWidgets('never 且 disableAnimations 为 true 时保留原配置引用', (tester) async {
    final config = gridFixture.copyWith(
        options: const GridOptions(reduceMotion: GridReduceMotion.never));
    final controller = await _mount(tester, config, disableAnimations: true);
    expect(controller.appliedConfig, same(config));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('仅显式上限按参考帧单位封顶巡航与待机速度', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(
            maxStepsPerSecond: _looseLimit,
            motion: LuckyMotionOptions(idleSpinSpeed: _defaultSpeed)));
    expect(applied.options.motion.speed, _looseSpeed);
    expect(applied.options.motion.idleSpinSpeed, _looseSpeed);
  });

  testWidgets('never 仍应用显式上限', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(
            reduceMotion: GridReduceMotion.never,
            maxStepsPerSecond: _strictLimit),
        disableAnimations: true);
    expect(applied.options.motion.speed, _strictSpeed);
    expect(applied.options.motion.idleSpinSpeed, _strictSpeed);
  });

  testWidgets('system 未减少动效时仍应用显式上限', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(maxStepsPerSecond: _looseLimit),
        disableAnimations: false);
    expect(applied.options.motion.speed, _looseSpeed);
  });

  testWidgets('减少动效与宽松显式上限并存时取三次', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(maxStepsPerSecond: _looseLimit),
        disableAnimations: true);
    expect(applied.options.motion.speed, _reducedSpeed);
    expect(applied.options.maxStepsPerSecond, kLuckyReducedStepsPerSecond);
  });

  testWidgets('减少动效与严格显式上限并存时取较小值且不提高低速', (tester) async {
    final applied = await _resolve(tester,
        options: const GridOptions(
            reduceMotion: GridReduceMotion.always,
            maxStepsPerSecond: _strictLimit,
            motion: LuckyMotionOptions(
                speed: _slowSpeed, idleSpinSpeed: _slowSpeed)));
    expect(applied.options.maxStepsPerSecond, _strictLimit);
    expect(applied.options.motion.speed, _slowSpeed);
    expect(applied.options.motion.idleSpinSpeed, _slowSpeed);
  });

  testWidgets('减少动效启动两秒内高亮至多七次且默认配置明显更多', (tester) async {
    final reduced = await _changes(tester, disableAnimations: true);
    final normal = await _changes(tester, disableAnimations: false);
    expect(reduced, inInclusiveRange(1, 7));
    expect(normal, greaterThan(reduced * 2));
  });

  testWidgets('封顶配置经一致性检查仍落在每个目标且待机可直接启动', (tester) async {
    final controller =
        await _mount(tester, gridFixture, disableAnimations: true);
    final applied = controller.appliedConfig;
    expect(applied.options.motion.speed, _reducedSpeed);
    final report = LuckyConformance.checkGrid(applied);
    expect(report.isOk, isTrue, reason: '$report');
    expect(report.problems, isEmpty);
    expect(controller.idleSpin(), isTrue);
    await tester.pump();
    await tester.pump(_frame);
    expect(controller.frame.activeIndex, -1);
    expect(controller.play(), isTrue);
    expect(controller.stop(_target), isTrue);
    await tester.pump();
    for (var frame = 0; frame < _twoSecondFrames * 3; frame++) {
      await tester.pump(_frame);
    }
    expect(controller.phase.value, LuckyPhase.settled);
    expect(controller.frame.activeIndex, _target);
    expect(controller.lastResult?.prize, gridFixture.prizes[_target]);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
