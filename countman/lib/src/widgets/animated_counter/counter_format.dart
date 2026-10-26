import 'package:flutter/foundation.dart';

import 'types.dart';

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
  });

  /// 小数位数。
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

  /// 紧凑缩写的小数位数。
  final int? compactFractionDigits;

  /// 阈值到缩写的映射；传入后请勿修改映射。
  final Map<num, String>? compactAbbreviations;

  /// 是否显示正号。
  final bool? showPositiveSign;

  /// 数字字形体系。
  final NumeralSystem? numeralSystem;

  /// 将 digit（0–9）映射为字形的函数。
  final String Function(int digit)? numeralMapper;

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
  }) =>
      CounterFormat(
        fractionDigits: fractionDigits ?? this.fractionDigits,
        wholeDigits: wholeDigits ?? this.wholeDigits,
        hideLeadingZeroes: hideLeadingZeroes ?? this.hideLeadingZeroes,
        thousandSeparator: thousandSeparator ?? this.thousandSeparator,
        groupingPattern: groupingPattern ?? this.groupingPattern,
        decimalSeparator: decimalSeparator ?? this.decimalSeparator,
        compactNotation: compactNotation ?? this.compactNotation,
        compactFractionDigits:
            compactFractionDigits ?? this.compactFractionDigits,
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
            : Object.hashAllUnordered(compactAbbreviations!.entries
                .map((e) => Object.hash(e.key, e.value))),
        showPositiveSign,
        numeralSystem,
        numeralMapper == null ? null : identityHashCode(numeralMapper),
      ]);
}
