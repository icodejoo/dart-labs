import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/motion/result.dart';
import '../../core/render/images_listener.dart';
import '../../core/render/invalidation_monitor.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/wheel_layout.dart';
import '../model/wheel_config.dart';
import '../model/wheel_parts.dart';
import '../motion/wheel_motion.dart';
import 'wheel_painter.dart';

/// 默认转盘 Canvas 后端；例如传给 LuckyWheel.renderer。
final class WheelCanvasRenderer extends LuckyRenderer<WheelConfig, WheelLayout,
    WheelFrame, LuckyResult<WheelPrize>> {
  /// 创建无状态渲染策略，缓存由其表面持有。
  const WheelCanvasRenderer();

  /// 构建持久缓存的 CustomPaint 表面。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) =>
      _WheelSurface(data: data);
}

/// 持有帧画笔和原生资源的渲染表面。
final class _WheelSurface extends StatefulWidget {
  /// 创建表面。
  const _WheelSurface({required this.data});

  /// 当前宿主输入。
  final LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data;

  /// 创建缓存所有者。
  @override
  State<_WheelSurface> createState() => _WheelSurfaceState();
}

/// 仅在低频输入变化时重新录制，动画期间保持同一画笔。
final class _WheelSurfaceState extends State<_WheelSurface>
    with LuckyImagesListener<_WheelSurface> {
  /// 仅在 assert 内创建并记录 config 引起的缓存失效。
  late final LuckyInvalidationMonitor _invalidationMonitor =
      LuckyInvalidationMonitor('wheel');

  /// 表面独占缓存。
  final LuckyPictureCache _cache = LuckyPictureCache();

  /// 监听当前控制器帧的持久画笔。
  late WheelPainter _painter;

  /// 上一次已录制图片代际；图片视图本身可变，不能比较旧 widget。
  int _imageGeneration = -1;

  /// 首次录制并监听图片更新。
  @override
  void initState() {
    super.initState();
    _painter = WheelPainter(widget.data, _cache);
    _imageGeneration = widget.data.images.generation;
  }

  /// 图片通知源。
  @override
  Listenable imagesListenableOf(_WheelSurface widget) =>
      widget.data.imagesListenable;

  /// 图片通知只重录含图片的段，并请求绘制。
  @override
  void onImagesChanged() {
    if (_imageGeneration == widget.data.images.generation) return;
    _imageGeneration = widget.data.images.generation;
    _painter.imagesChanged(widget.data);
    setState(() {});
    // 同一画笔不会触发 shouldRepaint，直接标记已有绘制对象。
    final renderObject = context.findRenderObject();
    renderObject?.markNeedsPaint();
  }

  /// 更新监听器并按缓存失效契约重录。
  @override
  void didUpdateWidget(covariant _WheelSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.data;
    final data = widget.data;
    if (old.frameListenable != data.frameListenable) {
      assert(() {
        if (old.config != data.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _painter = WheelPainter(data, _cache);
    } else if (old.layoutGeneration != data.layoutGeneration ||
        old.layout != data.layout ||
        old.hooks != data.hooks ||
        old.performance != data.performance ||
        old.devicePixelRatio != data.devicePixelRatio ||
        !listEquals(old.layers, data.layers) ||
        data.layers.asMap().entries.any((entry) =>
            entry.key < old.layers.length &&
            entry.value.shouldRepaint(old.layers[entry.key]))) {
      assert(() {
        if (old.config != data.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _painter.rebuildSegments(data);
    } else if (_imageGeneration != data.images.generation) {
      _painter.imagesChanged(data);
    } else {
      _painter.updateData(data);
    }
    _imageGeneration = data.images.generation;
    context.findRenderObject()?.markNeedsPaint();
  }

  /// 构建动画帧无关的绘制对象。
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: widget.data.layout.size,
      painter: _painter,
      willChange: widget.data.isAnimating,
      isComplex: true);

  /// 移除图片监听并释放显示列表及纹理；绘制对象负责帧监听。
  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }
}
