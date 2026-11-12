import 'package:flutter/widgets.dart';

import '../../core/motion/result.dart';
import '../../core/render/invalidation_monitor.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/number_wheel_layout.dart';
import '../model/number_wheel_config.dart';
import '../motion/number_wheel_motion.dart';
import 'number_wheel_painter.dart';

/// NumberWheel 的 Canvas 后端；缓存由表面状态持有并释放。
final class NumberWheelCanvasRenderer extends LuckyRenderer<NumberWheelConfig,
    NumberWheelLayout, NumberWheelFrame, LuckyResult<NumberWheelPocket>> {
  /// 创建无状态后端。
  const NumberWheelCanvasRenderer();

  /// 构建由帧通知驱动的绘制表面。
  @override
  Widget buildSurface(
          BuildContext context,
          LuckySurfaceData<NumberWheelConfig, NumberWheelLayout,
                  NumberWheelFrame>
              data) =>
      _Surface(data);
}

/// 持有渲染输入的表面。
final class _Surface extends StatefulWidget {
  /// 包装当前输入。
  const _Surface(this.data);

  /// 宿主输入。
  final LuckySurfaceData<NumberWheelConfig, NumberWheelLayout, NumberWheelFrame>
      data;

  /// 创建缓存所有者。
  @override
  State<_Surface> createState() => _SurfaceState();
}

/// 原生显示列表的所有者。
final class _SurfaceState extends State<_Surface> {
  /// 仅在 assert 内创建并记录 config 引起的缓存失效。
  late final LuckyInvalidationMonitor _invalidationMonitor =
      LuckyInvalidationMonitor('number_wheel');

  /// 可复用缓存。
  final LuckyPictureCache _cache = LuckyPictureCache();

  /// 最近图片版本，保存整数避免可变视图比较失效。
  int _imageGeneration = -1;

  /// 输入变化时只失效受影响的静态内容。
  @override
  void didUpdateWidget(covariant _Surface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.data, next = widget.data;
    var changed = old.layoutGeneration != next.layoutGeneration ||
        old.config != next.config ||
        old.textScale != next.textScale ||
        old.textDirection != next.textDirection ||
        old.devicePixelRatio != next.devicePixelRatio ||
        old.performance != next.performance ||
        old.layers.length != next.layers.length;
    if (!changed) {
      for (var i = 0; i < next.layers.length; i++) {
        final a = old.layers[i], b = next.layers[i];
        if (a.position != b.position ||
            a.isStatic != b.isStatic ||
            a.rotatesWithWheel != b.rotatesWithWheel ||
            b.shouldRepaint(a)) {
          changed = true;
        }
      }
    }
    if (changed) {
      assert(() {
        if (old.config != next.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _cache.invalidateAll();
    }
  }

  /// 在低频构建时预录制，动画帧只回放。
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (_imageGeneration != data.images.generation) {
      _cache.invalidateAll();
      _imageGeneration = data.images.generation;
    }
    _cache.mode = data.performance.cacheMode;
    _cache.maxRasterSide = data.performance.maxRasterSide;
    _cache.maxRasterBytes = data.performance.maxRasterBytes;
    return CustomPaint(
        painter: NumberWheelPainter(data, _cache),
        size: data.layout.size,
        isComplex: true,
        willChange: data.isAnimating);
  }

  /// 释放全部原生资源。
  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }
}
