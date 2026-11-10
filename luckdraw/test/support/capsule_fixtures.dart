import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/capsule/layout/capsule_layout.dart';
import 'package:luckdraw/testing.dart';

/// 固定几何尺寸。
const capsuleSize = Size(300, 500);

/// 两种配色夹具。
const capsuleConfig = CapsuleConfig(prizes: [
  CapsulePrize(
      topFill: LuckyFill.color(Color(0xFFFFCC55)),
      bottomFill: LuckyFill.color(Color(0xFFFFFFFF)),
      weight: 1,
      texts: [LuckyText('Lucky')]),
  CapsulePrize(
      topFill: LuckyFill.color(Color(0xFF66CCFF)),
      bottomFill: LuckyFill.color(Color(0xFFFFFFFF)),
      weight: 2,
      texts: [LuckyText('Bonus')])
]);

/// 计算并释放测量器。
CapsuleLayout capsuleLayout(
    [CapsuleConfig config = capsuleConfig, Size size = capsuleSize]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return computeCapsuleLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 无图片的只读集合，供渲染单元测试注入。
final class CapsuleEmptyImages implements LuckyImageSet {
  /// 创建空视图。
  const CapsuleEmptyImages();

  /// 固定图片版本。
  @override
  int get generation => 0;

  /// 空视图已完成。
  @override
  bool get isSettled => true;

  /// 未加载的图片返回空。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => null;
}

/// 不发送图片变更的监听源。
final class CapsuleSilentListenable implements Listenable {
  /// 创建无状态监听源。
  const CapsuleSilentListenable();

  /// 静态源无需保存监听。
  @override
  void addListener(VoidCallback listener) {}

  /// 静态源无需移除监听。
  @override
  void removeListener(VoidCallback listener) {}
}

/// 生成渲染输入；帧通知器由调用方释放。
LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> capsuleSurface(
        CapsuleFrame frame, LuckyFrameNotifier notifier,
        {CapsuleConfig config = capsuleConfig,
        List<LuckyLayer<CapsuleLayout, CapsuleFrame>> layers = const [],
        LuckyHooks hooks = const LuckyHooks(),
        LuckyImageSet images = const CapsuleEmptyImages(),
        Listenable imagesListenable = const CapsuleSilentListenable(),
        int generation = 0}) =>
    LuckySurfaceData(
        config: config,
        layout: capsuleLayout(config),
        layoutGeneration: generation,
        frame: frame,
        frameListenable: notifier,
        images: images,
        imagesListenable: imagesListenable,
        layers: layers,
        hooks: hooks,
        devicePixelRatio: 1,
        textDirection: TextDirection.ltr,
        performance: const LuckyPerformanceOptions(),
        isAnimating: frame.phase.isMoving);

/// 提供确定性组件测试环境。
Widget capsuleHost(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
        data: const MediaQueryData(),
        child: Align(alignment: Alignment.topLeft, child: child)));

