import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'constants.dart';
import 'length.dart';

/// 文字项；未设置的可选字段由玩法的文字默认值补足。
///
/// 例如 `const LuckyText('一等奖', wordWrap: false)` 显式禁用自动换行。
@immutable
final class LuckyText {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyText(this.text,
      {this.top,
      this.left,
      this.color,
      this.fontSize,
      this.fontFamily,
      this.fontFamilyFallback,
      this.fontWeight,
      this.lineHeight,
      this.wordWrap,
      this.lengthLimit,
      this.lineClamp});

  /// 要显示的文本。
  final String text;

  /// 顶部偏移；null 按零处理。
  final LuckyLength? top;

  /// 水平偏移；解析基准由所在玩法约定。
  final LuckyLength? left;

  /// 文字颜色；null 使用默认颜色。
  final Color? color;

  /// 字号（逻辑像素），测量和绘制时向零截断。
  final double? fontSize;

  /// 字体族；null 使用默认字体。
  final String? fontFamily;

  /// 后备字体族列表；调用方须保持列表不可变。
  final List<String>? fontFamilyFallback;

  /// 字重；null 使用默认字重。
  final FontWeight? fontWeight;

  /// 行高（逻辑像素）；null 按默认行高和字号回退。
  final double? lineHeight;

  /// 是否换行；null 使用默认值，false 显式禁用。
  final bool? wordWrap;

  /// 每行宽度限制；null 使用默认限制。
  final LuckyLength? lengthLimit;

  /// 最大行数；null 使用默认值，非正数表示无限。
  final int? lineClamp;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 列表参数须由调用方保持不可变；例如 `value.copyWith()` 保留全部字段。
  LuckyText copyWith(
          {String? text,
          LuckyLength? top,
          LuckyLength? left,
          Color? color,
          double? fontSize,
          String? fontFamily,
          List<String>? fontFamilyFallback,
          FontWeight? fontWeight,
          double? lineHeight,
          bool? wordWrap,
          LuckyLength? lengthLimit,
          int? lineClamp}) =>
      LuckyText(text ?? this.text,
          top: top ?? this.top,
          left: left ?? this.left,
          color: color ?? this.color,
          fontSize: fontSize ?? this.fontSize,
          fontFamily: fontFamily ?? this.fontFamily,
          fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
          fontWeight: fontWeight ?? this.fontWeight,
          lineHeight: lineHeight ?? this.lineHeight,
          wordWrap: wordWrap ?? this.wordWrap,
          lengthLimit: lengthLimit ?? this.lengthLimit,
          lineClamp: lineClamp ?? this.lineClamp);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is LuckyText &&
      other.text == text &&
      other.top == top &&
      other.left == left &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      listEquals(other.fontFamilyFallback, fontFamilyFallback) &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.wordWrap == wordWrap &&
      other.lengthLimit == lengthLimit &&
      other.lineClamp == lineClamp;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      text,
      top,
      left,
      color,
      fontSize,
      fontFamily,
      Object.hashAll(fontFamilyFallback ?? const <String>[]),
      fontWeight,
      lineHeight,
      wordWrap,
      lengthLimit,
      lineClamp);
}

/// 文字默认值，对齐上游 defaultStyle 的文字字段。
///
/// 例如 `const LuckyTextDefaults(fontSize: 24)` 只调整默认字号。
@immutable
final class LuckyTextDefaults {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyTextDefaults(
      {this.color = kLuckyDefaultFontColor,
      this.fontSize = kLuckyDefaultFontSize,
      this.fontFamily,
      this.fontFamilyFallback,
      this.fontWeight = FontWeight.w400,
      this.lineHeight,
      this.wordWrap = true,
      this.lengthLimit = kLuckyDefaultLengthLimit,
      this.lineClamp});

  /// 默认文字颜色。
  final Color color;

  /// 默认字号（逻辑像素）。
  final double fontSize;

  /// 默认字体族；null 表示平台默认无衬线字体。
  final String? fontFamily;

  /// 后备字体族列表；调用方须保持列表不可变。
  final List<String>? fontFamilyFallback;

