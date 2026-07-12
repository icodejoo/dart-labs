import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/types.dart'
    show DurationFormatter, CountdownFormat, TimeParts;
import 'package:countman/src/elapsed/plugin.dart';
import 'providers.dart';
import 'text_style.dart';
import 'elapsed_builder.dart';

export 'text_style.dart' show CountmanTextStyle;

/// Visual style for [TextElapsed]. Alias of the shared [CountmanTextStyle].
///
/// [TextElapsed] 的视觉样式。共享 [CountmanTextStyle] 的别名。
typedef TextElapsedStyle = CountmanTextStyle;

/// Displays an open-ended elapsed-time counter — a stopwatch, not a
/// countdown. Starts at zero the moment it's mounted and counts up
/// indefinitely until removed or [ElapsedController.cancel]led.
///
/// Reuses [CountdownFormat]'s duration formatters ([DurationFormatter]).
/// Derives from [ElapsedBuilder], which owns the plugin/task wiring (mirrors
/// [TextCounter] building on `CounterBuilder`).
///
/// ```dart
/// TextElapsed() // 00:00, 00:01, 00:02, ...
/// TextElapsed(formatter: CountdownFormat.hms)
/// ```
///
/// ## Imperative control (pause / resume / reset)
/// ```dart
/// final _ctrl = ElapsedController();
/// TextElapsed(controller: _ctrl);
/// _ctrl.pause();
/// _ctrl.resume();
/// _ctrl.reset();
/// ```
class TextElapsed extends StatelessWidget {
  const TextElapsed({
    super.key,
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
    this.onTick,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Converts elapsed time ([TimeParts]) to a display string. `null` (default)
  /// inherits the enclosing [ElapsedProvider]'s formatter, then
  /// [CountdownFormat.auto].
  ///
  /// 把经过时间（[TimeParts]）转成显示字符串。`null`（默认）继承所在
  /// [ElapsedProvider] 的 formatter，再到 [CountdownFormat.auto]。
  final DurationFormatter? formatter;

  /// Visual style. Merged over the enclosing [ElapsedProvider]'s text style.
  ///
  /// 视觉样式。叠加在所在 [ElapsedProvider] 的文本样式之上。
  final TextElapsedStyle? style;

  /// Plain-text prefix. Ignored when [prefixWidget] is provided.
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

  /// Optional [Elapsed] group. Defaults to [defaultElapsed].
  final Elapsed? plugin;

  /// Drive on the shared precise group ([defaultElapsedMs], `interval: 0`) so
  /// sub-second formatters update every frame. Ignored when [plugin] or a
  /// provider group is set.
  ///
  /// 用共享精确组（[defaultElapsedMs]，`interval: 0`）驱动，使亚秒格式化器每帧
  /// 更新。设置了 [plugin] 或 provider 分组时忽略。
  final bool precise;

  /// Optional controller for pause / resume / reset.
  final ElapsedController? controller;

  /// Called every tick with the current elapsed [TimeParts] — for side effects
  /// (analytics, syncing) without writing a custom [ElapsedBuilder].
  ///
  /// 每 tick 以当前经过时间 [TimeParts] 回调——用于埋点/同步等副作用。
  final void Function(TimeParts parts)? onTick;

  /// When elapsed time first reaches or exceeds this, [onThreshold] fires
  /// once. null (default) disables the check.
  final Duration? threshold;

  /// Called once when elapsed time crosses [threshold].
  final void Function()? onThreshold;

  /// Lifecycle callbacks: enqueued / first frame / cancelled / paused / resumed.
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    // Resolve style over the provider default.
    //
    // 解析样式，叠加在 provider 默认之上。
    final scope = CountmanScope.maybeOf<Elapsed>(context);
    final s = (style ?? const TextElapsedStyle()).merge(scope?.textElapsedStyle);
    final effTextStyle = s.textStyle ?? scope?.textStyle;
    final effFormatter = formatter ?? scope?.formatter ?? CountdownFormat.auto;

    final number = ElapsedBuilder(
      plugin: plugin,
      precise: precise,
      controller: controller,
      onTick: onTick,
      threshold: threshold,
      onThreshold: onThreshold,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      onPause: onPause,
      onResume: onResume,
      builder: (_, parts, __) =>
          styledNumberText(effFormatter(parts), s, effTextStyle, semanticsLabel: semanticsLabel),
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
