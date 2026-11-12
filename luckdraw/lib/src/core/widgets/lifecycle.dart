import 'package:flutter/widgets.dart';

/// 将应用生命周期转换为独立的暂停与恢复请求。
final class LuckyLifecycle {
  /// 创建监听，隐藏或暂停调用 [onPause]，恢复调用 [onResume]。
  LuckyLifecycle(
      {required VoidCallback onPause, required VoidCallback onResume})
      : _listener = AppLifecycleListener(
            onHide: onPause,
            onPause: onPause,
            onResume: onResume,
            onShow: onResume);

  /// Flutter 生命周期监听。
  final AppLifecycleListener _listener;

  /// 解除生命周期监听。
  void dispose() => _listener.dispose();
}
