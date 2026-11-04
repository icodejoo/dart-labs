part of 'animated_counter.dart';

// ── 测量与语义 ────────────────────────────────────────────────────────────────

/// 数字格式解析、原型单元格测量、文字样式解析与语义文本。
mixin _CounterMeasure<W extends _BaseAnimatedCounter> on State<W> {
  /// 当前数值，由状态机维护；文字颜色解析与语义文本读取它。
  num get _currentValue;

  // 格式配置随组件更新；一次排序供拆位与构建共同使用。
  final _numberFormat = CounterNumberFormat();


  Size?       _prototypeSize;
  TextStyle?  _lastStyle;
  TextScaler? _lastTextScaler;
  // Signature of the 0–9 glyphs last measured. Recompute the prototype cell
  // when it changes (e.g. numeralMapper / numeralSystem swapped) so the cell
  // keeps fitting the actual glyphs.
  //
  // 上次测量的 0–9 字形签名。当其变化时（例如切换 numeralMapper /
  // numeralSystem）重新计算原型单元格，使单元格始终适配真实字形。
  String?     _lastGlyphSig;

  // 初始化、动画端点和渲染使用相同的格式解析结果。
  CounterDisplayNumber _displayNumber(num value) {
    // 控制器更新也可能伴随字典原地修改；仅配置变化时重新排序。
    _numberFormat.updateAbbreviations(widget._fmtCompactAbbreviations);
    return _numberFormat.resolve(
      value,
      minValue: widget.minValue,
      maxValue: widget.maxValue,
      fractionDigits: widget._fmtFractionDigits,
      compactNotation: widget._fmtCompactNotation,
      compactFractionDigits: widget._fmtCompactFractionDigits,
    );
  }

  List<double> _getDigitsList(num targetValue) =>
      _displayNumber(targetValue).digits(widget._fmtWholeDigits);

  // ── 样式与测量 ────────────────────────────────────────────────────────────

  TextStyle _resolveStyle(BuildContext context) {
    final baseStyle = DefaultTextStyle.of(context).style.merge(widget.textStyle);
    var style = (widget.useTabularFigures && widget.textStyle?.fontFeatures == null)
        ? baseStyle.merge(const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))
        : baseStyle;
    if (widget.colorResolver != null) {
      final resolved = widget.colorResolver!(_currentValue);
      if (resolved != null) style = style.merge(TextStyle(color: resolved));
    }
    return style;
  }

  /// Resolve the glyph a digit renders as, mirroring [_DigitColumn]'s logic:
  /// custom [numeralMapper] wins, else the [numeralSystem] table, else the
  /// Latin digit. Kept in sync with `digit_column.dart` so the prototype cell
  /// is measured with the exact glyph that will be painted.
  ///
  /// 解析某个数字实际渲染成的字形，逻辑与 [_DigitColumn] 一致：优先自定义
  /// [numeralMapper]，其次 [numeralSystem] 表，最后回退到拉丁数字。与
  /// `digit_column.dart` 保持同步，使原型单元格用真正绘制的字形来测量。
  ///
  /// @param digit The digit 0–9 to resolve.
  ///
  ///   要解析的数字 0–9。
  ///
  /// @returns The display string for [digit].
  ///
  ///   [digit] 对应的显示字符串。
  String _glyphForDigit(int digit) => widget._fmtNumeralMapper != null
      ? widget._fmtNumeralMapper!(digit)
      : (numeralSystemDigits[widget._fmtNumeralSystem]?[digit] ?? '$digit');

  void _updatePrototypeSize(TextStyle style, TextScaler textScaler) {
    // Resolve the glyphs first (cheap, no layout) so a change of
    // numeralMapper / numeralSystem invalidates the cached size even when the
    // text style is unchanged.
    //
    // 先解析字形（廉价，无需布局），使 numeralMapper / numeralSystem 变化时
    // 即便文本样式不变也能让缓存尺寸失效。
    final glyphs = [for (var d = 0; d <= 9; d++) _glyphForDigit(d)];
    final glyphSig = glyphs.join('\u0000');
    // 缓存命中时直接返回，显式括号满足静态检查。
    if (_prototypeSize != null &&
        style == _lastStyle &&
        textScaler == _lastTextScaler &&
        glyphSig == _lastGlyphSig) {
      return;
    }
    _lastStyle = style; _lastTextScaler = textScaler; _lastGlyphSig = glyphSig;
    // Measure every digit 0–9 as it will actually render (numeralMapper /
    // numeralSystem may yield glyphs wider or taller than Latin '0', e.g.
    // circled numbers ①–⑨), and size the cell to the widest & tallest so no
    // glyph is clipped.
    //
    // 按实际渲染字形逐一测量数字 0–9（numeralMapper / numeralSystem 可能产生
    // 比拉丁 '0' 更宽或更高的字形，例如圆圈数字 ①–⑨），单元格取最大宽高，
    // 使任何字形都不会被裁剪。
    double w = 0, h = 0;
    for (final g in glyphs) {
      final tp = TextPainter(
        text: TextSpan(text: g, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      if (tp.size.width  > w) w = tp.size.width;
      if (tp.size.height > h) h = tp.size.height;
      tp.dispose();
    }
    _prototypeSize = Size(w, h);
  }

  Widget _wrapSemantics(Widget child, String label) {
    // Apply the style's container decoration around the whole counter.
    //
    // 应用样式的容器装饰，包裹整个计数器。
    final decorated = applyBoxStyle(child, decoration: widget.decoration);
    if (label.isEmpty) return decorated;
    return Semantics(label: label, child: ExcludeSemantics(child: decorated));
  }

  /// 语义文本与屏幕共用缩写、小数位和有限值处理。
  String _buildSemanticText(int intValue) {
    final display = _displayNumber(_currentValue);
    final absValue = display.scaledValue.abs() / math.pow(10, display.fractionDigits);
    final sign = display.scaledValue < 0 ? '-' :
        (widget._fmtShowPositiveSign && display.scaledValue > 0 ? '+' : '');
    return '$sign${absValue.toStringAsFixed(display.fractionDigits)}${display.suffix ?? ""}';
  }

  Widget _buildAffix(String text, TextStyle? style, TextOverflow? overflow) {
    final w = Text(text, style: style, overflow: overflow);
    return overflow != null ? Flexible(child: w) : w;
  }
}
