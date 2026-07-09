import 'package:flutter/widgets.dart';
import 'package:countman/src/counter/plugin.dart';
import 'counter_builder.dart';
import 'providers.dart';

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
    this.duration,
    this.curve,
    this.allowNegative,
    this.plugin,
    this.controller,
    this.formatter,
    this.fractionDigits,
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
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
  });

  final double? from;
  final double to;

  /// Animation duration. Falls back to the enclosing [CounterProvider], then
  /// to 1000ms.
  final Duration? duration;

  /// Easing curve. Falls back to the provider, then to [Curves.easeOut].
  final Curve? curve;

  /// When `false` (default) the value never goes below 0. Set `true` to
  /// count through / to negative numbers. Falls back to the provider.
  final bool? allowNegative;

  /// Optional [Counter] group for isolation. Defaults to the shared instance.
  final Counter? plugin;

  /// Optional controller for imperative retarget/cancel and value read-out.
  final CounterController? controller;

  /// Formats the animated value to a display string. Takes precedence over
  /// [fractionDigits]. Defaults (both null) to `value.toInt().toString()`.
  final String Function(double value)? formatter;

  /// Convenience decimal-places control used when [formatter] is null.
  /// `null` (default) → integer display; otherwise `toStringAsFixed`.
  final int? fractionDigits;

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

  /// Called every frame with the raw animated value.
  final void Function(double value)? onUpdate;

  final void Function(double value)? onComplete;

  /// Lifecycle callbacks: enqueued / first frame / cancelled before completion.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  String _format(double value) {
    if (formatter != null) return formatter!(value);
    if (fractionDigits != null) return value.toStringAsFixed(fractionDigits!);
    return value.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasPrefix = prefixWidget != null || prefix != null;
    final hasSuffix = suffixWidget != null || suffix != null;

    // Resolve unset values from the nearest CounterProvider, then defaults.
    final scope = CountmanScope.maybeOf<Counter>(context);
    final effStyle = style ?? scope?.textStyle;

    final numberWidget = CounterBuilder(
      from: from,
      to: to,
      duration: duration ?? scope?.duration ?? const Duration(milliseconds: 1000),
      curve: curve ?? scope?.curve ?? Curves.easeOut,
      allowNegative: allowNegative ?? scope?.allowNegative ?? false,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      onUpdate: onUpdate,
      onComplete: onComplete,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      builder: (_, value, __) => Text(
        _format(value),
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
          Text(prefix!, style: effStyle),
        numberWidget,
        if (suffixWidget != null)
          suffixWidget!
        else if (suffix != null)
          Text(suffix!, style: effStyle),
      ],
    );
  }
}
