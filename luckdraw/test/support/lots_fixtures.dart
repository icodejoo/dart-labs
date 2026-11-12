import 'package:flutter/painting.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/lots/layout/lots_layout.dart';
import 'package:luckdraw/src/lots/model/lots_config.dart';
import 'package:luckdraw/src/lots/model/lots_parts.dart';
import 'package:luckdraw/src/lots/motion/lots_motion.dart';

/// 测试签筒的短时间配置。
const LotsConfig lotsFixture = LotsConfig(
    sticks: [
      LotsStick(label: 'first', weight: 0),
      LotsStick(
          label: 'fortune', texts: [LuckyText('Good fortune')], weight: 1),
      LotsStick(label: 'third', weight: 0)
    ],
    options: LotsOptions(
        riseTime: Duration(milliseconds: 100),
        revealTime: Duration(milliseconds: 100),
        motion: LuckyMotionOptions(
            accelerationTime: Duration(milliseconds: 100),
            decelerationTime: Duration(milliseconds: 200))));

/// 计算测试布局并释放测量器。
LotsLayout lotsLayout(
    [LotsConfig config = lotsFixture, Size size = const Size(300, 400)]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return computeLotsLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 创建已配置的抽签状态机。
LotsMotion lotsMotion([LotsConfig config = lotsFixture]) =>
    LotsMotion()..configure(config, lotsLayout(config));

/// 推进到匀速。
void cruiseLots(LotsMotion motion) {
  motion.start();
  motion.tick(100, 100);
}

/// 推进全部收尾阶段。
void settleLots(LotsMotion motion) {
  for (var i = 0; i < 100 && motion.phase != LuckyPhase.settled; i++) {
    motion.tick(i * 20, 20);
  }
}

/// 可注入的测试图片视图。
final class LotsTestImages implements LuckyImageSet {
  /// 创建空图片视图。
  LotsTestImages();

  /// 图片版本。
  @override
  int generation = 0;

  /// 注入解析图片。
  final Map<LuckyImageSlot, LuckyResolvedImage> values = {};

  /// 全部请求已经完成。
  @override
  bool get isSettled => true;

  /// 返回注入图片。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => values[slot];
}

/// 直接创建渲染测试输入，通知器由测试负责释放。
LuckySurfaceData<LotsConfig, LotsLayout, LotsFrame> lotsSurface(
        LuckyFrameNotifier notifier,
        {LotsConfig config = lotsFixture,
        LotsFrame? frame,
        List<LuckyLayer<LotsLayout, LotsFrame>> layers = const [],
        LuckyHooks hooks = const LuckyHooks(),
        LotsTestImages? images,
        int generation = 1}) =>
    LuckySurfaceData(
        config: config,
        layout: lotsLayout(config),
        layoutGeneration: generation,
        frame: frame ?? LotsFrame(),
        frameListenable: notifier,
        images: images ?? LotsTestImages(),
        imagesListenable: notifier,
        layers: layers,
        hooks: hooks,
        devicePixelRatio: 1,
        textDirection: TextDirection.ltr,
        performance: const LuckyPerformanceOptions(),
        isAnimating: false);
