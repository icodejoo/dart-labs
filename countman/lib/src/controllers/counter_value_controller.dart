import 'package:countman/src/core/run_state.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show VoidCallback, internal;

/// 由展示组件调用的任务重启函数，业务代码不要直接调用。
/// [to] 为目标值，[duration]、[curve] 为空时沿用组件配置；无返回值。
/// 例如展示组件绑定时传入 `relaunch: _relaunch`。
typedef CounterRelaunch = void Function({
  required double to,
  Duration? duration,
  Curve? curve,
});

/// 计数展示组件的命令式控制器，完成后的 update 会请求组件重启任务。
///
/// 传给展示组件的 `controller` 参数后，可调用 [update] 改目标、[pause] / [resume]
/// 暂停恢复、[cancel] 取消、[restart] 按组件当前配置从头播放，并通过 [value] 读取
/// 当前动画数值，通过 [runState] / [runStateListenable] 观察 idle / running /
/// paused / completed 四种运行状态。与 `CountdownController` 的结构一致。
///
/// 示例：
/// ```dart
/// final c = CounterValueController();
/// c.runStateListenable.addListener(() => print(c.runState));
/// // TextCounter(to: 100, controller: c) 之后：
/// c.update(to: 500);
/// c.restart();
/// ```
class CounterValueController with CountmanRunStateNotifier {
  /// 当前绑定的任务句柄；未绑定时为 null。
  CounterHandle? _handle;

  /// 展示组件最近写入的显示值。
  double _value = 0;

  /// 保存展示组件提供的重启动作（从当前值到新目标）。
  CounterRelaunch? _relaunch;

  /// 保存展示组件提供的“按当前配置从头开始”动作。
  VoidCallback? _restart;

  /// 已释放后忽略展示组件迟到的状态写入。
  bool _disposed = false;

  /// 由展示组件调用，业务代码不要直接调用。
  /// 绑定 [handle]、结束后使用的 [relaunch] 与 [restart]，替换已有绑定；无返回值。
  /// 例如 `controller.attach(handle, relaunch: relaunch, restart: restart)`。
  @internal
  void attach(
    CounterHandle handle, {
    CounterRelaunch? relaunch,
    VoidCallback? restart,
  }) {
    _handle = handle;
    _relaunch = relaunch;
    _restart = restart;
  }

  /// 由展示组件调用，业务代码不要直接调用。
  /// [handle] 为空时无条件解绑，否则仅解绑相同实例，并清除重启动作，状态回到 idle；
  /// 无返回值。例如销毁时 `controller.detach(handle)`；旧式 `controller.detach()` 仍可用。
  @internal
  void detach([CounterHandle? handle]) {
    if (handle != null && !identical(_handle, handle)) return;
    _handle = null;
    _relaunch = null;
    _restart = null;
    setRunState(CountmanRunState.idle);
  }

  /// 由展示组件调用，业务代码不要直接调用；写入当前显示值 [v]，无返回值。
  /// 例如每帧 `controller.latestValue = value`。
  @internal
  set latestValue(double v) => _value = v;

  /// 展示组件写入运行状态；控制器已释放后静默忽略，避免组件晚于控制器销毁时抛异常。
  @internal
  @override
  void setRunState(CountmanRunState state) {
    if (_disposed) return;
    super.setRunState(state);
  }

  /// 按存活任务的真实状态刷新 runState（运行中或已暂停）；任务已结束则保持原状态。
  void _syncLive(CounterHandle handle) {
    if (handle.isDone) return;
    setRunState(
        handle.isPaused ? CountmanRunState.paused : CountmanRunState.running);
  }

  /// 从当前值更新到 [to]；[duration]、[curve] 为空时沿用任务或组件配置。
  /// 任务结束后请求展示组件重启，未绑定时无操作；无返回值。
  /// 例如 `controller.update(to: 500, duration: Duration(seconds: 1))`。
  void update({required double to, Duration? duration, Curve? curve}) {
    final handle = _handle;
    if (handle != null && !handle.isDone) {
      handle.update(to: to, duration: duration, curve: curve);
    } else {
      _relaunch?.call(to: to, duration: duration, curve: curve);
    }
  }

  /// 按组件当前配置（`from`、`to`、时长、曲线）从头重新播放，
  /// 运行中、暂停中或结束后均可用，并回到 running；未绑定时无操作。
  /// 例如 `controller.restart()`。
  void restart() => _restart?.call();

  /// 将动画冻结在当前值，runState 变为 paused；未绑定或已结束时无操作。
  void pause() {
    final handle = _handle;
    if (handle == null) return;
    handle.pause();
    _syncLive(handle);
  }

  /// 恢复已暂停的动画，runState 回到 running；未暂停时无操作。
  void resume() {
    final handle = _handle;
    if (handle == null) return;
    handle.resume();
    _syncLive(handle);
  }

  /// 立即移除底层任务，runState 变为 idle；任务已自然完成时保持 completed。
  void cancel() => _handle?.cancel();

  /// 展示组件最近报告的动画值（启动前为 0）。
  double get value => _value;

  /// 动画运行中（未暂停、未完成）时为 true。
  bool get isAnimating => _handle?.isAnimating ?? false;

  /// 动画当前暂停时为 true。
  bool get isPaused => _handle?.isPaused ?? false;

  /// 动画已完成（或尚未绑定）时为 true。
  bool get isDone => _handle?.isDone ?? true;

  /// 释放运行状态通知器；调用后不得再监听 [runStateListenable]，晚到的状态写入被忽略。
  /// 不调用也不会影响动画，仅在需要严格释放监听时使用。
  void dispose() {
    _disposed = true;
    disposeRunState();
  }
}
