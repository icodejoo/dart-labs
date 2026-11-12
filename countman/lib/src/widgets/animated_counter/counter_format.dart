import 'package:flutter/foundation.dart';

import 'grouping.dart';
import 'number_format.dart';
import 'types.dart';

/// 字符 '0' 的码元，用于数位与字符互转。
const int _zeroCodeUnit = 0x30;

/// 未设置小数位时的默认值，与 AnimatedCounter 的平铺参数默认值一致。
const int _defaultFractionDigits = 0;

/// 未设置最少整数位数时的默认值。
const int _defaultWholeDigits = 1;

/// 未设置小数分隔符时的默认值。
const String _defaultDecimalSeparator = '.';

/// 未设置分组位数时的默认值（每三位一组）。
const List<int> _defaultGroupingPattern = [3];

/// 两种动画计数器共享的不可变格式配置；空字段回退到组件平铺参数。
///
/// 示例：`AnimatedCounter(value: 12.3, format: CounterFormat(fractionDigits: 2))`。
@immutable
class CounterFormat {
  /// 创建格式配置；各同名参数设置对应字段，省略表示回退。
  const CounterFormat({
    this.fractionDigits,
    this.wholeDigits,
    this.hideLeadingZeroes,
    this.thousandSeparator,
    this.groupingPattern,
    this.decimalSeparator,
    this.compactNotation,
    this.compactFractionDigits,
    this.compactAbbreviations,
    this.showPositiveSign,
    this.numeralSystem,
    this.numeralMapper,
  }) : assert(
         fractionDigits == null ||
             (fractionDigits >= 0 &&
                 fractionDigits <= counterMaxFractionDigits),
       ),
       assert(
         compactFractionDigits == null ||
             (compactFractionDigits >= 0 &&
                 compactFractionDigits <= counterMaxFractionDigits),
       );

  /// 小数位数，必须为 0–20。
  final int? fractionDigits;

  /// 最少整数位数。
  final int? wholeDigits;

  /// 是否隐藏整数前导零。
  final bool? hideLeadingZeroes;

  /// 整数分组分隔符。
  final String? thousandSeparator;

  /// 从右向左的分组位数；传入后请勿修改列表。
  final List<int>? groupingPattern;

  /// 小数分隔符。
  final String? decimalSeparator;

  /// 是否使用紧凑缩写。
  final bool? compactNotation;

  /// 紧凑缩写的小数位数，必须为 0–20。
  final int? compactFractionDigits;

  /// 阈值到缩写的映射；传入后请勿修改映射。
  final Map<num, String>? compactAbbreviations;

  /// 是否显示正号。
  final bool? showPositiveSign;

  /// 数字字形体系。
  final NumeralSystem? numeralSystem;

  /// 将 digit（0–9）映射为字形的函数。
  final String Function(int digit)? numeralMapper;

  /// 把 [value] 格式化成与 AnimatedCounter 静止时屏幕上完全一致的字符串。
  ///
  /// 覆盖符号（`-`、`showPositiveSign` 的 `+`）、整数分组、小数、紧凑缩写、
  /// 数字字形体系（`numeralSystem`/`numeralMapper`）、`hideLeadingZeroes` 与
  /// `wholeDigits`；字段为空时取组件的默认值。不含 prefix/infix/suffix 等
  /// 组件级装饰。[minValue]/[maxValue] 与组件的同名参数一致，先钳制再格式化。
  ///
  /// 示例：
  /// ```dart
  /// const f = CounterFormat(thousandSeparator: ',', fractionDigits: 2);
  /// f.format(1234.5); // '1,234.50'
  /// ```
  String format(num value, {num? minValue, num? maxValue}) {
    final fractionDigits = this.fractionDigits ?? _defaultFractionDigits;
    final numberFormat = CounterNumberFormat()
      ..updateAbbreviations(compactAbbreviations);
    final display = numberFormat.resolve(
      value,
      minValue: minValue,
      maxValue: maxValue,
      fractionDigits: fractionDigits,
      compactNotation: compactNotation ?? false,
      compactFractionDigits: compactFractionDigits,
    );
    final fraction = display.fractionDigits;
    final scaled = display.scaledValue;

    // 与 CounterDisplayNumber.digits 同口径：至少 wholeDigits + 小数位，0 至少一位。
    var digits = scaled.abs().toString();
    final minCount = (wholeDigits ?? _defaultWholeDigits) + fraction;
    if (digits.length < minCount) digits = digits.padLeft(minCount, '0');

    // 隐藏前导零时只在整数区间收起，至少保留个位；小数位不参与隐藏。
    final unitsIndex = digits.length - fraction - 1;
    var first = 0;
    if (hideLeadingZeroes ?? true) {
      while (first < unitsIndex && digits.codeUnitAt(first) == _zeroCodeUnit) {
        first++;
      }
    }

    final grouping = thousandSeparator;
    final pattern = groupingPattern ?? _defaultGroupingPattern;
    final decimal = decimalSeparator ?? _defaultDecimalSeparator;
    final buffer = StringBuffer();
    if (scaled < 0) {
      buffer.write('-');
    } else if (scaled > 0 && (showPositiveSign ?? false)) {
      buffer.write('+');
    }
    for (var i = first; i < digits.length; i++) {
      if (fraction > 0 && i == digits.length - fraction) buffer.write(decimal);
      if (grouping != null &&
          i > first &&
          isGroupingBoundary(digits.length - fraction - i, pattern)) {
        buffer.write(grouping);
      }
      buffer.write(_glyphOf(digits.codeUnitAt(i) - _zeroCodeUnit));
    }
    buffer.write(display.suffix ?? '');
    return buffer.toString();
  }

