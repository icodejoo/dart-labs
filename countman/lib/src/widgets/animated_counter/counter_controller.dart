// Adapted from flip_counter_plus (MIT).
// Original: https://github.com/Itsxhadi/flip_counter_plus

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show internal;

/// 动画计数组件的命令式控制器，由当前绑定的展示组件响应命令。
///
/// Pass to [AnimatedCounter.controller] and call [animateTo], [jumpTo],
/// [pause], [resume], [stop], [restart], [repeat], or [reverse].
class AnimatedCounterController extends ChangeNotifier {
  num _value;
  Duration? _overrideDuration;

  // Internal callbacks wired up by _AnimatedCounterState — not public API.
  // (Dart has no package-private; these are left without _ to cross file boundaries.)
  /// 由展示组件调用，业务代码不要直接调用。
  /// 当前绑定的 State 标记，未绑定时为 null；例如组件绑定时 `$owner = this`。
  @internal
  Object? $owner;

  VoidCallback? $pauseCallback;
  VoidCallback? $resumeCallback;
  VoidCallback? $stopCallback;
  VoidCallback? $restartCallback;
  void Function({bool reverse})? $repeatCallback;
  VoidCallback? $reverseCallback;
  ValueGetter<AnimationStatus>? $statusGetter;
  final List<AnimationStatusListener> $statusListeners = [];

  AnimatedCounterController({num initialValue = 0}) : _value = initialValue;

  num get value => _value;
  Duration? get overrideDuration => _overrideDuration;

  /// Animates the counter to [targetValue].
  void animateTo(num targetValue) {
    _overrideDuration = null;
    _value = targetValue;
    notifyListeners();
  }

  /// Instantly jumps to [targetValue] without animation.
  void jumpTo(num targetValue) {
    _overrideDuration = Duration.zero;
    _value = targetValue;
    notifyListeners();
  }

  void pause()                        => $pauseCallback?.call();
  void resume()                       => $resumeCallback?.call();
  void stop()                         => $stopCallback?.call();
  void restart()                      => $restartCallback?.call();
  void repeat({bool reverse = false}) => $repeatCallback?.call(reverse: reverse);
  void reverse()                      => $reverseCallback?.call();

  /// 当前播放方向或端点状态；pause 保持原方向，reverse 到起点发 dismissed。
  /// 例如 `controller.status == AnimationStatus.reverse`。
  AnimationStatus get status => $statusGetter?.call() ?? AnimationStatus.dismissed;

  void addStatusListener(AnimationStatusListener listener)    => $statusListeners.add(listener);
  void removeStatusListener(AnimationStatusListener listener) => $statusListeners.remove(listener);

  void $notifyStatusListeners(AnimationStatus status) {
    for (final l in List.of($statusListeners)) { l(status); }
  }
}

