import 'package:flutter/widgets.dart';

import '../../core/motion/motion.dart';
import '../../core/motion/result.dart';
import '../../core/render/images_listener.dart';
import '../../core/render/invalidation_monitor.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/grid_layout.dart';
import '../model/grid_config.dart';
import '../model/grid_parts.dart';
import '../motion/grid_motion.dart';
import 'grid_painter.dart';

/// 九宫格默认 Canvas 后端；每格缓存普通态及激活态。
final class GridCanvasRenderer extends LuckyRenderer<GridConfig, GridLayout,
    GridFrame, LuckyResult<GridPrize>> {
  /// 创建无状态后端。
  const GridCanvasRenderer();

  /// 创建持有 Picture 缓存的渲染表面。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<GridConfig, GridLayout, GridFrame> data) =>
      _GridSurface(data);
}

/// 缓存随表面生命周期持有，不随 Widget 重建丢失。
final class _GridSurface extends StatefulWidget {
  /// 指定渲染数据。
  const _GridSurface(this.data);

  /// 当前渲染输入。
  final LuckySurfaceData<GridConfig, GridLayout, GridFrame> data;

  /// 创建资源所有者。
  @override
  State<_GridSurface> createState() => _GridSurfaceState();
}

/// 持有长期 painter、缓存及图片版本。
final class _GridSurfaceState extends State<_GridSurface>
    with LuckyImagesListener<_GridSurface> {
  /// 仅在 assert 内创建并记录 config 引起的缓存失效。
  late final LuckyInvalidationMonitor _invalidationMonitor =
      LuckyInvalidationMonitor('grid');

  /// 布局或样式变化时通知绘制，避免重建同一个 painter 被框架略过。
  final LuckyFrameNotifier _updates = LuckyFrameNotifier();

  /// 显示列表缓存。
  final LuckyPictureCache _cache = LuckyPictureCache();

  /// 长期复用的 painter。
  late GridPainter _painter;

  /// 上次录制时的图片代次。
  int _imageGeneration = -1;

  /// 创建 painter 并监听图片渐进到达。
  @override
  void initState() {
    super.initState();
    _painter = GridPainter(data: widget.data, cache: _cache, updates: _updates);
    _imageGeneration = widget.data.images.generation;
  }

  /// 图片通知源。
  @override
  Listenable imagesListenableOf(_GridSurface widget) =>
      widget.data.imagesListenable;

  /// 图片到达时录制新图片，无需重建布局或宿主。
  @override
  void onImagesChanged() {
    _painter.rebuildSegments(widget.data);
    _imageGeneration = widget.data.images.generation;
  }

  /// 静态输入变化时失效；纯动画阶段变化只更新动态数据。
  @override
  void didUpdateWidget(_GridSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.data;
    final next = widget.data;
    if (old.frameListenable != next.frameListenable ||
        old.imagesListenable != next.imagesListenable) {
      assert(() {
        if (old.config != next.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _painter = GridPainter(data: next, cache: _cache, updates: _updates);
    } else if (old.layoutGeneration != next.layoutGeneration ||
        _imageGeneration != next.images.generation ||
        old.layers != next.layers ||
        old.performance != next.performance ||
        old.textDirection != next.textDirection ||
        old.textScale != next.textScale) {
      assert(() {
        if (old.config != next.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _painter.rebuildSegments(next);
    } else {
      _painter.updateData(next);
    }
    _imageGeneration = next.images.generation;
    _updates.notify();
  }

  /// 帧通知只驱动 CustomPaint。
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: widget.data.layout.size,
      painter: _painter,
      willChange: widget.data.isAnimating,
      isComplex: true);

  /// 移除图片监听并释放全部原生图片。
  @override
  void dispose() {
    _updates.dispose();
    _cache.dispose();
    super.dispose();
  }
}
