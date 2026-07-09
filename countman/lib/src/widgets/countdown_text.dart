import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_widget.dart';

/// Displays a countdown as formatted text. Composes [CountdownWidget].
///
/// [to] accepts any of: [DateTime], [Duration], [int] (ms epoch), [String] (ISO-8601).
///
/// ```dart
/// CountdownText(to: DateTime(2025, 12, 31))
/// CountdownText(to: const Duration(minutes: 5), formatter: CountdownFormat.ms)
/// ```
class CountdownText extends StatelessWidget {
  const CountdownText({
    super.key,
    required this.to,
    this.formatter = CountdownFormat.auto,
    this.style,
    this.textAlign,
    this.semanticsLabel,
    this.plugin,
    this.controller,
    this.onComplete,
    this.threshold,
    this.onThreshold,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final Object to;

  /// Converts remaining [Duration] to a display string.
  final DurationFormatter formatter;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Fixed screen-reader label. When set, the reader announces this instead of
  /// the per-second changing digits (which otherwise re-announce every tick).
  final String? semanticsLabel;

  /// Optional [Countdown] group. Defaults to [defaultCountdown].
  final Countdown? plugin;

  /// Optional controller for pause / resume / reset.
  final CountdownController? controller;

  /// Called once when the countdown reaches zero.
  final void Function()? onComplete;

  /// When remaining first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check.
  final Duration? threshold;

  /// Called once when remaining crosses [threshold].
  final void Function()? onThreshold;

  @override
  Widget build(BuildContext context) {
    return CountdownWidget(
      to: to,
      plugin: plugin,
      controller: controller,
      onComplete: onComplete,
      threshold: threshold,
      onThreshold: onThreshold,
      builder: (_, p) => Text(
        formatter(p),
        style: style,
        textAlign: textAlign,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}
