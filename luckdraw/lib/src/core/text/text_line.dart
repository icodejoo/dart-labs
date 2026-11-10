import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../foundation/constants.dart';
import '../foundation/text.dart';
import '../render/perf_trace.dart';
import 'split_text.dart';
import 'text_measurer.dart';

/// 一行文字的内容、左边缘和字母基线坐标；例如 `LuckyTextLine('奖', 0, 18, style)`。
@immutable
final class LuckyTextLine {
  /// 创建一行；[x]/[baselineY] 单位为逻辑像素。
  const LuckyTextLine(this.text, this.x, this.baselineY, this.style);

  /// 单行内容。
  final String text;

  /// 左边缘横坐标。
  final double x;

  /// 字母基线纵坐标。
  final double baselineY;

  /// 测量与绘制共用的样式。
  final TextStyle style;
}

/// 将 [text] 按默认值和激活覆盖值解析，返回每行文字及基线位置。
///
/// [box] 决定水平居中，[leftBase]/[topBase] 解析偏移百分比；[maxWidthOf]
/// 接收已完成行数与该行相对顶部的基线。[dropEmptyLines] 丢弃空行，
/// [wrap] 为 false 时只按换行符分行；例如按钮使用 `wrap: false`。
List<LuckyTextLine> layoutLuckyTextLines(
    {required LuckyText text,
    required LuckyTextDefaults defaults,
    LuckyTextOverride? override,
    required LuckyTextMeasurer measurer,
    required Rect box,
    required double leftBase,
    required double topBase,
    required double Function(int finishedLines, double fontY) maxWidthOf,
    bool dropEmptyLines = false,
    bool wrap = true}) {
  luckyTraceStart('luckdraw.text.layout');
  try {
    final size = override?.fontSize ?? text.fontSize ?? defaults.fontSize;
    final style = TextStyle(
        color: override?.color ?? text.color ?? defaults.color,
        fontSize: size.truncateToDouble(),
        fontFamily:
            override?.fontFamily ?? text.fontFamily ?? defaults.fontFamily,
        fontFamilyFallback: override?.fontFamilyFallback ??
            text.fontFamilyFallback ??
            defaults.fontFamilyFallback,
        fontWeight:
            override?.fontWeight ?? text.fontWeight ?? defaults.fontWeight);
    // 上游 grid.ts:443-462：激活字号不参与行高回退。
    final lineHeight = override?.lineHeight ??
        text.lineHeight ??
        defaults.lineHeight ??
        text.fontSize ??
        defaults.fontSize;
    final top = text.top?.resolve(topBase) ?? 0;
    final left = text.left?.resolve(leftBase) ?? 0;

    /// 返回第 i 行相对容器顶的基线。
    double fontY(int i) => top + (i + 1) * lineHeight;
    final lines = wrap && (text.wordWrap ?? defaults.wordWrap)
        ? splitLuckyText(removeLineBreaks(text.text),
            (s) => measurer.measure(s, style), (i) => maxWidthOf(i, fontY(i)),
            lineClamp: text.lineClamp ?? defaults.lineClamp)
        : text.text.split('\n');
    final filtered =
        dropEmptyLines ? lines.where((s) => s.isNotEmpty).toList() : lines;
    return [
      for (var i = 0; i < filtered.length; i++)
        LuckyTextLine(
            filtered[i],
            box.left +
                (box.width - measurer.measure(filtered[i], style)) /
                    kLuckyHalfDivisor +
                left,
            box.top + fontY(i),
            style)
    ];
  } finally {
    luckyTraceEnd();
  }
}
