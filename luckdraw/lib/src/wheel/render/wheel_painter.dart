import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/foundation/angles.dart';
import '../../core/foundation/options.dart';
import '../../core/geometry/image_box.dart';
import '../../core/motion/phase.dart';
import '../../core/motion/timebase.dart';
import '../../core/render/layer.dart';
import '../../core/render/paint_helpers.dart';
import '../../core/render/perf_trace.dart';
import '../../core/render/picture_cache.dart';
import '../../core/render/renderer.dart';
import '../layout/wheel_layout.dart';
import '../model/wheel_config.dart';
import '../model/wheel_parts.dart';
import '../motion/wheel_motion.dart';

/// 一段连续的绘制操作；静态相邻同旋转属性的操作合并录制。
final class _WheelSegment {
  /// 创建段，静态与旋转属性在布局周期内固定。
  _WheelSegment(this.isStatic, this.rotates);

  /// 是否只在失效时录制。
  final bool isStatic;

  /// 是否围绕转盘圆心旋转。
  final bool rotates;

  /// 是否包含可能异步到达的图片。
  bool hasImages = false;

  /// 在低频路径创建的录制或动态操作。
  final List<void Function(Canvas)> operations = [];

  /// 缓存的矢量显示列表。
  late ui.Picture picture;

  /// 可选栅格纹理。
  ui.Image? raster;

  /// 纹理源矩形，仅在缓存准备时创建。
  Rect source = Rect.zero;

  /// 顺序执行段内容，录制时与测试画布使用同一路径。
  void record(Canvas canvas) {
    for (final operation in operations) {
      operation(canvas);
    }
  }
}

/// 持久转盘画笔；布局阶段录制，帧路径只变换并回放。
final class WheelPainter extends CustomPainter {
  /// 使用宿主帧监听器；[cache] 的所有权属于 surface。
  WheelPainter(
      LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data, this.cache)
      : _data = data,
        super(repaint: data.frameListenable) {
    rebuildSegments(data);
  }

  /// 外部持有的显示列表缓存。
  final LuckyPictureCache cache;

  /// 最新宿主输入。
  LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> _data;

  /// 按上游 z 序排列的段。
  final List<_WheelSegment> _segments = [];

  /// 复用的用户层上下文。
  final LuckyLayerContext<WheelLayout, WheelFrame> _context =
      LuckyLayerContext<WheelLayout, WheelFrame>();

  /// 位图回放复用画笔。
  final Paint _rasterPaint = Paint();

  /// 逻辑纹理目标矩形。
  Rect _bounds = Rect.zero;

  /// 静态段版本，用于替换画笔时的重绘判断。
  int segmentsVersion = 0;

  /// 更新输入和复用上下文，不创建逐帧对象。
  void updateData(LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) {
    _data = data;
    _context
      ..size = data.layout.size
      ..layout = data.layout
      ..frame = data.frame
      ..devicePixelRatio = data.devicePixelRatio;
  }

  /// 布局或绘制策略变化时重新分段并提前准备缓存。
  void rebuildSegments(
      LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) {
    luckyTraceStart('luckdraw.wheel.record');
    try {
      updateData(data);
      cache
        ..invalidateAll()
        ..mode = data.performance.cacheMode
        ..maxRasterSide = data.performance.maxRasterSide;
      _segments.clear();
      _bounds = Offset.zero & data.layout.size;
      _rasterPaint.filterQuality = data.performance.filterQuality;
      if (data.performance.cacheMode == LuckyCacheMode.auto &&
          data.config.options.motion.timebase == LuckyTimebase.frame) {
        cache.mode = LuckyCacheMode.picture;
      }
      segmentsVersion++;
      final layout = data.layout;
      if (data.hooks.beforeDraw != null) {
        _add((canvas) => _data.hooks.beforeDraw!(canvas, layout.size),
            isStatic: false, centered: false);
      }
      _layers(LuckyLayerPosition.background);
      for (final block in layout.blocks) {
        _add((canvas) {
          final background = block.background;
          if (background != null) {
            final bounds =
                Rect.fromCircle(center: Offset.zero, radius: block.radius);
            paintLuckyFill(canvas, Path()..addOval(bounds), background, bounds);
          }
        });
        for (var i = 0; i < block.images.length; i++) {
          final placement = block.images[i];
          _add((canvas) => _images(canvas, [placement]),
              rotates: block.rotate[i], hasImages: true);
        }
      }
      _layers(LuckyLayerPosition.belowItems);
      _add(_prizes,
          rotates: true,
          hasImages: layout.sectors.any((sector) => sector.images.isNotEmpty));
      _layers(LuckyLayerPosition.aboveItems);
      _add(_buttons,
          hasImages: layout.buttons.any((button) => button.images.isNotEmpty));
      _layers(LuckyLayerPosition.foreground);
      if (data.hooks.afterDraw != null) {
        _add((canvas) => _data.hooks.afterDraw!(canvas, layout.size),
            isStatic: false, centered: false);
      }
      _prepare();
    } finally {
      luckyTraceEnd();
    }
  }

  /// 只失效含图片的段，保留不依赖图片的静态缓存。
  void imagesChanged(
      LuckySurfaceData<WheelConfig, WheelLayout, WheelFrame> data) {
    updateData(data);
    for (var i = 0; i < _segments.length; i++) {
      if (_segments[i].hasImages) cache.invalidate(i);
    }
    segmentsVersion++;
    _prepare();
  }

