import 'package:flutter/widgets.dart';

import 'style_support.dart';

/// Visual style for the text displays — shared by [CounterText],
/// [CountdownText] and [ElapsedText] (see the `CounterTextStyle` /
/// `CountdownTextStyle` / `ElapsedTextStyle` aliases in those files).
///
/// Groups text styling, per-affix styling, [Text] forwarding options, and the
/// container decoration into one reusable, themeable, mergeable object. All
/// fields nullable; unset fields fall back to the enclosing provider then to
/// framework defaults.
///
/// 文本显示组件的视觉样式——由 [CounterText]、[CountdownText]、[ElapsedText] 共用
/// （见各文件中的 `CounterTextStyle` / `CountdownTextStyle` / `ElapsedTextStyle`
/// 别名）。
///
/// 把文字样式、前后缀样式、[Text] 转发选项、容器装饰聚合为一个可复用、可主题化、
/// 可合并的对象。所有字段可空；未设置的字段回退到所在 provider，再回退到框架默认值。
@immutable
class CountmanTextStyle with BoxStyleFields, TextualStyleFields, StyleProps {
  /// Creates a text style. All fields optional.
  ///
  /// 创建文本样式。所有字段可选。
  const CountmanTextStyle({
    this.textStyle,
    this.prefixStyle,
    this.suffixStyle,
    this.padding,
    this.decoration,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.strutStyle,
    this.textScaler,
    this.locale,
    this.textWidthBasis,
  });

  @override
  final TextStyle? textStyle;
  @override
  final TextStyle? prefixStyle;
  @override
  final TextStyle? suffixStyle;
  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Forwarded to the number [Text]. See [Text] for semantics.
  ///
  /// 转发给数字 [Text]。语义见 [Text]。
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final StrutStyle? strutStyle;
  final TextScaler? textScaler;
  final Locale? locale;
  final TextWidthBasis? textWidthBasis;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  CountmanTextStyle copyWith({
    TextStyle? textStyle,
    TextStyle? prefixStyle,
    TextStyle? suffixStyle,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
    bool? softWrap,
    StrutStyle? strutStyle,
    TextScaler? textScaler,
    Locale? locale,
    TextWidthBasis? textWidthBasis,
  }) {
    return CountmanTextStyle(
      textStyle: textStyle ?? this.textStyle,
      prefixStyle: prefixStyle ?? this.prefixStyle,
      suffixStyle: suffixStyle ?? this.suffixStyle,
      padding: padding ?? this.padding,
      decoration: decoration ?? this.decoration,
      textAlign: textAlign ?? this.textAlign,
      maxLines: maxLines ?? this.maxLines,
      overflow: overflow ?? this.overflow,
      softWrap: softWrap ?? this.softWrap,
      strutStyle: strutStyle ?? this.strutStyle,
      textScaler: textScaler ?? this.textScaler,
      locale: locale ?? this.locale,
      textWidthBasis: textWidthBasis ?? this.textWidthBasis,
    );
  }

  /// Merges with a lower-priority [other]: this object's non-null fields win,
  /// [other]'s fill the gaps. Used to layer widget style over provider style.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先，[other] 补空缺。用于把
  /// widget 样式叠加在 provider 样式之上。
  CountmanTextStyle merge(CountmanTextStyle? other) {
    if (other == null) return this;
    return CountmanTextStyle(
      textStyle: textStyle ?? other.textStyle,
      prefixStyle: prefixStyle ?? other.prefixStyle,
      suffixStyle: suffixStyle ?? other.suffixStyle,
      padding: padding ?? other.padding,
      decoration: decoration ?? other.decoration,
      textAlign: textAlign ?? other.textAlign,
      maxLines: maxLines ?? other.maxLines,
      overflow: overflow ?? other.overflow,
      softWrap: softWrap ?? other.softWrap,
      strutStyle: strutStyle ?? other.strutStyle,
      textScaler: textScaler ?? other.textScaler,
      locale: locale ?? other.locale,
      textWidthBasis: textWidthBasis ?? other.textWidthBasis,
    );
  }

  @override
  List<Object?> get props => [
        textStyle,
        prefixStyle,
        suffixStyle,
        padding,
        decoration,
        textAlign,
        maxLines,
        overflow,
        softWrap,
        strutStyle,
        textScaler,
        locale,
        textWidthBasis,
      ];
}

