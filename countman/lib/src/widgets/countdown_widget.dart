import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';

export 'package:countman/src/count_down/types.dart'
    show DurationFormatter, CountdownFormat;

/// A widget that drives a countdown timer on the shared ticker and
/// exposes the remaining [Duration] via a [builder] callback.
///
/// ## Basic usage
/// ```dart
/// CountdownWidget(
///   duration: const Duration(minutes: 5),
///   builder: (context, remaining) => Text(CountdownFormat.ms(remaining)),
/// )
/// ```
///
/// ## Imperative control (pause / resume / reset)
/// Create a [CountdownController] and pass it via [controller]:
/// ```dart
/// final _ctrl = CountdownController();
///
/// CountdownWidget(
///   duration: const Duration(minutes: 5),
///   controller: _ctrl,
///   builder: (context, remaining) => Text(CountdownFormat.ms(remaining)),
/// )
///
/// _ctrl.pause();
/// _ctrl.resume();
/// _ctrl.reset();
/// ```
///
/// ## Grouping
/// Pass a custom [Countdown] instance to isolate this widget's timer from the
/// default group:
/// ```dart
/// final _group = Countdown(name: 'auction');
/// Countman.use(_group);
///
/// CountdownWidget(duration: ..., plugin: _group, builder: ...)
/// ```
class CountdownWidget extends StatefulWidget {
  const CountdownWidget({
    super.key,
    required this.duration,
    required this.builder,
    this.controller,
    this.plugin,
    this.onDone,
  });

  final Duration duration;

  /// Called on each interval tick with the remaining [Duration].
  /// Update rate is determined by [Countdown.interval] on the [plugin]
  /// (default: once per second).
  final Widget Function(BuildContext context, Duration remaining) builder;

  /// Optional controller for pause / resume / reset.
  final CountdownController? controller;

  /// Override the default [Countdown] group. Useful for isolating timer sets.
  final Countdown? plugin;

  /// Called once when the countdown reaches [Duration.zero].
  final void Function()? onDone;

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  late final ValueNotifier<Duration> _remaining;
  CountdownHandle? _handle;

  @override
  void initState() {
    super.initState();
    _remaining = ValueNotifier(widget.duration);
    _start();
  }

  void _start() {
    _handle?.cancel();
    final plugin = widget.plugin ?? defaultCountdown;
    _handle = plugin.add(CountdownOptions(
      duration: widget.duration,
      onUpdate: (r) => _remaining.value = r,
      onDone: widget.onDone,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CountdownWidget old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration) {
      widget.controller?.detach();
      _start();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _handle?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _remaining,
      builder: (ctx, value, _) => widget.builder(ctx, value),
    );
  }
}

// CountdownController is defined in plugin.dart and re-exported via countman.dart.
