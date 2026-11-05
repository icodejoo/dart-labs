import 'package:flutter/foundation.dart' show internal, ValueListenable;
import 'package:flutter/widgets.dart';

import '../core/ticker.dart';

/// 统一订阅祖先 TickerMode；仅在可见性变化时同步任务静音状态。
@internal
mixin HiddenTaskState<W extends StatefulWidget> on State<W> {
  /// 当前任务应使用的静音状态，新任务入队前也读取它。
  @internal
  bool taskMuted = false;

  /// 当前祖先的可见性通知源；换祖先或销毁时移除监听。
  ValueListenable<bool>? _tickerMode;

  /// 把静音状态同步到本组件持有的任务，不改变用户暂停状态。
  @internal
  void onTaskMuteChanged(bool muted);

  /// 依赖变化时重新绑定 notifier；关闭全局开关则完全不订阅。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 使用 3.35 下限提供的接口，只读取 enabled，不依赖新版 forceFrames。
    final notifier = Countman.muteWhenHidden
        // ignore: deprecated_member_use
        ? TickerMode.getNotifier(context)
        : null;
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_syncMuted);
      _tickerMode = notifier;
      _tickerMode?.addListener(_syncMuted);
    }
    _syncMuted();
  }

  /// 通知仅作字段写入与请求帧，显示回调仍留在任务 tick 边界内。
  void _syncMuted() {
    final muted = !(_tickerMode?.value ?? true);
    if (taskMuted == muted) return;
    taskMuted = muted;
    onTaskMuteChanged(muted);
  }

  /// 释放监听，避免隐藏组件被祖先通知源持有。
  @override
  void dispose() {
    _tickerMode?.removeListener(_syncMuted);
    _tickerMode = null;
    super.dispose();
  }
}
