import 'dart:async';

import 'package:layerman/layerman.dart';

/// 排空引擎依赖的异步续体，不创建 Flutter 绑定。
Future<void> flushAsync() => Future<void>.delayed(Duration.zero);

/// 无界面的可控后端，显式确认 dismissed。
class HeadlessBackend<T> {
  /// 后端结束信号。
  final done = Completer<T?>();

  /// 展示时绑定的类型化上下文。
  PresentContext<T>? context;

  /// 记录是否已出场。
  bool get shown => context != null;

  /// 模拟展示与定向关闭。
  PresentedOverlay<T> present(PresentContext<T> ctx) {
    context = ctx;
    return PresentedOverlay<T>(
        dismissed: done.future,
        dismiss: ([result]) async {
          if (!done.isCompleted) done.complete(result);
        });
  }
}