/// Builds the number [Text] from [style]'s forwarding options.
///
/// Shared by the text displays so the ~10 forwarded [Text] arguments are wired
/// in exactly one place.
///
/// 依据 [style] 的转发选项构建数字 [Text]。
///
/// 由各文本显示组件共用，使 ~10 个转发给 [Text] 的参数只在一处接线。
///
/// @param number The formatted number/time string to render.
///
///   要渲染的已格式化数字/时间字符串。
///
/// @param style The resolved [CountmanTextStyle].
///
///   已解析的 [CountmanTextStyle]。
///
/// @param textStyle The resolved base text style (style.textStyle ?? provider).
///
///   已解析的基础文字样式（style.textStyle ?? provider）。
///
/// @param semanticsLabel Optional fixed screen-reader label.
///
///   可选的固定读屏标签。
///
/// @returns The configured number [Text].
///
///   配置好的数字 [Text]。
Text styledNumberText(
  String number,
  CountmanTextStyle style,
  TextStyle? textStyle, {
  String? semanticsLabel,
}) {
  return Text(
    number,
    style: textStyle,
    textAlign: style.textAlign,
    maxLines: style.maxLines,
    overflow: style.overflow,
    softWrap: style.softWrap,
    strutStyle: style.strutStyle,
    textScaler: style.textScaler,
    locale: style.locale,
    textWidthBasis: style.textWidthBasis,
    semanticsLabel: semanticsLabel,
  );
}

/// Wraps an animated [number] widget with optional prefix/suffix (string or
/// widget) in a baseline-aligned [Row], then applies the style's box layer
/// (padding + decoration). Returns [number] unchanged (only box-wrapped) when
/// there are no affixes.
///
/// The affix scaffold is value-independent — building it around the
/// self-rebuilding [number] widget (rather than inside the per-tick builder)
/// keeps the prefix/suffix from rebuilding every frame.
///
/// 用可选前后缀（字符串或 widget）在基线对齐的 [Row] 中包裹动画 [number]，再应用
/// 样式的盒层（padding + decoration）。无前后缀时原样返回 [number]（仅包盒）。
///
/// 前后缀脚手架不依赖值——把它构建在自重建的 [number] 外围（而非每 tick 的 builder
/// 内），可避免前后缀每帧重建。
///
/// @param number The animated number widget (a builder-driven subtree).
///
///   动画数字 widget（由 builder 驱动的子树）。
///
/// @param style The resolved [CountmanTextStyle] (supplies affix styles + box).
///
///   已解析的 [CountmanTextStyle]（提供前后缀样式与盒层）。
///
/// @param affixTextStyle Fallback style for string affixes (style.prefixStyle /
///   suffixStyle default to this).
///
///   字符串前后缀的回退样式（style.prefixStyle / suffixStyle 默认取此）。
///
/// @param prefix Plain-text prefix; ignored when [prefixWidget] is set.
///
///   纯文本前缀；设置 [prefixWidget] 时忽略。
///
/// @param suffix Plain-text suffix; ignored when [suffixWidget] is set.
///
///   纯文本后缀；设置 [suffixWidget] 时忽略。
///
/// @param prefixWidget Widget before the number; wins over [prefix].
///
///   数字前的 widget；优先于 [prefix]。
///
/// @param suffixWidget Widget after the number; wins over [suffix].
///
///   数字后的 widget；优先于 [suffix]。
///
/// @returns The affixed, box-decorated display widget.
///
///   加了前后缀与盒装饰的显示 widget。
Widget wrapAffixedText(
  Widget number,
  CountmanTextStyle style,
  TextStyle? affixTextStyle, {
  String? prefix,
  String? suffix,
  Widget? prefixWidget,
  Widget? suffixWidget,
}) {
  final hasPrefix = prefixWidget != null || prefix != null;
  final hasSuffix = suffixWidget != null || suffix != null;
  final prefixStyle = style.prefixStyle ?? affixTextStyle;
  final suffixStyle = style.suffixStyle ?? affixTextStyle;

  Widget content;
  if (!hasPrefix && !hasSuffix) {
    content = number;
  } else {
    content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (prefixWidget != null)
          prefixWidget
        else if (prefix != null)
          Text(prefix, style: prefixStyle),
        number,
        if (suffixWidget != null)
          suffixWidget
        else if (suffix != null)
          Text(suffix, style: suffixStyle),
      ],
    );
  }
  return applyBoxStyle(content, padding: style.padding, decoration: style.decoration);
}
