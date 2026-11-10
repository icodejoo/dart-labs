import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/testing.dart';

/// 测试帧时长。
const Duration slotTestStep = Duration(milliseconds: 16);

/// 快速且可逐帧断言的动画配置。
const LuckyMotionOptions slotTestMotion = LuckyMotionOptions(
    speed: 12,
    accelerationTime: Duration(milliseconds: 32),
    decelerationTime: Duration(milliseconds: 64),
    timebase: LuckyTimebase.frame);

/// 三个可选奖品。
const List<SlotPrize> slotTestPrizes = [
  SlotPrize(
      weight: 1,
      background: LuckyFill.color(Color(0xFFFF4444)),
      texts: [LuckyText('A')]),
  SlotPrize(
      weight: 1,
      background: LuckyFill.color(Color(0xFF44BB66)),
      texts: [LuckyText('B')]),
  SlotPrize(
      weight: 1,
      background: LuckyFill.color(Color(0xFF4488EE)),
      texts: [LuckyText('C')]),
];

/// 三列默认配置。
const SlotConfig slotTestConfig = SlotConfig(
    prizes: slotTestPrizes,
    reels: [SlotReel(), SlotReel(), SlotReel()],
    options: SlotOptions(motion: slotTestMotion));

/// 默认逻辑尺寸。
const Size slotTestSize = Size(300, 180);

