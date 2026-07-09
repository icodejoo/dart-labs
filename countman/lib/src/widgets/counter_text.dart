import 'package:flutter/widgets.dart';
import 'counter_builder.dart';

/// A [Text]-based count-up widget with optional prefix/suffix.
///
/// Simple usage:
/// ```dart
/// CounterText(to: 9999)
/// CounterText(to: 9999, prefix: '¥', style: TextStyle(fontSize: 32))
/// CounterText(to: 9999, prefixWidget: Icon(Icons.star), suffix: ' pts')
/// CounterText(to: 9999, formatter: (v) => v.toStringAsFixed(2))
/// ```
///
/// For custom layouts beyond prefix/suffix, use [CounterBuilder] directly.
class CounterText extends StatelessWidget {
  const CounterText({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.formatter,
    this.style,
    this.semanticsLabel,
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.onComplete,
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default) the value never goes below 0. Set `true` to
  /// count through / to negative numbers.
  final bool allowNegative;

  /// Formats the animated value to a display string.
  /// Defaults to `value.toInt().toString()`.
  final String Function(double value)? formatter;

  final TextStyle? style;

  /// Fixed screen-reader label. When set, the reader announces this instead of
  /// the animating number.
  final String? semanticsLabel;

  /// Plain-text prefix, e.g. `'¥'`. Ignored when [prefixWidget] is provided.
  final String? prefix;

  /// Plain-text suffix, e.g. `' pts'`. Ignored when [suffixWidget] is provided.
  final String? suffix;

  /// Widget placed before the number. Takes precedence over [prefix].
  final Widget? prefixWidget;

  /// Widget placed after the number. Takes precedence over [suffix].
  final Widget? suffixWidget;

  final void Function(double value)? onComplete;

  String _format(double value) =>
      formatter != null ? formatter!(value) : value.toInt().toString();

  @override
  Widget build(BuildContext context) {
    final hasPrefix = prefixWidget != null || prefix != null;
    final hasSuffix = suffixWidget != null || suffix != null;

    final numberWidget = CounterBuilder(
      from: from,
      to: to,
      duration: duration,
      curve: curve,
      allowNegative: allowNegative,
      onComplete: onComplete,
      builder: (_, value) =>
          Text(_format(value), style: style, semanticsLabel: semanticsLabel),
    );

    if (!hasPrefix && !hasSuffix) return numberWidget;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefixWidget != null)
          prefixWidget!
        else if (prefix != null)
          Text(prefix!, style: style),
        numberWidget,
        if (suffixWidget != null)
          suffixWidget!
        else if (suffix != null)
          Text(suffix!, style: style),
      ],
    );
  }
}
