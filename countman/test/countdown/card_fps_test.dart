// ignore_for_file: invalid_use_of_internal_member

import 'package:countman/countman.dart';
import 'package:countman/src/core/fps.dart';
import 'package:countman/src/widgets/card_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/manual_clock.dart';
import '../support/vsync_simulator.dart';

/// 无额外动画的测试宿主，便于准确统计共享调度回调。
Widget _host(Widget child, {bool visible = true}) => Directionality(
  textDirection: TextDirection.ltr,
  child: TickerMode(enabled: visible, child: child),
);

/// 通过公开 painter 检查模型与内部进度，避免依赖 State 私有字段。
FlipCardPainter _painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<FlipCardPainter>()
    .first;

void main() {
  late ManualCountmanClock clock;
  setUp(() => clock = installManualClock());
  tearDown(() {
    Countman.destroy();
    Countman.fps = null;
    debugRefreshRateHz = null;
  });

  for (final type in CountdownType.values) {
    testWidgets('$type 精确时间线、提交与共享回调，结束后休眠', (t) async {
      const leg = Duration(milliseconds: 200);
      await t.pumpWidget(
        _host(
          CardCountdown(
            to: const Duration(seconds: 10, milliseconds: 500),
            duration: leg,
            style: CardCountdownStyle(transitionType: type),
          ),
        ),
      );
      await t.pump();
      clock.advance(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      final p = _painter(t);
      final progress = p.controller as CardProgress;
      expect(progress.value, 0);
      expect(progress.status, AnimationStatus.forward);
      expect(progress.isAnimating, isTrue);
      expect(p.model.committed.last, 0);
      expect(p.model.target!.last, 9);
      // 卡片动画仅登记 Countman 的一个共享 transient callback。
      expect(t.binding.transientCallbackCount, 1);
      clock.advance(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(progress.value, closeTo(.5, 1e-9));
      expect(_painter(t), same(p));
      clock.advance(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 100));
      expect(progress.value, 1);
      if (type == CountdownType.calendar) {
        expect(progress.status, AnimationStatus.reverse);
        expect(p.model.reversePhase, isTrue);
        expect(p.model.committed.last, 0);
        clock.advance(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 100));
        expect(progress.value, closeTo(.5, 1e-9));
        clock.advance(const Duration(milliseconds: 100));
        await t.pump(const Duration(milliseconds: 100));
        expect(progress.value, 0);
        expect(progress.status, AnimationStatus.dismissed);
      } else {
        expect(progress.status, AnimationStatus.completed);
      }
      expect(p.model.committed.last, 9);
      expect(p.model.target, isNull);
      expect(progress.isAnimating, isFalse);
      expect(Countman.isSleeping, isTrue);
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(Countman.isRunning, isFalse);
    });
  }

  testWidgets('进度 stop/reset、部分路程、时长变更及状态通知与控制器一致', (t) async {
    final progress = CardProgress(duration: const Duration(milliseconds: 200));
    final statuses = <AnimationStatus>[];
    final endpointStates = <(AnimationStatus, bool)>[];
    progress.addStatusListener(statuses.add);
    progress.addListener(() {
      if (progress.value == 1) {
        endpointStates.add((progress.status, progress.isAnimating));
      }
    });
    progress.forward(from: .5);
    await t.pump();
    clock.advance(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(progress.value, 1);
    expect(endpointStates, [(AnimationStatus.completed, false)]);
    expect(statuses, [AnimationStatus.forward, AnimationStatus.completed]);
    progress.forward(from: 0);
    expect(statuses.skip(2), [
      AnimationStatus.dismissed,
      AnimationStatus.forward,
    ]);
    await t.pump();
    clock.advance(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
    expect(progress.value, .25);
    progress.stop();
    expect(progress.status, AnimationStatus.forward);
    expect(progress.isAnimating, isFalse);
    progress.duration = const Duration(milliseconds: 400);
    progress.reverse();
    await t.pump();
    clock.advance(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(progress.value, 0);
    expect(progress.status, AnimationStatus.dismissed);
    progress.reset();
    expect(progress.value, 0);
    progress.duration = const Duration(microseconds: -1);
    progress.forward();
    expect(progress.value, 1);
    expect(progress.isAnimating, isFalse);
    progress.dispose();
    await t.pump();
    expect(Countman.isRunning, isFalse);
  });

  testWidgets('50 张 calendar 卡限帧降低实际出帧；不限帧只用共享回调', (t) async {
    debugRefreshRateHz = 60;
    Future<double> run(double? fps, {bool continuous = false}) async {
      final controllers = List.generate(50, (_) => CountdownController());
      await t.pumpWidget(
        _host(
          Wrap(
            children: [
              for (var i = 0; i < 50; i++)
                SizedBox(
                  width: 60,
                  height: 40,
                  child: FittedBox(
                    child: CardCountdown(
                      to: const Duration(minutes: 5),
                      fps: fps,
                      controller: controllers[i],
                      // 长动画冻结秒目标，采样跨过往返边界，验证持续运动时 60→30。
                      duration: continuous ? const Duration(seconds: 4) : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      await t.pump();
      if (continuous) {
        clock.advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        for (final controller in controllers) {
          controller.pause();
        }
      }
      // 先预热到翻牌中，再采 5 秒，避免初始静止的整秒影响统计。
      await simulateVsync(t, clock, () => 0, seconds: 2);
      expect(t.binding.transientCallbackCount, lessThanOrEqualTo(1));
      final stats = await simulateVsync(t, clock, () => 0);
      debugPrint('CARD VSYNC continuous=$continuous fps=$fps $stats');
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(Countman.isRunning, isFalse);
      Countman.destroy();
      return stats.fps;
    }

    final free = await run(null);
    final capped = await run(30);
    expect(free, inInclusiveRange(53, 61));
    expect(capped, inInclusiveRange(28.5, 31.5));
    expect(capped, lessThan(free * .65));
    final continuousFree = await run(null, continuous: true);
    final continuousCapped = await run(30, continuous: true);
    expect(continuousFree, inInclusiveRange(59, 61));
    expect(continuousCapped, inInclusiveRange(28.5, 31.5));
    expect(continuousCapped, lessThan(continuousFree * .55));
  });

  testWidgets('动态实例、插件与全局上限保持时间线与端点', (t) async {
    final plugin = Countdown(name: 'card-cap', fps: 20);
    Widget card(double? fps) => _host(
      CardCountdown(
        plugin: plugin,
        fps: fps,
        to: const Duration(seconds: 10, milliseconds: 500),
        duration: const Duration(milliseconds: 400),
        style: const CardCountdownStyle(transitionType: CountdownType.slide),
      ),
    );
    await t.pumpWidget(card(null));
    await t.pump();
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    final p = _painter(t);
    var updates = 0;
    p.controller.addListener(() => updates++);
    Future<void> advance(int ms) async {
      clock.advance(Duration(milliseconds: ms));
      await t.pump(Duration(milliseconds: ms));
    }

    await advance(1); // 首次显示。
    final before = updates;
    await advance(10);
    expect(updates, before); // 插件 20fps。
    await t.pumpWidget(card(60));
    await advance(10);
    expect(updates, greaterThan(before));
    expect(_painter(t).controller, same(p.controller));
    await t.pumpWidget(card(null));
    await advance(379);
    expect(p.controller.value, 1);
    expect(p.model.target, isNull);
    await t.pumpWidget(const SizedBox());
    Countman.destroy();
    // 没有插件覆盖时运行时全局配置由任务直接继承。
    final progress = CardProgress(duration: const Duration(seconds: 1));
    progress.forward();
    Countman.fps = 10;
    await t.pump();
    expect(Countman.isSleeping, isTrue);
    Countman.fps = null;
    await t.pump();
    expect(Countman.isSleeping, isFalse);
    progress.dispose();
    await t.pump();
    expect(Countman.isRunning, isFalse);
  });

  testWidgets('Provider 换插件时同步活动进度上限，不重启翻牌或丢失暂停', (t) async {
    debugRefreshRateHz = 60;
    final first = Countdown(name: 'card-first', fps: 20);
    final second = Countdown(name: 'card-second', fps: 10);
    final controller = CountdownController();
    final card = CardCountdown(
      to: const Duration(seconds: 10, milliseconds: 500),
      controller: controller,
      duration: const Duration(seconds: 4),
    );
    Widget tree(Countdown plugin) =>
        _host(CountdownProvider(plugin: plugin, child: card));
    await t.pumpWidget(tree(first));
    await t.pump();
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    controller.pause();
    final progress = _painter(t).controller;
    final target = _painter(t).model.target;
    final oldStats = await simulateVsync(t, clock, () => 0, seconds: 1);
    expect(oldStats.fps, inInclusiveRange(19, 21));
    final before = progress.value;
    await t.pumpWidget(tree(second));
    expect(_painter(t).controller, same(progress));
    expect(_painter(t).model.target, same(target));
    expect(controller.isPaused, isTrue);
    expect(first.activeTaskCount, 0);
    expect(second.activeTaskCount, 1);
    await t.pump();
    final newStats = await simulateVsync(t, clock, () => 0, seconds: 1);
    expect(newStats.fps, inInclusiveRange(9, 11));
    expect(progress.value, greaterThan(before));
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(Countman.isRunning, isFalse);
  });

  testWidgets('隐藏落定、停止出帧；恢复显示当前值；中途 dispose 无任务泄漏', (t) async {
    final controller = CountdownController();
    final card = CardCountdown(
      to: const Duration(seconds: 10, milliseconds: 500),
      controller: controller,
    );
    await t.pumpWidget(_host(card));
    await t.pump();
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    clock.advance(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(_painter(t).controller.value, greaterThan(0));
    await t.pumpWidget(_host(card, visible: false));
    await t.pump();
    expect(_painter(t).controller.value, 0);
    expect(_painter(t).model.target, isNull);
    expect(controller.runState, CountmanRunState.running);
    final hidden = await simulateVsync(t, clock, () => 0, seconds: 2);
    expect(hidden.frames, 0);
    expect(Countman.isSleeping, isTrue);
    await t.pumpWidget(_host(card));
    await t.pump();
    expect(_painter(t).model.committed.last, 7);
    expect(_painter(t).model.target, isNull);
    clock.advance(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    final progress = _painter(t).controller as CardProgress;
    expect(progress.isAnimating, isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(progress.isAnimating, isFalse);
    expect(Countman.isRunning, isFalse);
    expect(t.binding.transientCallbackCount, 0);
    expect(t.takeException(), isNull);
  });

  for (final reduce in [false, true]) {
    testWidgets('零时长/减弱动画立即提交 reduceMotion=$reduce', (t) async {
      t.binding.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduce);
      addTearDown(
        t.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      for (final type in CountdownType.values) {
        await t.pumpWidget(
          _host(
            CardCountdown(
              key: ValueKey(type),
              to: const Duration(seconds: 10, milliseconds: 500),
              duration: reduce
                  ? const Duration(milliseconds: 450)
                  : Duration.zero,
              style: CardCountdownStyle(transitionType: type),
            ),
          ),
        );
        await t.pump();
        clock.advance(const Duration(seconds: 1));
        await t.pump(const Duration(seconds: 1));
        final p = _painter(t);
        expect(p.model.committed.last, 9);
        expect(p.model.target, isNull);
        expect((p.controller as CardProgress).isAnimating, isFalse);
        expect(Countman.isSleeping, isTrue);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        Countman.destroy();
      }
    });
  }
}
