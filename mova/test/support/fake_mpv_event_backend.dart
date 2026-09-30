import 'package:mova/src/core/kernel/mpv_event_backend.dart';

/// 假实现：用于单测的 mpv 事件后端。
class FakeMpvEventBackend implements MovaMpvEventBackend {
  /// 是否在 [createClient] 时直接返回 false。
  bool createFail = false;
  
  /// 是否在 [restrictEvents] 时返回 false。
  bool restrictFail = false;
  
  /// 在 [createClient] 时需要抛出的异常。
  Object? createThrow;

  /// 在 [restrictEvents] 时需要抛出的异常。
  Object? restrictThrow;

  /// 在 [armWakeup] 时需要抛出的异常。
  Object? armThrow;

  /// 在 [poll] 时需要抛出的异常（如果不为空）。
  Object? pollThrow;
  
  /// 在 [destroy] 时需要抛出的异常（如果不为空）。
  Object? destroyThrow;
  
  /// 事件队列，供 [poll] 取用。
  final List<MovaRawEvent> events = [];
  
  /// 记录的调用序列，可用于断言顺序。
  final List<String> callLog = [];
  
  /// 成功调用 createClient 的次数。
  int createCount = 0;
  
  /// 成功调用 destroy (销毁句柄阶段) 的次数。
  int destroyCount = 0;
  
  void Function()? _onWake;
  
  /// 备份最近一次注册的唤醒回调，用于测试迟到的事件唤醒。
  void Function()? _lastOnWake;
  
  /// 记录 [restrictEvents] 收到的事件集合。
  Set<int>? lastRestrictedEvents;
  
  /// 在 [createClient] 之后调用的钩子。
  void Function()? onCreateClient;
  
  /// 在 [restrictEvents] 之后调用的钩子。
  void Function()? onRestrictEvents;

  @override
  bool createClient(String name) {
    callLog.add('createClient');
    if (createThrow != null) throw createThrow!;
    if (createFail) return false;
    createCount++;
    onCreateClient?.call();
    return true;
  }

  @override
  bool restrictEvents(Set<int> keep) {
    callLog.add('restrictEvents');
    if (restrictThrow != null) throw restrictThrow!;
    lastRestrictedEvents = keep;
    final result = !restrictFail;
    onRestrictEvents?.call();
    return result;
  }

  /// 在 [armWakeup] 之后调用的钩子。
  void Function()? onArmWakeup;

  @override
  void armWakeup(void Function() onWake) {
    callLog.add('armWakeup');
    if (armThrow != null) throw armThrow!;
    _onWake = onWake;
    _lastOnWake = onWake;
    onArmWakeup?.call();
  }

  /// 手动触发唤醒（模拟原生投递）。
  /// 
  /// 示例：`backend.wake()`
  void wake() {
    _onWake?.call();
  }

  /// 模拟“迟到的已排队唤醒”，绕过注销，直接调用最后一次 arm 的回调副本。
  void staleWake() {
    _lastOnWake?.call();
  }

  @override
  MovaRawEvent? poll() {
    callLog.add('poll');
    if (pollThrow != null) throw pollThrow!;
    if (events.isEmpty) return null;
    return events.removeAt(0);
  }

  @override
  void destroy() {
    callLog.add('destroy');
    if (destroyThrow != null) throw destroyThrow!;
    // 要求：destroy 记录“先注销通知再销毁句柄”两步
    callLog.add('注销通知');
    _onWake = null;
    callLog.add('销毁句柄');
    destroyCount++;
  }
}
