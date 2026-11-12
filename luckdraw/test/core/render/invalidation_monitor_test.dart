import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/wheel.dart';

import '../../grid/grid_render_fixtures.dart';
import '../../support/capsule_fixtures.dart';
import '../../support/fixtures.dart';
import '../../support/grid_fixtures.dart';
import '../../support/lots_fixtures.dart';
import '../../support/lotto_fixtures.dart';
import '../../support/number_wheel_fixtures.dart';
import '../../support/slot_fixtures.dart';

/// 告警阈值，用于断言第八次才报告。
const int _threshold = 8;

/// 一个告警窗口。
const Duration _window = Duration(seconds: 2);

/// 在有界画布中构建真实玩法。
Widget _host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
        data: const MediaQueryData(),
        child: Center(child: SizedBox(width: 300, height: 400, child: child))));

/// 只修改运动配置值，让各玩法沿现有路径失效。
LuckyMotionOptions _motion(LuckyMotionOptions base, int revision) =>
    base.copyWith(speed: base.speed + revision);

/// 为转盘替换帧监听器，验证重建 painter 的配置失效路径。
LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> _wheelSurface(
    int revision, LuckyFrameNotifier notifier) {
  final config = kLuckyWheelFixture.copyWith(
      options: kLuckyWheelFixture.options.copyWith(
          motion: _motion(kLuckyWheelFixture.options.motion, revision)));
  final input = LuckyLayoutInput.headless(const Size(300, 300));
  final layout = const WheelGame().computeLayout(config, input);
  input.measurer.dispose();
  return LuckySurfaceData(
      config: config,
      layout: layout,
      layoutGeneration: 0,
      frame: WheelFrame(),
      frameListenable: notifier,
      images: const CapsuleEmptyImages(),
      imagesListenable: notifier,
      layers: const [],
      hooks: const LuckyHooks(),
      devicePixelRatio: 1,
      textDirection: TextDirection.ltr,
      performance: const LuckyPerformanceOptions(),
      isAnimating: false);
}