/// 以手动时间验证指定状态迁移边；每条边都有独立断言和资源释放。
void verifyCapsuleEdge(String edge) {
  final clock = ManualLuckyClock();
  final config = edge == 'E15'
      ? capsuleConfig
          .copyWith(prizes: [capsuleConfig.prizes.first.copyWith(weight: 0)])
      : capsuleConfig;
  final c = CapsuleController()
    ..attachHeadless(
        clock: clock, config: config, layout: capsuleLayout(config));

  /// 推进指定帧数，默认覆盖完整收尾。
  void pump([int count = 400]) =>
      clock.advanceFrames(count, step: const Duration(milliseconds: 20));

  /// 加速到匀速。
  void cruise() {
    expect(c.play(), isTrue);
    pump(50);
    expect(c.phase.value, LuckyPhase.cruising);
  }

  /// 进入减速首帧。
  void decelerate() {
    cruise();
    expect(c.stop(0), isTrue);
    pump(1);
    expect(c.phase.value, LuckyPhase.decelerating);
  }

  /// 完成一局。
  void settle() {
    decelerate();
    pump();
    expect(c.phase.value, LuckyPhase.settled);
  }

  try {
    switch (edge) {
      case 'E01':
        expect(c.play(), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E02':
        settle();
        expect(c.play(), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E03':
        expect(c.idleSpin(), isTrue);
        pump(2);
        final before = c.frame.swirlDeg;
        expect(c.play(), isTrue);
        pump(1);
        expect(c.frame.swirlDeg - before,
            greaterThanOrEqualTo(config.options.motion.idleSpinSpeed));
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E04':
        expect(c.idleSpin(), isTrue);
        expect(c.phase.value, LuckyPhase.idleSpinning);
      case 'E05':
        settle();
        expect(c.idleSpin(), isTrue);
        expect(c.phase.value, LuckyPhase.idleSpinning);
      case 'E06':
        c.idleSpin();
        expect(c.cancel(), isTrue);
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.lastResult, isNull);
      case 'E07':
        cruise();
      case 'E08':
        c.play();
        expect(c.stop(0), isTrue);
        expect(c.phase.value, LuckyPhase.accelerating);
      case 'E09':
        c.play();
        c.stop(0);
        for (var i = 0;
            i < 60 && c.phase.value == LuckyPhase.accelerating;
            i++) {
          pump(1);
        }
        expect(c.phase.value, LuckyPhase.cruising);
        pump(1);
        expect(c.phase.value, LuckyPhase.decelerating);
      case 'E10':
        cruise();
        c.stop(0);
        expect(c.phase.value, LuckyPhase.cruising);
        pump(1);
        expect(c.phase.value, LuckyPhase.decelerating);
      case 'E11':
        settle();
        expect(c.lastResult?.index, 0);
        expect(c.lastResult?.cancelled, isFalse);
      case 'E12':
        c.play();
        expect(c.cancel(), isTrue);
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.lastResult?.cancelled, isTrue);
      case 'E13':
        cruise();
        expect(c.cancel(), isTrue);
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.lastResult?.cancelled, isTrue);
      case 'E14':
        cruise();
        expect(c.stop(-1), isTrue);
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.lastResult?.cancelled, isTrue);
      case 'E15':
        c.play();
        expect(c.stop(), isTrue);
        expect(c.phase.value, LuckyPhase.idle);
        expect(c.lastResult?.cancelled, isTrue);
      case 'E16':
        decelerate();
        expect(c.stop(1), isFalse);
        expect(c.cancel(), isFalse);
        expect(c.phase.value, LuckyPhase.decelerating);
      case 'E17':
        expect(c.stop(0), isFalse);
        settle();
        expect(c.stop(0), isFalse);
      case 'E18':
        c.play();
        expect(c.play(), isFalse);
        pump(50);
        expect(c.play(), isFalse);
        c.stop(0);
        pump(1);
        expect(c.play(), isFalse);
      case 'E19':
        cruise();
        expect(c.pause(), isTrue);
        final before = c.frame.swirlDeg;
        pump(20);
        expect(c.frame.swirlDeg, before);
        expect(c.resume(), isTrue);
        pump(1);
        expect(c.frame.swirlDeg, before);
        pump(1);
        expect(c.frame.swirlDeg, greaterThan(before));
      case 'E20':
        for (final phase in [
          LuckyPhase.idle,
          LuckyPhase.idleSpinning,
          LuckyPhase.accelerating,
          LuckyPhase.cruising,
          LuckyPhase.decelerating,
          LuckyPhase.settled
        ]) {
          c.reset();
          if (phase == LuckyPhase.idleSpinning) {
            c.idleSpin();
          } else if (phase != LuckyPhase.idle) {
            c.play();
            if (phase != LuckyPhase.accelerating) {
              pump(50);
              if (phase != LuckyPhase.cruising) {
                c.stop(0);
                pump(1);
                if (phase == LuckyPhase.settled) {
                  pump();
                }
              }
            }
          }
          expect(c.phase.value, phase);
          c.reset();
          expect(c.phase.value, LuckyPhase.idle);
          expect(c.frame.swirlDeg, 0);
          expect(c.frame.droppedCapsule, -1);
        }
      case 'E21':
        cruise();
        final before = c.frame.swirlDeg;
        c.dispose();
        expect(clock.isTicking, isFalse);
        pump(50);
        expect(c.frame.swirlDeg, before);
      case 'E22':
        c.idleSpin();
        expect(c.stop(), isFalse);
        expect(c.phase.value, LuckyPhase.idleSpinning);
      case 'E23':
        for (var i = 0; i < 100; i++) {
          settle();
          expect(c.lastResult?.index, 0);
        }
      case 'E24':
        cruise();
        expect(c.stop(), isTrue);
        pump(1);
        expect(c.phase.value, LuckyPhase.decelerating);
        pump();
        expect(c.lastResult?.cancelled, isFalse);
      case 'E26':
        expect(c.pause(), isFalse);
        settle();
        expect(c.pause(), isFalse);
      default:
        fail('未知状态边 $edge');
    }
  } finally {
    c.dispose();
    clock.dispose();
  }
}
