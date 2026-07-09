// Custom painter for CountupPlus digits.
//
// Key design: the painter is created ONCE per widget lifetime (in initState)
// and updated in-place each frame. Combined with the `repaint` Listenable,
// Flutter only calls paint() — the widget build phase is skipped entirely.
//
// Build cost per frame: ~0ms (no widget instantiation).
// Paint cost per frame: O(digits) canvas draw calls, no saveLayer.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'types.dart';

class CounterPainter extends CustomPainter {
  CounterPainter({
    required Listenable repaint,        // ← drives markNeedsPaint, NOT build
    required List<double> digitValues,
    required this.style,
    required this.digitSize,
    required this.transitionType,
    required this.flipDirection,
    required bool increasing,
    required this.fractionDigits,
    required this.groupingPattern,
    required this.hideLeadingZeroes,
    required this.numeralSystem,
    this.numeralMapper,
    this.thousandSeparator,
    this.separatorStyle,
    this.padding = EdgeInsets.zero,
  })  : _digitValues = List<double>.of(digitValues),
        _increasing = increasing,
        _color = style.color ?? const Color(0xFFFFFFFF),
        super(repaint: repaint);

  // ── mutable state updated each frame ──────────────────────────────────────
  List<double> _digitValues;
  bool _increasing;

  /// Update digit values and increasing direction.
  /// Called from onUpdate; the caller is responsible for triggering repaint.
  void update(List<double> values, bool increasing) {
    _digitValues = values;
    _increasing  = increasing;
  }

  // ── immutable config ───────────────────────────────────────────────────────
  final TextStyle style;
  final Size digitSize;
  final CounterTransitionType transitionType;
  final AxisDirection flipDirection;
  final int fractionDigits;
  final List<int> groupingPattern;
  final bool hideLeadingZeroes;
  final NumeralSystem numeralSystem;
  final String Function(int)? numeralMapper;
  final String? thousandSeparator;
  final TextStyle? separatorStyle;
  final EdgeInsets padding;
  final Color _color;

  // ── paragraph cache ────────────────────────────────────────────────────────
  // Key: digit * 256 + alpha_byte → Paragraph (pre-laid-out)
  // Survives across frames because the painter is long-lived.
  final Map<int, ui.Paragraph> _cache = {};

