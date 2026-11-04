import 'package:flutter/material.dart';

import 'animated_counter/animated_counter.dart' show AnimatedCounterStyle;
import 'bar_style.dart' show BarCounterStyle, BarCountdownStyle, BarStyle;
import 'card_countdown.dart' show CardCountdownStyle;
import 'dial_countdown.dart' show DialCountdownStyle;
import 'odometer_counter.dart' show OdometerCounterStyle;
import 'ring_style.dart' show RingCounterStyle, RingCountdownStyle, RingStyle;
import 'text_style.dart' show CountmanTextStyle;

/// countman 各展示组件的主题默认样式，通过 `ThemeData.extensions` 注入。
///
/// 样式解析顺序：组件自身的 `style` > Provider 上的 `*Style`（已弃用）>
/// 本主题 > 内置默认；字段级合并，空字段逐层回退。所有字段可空，未设置的组件
/// 沿用内置默认。第三方组件可用 [maybeOf] / [of] 读到同一套样式。
///
/// 示例：
/// ```dart
/// MaterialApp(
///   theme: ThemeData(extensions: [
///     CountmanTheme(
///       ringCounterStyle: RingCounterStyle(size: 96, strokeWidth: 10),
///       textCounterStyle: CountmanTextStyle(
///         textStyle: TextStyle(fontSize: 28),
///       ),
///     ),
///   ]),
/// );
/// // 第三方组件：
/// final ring = CountmanTheme.of(context).ringCounterStyle;
/// ```
@immutable
class CountmanTheme extends ThemeExtension<CountmanTheme> {
  /// 创建主题；所有样式可空。
  const CountmanTheme({
    this.textCounterStyle,
    this.textCountdownStyle,
    this.textElapsedStyle,
    this.ringCounterStyle,
    this.ringCountdownStyle,
    this.barCounterStyle,
    this.barCountdownStyle,
    this.dialCountdownStyle,
    this.cardCountdownStyle,
    this.odometerCounterStyle,
    this.animatedCounterStyle,
  });

  /// [TextCounter] 的默认样式。
  final CountmanTextStyle? textCounterStyle;

  /// [TextCountdown] 的默认样式。
  final CountmanTextStyle? textCountdownStyle;

  /// [TextElapsed] 的默认样式。
  final CountmanTextStyle? textElapsedStyle;

  /// [RingCounter] 的默认样式。
  final RingCounterStyle? ringCounterStyle;

  /// [RingCountdown] 的默认样式。
  final RingCountdownStyle? ringCountdownStyle;

  /// [BarCounter] 的默认样式。
  final BarCounterStyle? barCounterStyle;

  /// [BarCountdown] 的默认样式。
  final BarCountdownStyle? barCountdownStyle;

  /// [DialCountdown] 的默认样式。
  final DialCountdownStyle? dialCountdownStyle;

  /// [CardCountdown] 的默认样式。
  final CardCountdownStyle? cardCountdownStyle;

  /// [OdometerCounter] 的默认样式。
  final OdometerCounterStyle? odometerCounterStyle;

  /// [AnimatedCounter] 与 [AnimatedCounterBuilder] 的默认样式。
  final AnimatedCounterStyle? animatedCounterStyle;

  /// 读取最近的 [Theme] 上注册的 [CountmanTheme]；未注册时返回 null。
  /// 会向 Theme 注册依赖，主题变化时组件随之重建；可在 `build` /
  /// `didChangeDependencies` 中调用。
  ///
  /// 示例：`final theme = CountmanTheme.maybeOf(context);`
  static CountmanTheme? maybeOf(BuildContext context) =>
      Theme.of(context).extension<CountmanTheme>();

  /// 同 [maybeOf]，但没有注册主题时返回全空的 `CountmanTheme()`，方便直接取字段。
  ///
  /// 示例：`final style = CountmanTheme.of(context).textCounterStyle;`
  static CountmanTheme of(BuildContext context) =>
      maybeOf(context) ?? const CountmanTheme();