/// 计算布局并立即释放文字测量器。
SlotLayout slotLayout(
    [SlotConfig config = slotTestConfig, Size size = slotTestSize]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return const SlotGame().computeLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 带宿主回调记录的手动老虎机驱动器。
final class SlotHarness implements LuckyControllerHost<SlotResult> {
  /// 创建、挂接并配置；调用方必须 dispose。
  SlotHarness([SlotConfig config = slotTestConfig]) {
    controller.attach(this);
    controller.configure(config, slotLayout(config));
  }

  /// 被测控制器。
  final SlotController controller = SlotController();

  /// 手动时钟。
  @override
  final ManualLuckyClock clock = ManualLuckyClock();

  /// 正常结束回调记录。
  final List<SlotResult> results = [];

  /// 跨格事件记录。
  final List<(int, int)> passed = [];

  /// 阶段回调记录。
  final List<LuckyPhase> phases = [];

  /// 开始次数。
  int starts = 0;

  /// 当前阶段。
  LuckyPhase get phase => controller.phase.value;

  /// 记录结果。
  @override
  void handleResult(SlotResult result) => results.add(result);

  /// 记录列和奖品。
  @override
  void handleItemPassed(int reel, int index) => passed.add((reel, index));

  /// 记录阶段。
  @override
  void handlePhaseChanged(LuckyPhase phase) => phases.add(phase);

  /// 记录开始。
  @override
  void handleStarted() {
    starts++;
  }

  /// 推进指定帧数。
  void advance([int frames = 1]) => clock.advanceFrames(frames);

  /// 进入匀速。
  void cruise() {
    expect(controller.play(), isTrue);
    advance(3);
    expect(phase, LuckyPhase.cruising);
  }

  /// 进入减速。
  void decelerate() {
    cruise();
    expect(controller.stop(1), isTrue);
    advance();
    expect(phase, LuckyPhase.decelerating);
  }

  /// 推进到结算；有上限，永不等待挂起动画。
  void settle() {
    advance(20);
    expect(phase, LuckyPhase.settled);
  }

  /// 释放自己持有的资源。
  void dispose() {
    controller.dispose();
    clock.dispose();
  }
}

/// 独立验证老虎机的每条公共状态迁移，供共享状态矩阵调用。
Future<void> verifySlotEdge(String edge) async {
  final config = edge == 'E15'
      ? slotTestConfig.copyWith(
          prizes: [const SlotPrize(), const SlotPrize(), const SlotPrize()])
      : slotTestConfig;
  final h = SlotHarness(config);
  addTearDown(h.dispose);
  final c = h.controller;
  switch (edge) {
    case 'E01':
      expect(c.play(), isTrue);
      expect(h.phase, LuckyPhase.accelerating);
    case 'E02':
      h.decelerate();
      h.settle();
      expect(c.play(), isTrue);
      expect(h.phase, LuckyPhase.accelerating);
    case 'E03':
      expect(c.idleSpin(), isTrue);
      h.advance();
      final prev = c.frame.scroll.first;
      expect(c.play(), isTrue);
      h.advance();
      expect(c.frame.scroll.first - prev, slotTestMotion.idleSpinSpeed);
    case 'E04':
      expect(c.idleSpin(), isTrue);
      expect(h.phase, LuckyPhase.idleSpinning);
    case 'E05':
      h.decelerate();
      h.settle();
      expect(c.idleSpin(), isTrue);
      expect(h.phase, LuckyPhase.idleSpinning);
    case 'E06':
      c.idleSpin();
      h.advance();
      expect(c.cancel(), isTrue);
      expect(h.phase, LuckyPhase.idle);
      expect(h.results, isEmpty);
      expect(c.lastResult, isNull);
    case 'E07':
      h.cruise();
      expect(h.phase, LuckyPhase.cruising);
    case 'E08':
      c.play();
      expect(c.stop(1), isTrue);
      expect(h.phase, LuckyPhase.accelerating);
      expect(c.frame.targets, [1, 1, 1]);
    case 'E09':
      c.play();
      c.stop(1);
      h.advance(3);
      expect(h.phase, LuckyPhase.cruising);
      h.advance();
      expect(h.phase, LuckyPhase.decelerating);
    case 'E10':
      h.cruise();
      c.stop(1);
      expect(h.phase, LuckyPhase.cruising);
      h.advance();
      expect(h.phase, LuckyPhase.decelerating);
    case 'E11':
      h.decelerate();
      h.settle();
      expect(h.results.single.index, 1);
    case 'E12':
      c.play();
      expect(c.cancel(), isTrue);
      expect(h.phase, LuckyPhase.idle);
      expect(c.lastResult!.cancelled, isTrue);
      expect(h.results, isEmpty);
    case 'E13':
      h.cruise();
      expect(c.cancel(), isTrue);
      expect(h.phase, LuckyPhase.idle);
      expect(h.results, isEmpty);
    case 'E14':
      h.cruise();
      expect(c.stop(-2), isTrue);
      expect(h.phase, LuckyPhase.idle);
      expect(c.lastResult!.cancelled, isTrue);
    case 'E15':
      h.cruise();
      expect(c.stop(), isTrue);
      expect(h.phase, LuckyPhase.idle);
      expect(c.lastResult!.cancelled, isTrue);
    case 'E16':
      h.decelerate();
      expect(c.stop(2), isFalse);
      expect(c.stopEach([2, 2, 2]), isFalse);
      expect(c.cancel(), isFalse);
      h.settle();
      expect(h.results.single.index, 1);
    case 'E17':
      expect(c.stop(1), isFalse);
      expect(c.stopEach([1, 1, 1]), isFalse);
      h.decelerate();
      h.settle();
      expect(c.stop(1), isFalse);
    case 'E18':
      h.cruise();
      expect(c.play(), isFalse);
      expect(h.starts, 1);
    case 'E19':
      h.cruise();
      expect(c.pause(), isTrue);
      final prev = c.frame.scroll.toList();
      h.advance(100);
      expect(c.frame.scroll, prev);
      expect(c.resume(), isTrue);
      h.advance();
      expect(c.frame.scroll.first - prev.first, slotTestMotion.speed);
      expect(c.stop(1), isTrue);
      h.settle();
    case 'E20':
      c.reset();
      expect(c.frame.scroll, [0, 0, 0]);
      c.idleSpin();
      c.reset();
      expect(h.phase, LuckyPhase.idle);
      c.play();
      c.reset();
      expect(h.phase, LuckyPhase.idle);
      h.cruise();
      c.reset();
      expect(h.phase, LuckyPhase.idle);
      h.decelerate();
      c.reset();
      expect(h.phase, LuckyPhase.idle);
      expect(c.frame.scroll, [0, 0, 0]);
      h.decelerate();
      h.settle();
      c.reset();
      expect(h.phase, LuckyPhase.idle);
    case 'E21':
      h.cruise();
      c.dispose();
      final callbacks = h.phases.length;
      h.advance(100);
      expect(h.phases, hasLength(callbacks));
      expect(h.results, isEmpty);
      expect(h.clock.isTicking, isFalse);
    case 'E22':
      c.idleSpin();
      expect(c.stop(1), isFalse);
      expect(c.stopEach([1, 1, 1]), isFalse);
      expect(h.phase, LuckyPhase.idleSpinning);
    case 'E23':
      for (var i = 0; i < 100; i++) {
        h.decelerate();
        h.settle();
      }
      expect(h.results, hasLength(100));
      expect(h.results.every((r) => r.index == 1), isTrue);
    case 'E24':
      h.cruise();
      expect(c.stop(), isTrue);
      h.settle();
      expect(h.results.single.prize, isNotNull);
    case 'E26':
      expect(c.pause(), isFalse);
      h.decelerate();
      h.settle();
      expect(c.pause(), isFalse);
      expect(h.clock.isTicking, isFalse);
    default:
      fail('未注册迁移 $edge');
  }
}

/// 渲染测试的可注入图片视图。
final class SlotTestImages implements LuckyImageSet {
  /// 当前版本。
  @override
  int generation = 0;

  /// 各槽解析结果。
  final Map<LuckyImageSlot, LuckyResolvedImage> values = {};

  /// 测试视图始终已有结论。
  @override
  bool get isSettled => true;

  /// 返回注入的图片。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => values[slot];
}

/// 创建可直接传给默认后端或绘制器的渲染数据。
LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> slotSurfaceData({
  SlotConfig config = slotTestConfig,
  SlotFrame? frame,
  SlotTestImages? images,
  Listenable? frames,
  Listenable? imagesListenable,
  int generation = 1,
  List<LuckyLayer<SlotLayout, SlotFrame>> layers = const [],
  LuckyHooks hooks = const LuckyHooks(),
  LuckyPerformanceOptions performance = const LuckyPerformanceOptions(),
  double devicePixelRatio = 1,
}) =>
    LuckySurfaceData(
        config: config,
        layout: slotLayout(config),
        layoutGeneration: generation,
        frame: frame ??
            (SlotFrame()
              ..scroll = Float64List(config.reels.length)
              ..targets = Int32List(config.reels.length)),
        frameListenable: frames ?? const _SilentListenable(),
        images: images ?? SlotTestImages(),
        imagesListenable: imagesListenable ?? const _SilentListenable(),
        layers: layers,
        hooks: hooks,
        devicePixelRatio: devicePixelRatio,
        textDirection: TextDirection.ltr,
        performance: performance,
        isAnimating: false);

/// 无通知的常量监听器，避免夹具泄漏。
final class _SilentListenable implements Listenable {
  /// 创建空监听器。
  const _SilentListenable();

  /// 没有帧源，无需保留监听。
  @override
  void addListener(VoidCallback listener) {}

  /// 没有保留监听，无需移除。
  @override
  void removeListener(VoidCallback listener) {}
}
