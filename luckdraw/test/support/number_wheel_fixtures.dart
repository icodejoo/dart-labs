import 'package:flutter/painting.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/src/number_wheel/layout/number_wheel_layout.dart';
import 'package:luckdraw/src/number_wheel/model/number_wheel_config.dart';
import 'package:luckdraw/src/number_wheel/motion/number_wheel_motion.dart';

/// 无图片的测试视图。
final class NumberWheelTestImages implements LuckyImageSet {
  /// 创建空视图。
  NumberWheelTestImages();

  /// 可手动推进的图片版本。
  @override
  int generation = 0;

  /// 空视图已经就绪。
  @override
  bool get isSettled => true;

  /// 空视图没有图片。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => null;
}

/// 创建可直接供画笔测试使用的输入；通知器由测试负责释放。
LuckySurfaceData<NumberWheelConfig, NumberWheelLayout, NumberWheelFrame>
    numberWheelSurface(LuckyFrameNotifier notifier,
            {NumberWheelConfig config = numberWheelFixture,
            NumberWheelFrame? frame,
            List<LuckyLayer<NumberWheelLayout, NumberWheelFrame>> layers =
                const [],
            LuckyHooks hooks = const LuckyHooks(),
            NumberWheelTestImages? images,
            int generation = 1}) =>
        LuckySurfaceData(
            config: config,
            layout: numberWheelLayout(config),
            layoutGeneration: generation,
            frame: frame ??
                (NumberWheelFrame()
                  ..ballRadius = numberWheelLayout(config).trackRadius),
            frameListenable: notifier,
            images: images ?? NumberWheelTestImages(),
            imagesListenable: notifier,
            layers: layers,
            hooks: hooks,
            devicePixelRatio: 1,
            textDirection: TextDirection.ltr,
            performance: const LuckyPerformanceOptions(),
            isAnimating: false);

/// 快速运动参数，不依赖真实时间。
const LuckyMotionOptions numberWheelTestMotion = LuckyMotionOptions(
    accelerationTime: Duration(milliseconds: 100),
    decelerationTime: Duration(milliseconds: 200),
    speed: 12);

/// 三个号码及确定选奖权重。
const NumberWheelConfig numberWheelFixture = NumberWheelConfig(pockets: [
  NumberWheelPocket(10, weight: 0),
  NumberWheelPocket(20, label: '二十', weight: 1),
  NumberWheelPocket(30, weight: 0)
], options: NumberWheelOptions(motion: numberWheelTestMotion));

/// 计算测试布局并释放测量器。
NumberWheelLayout numberWheelLayout(
    [NumberWheelConfig config = numberWheelFixture,
    Size size = const Size(300, 300)]) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return computeNumberWheelLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 创建已配置状态机。
NumberWheelMotion numberWheelMotion(
        [NumberWheelConfig config = numberWheelFixture]) =>
    NumberWheelMotion()..configure(config, numberWheelLayout(config));

/// 推进到匀速。
void cruiseNumberWheel(NumberWheelMotion motion) {
  motion.start();
  motion.tick(100, 100);
}

/// 推进到结束。
void settleNumberWheel(NumberWheelMotion motion) {
  for (var i = 0; i < 100 && motion.phase != LuckyPhase.settled; i++) {
    motion.tick(i * 20, 20);
  }
}
