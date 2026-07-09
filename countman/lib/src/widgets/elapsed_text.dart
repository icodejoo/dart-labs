import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/types.dart' show DurationFormatter, CountdownFormat, TimeParts;
import 'package:countman/src/elapsed/plugin.dart';
import 'package:countman/src/elapsed/types.dart';

/// Displays an open-ended elapsed-time counter — a stopwatch, not a
/// countdown. Starts at zero the moment it's mounted and counts up
/// indefinitely until removed or [ElapsedController.cancel]led.
///
/// Reuses [CountdownFormat]'s duration formatters ([DurationFormatter]) —
/// `hms`/`ms`/`msTenths`/`auto` are pure `Duration -> String` functions with
/// no assumption about counting direction, so the same formatters that
/// render "remaining" for a countdown render "elapsed" here unchanged.
///
/// ```dart
/// ElapsedText() // 00:00, 00:01, 00:02, ...
/// ElapsedText(formatter: CountdownFormat.hms)
/// ```
///
/// ## Imperative control (pause / resume / reset)
/// ```dart
/// final _ctrl = ElapsedController();
/// ElapsedText(controller: _ctrl);
/// _ctrl.pause();
/// _ctrl.resume();
/// _ctrl.reset();
/// ```
class ElapsedText extends StatefulWidget {
  const ElapsedText({
    super.key,
    this.formatter = CountdownFormat.auto,
    this.style,
    this.textAlign,
    this.semanticsLabel,
    this.plugin,
    this.controller,
    this.threshold,
    this.onThreshold,
  });

  /// Converts elapsed [Duration] to a display string.
  final DurationFormatter formatter;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Fixed screen-reader label. When set, the reader announces this instead of
  /// the per-second changing digits.
  final String? semanticsLabel;

  /// Optional [Elapsed] group. Defaults to [defaultElapsed].
  final Elapsed? plugin;

  /// Optional controller for pause / resume / reset.
  final ElapsedController? controller;

  /// When elapsed time first reaches or exceeds this, [onThreshold] fires
  /// once. null (default) disables the check.
  final Duration? threshold;

  /// Called once when elapsed time crosses [threshold].
  final void Function()? onThreshold;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  TimeParts _parts = TimeParts.of(Duration.zero);
  final ValueNotifier<int> _rev = ValueNotifier(0);
  ElapsedHandle? _handle;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _handle?.cancel();
    _handle = (widget.plugin ?? defaultElapsed).add(ElapsedOptions(
      onUpdate: (p) {
        _parts = p;
        _rev.value++;
      },
      threshold: widget.threshold,
      onThreshold: widget.onThreshold,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(ElapsedText old) {
    super.didUpdateWidget(old);
    // A changed plugin or controller must re-anchor the task and re-attach,
    // mirroring the countdown display widgets.
    if (widget.plugin != old.plugin || widget.controller != old.controller) {
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
      builder: (_, __, ___) => Text(widget.formatter(_parts),
          style: widget.style,
          textAlign: widget.textAlign,
          semanticsLabel: widget.semanticsLabel),
    );
  }
}
