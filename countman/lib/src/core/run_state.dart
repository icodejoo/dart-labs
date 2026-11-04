import 'package:flutter/foundation.dart';

/// 控制器的运行状态，供展示组件与业务代码统一观察。
enum CountmanRunState {
  /// 尚未启动，或任务已被取消。
  idle,

  /// 正在运行。
  running,

  /// 已暂停，可恢复。
  paused,

  /// 已自然完成。
  completed,
}

/// 为控制器提供可监听的运行状态的 mixin。
///
/// 控制器 `with CountmanRunStateNotifier` 后，业务侧可读取 [runState] 或监听
/// [runStateListenable]；展示组件绑定任务后通过 [setRunState] 同步状态。
///
/// 示例：
/// ```dart
/// class MyController with CountmanRunStateNotifier {}
///
/// final c = MyController();
/// c.runStateListenable.addListener(() => print(c.runState));
/// ```
mixin CountmanRunStateNotifier {
  /// 持有当前状态并负责通知监听者。
  final ValueNotifier<CountmanRunState> _runState =
      ValueNotifier<CountmanRunState>(CountmanRunState.idle);

  /// 当前运行状态，初始为 [CountmanRunState.idle]。
  CountmanRunState get runState => _runState.value;

  /// 可监听的运行状态；仅在状态真正变化时通知，不要手动 dispose。
  ValueListenable<CountmanRunState> get runStateListenable => _runState;

  /// 由展示组件调用，业务代码不要直接调用。
  /// 写入新的 [state]；与当前状态相同时不通知，无返回值。
  /// 例如绑定任务后 `controller.setRunState(CountmanRunState.running)`。
  @internal
  void setRunState(CountmanRunState state) {
    if (_runState.value == state) return;
    _runState.value = state;
  }

  /// 释放状态通知器；控制器自身被销毁时调用，调用后不得再监听或写入。
  @protected
  void disposeRunState() => _runState.dispose();
}
