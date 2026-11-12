import 'package:flutter/foundation.dart' show internal;

/// 调度器的内部休眠提示；限帧与静音任务临近到期也通过 Timer 对齐唤醒。
@internal
abstract interface class CountmanSleepHint {
  /// 最早唤醒是否可使用短等待窗口；自定义插件无需实现此接口。
  bool get useFrameWindow;
}