  /// 默认字重。
  final FontWeight fontWeight;

  /// 默认行高（逻辑像素）；null 时使用文字字号。
  final double? lineHeight;

  /// 默认是否换行。
  final bool wordWrap;

  /// 默认行宽限制。
  final LuckyLength lengthLimit;

  /// 默认最大行数；null 或非正数表示无限。
  final int? lineClamp;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 列表参数须由调用方保持不可变；例如 `value.copyWith()` 保留全部字段。
  LuckyTextDefaults copyWith(
          {Color? color,
          double? fontSize,
          String? fontFamily,
          List<String>? fontFamilyFallback,
          FontWeight? fontWeight,
          double? lineHeight,
          bool? wordWrap,
          LuckyLength? lengthLimit,
          int? lineClamp}) =>
      LuckyTextDefaults(
          color: color ?? this.color,
          fontSize: fontSize ?? this.fontSize,
          fontFamily: fontFamily ?? this.fontFamily,
          fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
          fontWeight: fontWeight ?? this.fontWeight,
          lineHeight: lineHeight ?? this.lineHeight,
          wordWrap: wordWrap ?? this.wordWrap,
          lengthLimit: lengthLimit ?? this.lengthLimit,
          lineClamp: lineClamp ?? this.lineClamp);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is LuckyTextDefaults &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      listEquals(other.fontFamilyFallback, fontFamilyFallback) &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight &&
      other.wordWrap == wordWrap &&
      other.lengthLimit == lengthLimit &&
      other.lineClamp == lineClamp;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      color,
      fontSize,
      fontFamily,
      Object.hashAll(fontFamilyFallback ?? const <String>[]),
      fontWeight,
      lineHeight,
      wordWrap,
      lengthLimit,
      lineClamp);
}

/// 激活态文字覆盖；null 表示保留普通态对应值。
///
/// 例如 `const LuckyTextOverride(fontWeight: FontWeight.w700)` 覆盖激活态字重。
@immutable
final class LuckyTextOverride {
  /// 创建配置，未指定的可选字段使用声明的默认值。
  const LuckyTextOverride(
      {this.color,
      this.fontSize,
      this.fontFamily,
      this.fontFamilyFallback,
      this.fontWeight,
      this.lineHeight});

  /// 激活态文字颜色。
  final Color? color;

  /// 激活态字号（逻辑像素）。
  final double? fontSize;

  /// 激活态字体族。
  final String? fontFamily;

  /// 激活态后备字体族；调用方须保持列表不可变。
  final List<String>? fontFamilyFallback;

  /// 激活态字重。
  final FontWeight? fontWeight;

  /// 激活态行高；激活字号不参与普通行高的回退。
  final double? lineHeight;

  /// 返回只替换指定字段的副本；参数为 null 时保留原值。
  ///
  /// 列表参数须由调用方保持不可变；例如 `value.copyWith()` 保留全部字段。
  LuckyTextOverride copyWith(
          {Color? color,
          double? fontSize,
          String? fontFamily,
          List<String>? fontFamilyFallback,
          FontWeight? fontWeight,
          double? lineHeight}) =>
      LuckyTextOverride(
          color: color ?? this.color,
          fontSize: fontSize ?? this.fontSize,
          fontFamily: fontFamily ?? this.fontFamily,
          fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
          fontWeight: fontWeight ?? this.fontWeight,
          lineHeight: lineHeight ?? this.lineHeight);

  /// 按字段值比较配置，列表按内容比较。
  @override
  bool operator ==(Object other) =>
      other is LuckyTextOverride &&
      other.color == color &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      listEquals(other.fontFamilyFallback, fontFamilyFallback) &&
      other.fontWeight == fontWeight &&
      other.lineHeight == lineHeight;

  /// 与字段值相等性一致的哈希值。
  @override
  int get hashCode => Object.hash(
      color,
      fontSize,
      fontFamily,
      Object.hashAll(fontFamilyFallback ?? const <String>[]),
      fontWeight,
      lineHeight);
}
