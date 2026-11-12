import 'package:flutter/widgets.dart';

import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/lotto_layout.dart';
import '../model/lotto_config.dart';
import '../motion/lotto_motion.dart';
import 'lotto_painter.dart';

/// 默认 Canvas 后端；缓存由 StatefulWidget 表面持有。
final class LottoCanvasRenderer
    extends LuckyRenderer<LottoConfig, LottoLayout, LottoFrame, LottoResult> {
  /// 创建无状态后端描述。
  const LottoCanvasRenderer();

  /// 创建绘制表面，帧更新只重绘 CustomPaint。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<LottoConfig, LottoLayout, LottoFrame> data) =>
      _LottoSurface(data: data);
}

/// 持有显示列表资源的绘制表面。
final class _LottoSurface extends StatefulWidget {
  /// 接收低频渲染输入。
  const _LottoSurface({required this.data});

  /// 当前渲染输入。
  final LuckySurfaceData<LottoConfig, LottoLayout, LottoFrame> data;

  /// 创建拥有缓存的状态。
  @override
  State<_LottoSurface> createState() => _LottoSurfaceState();
}

/// 缓存失效与原生资源生命周期。
final class _LottoSurfaceState extends State<_LottoSurface> {
  /// 表面独享的缓存。
  final LuckyPictureCache _cache = LuckyPictureCache();

  /// 输入变更时失效录制内容，阶段变化保留缓存。
  @override
  void didUpdateWidget(covariant _LottoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.data;
    final data = widget.data;
    if (old.layoutGeneration != data.layoutGeneration ||
        old.config != data.config ||
        old.layers != data.layers ||
        old.textScale != data.textScale ||
        old.devicePixelRatio != data.devicePixelRatio ||
        old.performance != data.performance ||
        old.textDirection != data.textDirection ||
        old.images.generation != data.images.generation) {
      _cache.invalidateAll();
    }
  }

  /// 构建时预录制显示列表，稳态帧不经过此路径。
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: widget.data.layout.size,
      isComplex: true,
      willChange: widget.data.isAnimating,
      painter: LottoPainter(data: widget.data, cache: _cache));

  /// 释放全部 Picture。
  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }
}
