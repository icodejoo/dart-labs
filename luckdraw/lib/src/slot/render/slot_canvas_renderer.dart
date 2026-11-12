import 'package:flutter/widgets.dart';

import '../../core/render/images_listener.dart';
import '../../core/render/invalidation_monitor.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/slot_layout.dart';
import '../model/slot_config.dart';
import '../model/slot_result.dart';
import '../motion/slot_motion.dart';
import 'slot_atlas.dart';
import 'slot_painter.dart';

/// 默认 Canvas 后端，缓存始终按单格录制，不受奖品长条纹理上限影响。
final class SlotCanvasRenderer
    extends LuckyRenderer<SlotConfig, SlotLayout, SlotFrame, SlotResult> {
  /// 创建无状态后端。
  const SlotCanvasRenderer();

  /// 创建拥有缓存的表面，帧变化只触发重绘。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> data) =>
      _SlotSurface(data);
}

/// 缓存生命周期所在表面。
class _SlotSurface extends StatefulWidget {
  /// 保存当前绘制数据。
  const _SlotSurface(this.data);

  /// 当前绘制数据。
  final LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> data;

  /// 创建缓存所有者。
  @override
  State<_SlotSurface> createState() => _SlotSurfaceState();
}

/// 保持跨重建缓存和图片变更监听。
final class _SlotSurfaceState extends State<_SlotSurface>
    with LuckyImagesListener<_SlotSurface> {
  /// 仅在 assert 内创建并记录 config 引起的缓存失效。
  late final LuckyInvalidationMonitor _invalidationMonitor =
      LuckyInvalidationMonitor('slot');

  /// 独立拥有并释放分页纹理。
  final SlotAtlas _atlas = SlotAtlas();

  /// 显示列表缓存。
  final LuckyPictureCache _cache = LuckyPictureCache();

  /// 最近应用的图片版本。
  int _imagesGeneration = -1;

  /// 监听异步图片到达。
  @override
  void initState() {
    super.initState();
  }

  /// 图片通知源。
  @override
  Listenable imagesListenableOf(_SlotSurface widget) =>
      widget.data.imagesListenable;

  /// 图片变化时在下一次构建重新录制。
  @override
  void onImagesChanged() {
    setState(() {
      _cache.invalidateAll();
    });
  }

  /// 更新数据，失效布局、样式或静态层有变化的缓存。
  @override
  void didUpdateWidget(covariant _SlotSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.data;
    final data = widget.data;
    if (old.layoutGeneration != data.layoutGeneration ||
        old.config != data.config ||
        old.textScale != data.textScale ||
        old.textDirection != data.textDirection ||
        old.devicePixelRatio != data.devicePixelRatio ||
        old.performance != data.performance ||
        !_sameLayers(old, data)) {
      assert(() {
        if (old.config != data.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _cache.invalidateAll();
    }
  }

  /// 比较各层身份及静态层的显式失效判定。
  bool _sameLayers(LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> old,
      LuckySurfaceData<SlotConfig, SlotLayout, SlotFrame> data) {
    if (old.layers.length != data.layers.length) return false;
    for (var i = 0; i < data.layers.length; i++) {
      if (!identical(old.layers[i], data.layers[i]) ||
          data.layers[i].shouldRepaint(old.layers[i])) {
        return false;
      }
    }
    return true;
  }

  /// 构建只监听帧重绘的画布。
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (_imagesGeneration != data.images.generation) {
      _cache.invalidateAll();
      _imagesGeneration = data.images.generation;
    }
    return CustomPaint(
        size: data.layout.size,
        painter: SlotPainter(data, _cache, atlas: _atlas),
        willChange: data.isAnimating,
        isComplex: true);
  }

  /// 释放图片监听和原生显示列表。
  @override
  void dispose() {
    _atlas.dispose();
    _cache.dispose();
    super.dispose();
  }
}
