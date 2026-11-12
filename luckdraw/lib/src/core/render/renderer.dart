import 'package:flutter/widgets.dart';

import '../control/hooks.dart';
import '../foundation/options.dart';
import '../game/frame.dart';
import '../game/layout.dart';
import '../image/image_set.dart';
import '../motion/result.dart';
import 'layer.dart';

/// 渲染后端；在宿主构建时创建表面，帧更新使用 data 中的监听器。
abstract class LuckyRenderer<C extends Object, L extends LuckyLayout,
    F extends LuckyFrame, R extends LuckyResult<Object?>> {
  /// 常量构造。
  const LuckyRenderer();

  /// 用 [data] 构建渲染表面；动画稳态不调用此方法。
  Widget buildSurface(BuildContext context, LuckySurfaceData<C, L, F> data);
}

/// 渲染后端所需的数据；帧快照与图片视图由宿主持有。
@immutable
final class LuckySurfaceData<C extends Object, L extends LuckyLayout,
    F extends LuckyFrame> {
  /// 创建渲染输入；例如后端可用 [frameListenable] 驱动 CustomPainter。
  const LuckySurfaceData(
      {required this.config,
      required this.layout,
      required this.layoutGeneration,
      required this.frame,
      required this.frameListenable,
      required this.images,
      required this.imagesListenable,
      required this.layers,
      required this.hooks,
      required this.devicePixelRatio,
      this.textScale = TextScaler.noScaling,
      required this.textDirection,
      required this.performance,
      required this.isAnimating});

  /// 当前不可变配置。
  final C config;

  /// 当前布局。
  final L layout;

  /// 布局与热重载版本。
  final int layoutGeneration;

  /// 复用的帧快照。
  final F frame;

  /// 帧重绘通知。
  final Listenable frameListenable;

  /// 已解析图片只读视图。
  final LuckyImageSet images;

  /// 图片变化通知。
  final Listenable imagesListenable;

  /// 用户绘制层。
  final List<LuckyLayer<L, F>> layers;

  /// 绘制与生命周期钩子。
  final LuckyHooks hooks;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 测量与录制共用的文字缩放；默认倍率为 1，保留系统非线性缩放。
  final TextScaler textScale;

  /// 文字整形方向。
  final TextDirection textDirection;

  /// 缓存与采样选项。
  final LuckyPerformanceOptions performance;

  /// 当前是否处于运动阶段。
  final bool isAnimating;
}