  /// 添加操作并合并相邻同类静态段；操作内容使用圆心坐标。
  void _add(void Function(Canvas) operation,
      {bool isStatic = true,
      bool rotates = false,
      bool hasImages = false,
      bool centered = true}) {
    final previous = _segments.lastOrNull;
    final segment = isStatic &&
            previous != null &&
            previous.isStatic &&
            previous.rotates == rotates
        ? previous
        : (_WheelSegment(isStatic, rotates));
    if (!identical(previous, segment)) _segments.add(segment);
    segment.hasImages |= hasImages;
    segment.operations.add((canvas) {
      canvas.save();
      try {
        if (centered) {
          canvas.translate(_data.layout.center.dx, _data.layout.center.dy);
        }
        operation(canvas);
      } finally {
        canvas.restore();
      }
    });
  }

  /// 按插入位置追加用户层，只有奖品前后层支持随盘旋转。
  void _layers(LuckyLayerPosition position) {
    for (final layer in _data.layers) {
      if (layer.position != position) continue;
      _add((canvas) => layer.paint(canvas, _context),
          isStatic: layer.isStatic,
          rotates: layer.rotatesWithWheel &&
              (position == LuckyLayerPosition.belowItems ||
                  position == LuckyLayerPosition.aboveItems),
          centered: false);
    }
  }

  /// 录制奖品，用户回调位于图片之后、文字之前的局部坐标系。
  void _prizes(Canvas canvas) {
    final layout = _data.layout;
    final bounds =
        Rect.fromCircle(center: Offset.zero, radius: layout.prizeRadius);
    for (final sector in layout.sectors) {
      final background = sector.background;
      if (background != null) {
        paintLuckyFill(canvas, sector.fan, background, bounds);
      }
      canvas.save();
      try {
        canvas.translate(sector.anchor.dx, sector.anchor.dy);
        canvas.rotate(sector.localRotation);
        _images(canvas, sector.images);
        _data.config.prizes[sector.index].painter?.call(
            canvas,
            WheelPrizePaintContext(
                index: sector.index,
                sweepRad: sector.sweepRad,
                prizeRadius: layout.prizeRadius,
                prizeHeight: sector.prizeHeight,
                shortSide: sector.shortSide));
        paintLuckyTextLines(canvas, sector.texts, null,
            textDirection: _data.textDirection, textScale: _data.textScale);
      } finally {
        canvas.restore();
      }
    }
  }

  /// 录制不随盘旋转的按钮和有背景的指针。
  void _buttons(Canvas canvas) {
    for (final button in _data.layout.buttons) {
      final background = button.background;
      if (background != null) {
        final bounds =
            Rect.fromCircle(center: Offset.zero, radius: button.radius);
        paintLuckyFill(canvas, Path()..addOval(bounds), background, bounds);
        final pointer = button.pointerPath;
        if (pointer != null) {
          paintLuckyFill(canvas, pointer, background, bounds);
        }
      }
      _images(canvas, button.images);
      paintLuckyTextLines(canvas, button.texts, null,
          textDirection: _data.textDirection, textScale: _data.textScale);
    }
  }

  /// 已成功图片按自然尺寸定位；未成功项不阻塞其它内容录制。
  void _images(Canvas canvas, List<LuckyImagePlacement> placements) {
    for (final placement in placements) {
      final resolved = _data.images[placement.slot];
      if (resolved == null) continue;
      drawLuckyImage(
          canvas, resolved.image, placement.place(resolved.naturalSize),
          borderRadius: placement.image.borderRadius,
          opacity: placement.image.opacity,
          filterQuality: _data.performance.filterQuality);
    }
  }

  /// 在低频路径填充显示列表、纹理和矩形，paint 中不触发录制。
  void _prepare() {
    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      if (!segment.isStatic) continue;
      segment.picture = cache.picture(i, segment.record);
      segment.raster = segment.rotates
          ? cache.raster(
              i, _data.layout.size, _data.devicePixelRatio, segment.record)
          : null;
      final raster = segment.raster;
      if (raster != null) {
        segment.source = Rect.fromLTWH(
            0, 0, raster.width.toDouble(), raster.height.toDouble());
      }
    }
  }

  /// 在测试画布重放录制操作，以检查内部剪裁、透明度和 save/restore。
  @visibleForTesting
  void debugRecordSegments(Canvas canvas) {
    for (final segment in _segments) {
      segment.record(canvas);
    }
  }

  /// 每帧仅做段回放及旋转；不创建 Path、Paint、Rect 或文字布局。
  @override
  void paint(Canvas canvas, Size size) {
    luckyTraceStart('luckdraw.wheel.paint');
    try {
      for (final segment in _segments) {
        if (segment.rotates) {
          canvas.save();
          canvas.translate(_data.layout.center.dx, _data.layout.center.dy);
          canvas.rotate(luckyDegToRad(_data.frame.rotateDeg));
          canvas.translate(-_data.layout.center.dx, -_data.layout.center.dy);
        }
        try {
          if (!segment.isStatic) {
            segment.record(canvas);
          } else {
            final raster = segment.raster;
            if (raster == null ||
                (_data.performance.cacheMode == LuckyCacheMode.auto &&
                    !_data.frame.phase.isMoving)) {
              canvas.drawPicture(segment.picture);
            } else {
              canvas.drawImageRect(
                  raster, segment.source, _bounds, _rasterPaint);
            }
          }
        } finally {
          if (segment.rotates) canvas.restore();
        }
      }
    } finally {
      luckyTraceEnd();
    }
  }

  /// 只在另一个画笔的静态段版本不同时请求重绘。
  @override
  bool shouldRepaint(covariant WheelPainter oldDelegate) =>
      oldDelegate.segmentsVersion != segmentsVersion;
}
