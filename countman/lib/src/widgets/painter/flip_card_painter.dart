import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../countdown_card_types.dart';
import 'perspective.dart';

/// Layout of one digit cell within a [CountdownCard], resolved by its
/// `_measure()` and consumed by [FlipCardPainter].
class Cell {
  const Cell(this.x, this.width, this.digitIndex, this.radius);
  final double x;
  final double width;
  final int digitIndex;
  final BorderRadius radius;
}

/// Resolved geometry for one [CountdownCard] paint pass — cell positions,
/// separator/label centers, and the overall canvas [size].
class CardGeometry {
  const CardGeometry({
    required this.size,
    required this.cells,
    required this.separatorCenters,
    required this.unitLabelCenters,
    required this.unitLabelText,
  });
  final Size size;
  final List<Cell> cells;
  final List<double> separatorCenters;
  final List<double> unitLabelCenters;
  final List<String?> unitLabelText;
}

/// Mutable, painter-visible animation state for one `CountdownCard` instance.
/// Digit ticks and transition progress mutate this directly — no `setState`
/// — the painter's `repaint` listenable (the shared [AnimationController])
/// is what schedules the repaint.
class CardModel {
  CardModel(this.committed);
  List<int> committed;
  List<int>? target;
  List<bool>? changedMask;
  bool reversePhase = false;
}

/// Paints one `CountdownCard` — every digit, separator and label — as a
/// single [CustomPainter] repainted in place, not a widget subtree rebuilt
/// per digit.
///
/// [CountdownType.calendar] mechanics: double-buffered, ported
/// from flip_panel_plus (MIT): https://pub.dev/packages/flip_panel_plus —
/// the upper flap falls away (0 → π/2) to reveal the new value's static
/// background beneath it, and the lower flap rises into place (-π/2 → 0) to
/// cover the old value's static background. Both backgrounds are correct
/// throughout, so neither half ever "pops" to the new value before its flap
/// has actually rotated into place.
///
/// Every drawing step is public and overridable so a subclass can swap in a
/// different look for one piece without reimplementing the rest — e.g.
/// override [drawFace] to change the card background shape, or
/// [paintChangingCell] to dispatch to an entirely custom transition:
///
/// ```dart
/// class NeonCardPainter extends FlipCardPainter {
///   NeonCardPainter({required super.repaint, ...});
///   @override
///   void drawFace(Canvas canvas, Rect rect, int value, BorderRadius radius) {
///     canvas.drawRRect(radius.toRRect(rect.inflate(2)), Paint()
///       ..color = cardColor.withValues(alpha: 0.4)
///       ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)); // glow
///     super.drawFace(canvas, rect, value, radius);
///   }
/// }
/// ```
class FlipCardPainter extends CustomPainter {
  FlipCardPainter({
    required Listenable repaint,
    required this.controller,
    required this.model,
    required this.geom,
    required this.transitionType,
    required this.scaleEffect,
    required this.scaleFactor,
    required this.opacityEffect,
    required this.perspective,
    this.curve = Curves.linear,
    required this.cardHeight,
    required this.cardColor,
    required this.textStyle,
    required this.labelStyle,
    required this.separatorStyle,
    required this.separator,
    required this.digitCache,
    required this.sepCache,
    required this.labelCache,
  }) : super(repaint: repaint);

  // There's something wrong in the perspective transform at angle exactly 0;
  // use a very small value instead to work around it (same workaround as
  // upstream flip_panel_plus).
  static const calendarZeroAngle = 0.0001;

  final AnimationController controller;
  final CardModel model;
  final CardGeometry geom;
  final CountdownType transitionType;
  final SlideEffect scaleEffect;
  final double scaleFactor;
  final SlideEffect opacityEffect;

  /// Perspective coefficient shared by both [CountdownType.calendar]'s
  /// half-card rotation and [CountdownType.flip]'s whole-card rotation.
  final double perspective;

  /// Easing curve applied to the transition progress [t] before painting.
  ///
  /// 绘制前应用到过渡进度 [t] 的缓动曲线。
  final Curve curve;