/// 验证窗口、节流、独立实例和各玩法接入行为。
void main() {
  late List<String> warnings;
  setUp(() {
    warnings = [];
    final previous = LuckyInvalidationMonitor.debugOnWarning;
    LuckyInvalidationMonitor.debugOnWarning = warnings.add;
    addTearDown(() => LuckyInvalidationMonitor.debugOnWarning = previous);
  });

  test('第八次失效告警，同一窗口只报告一次并包含修复建议', () {
    final now = DateTime.utc(2026);
    final monitor = LuckyInvalidationMonitor('lots', now: () => now);
    for (var i = 0; i < _threshold - 1; i++) {
      monitor.recordInvalidation();
    }
    expect(warnings, isEmpty);
    monitor.recordInvalidation();
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('[lots]'));
    expect(warnings.single, contains('config 每次构建都不相等，缓存被反复重建'));
    expect(warnings.single, contains('build 里内联创建了 painter/闭包/缓动对象'));
    expect(warnings.single, contains('static final 或稳定引用'));
    for (var i = 0; i < _threshold; i++) {
      monitor.recordInvalidation();
    }
    expect(warnings, hasLength(1));
  });

  test('包含两秒边界，窗口过期后重新累计八次才能再次告警', () {
    var now = DateTime.utc(2026);
    final monitor = LuckyInvalidationMonitor('slot', now: () => now);
    for (var i = 0; i < _threshold - 1; i++) {
      monitor.recordInvalidation();
    }
    now = now.add(_window);
    monitor.recordInvalidation();
    expect(warnings, hasLength(1));
    now = now.add(_window + const Duration(microseconds: 1));
    for (var i = 0; i < _threshold - 1; i++) {
      monitor.recordInvalidation();
    }
    expect(warnings, hasLength(1));
    monitor.recordInvalidation();
    expect(warnings, hasLength(2));
    expect(warnings.last, contains('[slot]'));
  });

  test('滚动窗口丢弃过期记录，不按固定时间分桶', () {
    var now = DateTime.utc(2026);
    final monitor = LuckyInvalidationMonitor('wheel', now: () => now);
    for (var i = 0; i < _threshold - 1; i++) {
      monitor.recordInvalidation();
    }
    now = now.add(_window + const Duration(microseconds: 1));
    monitor.recordInvalidation();
    expect(warnings, isEmpty);
    for (var i = 0; i < _threshold - 1; i++) {
      monitor.recordInvalidation();
    }
    expect(warnings, hasLength(1));
  });

  test('每个实例独立计数，默认时钟与空钩子仍可输出告警', () {
    final first = LuckyInvalidationMonitor('grid');
    final second = LuckyInvalidationMonitor('grid');
    for (var i = 0; i < _threshold - 1; i++) {
      first.recordInvalidation();
      second.recordInvalidation();
    }
    expect(warnings, isEmpty);
    first.recordInvalidation();
    expect(warnings, hasLength(1));
    second.recordInvalidation();
    expect(warnings, hasLength(2));
    LuckyInvalidationMonitor.debugOnWarning = null;
    final noHook = LuckyInvalidationMonitor('capsule');
    for (var i = 0; i < _threshold; i++) {
      noHook.recordInvalidation();
    }
    expect(warnings, hasLength(2));
  });

  testWidgets('build 内每次创建 painter 闭包只告警一次，稳定引用不告警', (tester) async {
    final recordings = <int>[];

    /// 模拟业务 build 中捕获局部值的新闭包。
    LotsConfig config(int revision) => lotsFixture.copyWith(
        style: lotsFixture.style.copyWith(
            backgroundPainter: (canvas, layout) => recordings.add(revision)));

    final stable = config(0);
    for (var i = 0; i <= _threshold * 2; i++) {
      await tester.pumpWidget(_host(LuckyLots(config: stable)));
    }
    expect(warnings, isEmpty);
    expect(recordings, [0]);
    for (var i = 1; i <= _threshold * 2; i++) {
      await tester.pumpWidget(_host(LuckyLots(config: config(i))));
    }
    expect(recordings, List<int>.generate(_threshold * 2 + 1, (i) => i));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('[lots]'));
    await tester.pumpWidget(const SizedBox());
  });

  final games = <String, Widget Function(int)>{
    'wheel': (revision) => LuckyWheel(
        config: kLuckyWheelFixture.copyWith(
            options: kLuckyWheelFixture.options.copyWith(
                motion: _motion(kLuckyWheelFixture.options.motion, revision)))),
    'grid': (revision) => LuckyGrid(
        config: gridFixture.copyWith(
            options: gridFixture.options.copyWith(
                motion: _motion(gridFixture.options.motion, revision)))),
    'slot': (revision) => LuckySlotMachine(
        config: slotTestConfig.copyWith(
            options: slotTestConfig.options.copyWith(
                motion: _motion(slotTestConfig.options.motion, revision)))),
    'lots': (revision) => LuckyLots(
        config: lotsFixture.copyWith(
            options: lotsFixture.options.copyWith(
                motion: _motion(lotsFixture.options.motion, revision)))),
    'lotto': (revision) => LuckyLotto(
        config: lottoConfig.copyWith(
            options: lottoConfig.options.copyWith(
                motion: _motion(lottoConfig.options.motion, revision)))),
    'number_wheel': (revision) => LuckyNumberWheel(
        config: numberWheelFixture.copyWith(
            options: numberWheelFixture.options.copyWith(
                motion: _motion(numberWheelFixture.options.motion, revision)))),
    'capsule': (revision) => LuckyCapsuleMachine(
        config: capsuleConfig.copyWith(
            options: capsuleConfig.options.copyWith(
                motion: _motion(capsuleConfig.options.motion, revision)))),
  };

  /// 稳定配置重建不告警，配置连续变化才告警；[game] 取 games 中的键。
  Future<void> churn(WidgetTester tester, String game) async {
    for (var i = 0; i <= _threshold; i++) {
      await tester.pumpWidget(_host(games[game]!(0)));
    }
    expect(warnings, isEmpty);
    for (var i = 1; i < _threshold; i++) {
      await tester.pumpWidget(_host(games[game]!(i)));
    }
    expect(warnings, isEmpty);
    await tester.pumpWidget(_host(games[game]!(_threshold)));
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('[$game]'));
    await tester.pumpWidget(_host(games[game]!(_threshold + 1)));
    expect(warnings, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('wheel：稳定配置重建不告警，配置连续变化才告警', (tester) => churn(tester, 'wheel'));
  testWidgets('grid：稳定配置重建不告警，配置连续变化才告警', (tester) => churn(tester, 'grid'));
  testWidgets('slot：稳定配置重建不告警，配置连续变化才告警', (tester) => churn(tester, 'slot'));
  testWidgets('lots：稳定配置重建不告警，配置连续变化才告警', (tester) => churn(tester, 'lots'));
  testWidgets('lotto：稳定配置重建不告警，配置连续变化才告警', (tester) => churn(tester, 'lotto'));
  testWidgets('number_wheel：稳定配置重建不告警，配置连续变化才告警',
      (tester) => churn(tester, 'number_wheel'));
  testWidgets(
      'capsule：稳定配置重建不告警，配置连续变化才告警', (tester) => churn(tester, 'capsule'));

  /// 替换监听器时只统计同时发生的配置失效；[game] 为 wheel 或 grid。
  Future<void> swap(WidgetTester tester, String game) async {
    final notifiers = <LuckyFrameNotifier>[];
    addTearDown(() {
      for (final notifier in notifiers) {
        notifier.dispose();
      }
    });

    /// 每次替换监听器，进入新建 painter 的原有分支。
    Future<void> rebuild(int revision) async {
      final notifier = LuckyFrameNotifier();
      notifiers.add(notifier);
      await tester.pumpWidget(_host(Builder(builder: (context) {
        if (game == 'wheel') {
          return const WheelCanvasRenderer()
              .buildSurface(context, _wheelSurface(revision, notifier));
        }
        return const GridCanvasRenderer().buildSurface(
            context,
            gridSurfaceData(
                config: gridFixture.copyWith(
                    options: gridFixture.options.copyWith(
                        motion: _motion(gridFixture.options.motion, revision))),
                frames: notifier,
                imageChanges: notifier));
      })));
    }

    for (var i = 0; i <= _threshold; i++) {
      await rebuild(0);
    }
    expect(warnings, isEmpty);
    for (var i = 1; i < _threshold; i++) {
      await rebuild(i);
    }
    expect(warnings, isEmpty);
    await rebuild(_threshold);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('[$game]'));
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('wheel：替换监听器时只统计同时发生的配置失效', (tester) => swap(tester, 'wheel'));
  testWidgets('grid：替换监听器时只统计同时发生的配置失效', (tester) => swap(tester, 'grid'));
}
