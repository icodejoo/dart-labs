import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';

/// Displays a countdown as formatted text.
///
/// [to] accepts any of: [DateTime], [Duration], [int] (ms epoch), [String] (ISO-8601).
///
/// ```dart
/// CountdownText(to: DateTime(2025, 12, 31))
/// CountdownText(to: const Duration(minutes: 5), formatter: CountdownFormat.ms)
/// ```
class CountdownText extends StatefulWidget {
  const CountdownText({
    super.key,
    required this.to,
    this.formatter = CountdownFormat.auto,
    this.style,
    this.textAlign,
    this.plugin,
    this.controller,
    this.onDone,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final dynamic to;

  /// Converts remaining [Duration] to a display string.
  final DurationFormatter formatter;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Optional [Countdown] group. Defaults to [defaultCountdown].
  final Countdown? plugin;

  /// Optional controller for pause / resume / reset.
  final CountdownController? controller;

  /// Called once when the countdown reaches zero.
  final void Function()? onDone;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  late final ValueNotifier<Duration> _remaining;
  CountdownHandle? _handle;

  @override
  void initState() {
    super.initState();
    _remaining = ValueNotifier(Duration.zero);
    _start();
  }

  void _start() {
    _handle?.cancel();
    final r = remainingUntil(widget.to);
    _remaining.value = r;
    _handle = (widget.plugin ?? defaultCountdown).add(CountdownOptions(
      duration: r,
      onUpdate: (v) => _remaining.value = v,
      onDone: widget.onDone,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CountdownText old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to) {
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
      builder: (_, r, __) =>
          Text(widget.formatter(r), style: widget.style, textAlign: widget.textAlign),
    );
  }
}
