import 'dart:ui' as ui;

import '../foundation/options.dart';
import 'perf_trace.dart';
import 'picture_cache.dart';

/// 低频准备的矢量及位图回放参数；原生资源由传入缓存统一拥有。
final class LuckyCachedPicture {
  /// 录制 [id]，按 [bounds] 与 [devicePixelRatio] 准备位图。
  ///
  /// [bounds] 须包含绘制内容及抗锯齿边缘；超出缓存上限时回退矢量。
  LuckyCachedPicture(
      LuckyPictureCache cache,
      int id,
      this.bounds,
      double devicePixelRatio,
      void Function(ui.Canvas) record,
      LuckyPerformanceOptions performance)
      : picture = cache.picture(id, record),
        mode = performance.cacheMode,
        _paint = (ui.Paint()..filterQuality = performance.filterQuality) {
    cache
      ..mode = mode
      ..maxRasterSide = performance.maxRasterSide
      ..maxRasterBytes = performance.maxRasterBytes;
    _image = cache.raster(id, bounds.size, devicePixelRatio, record,
        origin: bounds.topLeft);
    final image = _image;
    luckyTraceStart('luckdraw.raster.prepare');
    try {
      _source = image == null
          ? ui.Rect.zero
          : ui.Rect.fromLTWH(
              0, 0, image.width.toDouble(), image.height.toDouble());
    } finally {
      luckyTraceEnd();
    }
  }

  /// 原始矢量显示列表，停下后保持文字锐利。
  final ui.Picture picture;

  /// 与录制内容同坐标系的位图目标区域。
  final ui.Rect bounds;

  /// 本段使用的缓存策略。
  final LuckyCacheMode mode;

  /// 受缓存边长限制的纹理。
  late final ui.Image? _image;

  /// 低频准备的纹理源区域。
  late final ui.Rect _source;

  /// 跨帧复用的采样画笔。
  final ui.Paint _paint;

  /// 按 [isMoving] 选择缓存回放，不创建绘制对象或离屏图层。
  void paint(ui.Canvas canvas, {required bool isMoving}) {
    final image = _image;
    if (image != null && (mode == LuckyCacheMode.raster || isMoving)) {
      canvas.drawImageRect(image, _source, bounds, _paint);
    } else {
      canvas.drawPicture(picture);
    }
  }
}
