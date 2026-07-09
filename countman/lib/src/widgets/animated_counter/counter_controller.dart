// Adapted from flip_counter_plus (MIT).
// Original: https://github.com/Itsxhadi/flip_counter_plus

import 'package:flutter/widgets.dart';

/// Programmatic control over an [AnimatedCounter] widget.
///
/// Pass to [AnimatedCounter.controller] and call [animateTo], [jumpTo],
/// [pause], [resume], [stop], [restart], [repeat], or [reverse].
class AnimatedCounterController extends ChangeNotifier {
  num _value;
  Duration? _overrideDuration;

  // Internal callbacks wired up by _AnimatedCounterState — not public API.
  // (Dart has no package-private; these are left without _ to cross file boundaries.)
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

  AnimationStatus get status => $statusGetter?.call() ?? AnimationStatus.dismissed;

  void addStatusListener(AnimationStatusListener listener)    => $statusListeners.add(listener);
  void removeStatusListener(AnimationStatusListener listener) => $statusListeners.remove(listener);

  void $notifyStatusListeners(AnimationStatus status) {
    for (final l in List.of($statusListeners)) { l(status); }
  }
}

