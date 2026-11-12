import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../foundation/image.dart';
import '../render/perf_trace.dart';
import 'image_set.dart';

/// 解码尺寸滞回的放大上界（ARCHITECTURE §8.3）。
const double _growLimit = 1.25;

/// 解码尺寸滞回的缩小下界（ARCHITECTURE §8.3）。
const double _shrinkLimit = 0.5;

/// 每个 RGBA 像素的估算字节数。
const int _pixelBytes = 4;

/// 图片解析器：首帧、目标解码、转换、后备图和失效资源由实例管理。
///
/// 调用 `update(requests, configuration, dpr)` 更新请求；用完须调用 [dispose]。
final class LuckyImageResolver implements LuckyImageSet {
  /// 创建解析器；三个回调均在对应事件有结论时调用。
  LuckyImageResolver(
      {required VoidCallback onChanged,
      required ValueChanged<LuckyImageError> onError,
      required VoidCallback onReady})
      : _onChanged = onChanged,
        _onError = onError,
        _onReady = onReady;

  /// 图片更新回调。
  final VoidCallback _onChanged;

  /// 错误回调。
  final ValueChanged<LuckyImageError> _onError;

  /// 全部请求结算回调。
  final VoidCallback _onReady;

  /// 槽位状态。
  final Map<LuckyImageSlot, _ImageEntry> _entries = {};

  /// 当前版本。
  int _generation = 0;

  /// 当前集合是否已经通知就绪。
  bool _ready = false;

  /// 是否释放。
  bool _disposed = false;

  /// 是否正在批量更新，避免同步图片提前触发就绪。
  bool _updating = false;

  /// 当前只读图片集合。
  LuckyImageSet get images => this;

  /// 当前图片版本。
  @override
  int get generation => _generation;

  /// 返回对应槽位的已解析图片。
  @override
  LuckyResolvedImage? operator [](LuckyImageSlot slot) =>
      _entries[slot]?.resolved;

  /// 所有图片是否都有结论。
  @override
  bool get isSettled => _entries.values.every((entry) => entry.settled);

  /// 当前本解析器挂接的监听数，不含 Flutter 全局缓存监听。
  @visibleForTesting
  int get debugListenerCount =>
      _entries.values.where((entry) => entry.listener != null).length;

  /// 当前持有图片的 RGBA 字节估算。
  int get debugDecodedBytes => _entries.values.fold(0, (sum, entry) {
        final image = entry.resolved?.image ?? entry.pendingSource;
        return sum +
            (image == null ? 0 : image.width * image.height * _pixelBytes);
      });

  /// 更新图片请求；相同槽位、源、转换器、配置和滞回内尺寸复用首帧。
  ///
  /// [devicePixelRatio] 必须为正有限值；旧请求的迟到转换产物会被释放。
  void update(List<LuckyImageRequest> requests,
      ImageConfiguration configuration, double devicePixelRatio) {
    luckyTraceStart('luckdraw.image.update');
    try {
      assert(!_disposed);
      assert(devicePixelRatio > 0 && devicePixelRatio.isFinite);
      _updating = true;
      _ready = false;
      _generation++;
      final old = Map<LuckyImageSlot, _ImageEntry>.of(_entries);
      _entries.clear();
      for (final request in requests) {
        assert(!_entries.containsKey(request.slot));
        final previous = old.remove(request.slot);
        if (previous != null &&
            previous.reusable(request, configuration, devicePixelRatio)) {
          _entries[request.slot] = previous;
        } else {
          previous?.dispose();
          _entries[request.slot] =
              _ImageEntry(request, configuration, devicePixelRatio);
        }
      }
      for (final entry in old.values) {
        entry.dispose();
      }
      for (final entry in _entries.values) {
        if (!entry.started) {
          _listen(entry, entry.request.provider, false);
        }
      }
      _updating = false;
      _checkReady();
    } finally {
      luckyTraceEnd();
    }
  }

  /// 是否仍然拥有该请求。
  bool _owns(_ImageEntry entry) =>
      !_disposed && identical(_entries[entry.request.slot], entry);

  /// 订阅首帧；监听字段在 addListener 前就绪，支持同步缓存命中。
  void _listen(
      _ImageEntry entry, ImageProvider<Object> provider, bool fallback) {
    entry.started = true;
    final width = entry.width;
    final height = entry.height;
    final actual = width == null && height == null
        ? provider
        : ResizeImage(provider,
            width: width,
            height: height,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false);
    final stream = actual.resolve(entry.configuration);
    entry.stream = stream;
    final listener = ImageStreamListener((info, synchronous) {
      entry.unlisten();
      final source = info.image.clone();
      final scale = info.scale;
      info.dispose();
      if (!_owns(entry)) {
        source.dispose();
        return;
      }
      entry.pendingSource = source;
      unawaited(_format(entry, source, scale, fallback));
    }, onError: (Object error, StackTrace? stack) {
      entry.unlisten();
      _failure(entry, error, stack, fallback);
    });
    entry.listener = listener;
    stream.addListener(listener);
  }

