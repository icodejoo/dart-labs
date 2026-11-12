import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 内部位图 LRU；按实际像素计费，失败或单张超预算时返回 null。
@internal
class ImageByteCache<K> {
  ImageByteCache(this.maxBytes);

  static const _bytesPerPixel = 4;
  final int maxBytes;
  final _entries = <K, ui.Image>{};
  int _bytes = 0;

  @visibleForTesting
  int get bytes => _bytes;

  @visibleForTesting
  int get length => _entries.length;

  /// 命中时更新顺序；生成时包含逻辑边距，绘制原点仍在原矩形左上角。
  ui.Image? obtain(K key, {
    required ui.Size size,
    required double ratio,
    double padding = 0,
    required void Function(ui.Canvas) draw,
  }) {
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    try {
      final width = size.width + padding * 2;
      final height = size.height + padding * 2;
      final w = (width * ratio).ceil();
      final h = (height * ratio).ceil();
      final cost = w * h * _bytesPerPixel;
      if (size.isEmpty || w <= 0 || h <= 0 || cost > maxBytes) return null;
      recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..scale(w / width, h / height)
        ..translate(padding, padding);
      draw(canvas);
      picture = recorder.endRecording();
      final image = picture.toImageSync(w, h);
      while (_bytes + cost > maxBytes) {
        final oldest = _entries.remove(_entries.keys.first)!;
        _bytes -= oldest.width * oldest.height * _bytesPerPixel;
        oldest.dispose();
      }
      _entries[key] = image;
      _bytes += cost;
      return image;
    } catch (_) {
      return null;
    } finally {
      // 绘制或生成失败也释放录制资源。
      if (recorder?.isRecording ?? false) picture = recorder!.endRecording();
      picture?.dispose();
    }
  }

  /// 释放全部位图并清零计费；下次按需重建。
  void clear() {
    for (final image in _entries.values) {
      image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }
}