  /// 返回替换了给定字段的副本。
  ///
  /// 示例：`theme.copyWith(ringCounterStyle: RingCounterStyle(size: 64))`。
  @override
  CountmanTheme copyWith({
    CountmanTextStyle? textCounterStyle,
    CountmanTextStyle? textCountdownStyle,
    CountmanTextStyle? textElapsedStyle,
    RingCounterStyle? ringCounterStyle,
    RingCountdownStyle? ringCountdownStyle,
    BarCounterStyle? barCounterStyle,
    BarCountdownStyle? barCountdownStyle,
    DialCountdownStyle? dialCountdownStyle,
    CardCountdownStyle? cardCountdownStyle,
    OdometerCounterStyle? odometerCounterStyle,
    AnimatedCounterStyle? animatedCounterStyle,
  }) =>
      CountmanTheme(
        textCounterStyle: textCounterStyle ?? this.textCounterStyle,
        textCountdownStyle: textCountdownStyle ?? this.textCountdownStyle,
        textElapsedStyle: textElapsedStyle ?? this.textElapsedStyle,
        ringCounterStyle: ringCounterStyle ?? this.ringCounterStyle,
        ringCountdownStyle: ringCountdownStyle ?? this.ringCountdownStyle,
        barCounterStyle: barCounterStyle ?? this.barCounterStyle,
        barCountdownStyle: barCountdownStyle ?? this.barCountdownStyle,
        dialCountdownStyle: dialCountdownStyle ?? this.dialCountdownStyle,
        cardCountdownStyle: cardCountdownStyle ?? this.cardCountdownStyle,
        odometerCounterStyle: odometerCounterStyle ?? this.odometerCounterStyle,
        animatedCounterStyle: animatedCounterStyle ?? this.animatedCounterStyle,
      );

  /// 在本主题与 [other] 之间按 [t]（0–1）插值；[other] 不是 [CountmanTheme] 时返回本主题。
  /// 各样式使用自己的 `lerp`：数值逐字段插值，不可插值字段在 `t < 0.5` 时取前者。
  @override
  CountmanTheme lerp(ThemeExtension<CountmanTheme>? other, double t) {
    if (other is! CountmanTheme) return this;
    return CountmanTheme(
      textCounterStyle:
          CountmanTextStyle.lerp(textCounterStyle, other.textCounterStyle, t),
      textCountdownStyle: CountmanTextStyle.lerp(
          textCountdownStyle, other.textCountdownStyle, t),
      textElapsedStyle:
          CountmanTextStyle.lerp(textElapsedStyle, other.textElapsedStyle, t),
      ringCounterStyle:
          RingStyle.lerp(ringCounterStyle, other.ringCounterStyle, t),
      ringCountdownStyle:
          RingStyle.lerp(ringCountdownStyle, other.ringCountdownStyle, t),
      barCounterStyle:
          BarStyle.lerp(barCounterStyle, other.barCounterStyle, t),
      barCountdownStyle:
          BarStyle.lerp(barCountdownStyle, other.barCountdownStyle, t),
      dialCountdownStyle: DialCountdownStyle.lerp(
          dialCountdownStyle, other.dialCountdownStyle, t),
      cardCountdownStyle: CardCountdownStyle.lerp(
          cardCountdownStyle, other.cardCountdownStyle, t),
      odometerCounterStyle: OdometerCounterStyle.lerp(
          odometerCounterStyle, other.odometerCounterStyle, t),
      animatedCounterStyle: AnimatedCounterStyle.lerp(
          animatedCounterStyle, other.animatedCounterStyle, t),
    );
  }

  /// 逐字段值相等（样式自身按值比较）。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CountmanTheme &&
          other.textCounterStyle == textCounterStyle &&
          other.textCountdownStyle == textCountdownStyle &&
          other.textElapsedStyle == textElapsedStyle &&
          other.ringCounterStyle == ringCounterStyle &&
          other.ringCountdownStyle == ringCountdownStyle &&
          other.barCounterStyle == barCounterStyle &&
          other.barCountdownStyle == barCountdownStyle &&
          other.dialCountdownStyle == dialCountdownStyle &&
          other.cardCountdownStyle == cardCountdownStyle &&
          other.odometerCounterStyle == odometerCounterStyle &&
          other.animatedCounterStyle == animatedCounterStyle);

  @override
  int get hashCode => Object.hash(
        textCounterStyle,
        textCountdownStyle,
        textElapsedStyle,
        ringCounterStyle,
        ringCountdownStyle,
        barCounterStyle,
        barCountdownStyle,
        dialCountdownStyle,
        cardCountdownStyle,
        odometerCounterStyle,
        animatedCounterStyle,
      );
}
