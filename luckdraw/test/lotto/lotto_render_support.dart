import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/lotto.dart';

import '../support/lotto_fixtures.dart';

/// 没有图片请求的测试图片集合。
final class EmptyLottoImages implements LuckyImageSet {
  /// 创建固定版本空集合。
  const EmptyLottoImages();

  /// 空集合的版本。
  @override
  int get generation => 0;

  /// 全部图片均已完成。
  @override
  bool get isSettled => true;

  /// 不存在任何图片。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => null;
}

/// 为渲染测试组装表面数据。
LuckySurfaceData<LottoConfig, LottoLayout, LottoFrame> lottoSurfaceData({
  required LottoConfig config,
  required LottoLayout layout,
  required LottoFrame frame,
  required Listenable listenable,
  List<LuckyLayer<LottoLayout, LottoFrame>> layers = const [],
  LuckyHooks hooks = const LuckyHooks(),
  int generation = 0,
}) =>
    LuckySurfaceData(
        config: config,
        layout: layout,
        layoutGeneration: generation,
        frame: frame,
        frameListenable: listenable,
        images: const EmptyLottoImages(),
        imagesListenable: listenable,
        layers: layers,
        hooks: hooks,
        devicePixelRatio: 1,
        textDirection: TextDirection.ltr,
        performance:
            const LuckyPerformanceOptions(cacheMode: LuckyCacheMode.picture),
        isAnimating: frame.phase.isMoving);

/// 用测试专有姿态替换尚在容器中的球，避免 golden 锁定临时 core 搅拌器的具体输出。
///
/// 已抽出的号码和结果槽几何仍使用真实乐透状态机的输出。
void setLottoGoldenPose(LottoFrame frame, LottoLayout layout,
    {required bool mixing}) {
  final random = math.Random(42);
  for (var p = 0; p < layout.drums.length; p++) {
    final drum = layout.drums[p];
    for (var b = 0; b < frame.x[p].length; b++) {
      if (frame.slotOf[p][b] >= 0) continue;
      final theta = random.nextDouble() * math.pi * 2;
      final radial =
          math.sqrt(random.nextDouble()) * (drum.radius - drum.ballRadius);
      final x = radial * math.cos(theta);
      final y = mixing
          ? radial * math.sin(theta)
          : (radial * math.sin(theta) + drum.radius * 0.45)
              .clamp(-drum.radius, drum.radius);
      final length = math.sqrt(x * x + y * y);
      final scale = length > drum.radius - drum.ballRadius
          ? (drum.radius - drum.ballRadius) / length
          : 1.0;
      frame.x[p][b] = x * scale;
      frame.y[p][b] = y * scale;
      frame.angle[p][b] = mixing ? theta : 0;
    }
  }
}

/// 构造带背景和精确截图边界的渲染器视图。
Widget lottoSnapshot(
        LuckySurfaceData<LottoConfig, LottoLayout, LottoFrame> data) =>
    MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
                child: RepaintBoundary(
                    key: const ValueKey('lotto-golden'),
                    child: ColoredBox(
                        color: const Color(0xFFFAFCFF),
                        child: SizedBox.fromSize(
                            size: lottoSize,
                            child: Builder(
                                builder: (context) =>
                                    const LottoCanvasRenderer()
                                        .buildSurface(context, data))))))));
