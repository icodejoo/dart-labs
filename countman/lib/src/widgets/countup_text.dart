import 'package:flutter/widgets.dart';
import 'countup_builder.dart';

/// A [Text]-based count-up widget with optional prefix/suffix.
///
/// Simple usage:
/// ```dart
/// CountupText(to: 9999)
/// CountupText(to: 9999, prefix: '¥', style: TextStyle(fontSize: 32))
/// CountupText(to: 9999, prefixWidget: Icon(Icons.star), suffix: ' pts')
/// CountupText(to: 9999, formatter: (v) => v.toStringAsFixed(2))
/// ```
///
/// For custom layouts beyond prefix/suffix, use [CountupBuilder] directly.
class CountupText extends StatelessWidget {
  const CountupText({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.formatter,
    this.style,
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.onDone,
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// Formats the animated value to a display string.
  /// Defaults to `value.toInt().toString()`.
  final String Function(double value)? formatter;

  final TextStyle? style;

  /// Plain-text prefix, e.g. `'¥'`. Ignored when [prefixWidget] is provided.
  final String? prefix;

  /// Plain-text suffix, e.g. `' pts'`. Ignored when [suffixWidget] is provided.
  final String? suffix;

  /// Widget placed before the number. Takes precedence over [prefix].
  final Widget? prefixWidget;

  /// Widget placed after the number. Takes precedence over [suffix].
  final Widget? suffixWidget;

  final void Function(double value)? onDone;

  String _format(double value) =>
      formatter != null ? formatter!(value) : value.toInt().toString();

  @override
  Widget build(BuildContext context) {
    final hasPrefix = prefixWidget != null || prefix != null;
    final hasSuffix = suffixWidget != null || suffix != null;

    final numberWidget = CountupBuilder(
      from: from,
      to: to,
      duration: duration,
      curve: curve,
      onDone: onDone,
      builder: (_, value) => Text(_format(value), style: style),
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
