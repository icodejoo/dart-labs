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
///   builder: (context, value, child) => Text(value.toInt().toString()),
/// )
/// ```
///
/// The [child] passed to [builder] is built once and reused across every
/// frame — put any subtree that does not depend on the animated value there
/// to skip rebuilding it (the standard `AnimatedBuilder` optimization).
class CounterBuilder extends StatefulWidget {
  const CounterBuilder({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.controller,
    required this.builder,
    this.child,
    this.valueTransform,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
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

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterController? controller;

  /// Called every frame with the current animated value and the cached [child].
  final Widget Function(BuildContext context, double value, Widget? child) builder;

  /// Optional value-independent subtree, passed through to [builder] unchanged
  /// every frame so it is not rebuilt.
  final Widget? child;

  /// Optional mapping applied to the raw animated value before it reaches
  /// [builder] (e.g. rounding, scaling). [onUpdate] still receives the raw value.
  final double Function(double value)? valueTransform;

  /// Called every frame with the raw animated value (before [valueTransform]).
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onComplete;

  /// Fired when the task is enqueued (synchronous at start).
  final VoidCallback? onReady;

  /// Fired on the animation's first rendered frame (timing begins).
  final VoidCallback? onStart;

  /// Fired if the task is cancelled before completing (retarget / dispose).
  final VoidCallback? onCancel;

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
    _addTask(from: widget.from);
  }

  // Cancel any existing task and enqueue a fresh one starting at [from]
  // (null = the option's default of 0 / the current displayed value).
  void _addTask({required double? from}) {
    _handle?.cancel();
    _handle = (widget.plugin ?? defaultCounter).add(CounterOptions(
      from: from,
      to: widget.to,
      duration: motionDuration(widget.duration),
      curve: widget.curve,
      allowNegative: widget.allowNegative,
      onUpdate: (v) {
        _value.value = v;
        widget.controller?.latestValue = v;
        widget.onUpdate?.call(v);
      },
      onComplete: widget.onComplete,
      onReady: widget.onReady,
      onStart: widget.onStart,
      onCancel: widget.onCancel,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CounterBuilder old) {
    super.didUpdateWidget(old);
    if (widget.controller != old.controller) old.controller?.detach();
    if (widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve ||
        widget.plugin != old.plugin ||
        widget.controller != old.controller ||
        widget.allowNegative != old.allowNegative) {
      // Always create a fresh task from the current displayed value so
      // retargeting works even after the previous animation finished.
      _addTask(from: _value.value);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
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
      child: widget.child,
      builder: (ctx, value, child) => widget.builder(
        ctx,
        widget.valueTransform != null ? widget.valueTransform!(value) : value,
        child,
      ),
    );
    return widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
  }
}
