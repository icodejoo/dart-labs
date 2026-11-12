import 'package:flutter/widgets.dart';

/// 表面 State 的图片到达监听：初始化挂接、控制器更换时换挂、销毁时摘除。
///
/// 例如 `class _S extends State<W> with LuckyImagesListener<W>`，
/// 再实现 [imagesListenableOf] 与 [onImagesChanged]。
mixin LuckyImagesListener<T extends StatefulWidget> on State<T> {
  /// 取 [widget] 携带的图片通知源。
  Listenable imagesListenableOf(T widget);

  /// 图片到达时的重录或失效动作。
  void onImagesChanged();

  /// 挂接图片通知。
  @override
  void initState() {
    super.initState();
    imagesListenableOf(widget).addListener(onImagesChanged);
  }

  /// 通知源更换时从旧源摘除并挂到新源。
  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = imagesListenableOf(oldWidget);
    final next = imagesListenableOf(widget);
    if (old != next) {
      old.removeListener(onImagesChanged);
      next.addListener(onImagesChanged);
    }
  }

  /// 摘除图片通知。
  @override
  void dispose() {
    imagesListenableOf(widget).removeListener(onImagesChanged);
    super.dispose();
  }
}