  final double cardHeight;
  final Color cardColor;
  final TextStyle textStyle;
  final TextStyle labelStyle;
  final TextStyle separatorStyle;
  final String separator;

  // Glyph caches — see CountdownCard.build() for how these are routed to
  // either the card's own local cache or a CountdownCardProvider's shared one.
  final Map<(String, TextStyle), TextPainter> digitCache;
  final Map<(String, TextStyle), TextPainter> sepCache;
  final Map<(String, TextStyle), TextPainter> labelCache;

  @override
  void paint(Canvas canvas, Size size) {
    final t = curve.transform(controller.value.clamp(0.0, 1.0));
    final changedMask = model.changedMask;

    for (final cell in geom.cells) {
      final rect = Rect.fromLTWH(cell.x, 0, cell.width, cardHeight);
      final isChanging = changedMask != null && changedMask[cell.digitIndex] && model.target != null;
      if (!isChanging) {
        drawFace(canvas, rect, model.committed[cell.digitIndex], cell.radius);
      } else {
        paintChangingCell(
            canvas, rect, model.committed[cell.digitIndex], model.target![cell.digitIndex], t, cell.radius);
      }
      // The center seam line is a split-flap cue — only makes sense for calendar.
      if (transitionType == CountdownType.calendar) drawDivider(canvas, rect);
    }

    for (var i = 0; i < geom.separatorCenters.length; i++) {
      drawCenteredText(canvas, separator, separatorStyle, sepCache, geom.separatorCenters[i], cardHeight / 2);
    }

    for (var i = 0; i < geom.unitLabelText.length; i++) {
      final label = geom.unitLabelText[i];
      if (label == null) continue;
      drawCenteredText(
          canvas, label, labelStyle, labelCache, geom.unitLabelCenters[i], cardHeight + 4, alignTop: true);
    }
  }

  /// Dispatches a changing cell to [paintCalendarCell], [paintSlideCell], or
  /// [paintFlipCell] based on [transitionType]. Override to customize
  /// dispatch, or to add an entirely different transition (call this from a
  /// custom [paint] override — `transitionType` is a closed enum, so a
  /// genuinely new transition needs its own painter subclass with its own
  /// `paint`).
  void paintChangingCell(Canvas canvas, Rect rect, int from, int to, double t, BorderRadius radius) {
    switch (transitionType) {
      case CountdownType.calendar:
        paintCalendarCell(canvas, rect, from, to, t, radius);
      case CountdownType.slide:
        paintSlideCell(canvas, rect, from, to, t, radius);
      case CountdownType.flip:
        paintFlipCell(canvas, rect, from, to, t, radius);
    }
  }

  /// Draws a static (non-animating) card face: background + centered digit.
  void drawFace(Canvas canvas, Rect rect, int value, BorderRadius radius) {
    canvas.drawRRect(radius.toRRect(rect), Paint()..color = cardColor);
    drawCenteredText(canvas, '$value', textStyle, digitCache, rect.center.dx, rect.center.dy);
  }

