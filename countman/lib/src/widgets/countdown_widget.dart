import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';

export 'package:countman/src/count_down/types.dart'
    show DurationFormatter, CountdownFormat, TimeParts;

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
    this.duration,
    this.to,
    required this.builder,
    this.controller,
    this.plugin,
    this.onComplete,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  }) : assert(duration != null || to != null,
            'Provide either `duration` or `to`.');

  /// Fixed countdown length. Mutually exclusive with [to].
  final Duration? duration;

  /// Deadline target — [DateTime], [Duration], [int] (ms epoch), or ISO-8601
  /// [String]. Resolved via [remainingUntil]. Takes precedence over [duration].
  final Object? to;

  /// Called on each interval tick with the shared per-task [TimeParts]
  /// (pre-decomposed remaining; `parts.total`/`parts.progress` give the
  /// denominator for progress rings/bars). Update rate is determined by
  /// [Countdown.interval] on the [plugin] (default: once per second).
  final Widget Function(BuildContext context, TimeParts parts) builder;

  /// Optional controller for pause / resume / reset.
  final CountdownController? controller;

  /// Override the default [Countdown] group. Useful for isolating timer sets.
  final Countdown? plugin;

  /// Called once when the countdown reaches [Duration.zero].
  final void Function()? onComplete;

  /// When remaining first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check. Useful for e.g. turning the display
  /// red in the final minute.
  final Duration? threshold;

  /// Called once when remaining crosses [threshold].
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  // Reused instance from the engine's onUpdate (per-task, mutated in place).
  late TimeParts _parts;
  // Bumped each tick to drive a rebuild (TimeParts is reused, so identity
  // can't signal change on its own).
  final ValueNotifier<int> _rev = ValueNotifier(0);
  CountdownHandle? _handle;

  Duration get _initialRemaining =>
      widget.to != null ? remainingUntil(widget.to!) : widget.duration!;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _handle?.cancel();
    final r = _initialRemaining;
    _parts = TimeParts.of(r, r); // initial value before the first tick
    _rev.value++;
    final plugin = widget.plugin ?? defaultCountdown;
    _handle = plugin.add(CountdownOptions(
      duration: r,
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
      },
      onComplete: widget.onComplete,
      threshold: widget.threshold,
      onThreshold: widget.onThreshold,
      onReady: widget.onReady,
      onStart: widget.onStart,
      onCancel: widget.onCancel,
      onPause: widget.onPause,
      onResume: widget.onResume,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CountdownWidget old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration ||
        widget.to != old.to ||
        widget.plugin != old.plugin ||
        widget.controller != old.controller) {
      old.controller?.detach();
      _start();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _handle?.cancel();
    _rev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _rev,
      builder: (ctx, _, __) => widget.builder(ctx, _parts),
    );
  }
}

// CountdownController is defined in plugin.dart and re-exported via countman.dart.
