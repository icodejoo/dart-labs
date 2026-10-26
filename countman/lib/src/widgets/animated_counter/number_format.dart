import 'dart:math' as math;

import 'package:flutter/foundation.dart';

// 默认缩写只声明一次；按降序保存，避免每次拆位与构建时重复排序。
const _defaultAbbreviations = <num, String>{
  1000000000000: 'T',
  1000000000: 'B',
  1000000: 'M',
  1000: 'K',
};

// 动画位数与显示位数共用同一规则，避免缩写模式的默认小数位分叉。
int counterFractionDigits({
  required bool compactNotation,
  required int fractionDigits,
  int? compactFractionDigits,
}) =>
    compactNotation
        ? (compactFractionDigits ?? (fractionDigits == 0 ? 1 : fractionDigits))
        : fractionDigits;

// 包内格式计算器；不从 countman.dart 导出，保持公开构造参数不变。
class CounterNumberFormat {
  Map<num, String> _abbreviations = _defaultAbbreviations;
  List<num> _thresholds = const [1e12, 1e9, 1e6, 1e3];

  List<num> get thresholds => _thresholds;

  // 保存快照，既能识别原地修改，也能复用内容相同的新字典的排序结果。
  void updateAbbreviations(Map<num, String>? abbreviations) {
    final next = abbreviations ?? _defaultAbbreviations;
    if (mapEquals(_abbreviations, next)) return;
    _abbreviations = Map.of(next);
    _thresholds =
        List.unmodifiable(next.keys.toList()..sort((a, b) => b.compareTo(a)));
  }

  // 拆位与两条渲染路径共用有限值处理、钳制、缩写和舍入。
  CounterDisplayNumber resolve(
    num value, {
    num? minValue,
    num? maxValue,
    int fractionDigits = 0,
    bool compactNotation = false,
    int? compactFractionDigits,
  }) {
    final safe = value.isFinite ? value : 0;
    final clamped = safe.clamp(
      minValue ?? double.negativeInfinity,
      maxValue ?? double.infinity,
    );
    num display = clamped;
    String? suffix;
    if (compactNotation) {
      for (final threshold in _thresholds) {
        if (clamped.abs() >= threshold) {
          display = clamped / threshold;
          suffix = _abbreviations[threshold];
          break;
        }
      }
    }
    final digits = counterFractionDigits(
      compactNotation: compactNotation,
      fractionDigits: fractionDigits,
      compactFractionDigits: compactFractionDigits,
    );
    return CounterDisplayNumber(
      (display * math.pow(10, digits)).round(),
      digits,
      suffix,
    );
  }
}

// 累计位值仍沿用原有里程表轨迹，格式提取不改变动画算法。
class CounterDisplayNumber {
  const CounterDisplayNumber(
      this.scaledValue, this.fractionDigits, this.suffix);

  final int scaledValue;
  final int fractionDigits;
  final String? suffix;

  List<double> digits(int wholeDigits) {
    final values = scaledValue == 0 ? <double>[0] : <double>[];
    var remaining = scaledValue.abs();
    while (remaining > 0) {
      values.add(remaining.toDouble());
      remaining ~/= 10;
    }
    while (values.length < wholeDigits + fractionDigits) {
      values.add(0);
    }
    return values.reversed.toList(growable: false);
  }
}
