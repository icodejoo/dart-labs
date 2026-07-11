// Custom painter for AnimatedCounter digits.
//
// Key design: the painter is created ONCE per widget lifetime (in initState)
// and updated in-place each frame. Combined with the `repaint` Listenable,
// Flutter only calls paint() — the widget build phase is skipped entirely.
//
// Build cost per frame: ~0ms (no widget instantiation).
// Paint cost per frame: O(digits) canvas draw calls, no saveLayer.
//
// Every drawing step below is public and overridable (no leading
// underscore) specifically so a subclass can customize or add a transition
// without reimplementing paragraph caching / column layout from scratch —
// override `paintTransition` for a per-digit hook, or just one of
// `roll`/`fade`/`scale`/`rotate`/`flip` to tweak a single existing look.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../animated_counter/types.dart';
import 'perspective.dart';

/// Factory signature for [AnimatedCounter.painterBuilder]. Receives the exact
/// arguments the default [CounterPainter] would be built with, so a custom
/// implementation can subclass [CounterPainter] and forward them (overriding
/// only the drawing methods it cares about) while keeping the in-place
/// `update()` / repaint contract the fast path relies on.
typedef CounterPainterBuilder = CounterPainter Function({
  required Listenable repaint,
  required List<double> digitValues,
  required TextStyle style,
  required Size digitSize,
  required CounterTransitionType transitionType,
  required AxisDirection flipDirection,
  required bool increasing,
  required int fractionDigits,
  required List<int> groupingPattern,
  required bool hideLeadingZeroes,
  required NumeralSystem numeralSystem,
  String Function(int)? numeralMapper,
  String? thousandSeparator,
  String decimalSeparator,
  TextStyle? separatorStyle,
  EdgeInsets padding,
  double numberAlignment,
});

class CounterPainter extends CustomPainter {
  CounterPainter({
    required Listenable repaint,
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
    this.decimalSeparator = '.',
    this.separatorStyle,
    this.padding = EdgeInsets.zero,
    this.numberAlignment = 0.0,
  })  : _digitValues = List<double>.of(digitValues),
        _increasing = increasing,
        color = style.color ?? const Color(0xFFFFFFFF),
        super(repaint: repaint);

  // ── mutable state updated each frame ──────────────────────────────────────
  List<double> _digitValues;
  bool _increasing;
  /// Alpha multiplier applied to the incoming (nxt) digit during transitions.
  /// Set to < 1.0 during bounce so the overshoot digit is semi-transparent.
  double _bounceAlpha = 1.0;

  void update(List<double> values, bool increasing, {double bounceAlpha = 1.0}) {
    _digitValues   = values;
    _increasing    = increasing;
    _bounceAlpha   = bounceAlpha;
  }

  List<double> get digitValues => _digitValues;
  bool get increasing => _increasing;

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
  final String decimalSeparator;
  final TextStyle? separatorStyle;
  final EdgeInsets padding;
  /// Horizontal alignment of visible digits within the stable SizedBox.
  /// -1.0 = left, 0.0 = center (default), 1.0 = right.
  final double numberAlignment;
  final Color color;

  // ── paragraph cache ────────────────────────────────────────────────────────
  final Map<int, ui.Paragraph> _cache = {};

