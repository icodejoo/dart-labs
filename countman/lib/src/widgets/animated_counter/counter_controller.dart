// Adapted from flip_counter_plus (MIT).
// Original: https://github.com/Itsxhadi/flip_counter_plus

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/widgets.dart';

import 'package:countman/src/core/run_state.dart';

/// 动画计数组件的命令式控制器，由当前绑定的展示组件响应命令。
///
/// 传给 `AnimatedCounter.controller`（或 `AnimatedCounterBuilder.controller`）后，
/// 可调用 [animateTo]、[jumpTo]、[pause]、[resume]、[stop]、[restart]、[repeat]、
/// [reverse]。通过 [runState] / [runStateListenable] 观察 idle / running / paused /
/// completed 四种运行状态，通过 [status] / [addStatusListener] 观察方向与端点状态。
///
/// 示例：
/// ```dart
/// final c = AnimatedCounterController();
/// c.runStateListenable.addListener(() => print(c.runState));
/// // AnimatedCounter(controller: c) 之后：
/// c.animateTo(100);
/// ```
class AnimatedCounterController extends ChangeNotifier
    with CountmanRunStateNotifier {
  /// 创建控制器；[initialValue] 为 [value] 的初值。
  AnimatedCounterController({num initialValue = 0}) : _value = initialValue;

  /// 当前目标值。
  num _value;

  /// 本次命令临时覆盖的时长；null 表示用组件配置。
  Duration? _overrideDuration;

  /// 已释放后忽略展示组件迟到的状态写入。
  bool _disposed = false;

  /// 当前绑定的 State 标记，未绑定时为 null；例如组件绑定时 `$owner = this`。
  ///
  /// 由展示组件调用，包内使用，业务代码不要直接访问。
  @internal
  Object? $owner;

  /// 暂停命令的回调；由展示组件绑定，包内使用。
  @internal
  VoidCallback? $pauseCallback;

  /// 恢复命令的回调；由展示组件绑定，包内使用。
  @internal
  VoidCallback? $resumeCallback;

  /// 停止命令的回调；由展示组件绑定，包内使用。
  @internal
  VoidCallback? $stopCallback;

  /// 重启命令的回调；由展示组件绑定，包内使用。
  @internal
  VoidCallback? $restartCallback;

  /// 循环播放命令的回调；由展示组件绑定，包内使用。
  @internal
  void Function({bool reverse})? $repeatCallback;

  /// 反向命令的回调；由展示组件绑定，包内使用。
  @internal
  VoidCallback? $reverseCallback;

  /// 读取展示组件当前播放状态的回调；由展示组件绑定，包内使用。
  @internal
  ValueGetter<AnimationStatus>? $statusGetter;

  /// 状态监听者列表；包内使用，业务代码请用 [addStatusListener]。
  @internal
  final List<AnimationStatusListener> $statusListeners = [];

  /// 当前目标值。
  num get value => _value;

  /// 本次命令临时覆盖的时长（[jumpTo] 为 [Duration.zero]）；null 表示沿用组件配置。
  Duration? get overrideDuration => _overrideDuration;

  /// 动画滚动到 [targetValue]，使用组件配置的时长。
  void animateTo(num targetValue) {
    _overrideDuration = null;
    _value = targetValue;
    notifyListeners();
  }

  /// 立即跳到 [targetValue]，不播放动画。
  void jumpTo(num targetValue) {
    _overrideDuration = Duration.zero;
    _value = targetValue;
    notifyListeners();
  }

  /// 暂停当前动画；仅在运行中有效。
  void pause() => $pauseCallback?.call();

  /// 恢复被暂停的动画；仅在暂停态有效。
  void resume() => $resumeCallback?.call();

  /// 停止动画并清掉待启动动作，状态回到 idle。
  void stop() => $stopCallback?.call();

  /// 从当前端点的起点重新播放。
  void restart() => $restartCallback?.call();

  /// 循环播放；[reverse] 为 true 时每轮结束后交换端点往返。
  void repeat({bool reverse = false}) => $repeatCallback?.call(reverse: reverse);

  /// 反向播放：交换起止端点，从当前位置往回走。
  void reverse() => $reverseCallback?.call();

  /// 当前播放方向或端点状态；pause 保持原方向，reverse 到起点发 dismissed。
  /// 例如 `controller.status == AnimationStatus.reverse`。
  AnimationStatus get status => $statusGetter?.call() ?? AnimationStatus.dismissed;

  /// 添加播放状态监听。
  void addStatusListener(AnimationStatusListener listener) =>
      $statusListeners.add(listener);

  /// 移除播放状态监听。
  void removeStatusListener(AnimationStatusListener listener) =>
      $statusListeners.remove(listener);

  /// 向所有状态监听者广播 [status]；由展示组件调用，包内使用。
  @internal
  void $notifyStatusListeners(AnimationStatus status) {
    for (final l in List.of($statusListeners)) {
      l(status);
    }
  }

  /// 展示组件写入运行状态；控制器已释放后静默忽略，避免组件晚于控制器销毁时抛异常。
  @internal
  @override
  void setRunState(CountmanRunState state) {
    if (_disposed) return;
    super.setRunState(state);
  }

  /// 释放控制器及运行状态通知器。
  @override
  void dispose() {
    _disposed = true;
    disposeRunState();
    super.dispose();
  }
}
