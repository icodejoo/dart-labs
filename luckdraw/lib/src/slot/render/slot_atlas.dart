import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../core/foundation/constants.dart';
import '../../core/render/perf_trace.dart';
import '../layout/slot_layout.dart';
import '../model/slot_parts.dart';
import '../motion/slot_motion.dart';

/// 每个精灵的变换及源矩形都占四个浮点数。
const int _stride = 4;

/// 由表面持有的分页图集；单格超限时 [prepare] 返回 false。
final class SlotAtlas {
  /// 创建空图集；调用方最终必须 [dispose]。
  SlotAtlas();

  /// 已栅格化的页面及复用帧缓冲。
  final List<_AtlasPage> _pages = [];

  /// 当前格子显示列表，用身份识别缓存失效。
  List<ui.Picture> _pictures = const [];

  /// 当前几何。
  SlotLayout? _layout;

  /// 最近像素比。
  double _dpr = 0;

  /// 最近像素上限。
  int _limit = 0;

  /// 每行图集单元数。
  int _columns = 0;

  /// 每页单元容量。
  int _capacity = 0;

  /// 单元像素宽。
  int _width = 0;

  /// 单元像素高。
  int _height = 0;

  /// 每个图集单元四周的设备像素边距。
  int _padding = 0;

  /// 帧内复用画笔。
  final ui.Paint _paint = ui.Paint();

  /// 页面像素尺寸；仅用于检查纹理上限，例如每边不超过 4096。
  List<ui.Size> get pageSizes => [
        for (final page in _pages)
          ui.Size(page.image.width.toDouble(), page.image.height.toDouble())
      ];

  /// 布局或格子变更时录制分页；返回是否能使用图集。
  bool prepare(List<ui.Picture> pictures, SlotLayout layout, double dpr,
      int limit, ui.FilterQuality filterQuality,
      {double padding = 0}) {
    luckyTraceStart('luckdraw.raster.atlas');
    try {
      _paint.filterQuality = filterQuality;
      if (identical(_layout, layout) &&
          _dpr == dpr &&
          _limit == limit &&
          _padding == (padding * dpr).ceil() &&
          pictures.length == _pictures.length &&
          pictures
              .asMap()
              .entries
              .every((e) => identical(e.value, _pictures[e.key]))) {
        return _pages.isNotEmpty;
      }
      dispose();
      _pictures = pictures;
      _layout = layout;
      _dpr = dpr;
      _limit = limit;
      _padding = (padding * dpr).ceil();
      _width = (layout.cellWidth * dpr).ceil() + 2 * _padding;
      _height = (layout.cellHeight * dpr).ceil() + 2 * _padding;
      if (layout.isEmpty ||
          dpr <= 0 ||
          _width <= 0 ||
          _height <= 0 ||
          _width > limit ||
          _height > limit) {
        return false;
      }
      _columns = math.min(limit ~/ _width, pictures.length);
      _capacity = _columns * (limit ~/ _height);
      final visible =
          layout.reels.fold<int>(0, (n, r) => n + r.maxVisibleCells);
      for (var first = 0; first < pictures.length; first += _capacity) {
        final count = math.min(_capacity, pictures.length - first);
        final rows = (count / _columns).ceil();
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        for (var i = 0; i < count; i++) {
          canvas.save();
          canvas.translate((i % _columns * _width).toDouble(),
              (i ~/ _columns * _height).toDouble());
          canvas.translate(_padding.toDouble(), _padding.toDouble());
          canvas.scale(dpr);
          canvas.drawPicture(pictures[first + i]);
          canvas.restore();
        }
        final picture = recorder.endRecording();
        try {
          _pages.add(_AtlasPage(
              picture.toImageSync(_columns * _width, rows * _height), visible));
        } finally {
          picture.dispose();
        }
      }
      return true;
    } finally {
      luckyTraceEnd();
    }
  }

  /// 用预分配缓冲提交每页一次绘制，边缘裁剪在源矩形中完成。
  void paint(ui.Canvas canvas, SlotFrame frame, SlotMode mode, double spacing) {
    final layout = _layout!;
    final vertical = mode == SlotMode.vertical;
    final extent = vertical ? layout.cellHeight : layout.cellWidth;
    for (final page in _pages) {
      page.used = 0;
      page.transforms.fillRange(0, page.transforms.length, 0);
      page.rects.fillRange(0, page.rects.length, 0);
    }
    for (var r = 0; r < layout.reels.length; r++) {
      final reel = layout.reels[r];
      final count = reel.stripPrizes.length;
      if (count == 0 || reel.period <= 0) continue;
      var s = frame.scroll[r] + layout.windowStart;
      if (s < 0) s = s.remainder(reel.period) + reel.period;
      if (s > reel.period) s = s.remainder(reel.period);
      final first =
          ((s - spacing / kLuckyHalfDivisor) / layout.cellAndSpacing).floor();
      for (var j = first; j < first + reel.maxVisibleCells; j++) {
        final index = j % count;
        final start =
            reel.stripStart[index] + ((j - index) ~/ count) * reel.period - s;
        if (start >= layout.windowLength) break;
        if (start + extent <= 0) continue;
        final prize = reel.stripPrizes[index];
        if (prize < 0) continue;
        final page = _pages[prize ~/ _capacity];
        final cell = prize % _capacity;
        final padding = _padding / _dpr;
        final x = vertical ? -padding : start - padding;
        final y = vertical ? start - padding : -padding;
        final left = math.max(0.0, x);
        final top = math.max(0.0, y);
        final right = math.min(reel.clipRect.width, x + _width / _dpr);
        final bottom = math.min(reel.clipRect.height, y + _height / _dpr);
        final sx = cell % _columns * _width + (left - x) * _dpr;
        final sy = cell ~/ _columns * _height + (top - y) * _dpr;
        final p = page.used++ * _stride;
        page.transforms[p] = 1 / _dpr;
        page.transforms[p + 2] = reel.clipRect.left + left;
        page.transforms[p + 3] = reel.clipRect.top + top;
        page.rects[p] = sx;
        page.rects[p + 1] = sy;
        page.rects[p + 2] = sx + (right - left) * _dpr;
        page.rects[p + 3] = sy + (bottom - top) * _dpr;
      }
    }
    for (final page in _pages) {
      // 未用槽为零面积精灵，避免帧内创建 TypedData 视图。
      canvas.drawRawAtlas(page.image, page.transforms, page.rects, null,
          ui.BlendMode.srcOver, null, _paint);
    }
  }

  /// 释放全部页面；可以重复调用，下一次 prepare 会重新录制。
  void dispose() {
    for (final page in _pages) {
      page.image.dispose();
    }
    _pages.clear();
    _pictures = const [];
    _layout = null;
  }
}

/// 单页纹理和布局阶段分配的最坏可见容量。
final class _AtlasPage {
  /// 为一页分配可复用的变换和源矩形数组。
  _AtlasPage(this.image, int visible)
      : transforms = Float32List(visible * _stride),
        rects = Float32List(visible * _stride);

  /// 自有原生纹理。
  final ui.Image image;

  /// 变换缓冲。
  final Float32List transforms;

  /// 源矩形缓冲。
  final Float32List rects;

  /// 当前有效精灵数。
  int used = 0;
}
