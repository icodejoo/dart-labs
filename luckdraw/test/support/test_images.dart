import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 可手动成功、失败、延迟及发出多帧的图像流。
class LuckyTestImageCompleter extends ImageStreamCompleter {
  /// 创建尚未提供任何帧的图像流。
  LuckyTestImageCompleter();

  /// 当前监听器及其重复订阅次数。
  final Map<ImageStreamListener, int> _listeners = {};

  /// 最近移除的监听，用于模拟平台已经排队的迟到通知。
  ImageStreamListener? _removed;

  /// 当前监听器的数量（包含重复订阅）。
  int get listenerCount => _listeners.values.fold(0, (sum, n) => sum + n);

  /// 添加监听器并记录订阅。
  @override
  void addListener(ImageStreamListener listener) {
    _listeners[listener] = (_listeners[listener] ?? 0) + 1;
    super.addListener(listener);
  }

  /// 移除一次订阅。
  @override
  void removeListener(ImageStreamListener listener) {
    _removed = listener;
    final count = _listeners[listener];
    if (count == 1) {
      _listeners.remove(listener);
    } else if (count != null) {
      _listeners[listener] = count - 1;
    }
    super.removeListener(listener);
  }

  /// 提供一帧；克隆 [image]，原图仍由调用者释放。
  void succeed(ui.Image image, {double scale = 1}) =>
      setImage(ImageInfo(image: image.clone(), scale: scale));

  /// 向已移除的监听投递克隆帧，模拟取消时已经排队的回调。
  void deliverLateFrame(ui.Image image) =>
      _removed?.onImage(ImageInfo(image: image.clone()), false);

  /// 报告 [error]，由监听器的 onError 接收。
  void fail(Object error) =>
      reportError(context: ErrorDescription('可控测试图像加载失败'), exception: error);
}

/// 使用可控 [completer] 的图像提供者；可重复发送帧。
class LuckyTestImageProvider extends ImageProvider<LuckyTestImageProvider> {
  /// 创建可注入图像流的提供者。
  LuckyTestImageProvider(this.completer);

  /// 由测试控制的图像流。
  final LuckyTestImageCompleter completer;

  /// 同步返回当前实例作为图像缓存键。
  @override
  Future<LuckyTestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<LuckyTestImageProvider>(this);

  /// 返回可控图像流；兼容最低 Flutter 3.24 的图像加载接口。
  @override
  // ignore: deprecated_member_use
  ImageStreamCompleter loadImage(
          LuckyTestImageProvider key, ImageDecoderCallback decode) =>
      completer;
}