  ui.Paragraph _para(int digit, double alpha) {
    final key = digit * 256 + (alpha * 255).round().clamp(0, 255);
    return _cache.putIfAbsent(key, () {
      final str = numeralMapper != null
          ? numeralMapper!(digit)
          : (_numeralMap[numeralSystem]?[digit] ?? '$digit');
      final color = _color.withValues(alpha: alpha.clamp(0.0, 1.0));
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          fontStyle: style.fontStyle,
          fontFamily: style.fontFamily,
        ),
      )
        ..pushStyle(ui.TextStyle(
            color: color,
            fontSize: style.fontSize,
            fontWeight: style.fontWeight,
            fontFamily: style.fontFamily))
        ..addText(str);
      return pb.build()
        ..layout(ui.ParagraphConstraints(
            width: digitSize.width + padding.horizontal));
    });
  }

  // ── layout ─────────────────────────────────────────────────────────────────

  List<_Col> _buildColumns() {
    final n = digitValues.length;
    final dw = digitSize.width + padding.horizontal;
    final sw = _separatorWidth();
    double x = 0;

    int firstVisible = 0;
    if (hideLeadingZeroes) {
      // Use round() to match the widget-path visibility rule.
      // truncate() + fractional threshold was causing all digits to appear
      // immediately (e.g. v=0.014 has frac > 0.01 → shown at 1.4% progress).
      firstVisible = _digitValues.indexWhere((v) => v.round() != 0);
      if (firstVisible == -1) firstVisible = n - 1;
    }

    final cols = <_Col>[];
    for (int i = 0; i < n; i++) {
      final intPos   = i - fractionDigits;
      final fromRight = n - fractionDigits - 1 - intPos;
      if (hideLeadingZeroes && i < firstVisible) continue;

      if (thousandSeparator != null &&
          intPos >= 0 &&
          fromRight > 0 &&
          fromRight % _groupSize(fromRight) == 0) {
        x += sw;
      }
      cols.add(_Col(index: i, x: x, fromRight: fromRight));
      x += dw;
    }
    return cols;
  }

  int _groupSize(int fromRight) {
    int acc = 0;
    for (int gi = groupingPattern.length - 1; gi >= 0; gi--) {
      acc += groupingPattern[gi];
      if (fromRight <= acc) return groupingPattern[gi];
    }
    return groupingPattern.last;
  }

  double _separatorWidth() {
    if (thousandSeparator == null) return 0;
    final st = separatorStyle ?? style;
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: st.fontSize, fontFamily: st.fontFamily),
    )
      ..pushStyle(ui.TextStyle(
          color: st.color ?? _color,
          fontSize: st.fontSize,
          fontFamily: st.fontFamily))
      ..addText(thousandSeparator!);
    return (pb.build()..layout(const ui.ParagraphConstraints(width: 200)))
        .maxIntrinsicWidth;
  }

  // ── paint ──────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final cols = _buildColumns();
    final dh = digitSize.height + padding.vertical;
    final dw = digitSize.width + padding.horizontal;

    for (final col in cols) {
      final v   = _digitValues[col.index];
      final cur = v.truncate() % 10;
      final p   = (v - v.truncate()).clamp(0.0, 1.0);
      final nxt = _increasing ? (cur + 1) % 10 : (cur - 1 + 10) % 10;

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(col.x, 0, dw, dh));
      _paintTransition(canvas, cur, nxt, p, col.x, dh, dw);
      canvas.restore();

      if (thousandSeparator != null &&
          col.fromRight > 0 &&
          col.fromRight % _groupSize(col.fromRight) == 0) {
        _drawSep(canvas, col.x - _separatorWidth(), dh);
      }
    }
  }

  void _paintTransition(Canvas canvas, int cur, int nxt, double p,
      double x, double h, double w) {
    switch (transitionType) {
      case CounterTransitionType.roll:      _roll(canvas, cur, nxt, p, x, h);
      case CounterTransitionType.fade:      _fade(canvas, cur, nxt, p, x, h);
      case CounterTransitionType.scale:     _scale(canvas, cur, nxt, p, x, h, w, false);
      case CounterTransitionType.fadeScale: _scale(canvas, cur, nxt, p, x, h, w, true);
      case CounterTransitionType.rotate:    _rotate(canvas, cur, nxt, p, x, h, w);
      case CounterTransitionType.blur:
      case CounterTransitionType.flip:      _roll(canvas, cur, nxt, p, x, h);
    }
  }

  double _topY(double h) => (h - digitSize.height) / 2;
  double _exitDir() {
    final base = (flipDirection == AxisDirection.up ||
            flipDirection == AxisDirection.right) ? -1.0 : 1.0;
    return _increasing ? base : -base;
  }

  void _roll(Canvas c, int cur, int nxt, double p, double x, double h) {
    final d = _exitDir();
    c.drawParagraph(_para(cur, 1 - p), Offset(x, _topY(h) + p * h * d));
    c.drawParagraph(_para(nxt, p),     Offset(x, _topY(h) + (p - 1) * h * d));
  }

  void _fade(Canvas c, int cur, int nxt, double p, double x, double h) {
    final y = _topY(h);
    c.drawParagraph(_para(cur, 1 - p), Offset(x, y));
    c.drawParagraph(_para(nxt, p),     Offset(x, y));
  }

  void _scale(Canvas c, int cur, int nxt, double p,
      double x, double h, double w, bool isFadeScale) {
    final cx = x + w / 2;
    final cy = h / 2;
    final cs = isFadeScale ? (1 - 0.2 * p) : (1 - p);
    final ns = isFadeScale ? (0.8 + 0.2 * p) : p;
    _drawScaled(c, cur, 1 - p, cx, cy, cs.clamp(0.0, 1.0));
    _drawScaled(c, nxt, p,     cx, cy, ns.clamp(0.0, 1.0));
  }

  void _drawScaled(Canvas c, int d, double alpha, double cx, double cy, double s) {
    if (s <= 0) return;
    c.save();
    c.translate(cx, cy); c.scale(s, s); c.translate(-cx, -cy);
    c.drawParagraph(_para(d, alpha),
        Offset(cx - digitSize.width / 2, _topY(digitSize.height + padding.vertical)));
    c.restore();
  }

  void _rotate(Canvas c, int cur, int nxt, double p,
      double x, double h, double w) {
    final cx = x + w / 2; final cy = h / 2;
    _drawRotated(c, cur, 1 - p, cx, cy, -p * math.pi / 2);
    _drawRotated(c, nxt, p,     cx, cy,  (1 - p) * math.pi / 2);
  }

  void _drawRotated(Canvas c, int d, double alpha,
      double cx, double cy, double angle) {
    c.save();
    c.translate(cx, cy); c.rotate(angle); c.translate(-cx, -cy);
    c.drawParagraph(_para(d, alpha),
        Offset(cx - digitSize.width / 2,
               _topY(digitSize.height + padding.vertical)));
    c.restore();
  }

  void _drawSep(Canvas c, double x, double h) {
    final st = separatorStyle ?? style;
    final sw = _separatorWidth();
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: st.fontSize, fontFamily: st.fontFamily),
    )
      ..pushStyle(ui.TextStyle(
          color: st.color ?? _color,
          fontSize: st.fontSize,
          fontFamily: st.fontFamily))
      ..addText(thousandSeparator!);
    c.drawParagraph(
        pb.build()..layout(ui.ParagraphConstraints(width: sw + 4)),
        Offset(x, _topY(h)));
  }

  // shouldRepaint is not called when repaint is driven by the Listenable.
  // Return false to avoid unnecessary repaints on widget config changes
  // (those recreate the painter entirely via didUpdateWidget).
  @override
  bool shouldRepaint(CounterPainter old) => false;

  // Expose for _buildColumns (uses _digitValues)
  List<double> get digitValues => _digitValues;
}

class _Col {
  const _Col({required this.index, required this.x, required this.fromRight});
  final int index; final double x; final int fromRight;
}

const Map<NumeralSystem, List<String>> _numeralMap = {
  NumeralSystem.latin:         ['0','1','2','3','4','5','6','7','8','9'],
  NumeralSystem.easternArabic: ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'],
  NumeralSystem.persian:       ['۰','۱','۲','۳','۴','۵','۶','۷','۸','۹'],
  NumeralSystem.devanagari:    ['०','१','२','३','४','५','६','७','८','९'],
  NumeralSystem.bengali:       ['০','১','২','৩','৪','৫','৬','৭','৮','৯'],
};