  /// 数位 [digit]（0–9）实际渲染成的字形：自定义映射优先，其次体系表，最后拉丁数字。
  String _glyphOf(int digit) =>
      numeralMapper?.call(digit) ??
      numeralSystemDigits[numeralSystem ?? NumeralSystem.latin]?[digit] ??
      '$digit';

  /// 返回副本；同名非空参数替换字段，空参数保留原值。
  ///
  /// 示例：`format.copyWith(fractionDigits: 2)`。
  CounterFormat copyWith({
    int? fractionDigits,
    int? wholeDigits,
    bool? hideLeadingZeroes,
    String? thousandSeparator,
    List<int>? groupingPattern,
    String? decimalSeparator,
    bool? compactNotation,
    int? compactFractionDigits,
    Map<num, String>? compactAbbreviations,
    bool? showPositiveSign,
    NumeralSystem? numeralSystem,
    String Function(int digit)? numeralMapper,
  }) => CounterFormat(
    fractionDigits: fractionDigits ?? this.fractionDigits,
    wholeDigits: wholeDigits ?? this.wholeDigits,
    hideLeadingZeroes: hideLeadingZeroes ?? this.hideLeadingZeroes,
    thousandSeparator: thousandSeparator ?? this.thousandSeparator,
    groupingPattern: groupingPattern ?? this.groupingPattern,
    decimalSeparator: decimalSeparator ?? this.decimalSeparator,
    compactNotation: compactNotation ?? this.compactNotation,
    compactFractionDigits: compactFractionDigits ?? this.compactFractionDigits,
    compactAbbreviations: compactAbbreviations ?? this.compactAbbreviations,
    showPositiveSign: showPositiveSign ?? this.showPositiveSign,
    numeralSystem: numeralSystem ?? this.numeralSystem,
    numeralMapper: numeralMapper ?? this.numeralMapper,
  );

  /// 按字段值比较；列表和映射按内容比较，函数字段按引用比较。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CounterFormat &&
          runtimeType == other.runtimeType &&
          fractionDigits == other.fractionDigits &&
          wholeDigits == other.wholeDigits &&
          hideLeadingZeroes == other.hideLeadingZeroes &&
          thousandSeparator == other.thousandSeparator &&
          listEquals(groupingPattern, other.groupingPattern) &&
          decimalSeparator == other.decimalSeparator &&
          compactNotation == other.compactNotation &&
          compactFractionDigits == other.compactFractionDigits &&
          mapEquals(compactAbbreviations, other.compactAbbreviations) &&
          showPositiveSign == other.showPositiveSign &&
          numeralSystem == other.numeralSystem &&
          identical(numeralMapper, other.numeralMapper);

  /// 与字段值相等性一致的哈希值；映射顺序不影响结果。
  @override
  int get hashCode => Object.hashAll([
    fractionDigits,
    wholeDigits,
    hideLeadingZeroes,
    thousandSeparator,
    groupingPattern == null ? null : Object.hashAll(groupingPattern!),
    decimalSeparator,
    compactNotation,
    compactFractionDigits,
    compactAbbreviations == null
        ? null
        : Object.hashAllUnordered(
            compactAbbreviations!.entries.map(
              (e) => Object.hash(e.key, e.value),
            ),
          ),
    showPositiveSign,
    numeralSystem,
    numeralMapper == null ? null : identityHashCode(numeralMapper),
  ]);
}
