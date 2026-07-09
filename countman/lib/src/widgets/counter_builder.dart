import 'package:flutter/widgets.dart';
import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';

import 'reduce_motion.dart';

/// A widget that drives a count-up animation on the shared ticker and
/// exposes the current value via a [builder] callback.
///
/// ```dart
/// CounterBuilder(
///   to: 9999,
///   builder: (context, value) => Text(value.toInt().toString()),
/// )
/// ```
class CounterBuilder extends StatefulWidget {
  const CounterBuilder({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    required this.builder,
    this.onUpdate,
    this.onComplete,
    this.repaintBoundary = true,
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default) the animated value never goes below 0. Set `true`
  /// to count through / to negative numbers.
  final bool allowNegative;

  /// Optional [Counter] group for isolation/grouping. Defaults to the shared
  /// [defaultCounter] instance (equivalent to the top-level `counter()`).
  final Counter? plugin;

  /// Called every frame with the current animated value.
  final Widget Function(BuildContext context, double value) builder;

  /// Called every frame with the raw animated value (before the builder runs).
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  /// Wraps the builder output in a [RepaintBoundary].
  /// Default: true. Set to false when many instances share one layer
  /// (e.g. a dense grid) — too many boundaries increase GPU compositing cost.
  final bool repaintBoundary;

  @override
  State<CounterBuilder> createState() => _CounterBuilderState();
}

class _CounterBuilderState extends State<CounterBuilder> {
  late final ValueNotifier<double> _value;
  CounterHandle? _handle;

  @override
  void initState() {
    super.initState();
    _value = ValueNotifier(widget.from ?? 0);
    _addTask();
  }

  void _addTask() {
    _handle?.cancel();
    _handle = (widget.plugin ?? defaultCounter).add(CounterOptions(
      from: widget.from,
      to: widget.to,
      duration: motionDuration(widget.duration),
      curve: widget.curve,
      allowNegative: widget.allowNegative,
      onUpdate: (v) {
        _value.value = v;
        widget.onUpdate?.call(v);
      },
      onComplete: widget.onComplete,
    ));
  }

  @override
  void didUpdateWidget(CounterBuilder old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve ||
        widget.plugin != old.plugin ||
        widget.allowNegative != old.allowNegative) {
      // Cancel the old task (no-op if already completed and removed).
      // Always create a fresh task from the current displayed value so
      // retargeting works even after the previous animation finished.
      _handle?.cancel();
      _handle = (widget.plugin ?? defaultCounter).add(CounterOptions(
        from: _value.value,
        to: widget.to,
        duration: motionDuration(widget.duration),
        curve: widget.curve,
        allowNegative: widget.allowNegative,
        onUpdate: (v) {
          _value.value = v;
          widget.onUpdate?.call(v);
        },
        onComplete: widget.onComplete,
      ));
    }
  }

  @override
  void dispose() {
    _handle?.cancel();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates this widget's repaint from its siblings.
    // Without it a single dirty counter repaints the whole ancestor layer.
    final inner = ValueListenableBuilder<double>(
      valueListenable: _value,
      builder: (ctx, value, _) => widget.builder(ctx, value),
    );
    return widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
  }
}