  /// Draws the thin split-flap seam line across the vertical center of [rect].
  void drawDivider(Canvas canvas, Rect rect) {
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top + rect.height / 2 - 0.5, rect.width, 1),
      Paint()..color = const Color(0x28000000),
    );
  }

  /// Draws [text] centered at ([cx], [y]) (or top-aligned at `y` when
  /// [alignTop]), using (and populating) [cache] so repeated glyphs across
  /// frames/cards reuse the same laid-out [TextPainter].
  void drawCenteredText(Canvas canvas, String text, TextStyle style,
      Map<(String, TextStyle), TextPainter> cache, double cx, double y,
      {bool alignTop = false}) {
    final tp = cache.putIfAbsent(
        (text, style),
        () => TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
          ..layout());
    tp.paint(canvas, Offset(cx - tp.width / 2, alignTop ? y : y - tp.height / 2));
  }

  /// Upper half: `from` flap falls away (0 → π/2) revealing the `to` value's
  /// static background beneath it.
  /// Lower half: `to` flap rises into place (-π/2 → 0) covering the `from`
  /// value's static background.
  void paintCalendarCell(Canvas canvas, Rect rect, int from, int to, double t, BorderRadius radius) {
    final reverse = model.reversePhase;
    final upperFrontAngle = reverse ? math.pi / 2 : t * math.pi / 2;
    final lowerFrontAngle = reverse ? -(t * math.pi / 2) : math.pi / 2;

    rotatedCalendarHalf(canvas, rect, to, radius, calendarZeroAngle, upper: true); // upper background
    rotatedCalendarHalf(canvas, rect, from, radius, upperFrontAngle, upper: true); // upper flap

    rotatedCalendarHalf(canvas, rect, from, radius, calendarZeroAngle, upper: false); // lower background
    rotatedCalendarHalf(canvas, rect, to, radius, lowerFrontAngle, upper: false); // lower flap
  }

  /// Draws [value]'s face clipped to the upper or lower half of [rect],
  /// rotated by [angle] around the shared hinge line at the cell's vertical
  /// center (a perspective rotateX transform — see class doc for why this
  /// needs a small [calendarZeroAngle] instead of a literal 0).
  void rotatedCalendarHalf(Canvas canvas, Rect rect, int value, BorderRadius radius, double angle,
      {required bool upper}) {
    final center = Offset(rect.left + rect.width / 2, rect.top + rect.height / 2);
    applyRotateX(canvas, center, angle, perspective, () {
      canvas.clipRect(upper
          ? Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height / 2)
          : Rect.fromLTWH(rect.left, rect.top + rect.height / 2, rect.width, rect.height / 2));
      drawFaceNoDivider(canvas, rect, value, radius);
    });
  }

  /// Same as [drawFace] but without the divider — the calendar halves draw
  /// the divider once, on top, in [paint] instead of per-half.
  void drawFaceNoDivider(Canvas canvas, Rect rect, int value, BorderRadius radius) {
    canvas.drawRRect(radius.toRRect(rect), Paint()..color = cardColor);
    drawCenteredText(canvas, '$value', textStyle, digitCache, rect.center.dx, rect.center.dy);
  }

  /// The card face background stays put — only the digit glyph itself
  /// translates/scales/fades, clipped to the cell so it never spills into a
  /// neighboring cell mid-slide. `from` slides down and out, `to` slides in
  /// from above.
  void paintSlideCell(Canvas canvas, Rect rect, int from, int to, double t, BorderRadius radius) {
    canvas.drawRRect(radius.toRRect(rect), Paint()..color = cardColor);

    canvas.save();
    canvas.clipRect(rect);

    final oldDy = t * rect.height;
    final newDy = -(1 - t) * rect.height;

    final oldScale = appliesToExit(scaleEffect) ? lerp(1.0, 1 / scaleFactor, t) : 1.0;
    final newScale = appliesToEnter(scaleEffect) ? lerp(scaleFactor, 1.0, t) : 1.0;
    final oldAlpha = appliesToExit(opacityEffect) ? lerp(1.0, 0.0, t) : 1.0;
    final newAlpha = appliesToEnter(opacityEffect) ? lerp(0.0, 1.0, t) : 1.0;

    paintSlideDigit(canvas, rect, from, oldDy, oldScale, oldAlpha);
    paintSlideDigit(canvas, rect, to, newDy, newScale, newAlpha);

    canvas.restore();
  }

  /// The whole card (background + digit, one rigid plane) rotates around
  /// the X axis — a real 3D perspective transform (see [applyRotateX]), not
  /// a flat scale illusion. `from` rotates away during t: 0→0.5, `to`
  /// rotates in during t: 0.5→1; each is a full ±π/2 turn (⇒ π total across
  /// both halves) so the card is edge-on and invisible exactly at t=0.5.
  ///
  /// [scaleEffect]/[opacityEffect]/[scaleFactor] apply the same way they do
  /// for [paintSlideCell] (enter/exit/both/none), just measured against each
  /// face's own half of the rotation instead of the full duration — default
  /// [SlideEffect.none] means fully opaque, no scaling, pure rotation.
  void paintFlipCell(Canvas canvas, Rect rect, int from, int to, double t, BorderRadius radius) {
    if (t < 0.5) {
      final pp = t * 2; // 0..1 across this face's own half
      final alpha = appliesToExit(opacityEffect) ? lerp(1.0, 0.0, pp) : 1.0;
      final scale = appliesToExit(scaleEffect) ? lerp(1.0, 1 / scaleFactor, pp) : 1.0;
      drawRotatedFace(canvas, rect, from, radius, -t * math.pi, alpha, scale);
    } else {
      final pp = (t - 0.5) * 2;
      final alpha = appliesToEnter(opacityEffect) ? lerp(0.0, 1.0, pp) : 1.0;
      final scale = appliesToEnter(scaleEffect) ? lerp(scaleFactor, 1.0, pp) : 1.0;
      drawRotatedFace(canvas, rect, to, radius, (1 - t) * math.pi, alpha, scale);
    }
  }

  /// Draws [value]'s whole face (background + digit) rotated by [angle]
  /// around the cell's own center, at [alpha] opacity and [scale] size.
  void drawRotatedFace(
      Canvas canvas, Rect rect, int value, BorderRadius radius, double angle, double alpha, double scale) {
    final center = rect.center;
    applyRotateX(canvas, center, angle, perspective, () {
      if (scale == 1.0) {
        drawFaceWithAlpha(canvas, rect, value, radius, alpha);
        return;
      }
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);
      drawFaceWithAlpha(canvas, rect, value, radius, alpha);
      canvas.restore();
    });
  }

  /// Same as [drawFace] but at [alpha] opacity — see [paintSlideDigit] for
  /// why a fading digit bypasses [digitCache] instead of using `saveLayer`.
  void drawFaceWithAlpha(Canvas canvas, Rect rect, int value, BorderRadius radius, double alpha) {
    canvas.drawRRect(radius.toRRect(rect), Paint()..color = cardColor.withValues(alpha: alpha));
    if (alpha >= 1.0) {
      drawCenteredText(canvas, '$value', textStyle, digitCache, rect.center.dx, rect.center.dy);
    } else {
      final faded = textStyle.copyWith(color: (textStyle.color ?? const Color(0xFFFFFFFF)).withValues(alpha: alpha));
      final tp = TextPainter(text: TextSpan(text: '$value', style: faded), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
      tp.dispose(); // uncached, per-frame — release the native paragraph now
    }
  }

  bool appliesToEnter(SlideEffect e) => e == SlideEffect.enter || e == SlideEffect.both;
  bool appliesToExit(SlideEffect e) => e == SlideEffect.exit || e == SlideEffect.both;

  double lerp(double a, double b, double t) => a + (b - a) * t;

  /// Draws one sliding/scaling/fading digit glyph at vertical offset [dy]
  /// from the cell's center, scaled by [scale] around its own current
  /// position, at [alpha] opacity.
  ///
  /// Opacity can't be applied to an already-built (cached) [TextPainter]
  /// without either rebuilding it (defeats the point of caching a value
  /// that's fading, not repeating) or wrapping the draw in `saveLayer` (the
  /// exact per-frame compositing-layer cost the glyph cache elsewhere
  /// exists to avoid). So: fully-opaque digits use the shared cache as
  /// normal; a fading digit builds an uncached [TextPainter] with the alpha
  /// baked into its color for just the duration it's actually fading, no
  /// `saveLayer` involved.
  void paintSlideDigit(Canvas canvas, Rect rect, int value, double dy, double scale, double alpha) {
    final cx = rect.center.dx;
    final cy = rect.center.dy + dy;
    final scaled = scale != 1.0;
    if (scaled) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(scale);
      canvas.translate(-cx, -cy);
    }

    if (alpha >= 1.0) {
      drawCenteredText(canvas, '$value', textStyle, digitCache, cx, cy);
    } else {
      final faded = textStyle.copyWith(color: (textStyle.color ?? const Color(0xFFFFFFFF)).withValues(alpha: alpha));
      final tp = TextPainter(text: TextSpan(text: '$value', style: faded), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      tp.dispose(); // uncached, per-frame — release the native paragraph now
    }

    if (scaled) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FlipCardPainter oldDelegate) => true;
}
