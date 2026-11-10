import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../foundation/constants.dart';
import '../foundation/options.dart';
import 'perf_trace.dart';

/// 按整数段缓存录制结果；例如 `cache.picture(0, record)`。
final class LuckyPictureCache {
  /// 创建缓存；位图超过 [maxRasterSide] 时由调用方回退到 Picture。
  LuckyPictureCache(
      {this.mode = LuckyCacheMode.picture,
      this.maxRasterSide = kLuckyDefaultMaxRasterSide});

  /// 缓存模式。
  LuckyCacheMode mode;

  /// 位图最大设备像素边长。
  int maxRasterSide;

  /// 已录制显示列表。
  final Map<int, ui.Picture> _pictures = {};

  /// 已栅格化图片与对应像素尺寸。
  final Map<int, (ui.Image, int, int, double, ui.Offset)> _rasters = {};

  /// 累计录制次数。
  int _records = 0;

  /// 累计录制次数，失效不会清零。
  @visibleForTesting
  int get debugRecordCount => _records;

  /// 当前缓存位图的 RGBA 字节总数，不包含引擎或驱动的附加内存。
  @visibleForTesting
  int get debugRasterBytes => _rasters.values
      .fold(0, (bytes, raster) => bytes + raster.$2 * raster.$3 * 4);

  /// 返回 [id] 对应显示列表，首次调用 [record] 录制。
  ui.Picture picture(int id, void Function(ui.Canvas canvas) record) {
    luckyTraceStart('luckdraw.picture.record');
    try {
      final cached = _pictures[id];
      if (cached != null) return cached;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      try {
        record(canvas);
      } on Object {
        recorder.endRecording().dispose();
        rethrow;
      }
      final result = recorder.endRecording();
      _pictures[id] = result;
      _records++;
      return result;
    } finally {
      luckyTraceEnd();
    }
  }

  /// 返回物理像素位图；picture 模式、零尺寸或超限时返回 null。
  ///
  /// [origin] 是逻辑坐标中的左上角；例如负坐标球体可传其包围盒原点。
  ui.Image? raster(int id, ui.Size logicalSize, double devicePixelRatio,
      void Function(ui.Canvas canvas) record,
      {ui.Offset origin = ui.Offset.zero}) {
    luckyTraceStart('luckdraw.raster.build');
    try {
      final width = (logicalSize.width * devicePixelRatio).ceil();
      final height = (logicalSize.height * devicePixelRatio).ceil();
      if (mode == LuckyCacheMode.picture ||
          width <= 0 ||
          height <= 0 ||
          width > maxRasterSide ||
          height > maxRasterSide) {
        return null;
      }
      final old = _rasters[id];
      if (old != null &&
          old.$2 == width &&
          old.$3 == height &&
          old.$4 == devicePixelRatio &&
          old.$5 == origin) {
        return old.$1;
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..scale(devicePixelRatio)
        ..translate(-origin.dx, -origin.dy);
      canvas.drawPicture(picture(id, record));
      final scaled = recorder.endRecording();
      try {
        final result = scaled.toImageSync(width, height);
        _rasters[id] = (result, width, height, devicePixelRatio, origin);
        old?.$1.dispose();
        return result;
      } finally {
        scaled.dispose();
      }
    } finally {
      luckyTraceEnd();
    }
  }

  /// 失效单个段并释放原生资源。
  void invalidate(int id) {
    _pictures.remove(id)?.dispose();
    _rasters.remove(id)?.$1.dispose();
  }

  /// 失效全部段并释放原生资源。
  void invalidateAll() {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    for (final raster in _rasters.values) {
      raster.$1.dispose();
    }
    _pictures.clear();
    _rasters.clear();
  }

  /// 释放全部缓存；可重复调用。
  void dispose() => invalidateAll();
}
