import 'package:countman/src/core/run_state.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:flutter/foundation.dart' show VoidCallback, internal;

/// 由展示组件调用的任务重启函数，业务代码不要直接调用。
/// [duration] 为空时采用组件配置；无返回值。例如绑定时传入 `relaunch: _relaunch`。
typedef CountdownRelaunch = void Function({Duration? duration});

/// 倒计时展示组件的命令式控制器，结束后 reset 会请求组件重启。
///
/// 传给展示组件的 `controller` 参数后，可调用 [pause]、[resume]、[reset]、[cancel]、
/// [restart]，读取 [remaining] / [isPaused] / [isDone]，并通过 [runState] /
/// [runStateListenable] 观察 idle / running / paused / completed 四种运行状态。
///
/// 示例：
/// ```dart
/// final c = CountdownController();
/// c.runStateListenable.addListener(() => print(c.runState));
/// // TextCountdown(to: Duration(minutes: 5), controller: c) 之后：
/// c.pause();
/// c.restart();
/// ```
class CountdownController with CountmanRunStateNotifier {
  /// 当前绑定的任务句柄；未绑定时为 null。
  CountdownHandle? _handle;

  /// 保存展示组件提供的重启动作。
  CountdownRelaunch? _relaunch;

  /// 保存展示组件提供的“按当前配置从头开始”动作。
  VoidCallback? _restart;

  /// 已释放后忽略展示组件迟到的状态写入。
  bool _disposed = false;

  /// 由展示组件调用，业务代码不要直接调用。
  /// 绑定 [handle]、结束后使用的 [relaunch] 与 [restart]，替换已有绑定；无返回值。
  /// 例如 `controller.attach(handle, relaunch: relaunch, restart: restart)`。
  @internal
  void attach(
    CountdownHandle handle, {
    CountdownRelaunch? relaunch,
    VoidCallback? restart,
  }) {
    _handle = handle;
    _relaunch = relaunch;
    _restart = restart;
  }

  /// 由展示组件调用，业务代码不要直接调用。
  /// [handle] 为空时无条件解绑，否则仅解绑相同实例，并清除重启动作，状态回到 idle；
  /// 无返回值。例如 `controller.detach(handle)`；旧式 `controller.detach()` 仍可用。
  @internal
  void detach([CountdownHandle? handle]) {
    if (handle != null && !identical(_handle, handle)) return;
    _handle = null;
    _relaunch = null;
    _restart = null;
    setRunState(CountmanRunState.idle);
  }

  /// 展示组件写入运行状态；控制器已释放后静默忽略，避免组件晚于控制器销毁时抛异常。
  @internal
  @override
  void setRunState(CountmanRunState state) {
    if (_disposed) return;
    super.setRunState(state);
  }

  /// 按存活任务的真实状态刷新 runState（运行中或已暂停）；任务已结束则保持原状态。
  void _syncLive(CountdownHandle handle) {
    if (handle.isDone) return;
    setRunState(
        handle.isPaused ? CountmanRunState.paused : CountmanRunState.running);
  }

  /// 暂停倒计时，runState 变为 paused；未绑定或已结束时无操作。
  void pause() {
    final handle = _handle;
    if (handle == null) return;
    handle.pause();
    _syncLive(handle);
  }

  /// 恢复已暂停的倒计时，runState 回到 running；未暂停时无操作。
  void resume() {
    final handle = _handle;
    if (handle == null) return;
    handle.resume();
    _syncLive(handle);
  }

  /// 重置并恢复倒计时；[duration] 为空时存活任务沿用原时长，结束后采用组件配置。
  /// 已结束或取消时请求展示组件重启，未绑定时无操作；无返回值。
  /// 例如 `controller.reset(duration: Duration(seconds: 10))`。
  void reset({Duration? duration}) {
    final handle = _handle;
    if (handle != null && !handle.isDone) {
      handle.reset(duration: duration);
      _syncLive(handle);
    } else {
      _relaunch?.call(duration: duration);
    }
  }

  /// 按组件当前配置（`to` / `duration`、`total`、取整方式）从头重新开始，
  /// 运行中、暂停中或结束后均可用，并回到 running；未绑定时无操作。
  /// 与 [reset] 的区别：[reset] 沿用存活任务的时长，[restart] 重新读取组件配置。
  /// 例如 `controller.restart()`。
  void restart() => _restart?.call();

  /// 立即移除底层任务，runState 变为 idle；任务已自然完成时保持 completed。
  void cancel() => _handle?.cancel();

  /// 当前剩余时间；未绑定或已取消时为 [Duration.zero]。
  Duration get remaining => _handle?.remaining ?? Duration.zero;

  /// 倒计时当前暂停时为 true。
  bool get isPaused => _handle?.isPaused ?? false;

  /// 倒计时已完成（或尚未绑定）时为 true。
  bool get isDone => _handle?.isDone ?? true;

  /// 释放运行状态通知器；调用后不得再监听 [runStateListenable]，晚到的状态写入被忽略。
  /// 不调用也不会影响倒计时，仅在需要严格释放监听时使用。
  void dispose() {
    _disposed = true;
    disposeRunState();
  }
}
