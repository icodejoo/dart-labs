import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_widget.dart';
import 'providers.dart';

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
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.strutStyle,
    this.textScaler,
    this.locale,
    this.textWidthBasis,
    this.semanticsLabel,
    this.plugin,
    this.controller,
    this.onComplete,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final Object to;

  /// Converts remaining [Duration] to a display string.
  final DurationFormatter formatter;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Forwarded to the underlying [Text]. See [Text] for semantics.
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final StrutStyle? strutStyle;
  final TextScaler? textScaler;
  final Locale? locale;
  final TextWidthBasis? textWidthBasis;

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

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    // Resolve unset values from the nearest CountdownProvider.
    final scope = CountmanScope.maybeOf<Countdown>(context);
    final effStyle = style ?? scope?.textStyle;
    return CountdownWidget(
      to: to,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      onComplete: onComplete,
      threshold: threshold,
      onThreshold: onThreshold,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      onPause: onPause,
      onResume: onResume,
      builder: (_, p) => Text(
        formatter(p),
        style: effStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        strutStyle: strutStyle,
        textScaler: textScaler,
        locale: locale,
        textWidthBasis: textWidthBasis,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}
