import 'package:flutter/widgets.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';

import '../support/grid_fixtures.dart';

/// 可控的已加载图片集合，所有图片由测试释放。
final class GridTestImages implements LuckyImageSet {
  /// 图片槽映射。
  final Map<LuckyImageSlot, LuckyResolvedImage> values = {};

  /// 图片代次。
  @override
  int generation = 0;

  /// 请求是否结束。
  @override
  bool isSettled = true;

  /// 查询已提供的槽位。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) => values[slot];
}

/// 创建渲染数据，默认布局为 300 像素标准九宫格。
LuckySurfaceData<GridConfig, GridLayout, GridFrame> gridSurfaceData({
  GridConfig config = gridFixture,
  GridFrame? frame,
  GridTestImages? images,
  Listenable? frames,
  Listenable? imageChanges,
  int generation = 1,
  List<LuckyLayer<GridLayout, GridFrame>> layers = const [],
  LuckyHooks hooks = const LuckyHooks(),
  LuckyPerformanceOptions performance = const LuckyPerformanceOptions(),
  TextDirection direction = TextDirection.ltr,
  TextScaler scale = TextScaler.noScaling,
}) =>
    LuckySurfaceData(
        config: config,
        layout: gridLayout(config),
        layoutGeneration: generation,
        frame: frame ?? GridFrame(),
        frameListenable: frames ?? const _SilentListenable(),
        images: images ?? GridTestImages(),
        imagesListenable: imageChanges ?? const _SilentListenable(),
        layers: layers,
        hooks: hooks,
        devicePixelRatio: 2,
        textDirection: direction,
        textScale: scale,
        performance: performance,
        isAnimating: false);

/// 无资源的静态渲染通知器。
final class _SilentListenable implements Listenable {
  /// 创建静态通知器。
  const _SilentListenable();

  /// 静态输入不订阅事件。
  @override
  void addListener(VoidCallback listener) {}

  /// 静态输入不订阅事件。
  @override
  void removeListener(VoidCallback listener) {}
}
