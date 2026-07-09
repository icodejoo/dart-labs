import 'package:flutter/animation.dart';

/// Options for a count-up animation task.
class CountupOptions {
  const CountupOptions({
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.onUpdate,
    this.onDone,
  });

  /// Start value. Defaults to 0, or the task's current value when retargeting.
  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// Called every frame with the current interpolated value.
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onDone;
}

/// Internal task state.
class CountupTask {
  CountupTask({
    required this.id,
    required this.from,
    required this.to,
    required this.duration,
    required this.curve,
    required this.onUpdate,
    required this.onDone,
  });

  final int id;
  double from;
  double to;
  Duration duration;
  Curve curve;
  void Function(double)? onUpdate;
  void Function(double)? onDone;

  double value = 0;
  double accumMs = 0; // accumulated dt since the task became active
  bool started = false;
  bool done = false;
}
