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
/// CountdownBuilder(
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
/// CountdownBuilder(
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
/// CountdownBuilder(duration: ..., plugin: _group, builder: ...)
/// ```
class CountdownBuilder extends StatefulWidget {
  const CountdownBuilder({
    super.key,
    this.duration,
    this.to,
    required this.builder,
    this.child,
    this.controller,
    this.plugin,
    this.precise = false,
    this.onComplete,
    this.onTick,
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
  final Widget Function(BuildContext context, TimeParts parts, Widget? child) builder;

  /// Value-independent subtree passed through to [builder] unchanged each tick,
  /// so the per-tick rebuild can skip it (standard `AnimatedBuilder` child).
  ///
  /// 不依赖值的子树，每 tick 原样透传给 [builder]，使每 tick 重建跳过它
  /// （标准 `AnimatedBuilder` 的 child 优化）。
  final Widget? child;

  /// Optional controller for pause / resume / reset.
  final CountdownController? controller;

  /// Override the default [Countdown] group. Useful for isolating timer sets.
  final Countdown? plugin;

  /// When true and no [plugin] is supplied, drives this countdown on the shared
  /// precise ([defaultCountdownMs], `interval: 0`) group so sub-second
  /// formatters update every frame. Ignored when [plugin] is set.
  ///
  /// 为 true 且未提供 [plugin] 时，用共享的精确组（[defaultCountdownMs]，
  /// `interval: 0`）驱动本倒计时，使亚秒格式化器每帧更新。设置了 [plugin] 时忽略。
  final bool precise;

  /// Called once when the countdown reaches [Duration.zero].
  final void Function()? onComplete;

  /// Called on every tick with the current remaining [TimeParts], for side
  /// effects that don't rebuild UI.
  ///
  /// 每 tick 以当前剩余 [TimeParts] 回调，用于不重建 UI 的副作用。
  final void Function(TimeParts parts)? onTick;

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
  State<CountdownBuilder> createState() => _CountdownBuilderState();
}

class _CountdownBuilderState extends State<CountdownBuilder> {
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
    final plugin = widget.plugin ?? (widget.precise ? defaultCountdownMs : defaultCountdown);
    _handle = plugin.add(CountdownOptions(
      duration: r,
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
        widget.onTick?.call(p);
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
  void didUpdateWidget(CountdownBuilder old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration ||
        widget.to != old.to ||
        widget.plugin != old.plugin ||
        widget.precise != old.precise ||
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
      child: widget.child,
      builder: (ctx, _, child) => widget.builder(ctx, _parts, child),
    );
  }
}

// CountdownController is defined in plugin.dart and re-exported via countman.dart.
