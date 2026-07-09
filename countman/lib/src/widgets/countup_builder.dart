import 'package:flutter/widgets.dart';
import 'package:countman/src/count_up/plugin.dart';
import 'package:countman/src/count_up/types.dart';

/// A widget that drives a count-up animation on the shared ticker and
/// exposes the current value via a [builder] callback.
///
/// ```dart
/// CountupBuilder(
///   to: 9999,
///   builder: (context, value) => Text(value.toInt().toString()),
/// )
/// ```
class CountupBuilder extends StatefulWidget {
  const CountupBuilder({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    required this.builder,
    this.onUpdate,
    this.onDone,
    this.repaintBoundary = true,
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// Called every frame with the current animated value.
  final Widget Function(BuildContext context, double value) builder;

  /// Called every frame with the raw animated value (before the builder runs).
  final void Function(double value)? onUpdate;

  /// Called once when the animation reaches [to].
  final void Function(double value)? onDone;

  /// Wraps the builder output in a [RepaintBoundary].
  /// Default: true. Set to false when many instances share one layer
  /// (e.g. a dense grid) — too many boundaries increase GPU compositing cost.
  final bool repaintBoundary;

  @override
  State<CountupBuilder> createState() => _CountupBuilderState();
}

class _CountupBuilderState extends State<CountupBuilder> {
  late final ValueNotifier<double> _value;
  CountupHandle? _handle;

  @override
  void initState() {
    super.initState();
    _value = ValueNotifier(widget.from ?? 0);
    _addTask();
  }

  void _addTask() {
    _handle?.cancel();
    _handle = countup(CountupOptions(
      from: widget.from,
      to: widget.to,
      duration: widget.duration,
      curve: widget.curve,
      onUpdate: (v) {
        _value.value = v;
        widget.onUpdate?.call(v);
      },
      onDone: widget.onDone,
    ));
  }

  @override
  void didUpdateWidget(CountupBuilder old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve) {
      // Cancel the old task (no-op if already completed and removed).
      // Always create a fresh task from the current displayed value so
      // retargeting works even after the previous animation finished.
      _handle?.cancel();
      _handle = countup(CountupOptions(
        from: _value.value,
        to: widget.to,
        duration: widget.duration,
        curve: widget.curve,
        onUpdate: (v) {
          _value.value = v;
          widget.onUpdate?.call(v);
        },
        onDone: widget.onDone,
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
