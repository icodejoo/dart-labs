import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

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
  /// 对外发布、负责通知监听者的状态。
  final ValueNotifier<CountmanRunState> _runState =
      ValueNotifier<CountmanRunState>(CountmanRunState.idle);

  /// 最新状态；可能比 [_runState] 早一帧（构建期写入时通知被推迟）。
  CountmanRunState _current = CountmanRunState.idle;

  /// 是否已登记了帧末的推迟通知，同一帧内多次写入只通知一次。
  bool _publishScheduled = false;

  /// 是否已释放，释放后推迟的通知直接丢弃。
  bool _runStateDisposed = false;

  /// 当前运行状态，初始为 [CountmanRunState.idle]；总是最新值。
  CountmanRunState get runState => _current;

  /// 可监听的运行状态；仅在状态真正变化时通知，不要手动 dispose。
  /// 组件挂载等构建期写入的变化会在当帧结束后再通知，避免监听者在构建期间 setState。
  ValueListenable<CountmanRunState> get runStateListenable => _runState;

  /// 由展示组件调用，业务代码不要直接调用。
  /// 写入新的 [state]；与当前状态相同时不通知，无返回值。
  /// 构建/布局/绘制阶段写入时推迟到帧末通知，其余时机立即通知。
  /// 例如绑定任务后 `controller.setRunState(CountmanRunState.running)`。
  @internal
  void setRunState(CountmanRunState state) {
    if (_runStateDisposed || _current == state) return;
    _current = state;
    if (!_inPersistentPhase()) {
      _runState.value = state;
      return;
    }
    if (_publishScheduled) return;
    _publishScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      if (!_runStateDisposed) _runState.value = _current;
    });
  }

  /// 是否处于构建/布局/绘制阶段；未初始化 Flutter 绑定（纯 Dart 单测）时视为否。
  static bool _inPersistentPhase() {
    try {
      return SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks;
    } catch (_) {
      return false;
    }
  }

  /// 释放状态通知器；控制器自身被销毁时调用，调用后不得再监听或写入。
  @protected
  void disposeRunState() {
    _runStateDisposed = true;
    _runState.dispose();
  }
}
