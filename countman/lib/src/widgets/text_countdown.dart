import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'providers.dart';
import 'countdown_builder.dart';
import 'text_style.dart';

export 'text_style.dart' show CountmanTextStyle;

/// Visual style for [TextCountdown]. Alias of the shared [CountmanTextStyle].
///
/// [TextCountdown] 的视觉样式。共享 [CountmanTextStyle] 的别名。
typedef TextCountdownStyle = CountmanTextStyle;

/// A [Text]-based countdown widget with optional prefix/suffix.
///
/// ```dart
/// TextCountdown(to: const Duration(minutes: 5), formatter: CountdownFormat.ms)
/// ```
///
/// `const`-constructible when [to] is a [Duration] and no non-const style is
/// supplied.
///
/// 基于 [Text] 的倒计时组件，可选前后缀。
class TextCountdown extends StatelessWidget {
  const TextCountdown({
    super.key,
    required this.to,
    this.formatter,
    this.style,
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.semanticsLabel,
    this.plugin,
    this.precise = false,
    this.controller,
    this.onComplete,
    this.onTick,
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

  /// Converts remaining time ([TimeParts]) to a display string. `null`
  /// (default) inherits the enclosing [CountdownProvider]'s formatter, then
  /// [CountdownFormat.auto].
  ///
  /// 把剩余时间（[TimeParts]）转成显示字符串。`null`（默认）继承所在
  /// [CountdownProvider] 的 formatter，再到 [CountdownFormat.auto]。
  final DurationFormatter? formatter;

  /// Visual style. Merged over the enclosing [CountdownProvider]'s text style.
  ///
  /// 视觉样式。叠加在所在 [CountdownProvider] 的文本样式之上。
  final TextCountdownStyle? style;

  /// Plain-text prefix, e.g. `'⏱ '`. Ignored when [prefixWidget] is provided.
  final String? prefix;

  /// Plain-text suffix. Ignored when [suffixWidget] is provided.
  final String? suffix;

  /// Widget placed before the number. Takes precedence over [prefix].
  final Widget? prefixWidget;

  /// Widget placed after the number. Takes precedence over [suffix].
  final Widget? suffixWidget;

  /// Fixed screen-reader label. When set, the reader announces this instead of
  /// the per-second changing digits.
  final String? semanticsLabel;

  /// Optional [Countdown] group. Defaults to [defaultCountdown].
  final Countdown? plugin;

  /// Drive on the shared precise group ([defaultCountdownMs], `interval: 0`)
  /// so sub-second formatters update every frame. Ignored when [plugin] or a
  /// provider group is set.
  ///
  /// 用共享精确组（[defaultCountdownMs]，`interval: 0`）驱动，使亚秒格式化器每帧
  /// 更新。设置了 [plugin] 或 provider 分组时忽略。
  final bool precise;

  /// Optional controller for pause / resume / reset.
  final CountdownController? controller;

  final void Function()? onComplete;

  /// Called every tick with the current remaining [TimeParts] — for side
  /// effects (analytics, syncing) without writing a custom [CountdownBuilder].
  ///
  /// 每 tick 以当前剩余 [TimeParts] 回调——用于埋点/同步等副作用，无需自写
  /// [CountdownBuilder]。
  final void Function(TimeParts parts)? onTick;

  /// When remaining first drops to/below this, [onThreshold] fires once.
  final Duration? threshold;
  final void Function()? onThreshold;

  /// Lifecycle callbacks.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    // Resolve style over the provider's default text style + formatter.
    //
    // 解析样式，叠加在 provider 默认文本样式之上，并取默认 formatter。
    final scope = CountmanScope.maybeOf<Countdown>(context);
    final s = (style ?? const TextCountdownStyle()).merge(scope?.textCountdownStyle);
    final effTextStyle = s.textStyle ?? scope?.textStyle;
    final effFormatter = formatter ?? scope?.formatter ?? CountdownFormat.auto;

    final number = CountdownBuilder(
      to: to,
      plugin: plugin ?? scope?.plugin,
      precise: precise,
      controller: controller,
      onComplete: onComplete,
      onTick: onTick,
      threshold: threshold,
      onThreshold: onThreshold,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      onPause: onPause,
      onResume: onResume,
      builder: (_, p, __) =>
          styledNumberText(effFormatter(p), s, effTextStyle, semanticsLabel: semanticsLabel),
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