  /// Builds (or reuses) a laid-out [ui.Paragraph] for [digit] at [alpha].
  ui.Paragraph paragraphFor(int digit, double alpha) {
    final key = digit * 256 + (alpha * 255).round().clamp(0, 255);
    return _cache.putIfAbsent(key, () {
      final str = numeralMapper != null
          ? numeralMapper!(digit)
          : (numeralSystemDigits[numeralSystem]?[digit] ?? '$digit');
      final c = color.withValues(alpha: alpha.clamp(0.0, 1.0));
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
            color: c,
            fontSize: style.fontSize,
            fontWeight: style.fontWeight,
            fontFamily: style.fontFamily))
        ..addText(str);
      return pb.build()
        ..layout(ui.ParagraphConstraints(width: digitSize.width + padding.horizontal));
    });
  }

  // ── layout ─────────────────────────────────────────────────────────────────

  /// Computes each visible digit column's x-offset, skipping hidden leading
  /// zeroes and leaving room for thousand and decimal separators.
  List<DigitColumnLayout> buildColumns() {
    final n   = digitValues.length;
    final dw  = digitSize.width + padding.horizontal;
    final sw  = separatorWidth();
    final dsw = decimalSeparatorWidth();
    double x  = 0;

    int firstVisible = 0;
    if (hideLeadingZeroes) {
      firstVisible = _digitValues.indexWhere((v) => v.round() != 0);
      if (firstVisible == -1) firstVisible = n - 1;
    }

    final cols = <DigitColumnLayout>[];
    for (int i = 0; i < n; i++) {
      final intPos    = i - fractionDigits;
      final fromRight = n - fractionDigits - 1 - intPos;
      if (hideLeadingZeroes && i < firstVisible) continue;

      // Reserve space for decimal separator before the first fraction digit.
      if (fractionDigits > 0 && i == n - fractionDigits) x += dsw;

      final bool addSep = thousandSeparator != null &&
          intPos >= 0 &&
          cols.isNotEmpty &&
          (fromRight + 1) % groupSizeAt(fromRight + 1) == 0;
      if (addSep) x += sw;
      cols.add(DigitColumnLayout(index: i, x: x, fromRight: fromRight, hasSeparator: addSep));
      x += dw;
    }
    return cols;
  }

  /// Returns the total rendered width of all digit columns plus separators,
  /// respecting [hideLeadingZeroes] (variable — use [computeFullWidth] for
  /// a stable SizedBox size that doesn't shrink during animation).
  double computeTotalWidth() {
    final cols = buildColumns();
    if (cols.isEmpty) return 0;
    return cols.last.x + digitSize.width + padding.horizontal;
  }

  /// Width for ALL [n] digit columns regardless of leading-zero visibility.
  /// Call this in the host widget's build() to get a stable SizedBox size
  /// that doesn't change as digits transition from leading-zero to non-zero.
  double computeFullWidth() {
    final n   = digitValues.length;
    final dw  = digitSize.width + padding.horizontal;
    final sw  = separatorWidth();
    final dsw = decimalSeparatorWidth();
    double x  = 0;
    for (int i = 0; i < n; i++) {
      final intPos    = i - fractionDigits;
      final fromRight = n - fractionDigits - 1 - intPos;
      if (fractionDigits > 0 && i == n - fractionDigits) x += dsw;
      if (thousandSeparator != null && intPos >= 0 && i > 0 &&
          (fromRight + 1) % groupSizeAt(fromRight + 1) == 0) {
        x += sw;
      }
      x += dw;
    }
    return x;
  }

  int groupSizeAt(int fromRight) {
    int acc = 0;
    for (int gi = groupingPattern.length - 1; gi >= 0; gi--) {
      acc += groupingPattern[gi];
      if (fromRight <= acc) return groupingPattern[gi];
    }
    return groupingPattern.last;
  }

  double? _separatorWidthCache;
  double separatorWidth() => _separatorWidthCache ??= _measureSeparator();
  double _measureSeparator() {
    if (thousandSeparator == null) return 0;
    final st = separatorStyle ?? style;
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: st.fontSize, fontFamily: st.fontFamily),
    )
      ..pushStyle(ui.TextStyle(color: st.color ?? color, fontSize: st.fontSize, fontFamily: st.fontFamily))
      ..addText(thousandSeparator!);
    final p = pb.build()..layout(const ui.ParagraphConstraints(width: 200));
    final w = p.maxIntrinsicWidth;
    p.dispose();
    return w;
  }

  double? _decimalSepWidthCache;
  double decimalSeparatorWidth() {
    if (fractionDigits == 0) return 0;
    return _decimalSepWidthCache ??= _measureDecimalSep();
  }
  double _measureDecimalSep() {
    final st = separatorStyle ?? style;
    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: st.fontSize, fontFamily: st.fontFamily),
    )
      ..pushStyle(ui.TextStyle(color: st.color ?? color, fontSize: st.fontSize, fontFamily: st.fontFamily))
      ..addText(decimalSeparator);
    final p = pb.build()..layout(const ui.ParagraphConstraints(width: 200));
    final w = p.maxIntrinsicWidth;
    p.dispose();
    return w;
  }

  // ── paint ──────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final cols = buildColumns();
    final dh  = digitSize.height + padding.vertical;
    final dw  = digitSize.width  + padding.horizontal;
    final dsw = decimalSeparatorWidth();

    // Align visible content within the stable full-width SizedBox.
    // contentWidth is the actual rendered width; size.width is computeFullWidth().
    if (cols.isNotEmpty && hideLeadingZeroes) {
      final contentWidth = cols.last.x + dw;
      final gap = size.width - contentWidth;
      if (gap > 0) {
        // numberAlignment: -1=left(no shift), 0=center, 1=right(full shift)
        canvas.translate(gap * (numberAlignment + 1) / 2, 0);
      }
    }

    for (final col in cols) {
      // Draw decimal separator immediately before the first fraction digit.
      if (fractionDigits > 0 && col.index == _digitValues.length - fractionDigits) {
        drawDecimalSeparator(canvas, col.x - dsw, dh);
      }

      final v   = _digitValues[col.index];
      final cur = v.truncate() % 10;
      final p   = (v - v.truncate()).clamp(0.0, 1.0);
      final nxt = _increasing ? (cur + 1) % 10 : (cur - 1 + 10) % 10;

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(col.x, 0, dw, dh));
      paintTransition(canvas, cur, nxt, p, col.x, dh, dw);
      canvas.restore();

      if (col.hasSeparator) {
        drawSeparator(canvas, col.x - separatorWidth(), dh);
      }
    }
  }

  void paintTransition(Canvas canvas, int cur, int nxt, double p, double x, double h, double w) {
    switch (transitionType) {
      case CounterTransitionType.roll:      roll(canvas, cur, nxt, p, x, h);
      case CounterTransitionType.fade:      fade(canvas, cur, nxt, p, x, h);
      case CounterTransitionType.scale:     scale(canvas, cur, nxt, p, x, h, w, false);
      case CounterTransitionType.fadeScale: scale(canvas, cur, nxt, p, x, h, w, true);
      case CounterTransitionType.rotate:    rotate(canvas, cur, nxt, p, x, h, w);
      case CounterTransitionType.flip:      flip(canvas, cur, nxt, p, x, h, w);
      case CounterTransitionType.blur:      blur(canvas, cur, nxt, p, x, h, w);
    }
  }

  void blur(Canvas c, int cur, int nxt, double p, double x, double h, double w) {
    final sigma = (0.5 - (p - 0.5).abs()) * 8.0;
    if (sigma < 0.1) {
      roll(c, cur, nxt, p, x, h);
    } else {
      c.saveLayer(
        Rect.fromLTWH(x, 0, w, h),
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
      roll(c, cur, nxt, p, x, h);
      c.restore();
    }
  }

  double topY(double h) => (h - digitSize.height) / 2;

  double exitDirection() {
    final base = (flipDirection == AxisDirection.up || flipDirection == AxisDirection.right) ? -1.0 : 1.0;
    return _increasing ? base : -base;
  }

  void roll(Canvas c, int cur, int nxt, double p, double x, double h) {
    final d = exitDirection();
    c.drawParagraph(paragraphFor(cur, 1 - p), Offset(x, topY(h) + p * h * d));
    c.drawParagraph(paragraphFor(nxt, p * _bounceAlpha), Offset(x, topY(h) + (p - 1) * h * d));
  }

  void fade(Canvas c, int cur, int nxt, double p, double x, double h) {
    final y = topY(h);
    c.drawParagraph(paragraphFor(cur, 1 - p), Offset(x, y));
    c.drawParagraph(paragraphFor(nxt, p * _bounceAlpha), Offset(x, y));
  }

  void scale(Canvas c, int cur, int nxt, double p, double x, double h, double w, bool isFadeScale) {
    final cx = x + w / 2;
    final cy = h / 2;
    final cs = isFadeScale ? (1 - 0.2 * p) : (1 - p);
    final ns = isFadeScale ? (0.8 + 0.2 * p) : p;
    drawScaled(c, cur, 1 - p, cx, cy, cs.clamp(0.0, 1.0));
    drawScaled(c, nxt, p, cx, cy, ns.clamp(0.0, 1.0));
  }

  void drawScaled(Canvas c, int d, double alpha, double cx, double cy, double s) {
    if (s <= 0) return;
    c.save();
    c.translate(cx, cy);
    c.scale(s, s);
    c.translate(-cx, -cy);
    c.drawParagraph(paragraphFor(d, alpha), Offset(cx - digitSize.width / 2, topY(digitSize.height + padding.vertical)));
    c.restore();
  }

  void rotate(Canvas c, int cur, int nxt, double p, double x, double h, double w) {
    final cx = x + w / 2;
    final cy = h / 2;
    drawRotated(c, cur, 1 - p, cx, cy, -p * math.pi / 2);
    drawRotated(c, nxt, p, cx, cy, (1 - p) * math.pi / 2);
  }

  void drawRotated(Canvas c, int d, double alpha, double cx, double cy, double angle) {
    c.save();
    c.translate(cx, cy);
    c.rotate(angle);
    c.translate(-cx, -cy);
    c.drawParagraph(paragraphFor(d, alpha), Offset(cx - digitSize.width / 2, topY(digitSize.height + padding.vertical)));
    c.restore();
  }

  void flip(Canvas c, int cur, int nxt, double p, double x, double h, double w) {
    final cx = x + w / 2;
    final cy = h / 2;
    if (p < 0.5) {
      drawFlippedX(c, cur, 1 - p, cx, cy, -p * math.pi);
    } else {
      drawFlippedX(c, nxt, p, cx, cy, (1 - p) * math.pi);
    }
  }

  void drawFlippedX(Canvas c, int d, double alpha, double cx, double cy, double angle) {
    applyRotateX(c, Offset(cx, cy), angle, 0.002, () {
      c.drawParagraph(paragraphFor(d, alpha), Offset(cx - digitSize.width / 2, topY(digitSize.height + padding.vertical)));
    });
  }

  // ── separator drawing ──────────────────────────────────────────────────────

  ui.Paragraph? _separatorParagraphCache;
  ui.Paragraph _separatorParagraph() {
    return _separatorParagraphCache ??= () {
      final st = separatorStyle ?? style;
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: st.fontSize, fontFamily: st.fontFamily),
      )
        ..pushStyle(ui.TextStyle(color: st.color ?? color, fontSize: st.fontSize, fontFamily: st.fontFamily))
        ..addText(thousandSeparator!);
      return pb.build()..layout(ui.ParagraphConstraints(width: separatorWidth() + 4));
    }();
  }

  void drawSeparator(Canvas c, double x, double h) {
    c.drawParagraph(_separatorParagraph(), Offset(x, topY(h)));
  }

  ui.Paragraph? _decimalSepParagraphCache;
  ui.Paragraph _decimalSeparatorParagraph() {
    return _decimalSepParagraphCache ??= () {
      final st = separatorStyle ?? style;
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: st.fontSize, fontFamily: st.fontFamily),
      )
        ..pushStyle(ui.TextStyle(color: st.color ?? color, fontSize: st.fontSize, fontFamily: st.fontFamily))
        ..addText(decimalSeparator);
      return pb.build()..layout(ui.ParagraphConstraints(width: decimalSeparatorWidth() + 4));
    }();
  }

  void drawDecimalSeparator(Canvas c, double x, double h) {
    if (fractionDigits == 0) return;
    c.drawParagraph(_decimalSeparatorParagraph(), Offset(x, topY(h)));
  }

  /// Disposes all cached native [ui.Paragraph]s.
  void disposeCache() {
    for (final p in _cache.values) { p.dispose(); }
    _cache.clear();
    _separatorParagraphCache?.dispose();
    _separatorParagraphCache = null;
    _decimalSepParagraphCache?.dispose();
    _decimalSepParagraphCache = null;
  }

  @override
  bool shouldRepaint(CounterPainter old) => false;
}

class DigitColumnLayout {
  const DigitColumnLayout({
    required this.index,
    required this.x,
    required this.fromRight,
    this.hasSeparator = false,
  });
  final int index;
  final double x;
  final int fromRight;
  /// True when a thousand-separator was placed immediately before this column.
  final bool hasSeparator;
}
