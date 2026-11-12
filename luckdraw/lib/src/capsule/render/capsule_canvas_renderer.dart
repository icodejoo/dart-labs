import 'package:flutter/widgets.dart';

import '../../core/motion/result.dart';
import '../../core/render/images_listener.dart';
import '../../core/render/invalidation_monitor.dart';
import '../../core/render/renderer.dart';
import '../layout/capsule_layout.dart';
import '../model/capsule_config.dart';
import '../model/capsule_parts.dart';
import '../motion/capsule_motion.dart';
import 'capsule_painter.dart';

/// 扭蛋机 Canvas 后端；持久表面负责缓存原生资源。
final class CapsuleCanvasRenderer extends LuckyRenderer<CapsuleConfig,
    CapsuleLayout, CapsuleFrame, LuckyResult<CapsulePrize>> {
  /// 创建默认渲染器。
  const CapsuleCanvasRenderer();

  /// 构建监听帧更新的表面，稳态不会重新构建。
  @override
  Widget buildSurface(BuildContext context,
          LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> data) =>
      _CapsuleSurface(data);
}

/// 表面拥有显示列表，与 CustomPainter 生命周期分离。
final class _CapsuleSurface extends StatefulWidget {
  /// 包装当前输入。
  const _CapsuleSurface(this.data);

  /// 表面输入。
  final LuckySurfaceData<CapsuleConfig, CapsuleLayout, CapsuleFrame> data;

  /// 创建资源状态。
  @override
  State<_CapsuleSurface> createState() => _CapsuleSurfaceState();
}

/// 跨帧保留静态显示列表，图片与布局变化时重新录制。
final class _CapsuleSurfaceState extends State<_CapsuleSurface>
    with LuckyImagesListener<_CapsuleSurface> {
  /// 仅在 assert 内创建并记录 config 引起的缓存失效。
  late final LuckyInvalidationMonitor _invalidationMonitor =
      LuckyInvalidationMonitor('capsule');

  /// 当前显示列表集合。
  final CapsulePictures _pictures = CapsulePictures();

  /// 已录制图片版本，视图对象本身可能被原地更新。
  int _imagesGeneration = -1;

  /// 首次录制。
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// 按当前输入录制并保存图片版本。
  void _prepare() {
    _pictures.prepare(widget.data);
    _imagesGeneration = widget.data.images.generation;
  }

  /// 图片通知源。
  @override
  Listenable imagesListenableOf(_CapsuleSurface widget) =>
      widget.data.imagesListenable;

  /// 图片到达只失效包含图片的卡片段，保留机身与胶囊缓存。
  @override
  void onImagesChanged() {
    if (_imagesGeneration == widget.data.images.generation) return;
    _pictures.prepare(widget.data, imagesOnly: true);
    _imagesGeneration = widget.data.images.generation;
  }

  /// 只在布局、图片或静态输入变化时录制。
  @override
  void didUpdateWidget(_CapsuleSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.layoutGeneration != widget.data.layoutGeneration ||
        oldWidget.data.config != widget.data.config ||
        oldWidget.data.layers != widget.data.layers ||
        oldWidget.data.textDirection != widget.data.textDirection ||
        oldWidget.data.textScale != widget.data.textScale ||
        oldWidget.data.devicePixelRatio != widget.data.devicePixelRatio ||
        oldWidget.data.performance != widget.data.performance) {
      assert(() {
        if (oldWidget.data.config != widget.data.config) {
          _invalidationMonitor.recordInvalidation();
        }
        return true;
      }());
      _prepare();
    } else {
      onImagesChanged();
    }
  }

  /// 创建只回放显示列表的画笔。
  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: CapsulePainter(widget.data, _pictures),
      size: widget.data.layout.size);

  /// 解除监听并释放原生资源。
  @override
  void dispose() {
    _pictures.dispose();
    super.dispose();
  }
}