  /// 执行可能异步的转换，并明确移交与回收图片所有权。
  Future<void> _format(
      _ImageEntry entry, ui.Image source, double scale, bool fallback) async {
    ui.Image? output;
    try {
      final formatter = entry.request.image.formatter;
      if (formatter == null) {
        output = source;
      } else {
        final value = formatter(source);
        output = value is Future<ui.Image> ? await value : value;
      }
    } on Object catch (error, stack) {
      entry.releaseSource();
      _failure(entry, error, stack, fallback);
      return;
    }
    if (!_owns(entry)) {
      if (!identical(output, source)) {
        output.dispose();
      }
      entry.releaseSource();
      return;
    }
    if (!identical(output, source)) {
      entry.releaseSource();
    } else {
      entry.pendingSource = null;
    }
    final w = entry.request.decodeLogicalWidth;
    final h = entry.request.decodeLogicalHeight;
    final natural = w == null && h == null
        ? ui.Size(output.width / scale, output.height / scale)
        : w != null && h == null
            ? ui.Size(w, w * output.height / output.width)
            : w == null && h != null
                ? ui.Size(h * output.width / output.height, h)
                : ui.Size(output.width / entry.dpr, output.height / entry.dpr);
    entry.resolved = LuckyResolvedImage(output, natural);
    entry.settled = true;
    _changed();
  }

  /// 报错并尝试后备图；最终失败仍算已有结论。
  void _failure(
      _ImageEntry entry, Object error, StackTrace? stack, bool fallback) {
    if (!_owns(entry)) return;
    _onError(LuckyImageError(
        slot: entry.request.slot,
        error: error,
        stackTrace: stack,
        usedFallback: fallback));
    if (!_owns(entry)) return;
    final provider = entry.request.image.fallback;
    if (!fallback && provider != null) {
      _listen(entry, provider, true);
    } else {
      entry.settled = true;
      _changed();
    }
  }

  /// 增加图片版本并通知。
  void _changed() {
    _generation++;
    _onChanged();
    _checkReady();
  }

  /// 每轮更新最多通知一次全部就绪。
  void _checkReady() {
    if (!_disposed && !_updating && !_ready && isSettled) {
      _ready = true;
      _onReady();
    }
  }

  /// 移除全部监听并释放持有图片；可重复调用。
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
  }
}

/// 单槽请求的所有权与订阅状态。
final class _ImageEntry {
  /// 保存本次请求与解码环境。
  _ImageEntry(this.request, this.configuration, this.dpr);

  /// 原始请求。
  final LuckyImageRequest request;

  /// 解析环境。
  final ImageConfiguration configuration;

  /// 解码像素比。
  final double dpr;

  /// 当前图像流。
  ImageStream? stream;

  /// 当前监听器。
  ImageStreamListener? listener;

  /// 首帧结果。
  LuckyResolvedImage? resolved;

  /// 尚在转换中的借出源图，转换完成后才可释放。
  ui.Image? pendingSource;

  /// 是否开始过解析。
  bool started = false;

  /// 是否已有结论。
  bool settled = false;

  /// 目标设备像素宽度。
  int? get width => _pixels(request.decodeLogicalWidth);

  /// 目标设备像素高度。
  int? get height => _pixels(request.decodeLogicalHeight);

  /// 将逻辑长度转为至少一个像素。
  int? _pixels(double? value) =>
      value == null ? null : (value * dpr).round().clamp(1, 0x7fffffff);

  /// 判断新尺寸是否在滞回区间。
  bool _near(int? old, int? next) => old == null || next == null
      ? old == next
      : next >= old * _shrinkLimit && next <= old * _growLimit;

  /// 请求源与解码环境是否可复用。
  bool reusable(
          LuckyImageRequest next, ImageConfiguration config, double ratio) =>
      request.provider == next.provider &&
      request.image.formatter == next.image.formatter &&
      request.image.fallback == next.image.fallback &&
      configuration == config &&
      dpr == ratio &&
      _near(
          width,
          next.decodeLogicalWidth == null
              ? null
              : (next.decodeLogicalWidth! * ratio).round()) &&
      _near(
          height,
          next.decodeLogicalHeight == null
              ? null
              : (next.decodeLogicalHeight! * ratio).round());

  /// 移除解析器持有的监听。
  void unlisten() {
    final current = listener;
    listener = null;
    if (current != null) {
      stream!.removeListener(current);
    }
  }

  /// 释放订阅及结果。
  void dispose() {
    unlisten();
    // FutureOr formatter 未提供协作取消；源图由 _format 在完成后回收。
    resolved?.image.dispose();
    resolved = null;
  }

  /// 释放尚未转移所有权的转换源图，允许重复调用。
  void releaseSource() {
    pendingSource?.dispose();
    pendingSource = null;
  }
}
