import 'package:flutter/widgets.dart';
import 'package:countman/src/counter/plugin.dart';
import 'animate_once.dart';
import 'counter_builder.dart';
import 'providers.dart';
import 'text_style.dart';

export 'text_style.dart' show CountmanTextStyle;

/// Visual style for [TextCounter]. Alias of the shared [CountmanTextStyle].
///
/// [TextCounter] 的视觉样式。共享 [CountmanTextStyle] 的别名。
typedef TextCounterStyle = CountmanTextStyle;

/// A [Text]-based counter widget with optional prefix/suffix.
///
/// Simple usage:
/// ```dart
/// TextCounter(to: 9999)
/// TextCounter(to: 9999, prefix: '¥', style: TextCounterStyle(textStyle: TextStyle(fontSize: 32)))
/// TextCounter(to: 9999, prefixWidget: Icon(Icons.star), suffix: ' pts')
/// TextCounter(to: 9999, formatter: (v) => v.toStringAsFixed(2))
/// ```
///
/// 基于 [Text] 的向上计数组件，可选前后缀。
///
/// For custom layouts beyond prefix/suffix, use [CounterBuilder] directly.
class TextCounter extends StatelessWidget {
  const TextCounter({
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
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.semanticsLabel,
    this.repaintBoundary,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.animateOnce,
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
  final CounterValueController? controller;

  /// Formats the animated value to a display string. Takes precedence over
  /// [fractionDigits]. Defaults (both null) to `value.toInt().toString()`.
  final String Function(double value)? formatter;

  /// Convenience decimal-places control used when [formatter] is null.
  /// `null` (default) → integer display; otherwise `toStringAsFixed`.
  final int? fractionDigits;

  /// Visual style. Merged over the enclosing [CounterProvider]'s text style.
  ///
  /// 视觉样式。叠加在所在 [CounterProvider] 的文本样式之上。
  final TextCounterStyle? style;

  /// Plain-text prefix, e.g. `'¥'`. Ignored when [prefixWidget] is provided.
  final String? prefix;

  /// Plain-text suffix, e.g. `' pts'`. Ignored when [suffixWidget] is provided.
  final String? suffix;

  /// Widget placed before the number. Takes precedence over [prefix].
  final Widget? prefixWidget;

  /// Widget placed after the number. Takes precedence over [suffix].
  final Widget? suffixWidget;

  /// Fixed screen-reader label. When set, the reader announces this instead of
  /// the animating number.
  final String? semanticsLabel;

  /// Wraps the animating number in a [RepaintBoundary] so its per-frame
  /// repaint doesn't dirty surrounding widgets (useful in dense lists). Falls
  /// back to the enclosing [CounterProvider], then `false`.
  ///
  /// 用 [RepaintBoundary] 包裹动画数字，使其每帧重绘不弄脏周围 widget（密集列表
  /// 中有用）。回退到所在 [CounterProvider]，再到 `false`。
  final bool? repaintBoundary;

  /// Called every frame with the raw animated value.
  final void Function(double value)? onUpdate;

  final void Function(double value)? onComplete;

  /// Lifecycle callbacks: enqueued / first frame / cancelled before completion.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  /// Animate-once opt-in. `null` (default) inherits the enclosing
  /// [CounterProvider]'s `animateOnce`. When effectively `true` and this
  /// widget has a stable [ValueKey], the counter plays only the first time
  /// that key is seen; later rebuilds show [to] immediately.
  ///
  /// animate-once 开关。`null`（默认）继承所在 [CounterProvider] 的
  /// `animateOnce`。当实际为 `true` 且本 widget 带稳定 [ValueKey] 时，数字只在
  /// 该 key 首次出现时滚动；之后重建立即显示 [to]。
  final bool? animateOnce;

  /// Formats [value] using [formatter], else [fractionDigits], else integer.
  ///
  /// 用 [formatter]，否则 [fractionDigits]，否则整数格式化 [value]。
  String _format(double value) {
    if (formatter != null) return formatter!(value);
    if (fractionDigits != null) return value.toStringAsFixed(fractionDigits!);
    return value.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve style: widget style merged over the provider's default text style.
    //
    // 解析样式：widget 样式叠加在 provider 默认文本样式之上。
    final scope = CountmanScope.maybeOf<Counter>(context);
    final s = (style ?? const TextCounterStyle()).merge(scope?.textCounterStyle);
    final effTextStyle = s.textStyle ?? scope?.textStyle;

    final number = CounterBuilder(
      from: from,
      to: to,
      duration: duration ?? scope?.duration ?? const Duration(milliseconds: 1000),
      curve: curve ?? scope?.curve ?? Curves.easeOut,
      allowNegative: allowNegative ?? scope?.allowNegative ?? false,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      repaintBoundary: repaintBoundary ?? scope?.repaintBoundary ?? false,
      onUpdate: onUpdate,
      onComplete: onComplete,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      // Forward animate-once, deriving the stable id from THIS widget's key so
      // the inner CounterBuilder inherits our identity (see AnimateOnceScope).
      //
      // 透传 animate-once，从「本」widget 的 key 派生稳定 id，使内部 CounterBuilder
      // 继承我们的身份（见 AnimateOnceScope）。
      animateOnce: animateOnce,
      onceId: stableOnceIdFromKey(key),
      builder: (_, value, __) =>
          styledNumberText(_format(value), s, effTextStyle, semanticsLabel: semanticsLabel),
    );

    return wrapAffixedText(
      number,
      s,
      effTextStyle,
      prefix: prefix,
      suffix: suffix,
      prefixWidget: prefixWidget,
      suffixWidget: suffixWidget,
    );
  }
}
