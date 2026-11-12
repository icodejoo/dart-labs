import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../render/perf_trace.dart';

/// 将 Canvas 单行文字中的空白码点转换为空格；不改变原始分行内容。
String normalizeLuckyCanvasText(String text) =>
    text.replaceAll(RegExp(r'[\t\n\f\r\v\u2028\u2029\u0085]'), ' ');

/// 测量单行文字宽度与字母基线，使用结束后须调用 [dispose]。
abstract interface class LuckyTextMeasurer {
  /// 返回 [text] 在 [style] 下的宽度，包含尾随空格。
  double measure(String text, TextStyle style);

  /// 返回 [style] 的行顶到字母基线的距离，单位为逻辑像素。
  double baseline(TextStyle style);

  /// 释放测量资源。
  void dispose();
}

/// 样式缓存上限；超出时整体清空，限制本地文字资源占用。
const int _maxStyles = 32;

/// 单次布局中保留的精确文字宽度上限，限制长文本带来的缓存占用。
const int _maxWidths = 256;

/// 使用 TextPainter 测量；默认不缩放、从左向右整形。
///
/// 每种样式最多保留一个 painter；例如 `measurer.measure('奖品', style)`。
final class TextPainterMeasurer implements LuckyTextMeasurer {
  /// 创建测量器；[textScaler] 控制缩放，[textDirection] 只控制文字整形。
  TextPainterMeasurer(
      {TextScaler textScaler = TextScaler.noScaling,
      TextDirection textDirection = TextDirection.ltr})
      : _textScaler = textScaler,
        _textDirection = textDirection;

  /// 文字缩放策略。
  final TextScaler _textScaler;

  /// 文字整形方向。
  final TextDirection _textDirection;

  /// 按解析后的样式复用资源。
  final Map<TextStyle, TextPainter> _painters = {};

  /// 原始文本和样式的精确测量结果；方向与缩放由实例固定。
  final Map<(String, TextStyle), double> _widths = {};

  /// 仅供测试检查复用与释放；返回当前缓存资源的只读快照。
  @visibleForTesting
  List<TextPainter> get debugPainters => List.unmodifiable(_painters.values);

  /// 返回给定样式的已布局单行 painter。
  TextPainter _layout(String text, TextStyle style) {
    final resolved =
        style.copyWith(fontSize: style.fontSize?.truncateToDouble());
    var painter = _painters[resolved];
    if (painter == null) {
      if (_painters.length >= _maxStyles) dispose();
      painter =
          TextPainter(textDirection: _textDirection, textScaler: _textScaler);
      _painters[resolved] = painter;
    }
    painter.text =
        TextSpan(text: normalizeLuckyCanvasText(text), style: resolved);
    luckyTraceStart(kLuckyTextPainterLayoutTrace, layouts: 1);
    try {
      painter.layout();
    } finally {
      luckyTraceEnd();
    }
    return painter;
  }

  /// 返回单行宽度，包含尾随空格，字号向零截断。
  @override
  double measure(String text, TextStyle style) {
    final key = (text, style);
    final cached = _widths[key];
    if (cached != null) return cached;
    final width = _layout(text, style).width;
    if (_widths.length >= _maxWidths) _widths.clear();
    _widths[key] = width;
    return width;
  }

  /// 返回行顶到字母基线的距离。
  @override
  double baseline(TextStyle style) => _layout(' ', style)
      .computeDistanceToActualBaseline(TextBaseline.alphabetic);

  /// 释放并清空全部缓存资源；可重复调用。
  @override
  void dispose() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
    _widths.clear();
  }
}
