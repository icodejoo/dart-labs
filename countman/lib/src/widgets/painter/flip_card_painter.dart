import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import '../card_countdown_types.dart';
import '../card_countdown_provider.dart';
import 'perspective.dart';
import 'image_byte_cache.dart';

/// 整张卡面位图的缓存键：同值、同尺寸、同样式的卡面可跨卡片共享。
@immutable
class _FaceKey {
  const _FaceKey(
    this.value,
    this.width,
    this.height,
    this.radius,
    this.color,
    this.style,
    this.ratio,
    this.padding,
  );
  final int value;
  final double width;
  final double height;
  final BorderRadius radius;
  final Color color;
  final TextStyle style;
  final double ratio;
  final double padding;

  @override
  bool operator ==(Object other) =>
      other is _FaceKey &&
      other.value == value &&
      other.width == width &&
      other.height == height &&
      other.radius == radius &&
      other.color == color &&
      other.style == style &&
      other.ratio == ratio &&
      other.padding == padding;

  @override
  int get hashCode =>
      Object.hash(value, width, height, radius, color, style, ratio, padding);
}

/// 透视旋转用的卡面位图缓存（全局共享、LRU 淘汰）。
///
/// 透视矩阵下文字会退化为路径光栅化，是翻牌 raster 耗时的主要来源；
/// 把“背景 + 数字”预渲染成位图后，旋转只剩一次带纹理的四边形绘制。
class _FaceImageCache {
  /// 包含边距的像素预算。
  static const int byteBudget = 8 * 1024 * 1024;
  static final _cache = ImageByteCache<_FaceKey>(byteBudget);

  /// 取得卡面位图；失败或单张超预算时返回 null。
  static ui.Image? obtain(
    _FaceKey key,
    void Function(Canvas canvas, Rect rect) drawFace,
  ) {
    return _cache.obtain(
      key,
      size: Size(key.width, key.height),
      ratio: key.ratio,
      padding: key.padding,
      draw: (canvas) =>
          drawFace(canvas, Rect.fromLTWH(0, 0, key.width, key.height)),
    );
  }

  static void clear() => _cache.clear();
}

/// Layout of one digit cell within a [CardCountdown], resolved by its
/// `_measure()` and consumed by [FlipCardPainter].
class Cell {
  const Cell(this.x, this.width, this.digitIndex, this.radius);
  final double x;
  final double width;
  final int digitIndex;
  final BorderRadius radius;
}

/// Resolved geometry for one [CardCountdown] paint pass — cell positions,
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

/// Mutable, painter-visible animation state for one `CardCountdown` instance.
/// Digit ticks and transition progress mutate this directly — no `setState`
/// — the painter's `repaint` listenable (the shared [Animation])
/// is what schedules the repaint.
class CardModel {
  CardModel(this.committed);
  List<int> committed;
  List<int>? target;
  List<bool>? changedMask;
  bool reversePhase = false;
}

/// Paints one `CardCountdown` — every digit, separator and label — as a
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
/// 常驻翻牌画笔，复用画笔和有限透明度样式，保留原颜色的 alpha。
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

  final Animation<double> controller;
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

  // Glyph caches — see CardCountdown.build() for how these are routed to
  // either an equal-style reference-counted cache or the provider's cache.
  final Map<(String, TextStyle), TextPainter> digitCache;
  final Map<(String, TextStyle), TextPainter> sepCache;
  final Map<(String, TextStyle), TextPainter> labelCache;

  /// 背景和分隔线画笔常驻复用，避免在逐数位热路径创建 Paint。
  final Paint _facePaint = Paint();
  /// 翻牌缝隙画笔使用固定颜色。
  final Paint _dividerPaint = Paint()..color = const Color(0x28000000);
  /// 淡化文字样式只建立 16 档，帧间复用并命中字形缓存。
  late final List<TextStyle> _fadedStyles = List.generate(_alphaBuckets, (bucket) {
    final base = textStyle.color ?? const Color(0xFFFFFFFF);
    return textStyle.copyWith(color: base.withValues(alpha: base.a * bucket / (_alphaBuckets - 1)));
  });

  /// 十进制字形与常用标签表在预热后直接按身份读取，无需构造键。
  static const _digitTexts = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  /// 数字表长度与透明度表的每档跨度。
  static const _digitCount = 10;
  /// 最多记忆一个分隔符及四个单位标签。
  static const _smallGlyphCapacity = 5;
  /// 原始数字样式的本地段落引用。
  final _digits = List<TextPainter?>.filled(_digitCount, null);
  /// 各透明度档的本地数字引用。
  final _faded = List<TextPainter?>.filled(_alphaBuckets * _digitCount, null);
  /// 记忆标签文本身份，避免重复构造 record。
  final _smallTexts = List<String?>.filled(_smallGlyphCapacity, null);
  /// 记忆标签样式身份，与文本共同限定命中。
  final _smallStyles = List<TextStyle?>.filled(_smallGlyphCapacity, null);
  /// 记忆段落所属缓存，防止跨缓存误命中。
  final _smallCaches = List<Map<(String, TextStyle), TextPainter>?>.filled(_smallGlyphCapacity, null);
  /// 有界小表中的段落引用。
  final _smallGlyphs = List<TextPainter?>.filled(_smallGlyphCapacity, null);
  /// 小表的下一个循环替换位置。
  int _smallNext = 0;
  /// 最近一次淡化样式对应的透明度档。
  int _lastBucket = 0;
  /// 普通 Map 或尚未同步的缓存使用此版本哨兵。
  static const _unknownGeneration = -1;
  /// 三个缓存已同步的版本；普通 Map 不启用本地引用表。
  int _digitGeneration = _unknownGeneration,
      _sepGeneration = _unknownGeneration,
      _labelGeneration = _unknownGeneration;

  /// 仅十进制数字复用常量字符串，其他值保持原转换语义。
  String _digitText(int value) => value >= 0 && value < _digitCount ? _digitTexts[value] : '$value';

  /// 版本变化时原地清空引用，避免淘汰或释放后再绘制已销毁段落。
  void _syncGlyphTables() {
    final digits = digitCache;
    final separators = sepCache;
    final labels = labelCache;
    final dg = digits is CardGlyphCache ? digits.generation : _unknownGeneration;
    final sg = separators is CardGlyphCache ? separators.generation : _unknownGeneration;
    final lg = labels is CardGlyphCache ? labels.generation : _unknownGeneration;
    if (dg == _digitGeneration && sg == _sepGeneration && lg == _labelGeneration) return;
    _digits.fillRange(0, _digits.length, null);
    _faded.fillRange(0, _faded.length, null);
    _smallTexts.fillRange(0, _smallGlyphCapacity, null);
    _smallStyles.fillRange(0, _smallGlyphCapacity, null);
    _smallCaches.fillRange(0, _smallGlyphCapacity, null);
    _smallGlyphs.fillRange(0, _smallGlyphCapacity, null);
    _smallNext = 0;
    _digitGeneration = dg;
    _sepGeneration = sg;
    _labelGeneration = lg;
  }

  /// 身份未命中时沿用原 Map 路径，闭包仅在慢路径建立。
  TextPainter _lookupGlyph(String text, TextStyle style, Map<(String, TextStyle), TextPainter> cache) =>
      cache.putIfAbsent(
        (text, style),
        () => TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
          ..layout());

  @override
  void paint(Canvas canvas, Size size) {
    _syncGlyphTables();
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
  /// 用复用画笔绘制静态卡片，保持背景原始透明度。
  void drawFace(Canvas canvas, Rect rect, int value, BorderRadius radius) {
    canvas.drawRRect(radius.toRRect(rect), _facePaint..color = cardColor);
    drawCenteredText(canvas, _digitText(value), textStyle, digitCache, rect.center.dx, rect.center.dy);
  }

  /// Draws the thin split-flap seam line across the vertical center of [rect].
  /// 用固定画笔绘制翻牌中缝。
  void drawDivider(Canvas canvas, Rect rect) {
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top + rect.height / 2 - 0.5, rect.width, 1),
      _dividerPaint,
    );
  }

  /// Draws [text] centered at ([cx], [y]) (or top-aligned at `y` when
  /// [alignTop]), using (and populating) [cache] so repeated glyphs across
  /// frames/cards reuse the same laid-out [TextPainter].
  void drawCenteredText(Canvas canvas, String text, TextStyle style,
      Map<(String, TextStyle), TextPainter> cache, double cx, double y,
      {bool alignTop = false}) {
    TextPainter? tp;
    if (cache is CardGlyphCache &&
        (identical(cache, digitCache) || identical(cache, sepCache) || identical(cache, labelCache))) {
      final generation = cache.generation;
      final knownGeneration = identical(cache, digitCache) ? _digitGeneration :
          identical(cache, sepCache) ? _sepGeneration : _labelGeneration;
      if (generation != knownGeneration) _syncGlyphTables();
      List<TextPainter?>? table;
      var index = 0;
      if (identical(cache, digitCache) && text.length == 1) {
        final digit = text.codeUnitAt(0) - 0x30;
        if (digit >= 0 && digit < _digitCount) {
          if (identical(style, textStyle)) {
            table = _digits;
            index = digit;
          } else if (identical(style, _fadedStyles[_lastBucket])) {
            table = _faded;
            index = _lastBucket * _digitCount + digit;
          }
        }
      }
      if (table != null) {
        tp = table[index];
        if (tp == null) {
          tp = _lookupGlyph(text, style, cache);
          if (cache.generation != generation) _syncGlyphTables();
          table[index] = tp;
        }
      } else {
        for (var i = 0; i < _smallGlyphCapacity; i++) {
          if (identical(text, _smallTexts[i]) && identical(style, _smallStyles[i]) &&
              identical(cache, _smallCaches[i])) {
            tp = _smallGlyphs[i];
            break;
          }
        }
        if (tp == null) {
          tp = _lookupGlyph(text, style, cache);
          if (cache.generation != generation) _syncGlyphTables();
          final slot = _smallNext;
          _smallNext = (_smallNext + 1) % _smallGlyphCapacity;
          _smallTexts[slot] = text;
          _smallStyles[slot] = style;
          _smallCaches[slot] = cache;
          _smallGlyphs[slot] = tp;
        }
      }
    } else {
      tp = _lookupGlyph(text, style, cache);
    }
    tp.paint(canvas, Offset(cx - tp.width / 2, alignTop ? y : y - tp.height / 2));
  }

  /// A faded copy of [textStyle] with [alpha] quantized to [_alphaBuckets]
  /// levels. Routing a fading digit through this + [drawCenteredText] caches
  /// ≤ 10·16 faded glyphs instead of building/laying-out/disposing an uncached
  /// [TextPainter] every frame for the whole transition.
  ///
  /// [textStyle] 的淡化副本，[alpha] 量化到 [_alphaBuckets] 级。淡入数位经此 +
  /// [drawCenteredText] 缓存 ≤ 10·16 个淡化字形，而非整段过渡每帧新建/排版/销毁一个
  /// 未缓存 [TextPainter]。
  static const int _alphaBuckets = 16;
  /// 动画透明度与原文字透明度叠乘，返回有限档位的缓存样式。
  TextStyle _fadedStyle(double alpha) {
    _lastBucket = (alpha.clamp(0.0, 1.0) * (_alphaBuckets - 1)).round();
    return _fadedStyles[_lastBucket];
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
  void rotatedCalendarHalf(
    Canvas canvas,
    Rect rect,
    int value,
    BorderRadius radius,
    double angle, {
    required bool upper,
  }) {
    final center = Offset(
      rect.left + rect.width / 2,
      rect.top + rect.height / 2,
    );
    canvas.save();
    transformRotateX(canvas, center, angle, perspective);
    final half = upper
        ? Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height / 2)
        : Rect.fromLTWH(
            rect.left,
            rect.top + rect.height / 2,
            rect.width,
            rect.height / 2,
          );
    if (!_drawFaceImage(canvas, rect, value, radius, 1.0, half: half)) {
      canvas.clipRect(half);
      drawFaceNoDivider(canvas, rect, value, radius);
    }
    canvas.restore();
  }

  /// 以缓存位图绘制不透明的 [rect] 卡面（或其 [half] 半边）。
  /// 子类可能重写 [drawFaceNoDivider] 等外观钩子，因此仅原始类走位图；失败返回 false，
  /// 由调用方回退矢量绘制。
  bool _drawFaceImage(
    Canvas canvas,
    Rect rect,
    int value,
    BorderRadius radius,
    double alpha, {
    Rect? half,
  }) {
    // 淡化时背景与数字分别合成，不能对整张位图乘透明度。
    if (runtimeType != FlipCardPainter || alpha < 1.0) return false;
    final ratio = _devicePixelRatio();
    final glyph = _lookupGlyph(_digitText(value), textStyle, digitCache);
    // 字号覆盖字形边缘，额外保留超宽文字及阴影尾部。
    final margin = math.max(
      textStyle.fontSize ?? 14.0,
      math.max(
        (glyph.width - rect.width) / 2,
        (glyph.height - rect.height) / 2,
      ),
    );
    var shadowMargin = 0.0;
    for (final shadow in textStyle.shadows ?? const <Shadow>[]) {
      shadowMargin = math.max(
        shadowMargin,
        shadow.offset.dx.abs() + shadow.offset.dy.abs() + 3 * shadow.blurRadius,
      );
    }
    final padding = math.max(0.0, margin + shadowMargin).ceilToDouble();
    final image = _FaceImageCache.obtain(
      _FaceKey(
        value,
        rect.width,
        rect.height,
        radius,
        cardColor,
        textStyle,
        ratio,
        padding,
      ),
      (c, r) {
        c.drawRRect(radius.toRRect(r), Paint()..color = cardColor);
        _paintGlyphDirect(c, value, r);
      },
    );
    if (image == null) return false;
    final padded = rect.inflate(padding);
    final sx = image.width / padded.width;
    final sy = image.height / padded.height;
    final dst = half ?? padded;
    final src = half == null
        ? Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
        : Rect.fromLTWH(
            (half.left - padded.left) * sx,
            (half.top - padded.top) * sy,
            half.width * sx,
            half.height * sy,
          );
    canvas.drawImageRect(image, src, dst, _imagePaint);
    return true;
  }

  /// 位图常驻画笔：中等过滤质量，避免透视缩放时锯齿。
  final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;

  /// 释放所有实例共享的翻牌卡面位图；可重复调用，下次绘制时按需重建。
  /// 不清理字形缓存，也不主动触发重绘。
  /// 例如在内存紧张或测试清理时调用：
  /// ```dart
  /// FlipCardPainter.clearFaceImageCache();
  /// ```
  static void clearFaceImageCache() => _FaceImageCache.clear();

  /// 当前主视图的设备像素比，取不到时按 1。
  double _devicePixelRatio() {
    final views = ui.PlatformDispatcher.instance.views;
    final ratio = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    return ratio < 1.0 ? 1.0 : ratio;
  }

  /// 不经缓存、直接把数字居中画到 [rect]，供位图生成使用。
  void _paintGlyphDirect(Canvas canvas, int value, Rect rect) {
    final tp = _lookupGlyph(_digitText(value), textStyle, digitCache);
    tp.paint(
      canvas,
      Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
    );
  }

  /// Same as [drawFace] but without the divider — the calendar halves draw
  /// the divider once, on top, in [paint] instead of per-half.
  void drawFaceNoDivider(Canvas canvas, Rect rect, int value, BorderRadius radius) {
    canvas.drawRRect(radius.toRRect(rect), _facePaint..color = cardColor);
    drawCenteredText(canvas, _digitText(value), textStyle, digitCache, rect.center.dx, rect.center.dy);
  }

  /// The card face background stays put — only the digit glyph itself
  /// translates/scales/fades, clipped to the cell so it never spills into a
  /// neighboring cell mid-slide. `from` slides down and out, `to` slides in
  /// from above.
  void paintSlideCell(Canvas canvas, Rect rect, int from, int to, double t, BorderRadius radius) {
    canvas.drawRRect(radius.toRRect(rect), _facePaint..color = cardColor);

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
    Canvas canvas,
    Rect rect,
    int value,
    BorderRadius radius,
    double angle,
    double alpha,
    double scale,
  ) {
    final center = rect.center;
    canvas.save();
    transformRotateX(canvas, center, angle, perspective);
    if (scale == 1.0) {
      if (!_drawFaceImage(canvas, rect, value, radius, alpha)) {
        drawFaceWithAlpha(canvas, rect, value, radius, alpha);
      }
    } else {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);
      if (!_drawFaceImage(canvas, rect, value, radius, alpha)) {
        drawFaceWithAlpha(canvas, rect, value, radius, alpha);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  /// Same as [drawFace] but at [alpha] opacity, using cached quantized
  /// text colors instead of `saveLayer` for fading digits.
  /// 叠乘卡片和文字原 alpha；透明度为 1 时保持原始半透明样式。
  void drawFaceWithAlpha(Canvas canvas, Rect rect, int value, BorderRadius radius, double alpha) {
    canvas.drawRRect(radius.toRRect(rect), _facePaint..color = cardColor.withValues(alpha: cardColor.a * alpha));
    if (alpha >= 1.0) {
      drawCenteredText(canvas, _digitText(value), textStyle, digitCache, rect.center.dx, rect.center.dy);
    } else {
      drawCenteredText(canvas, _digitText(value), _fadedStyle(alpha), digitCache, rect.center.dx, rect.center.dy);
    }
  }

  bool appliesToEnter(SlideEffect e) => e == SlideEffect.enter || e == SlideEffect.both;
  bool appliesToExit(SlideEffect e) => e == SlideEffect.exit || e == SlideEffect.both;

  double lerp(double a, double b, double t) => a + (b - a) * t;

  /// Draws one sliding/scaling/fading digit glyph at vertical offset [dy]
  /// from the cell's center, scaled by [scale] around its own current
  /// position, at [alpha] opacity.
  ///
  /// Fading digits reuse the 16 quantized text-color styles and glyph
  /// cache entries, preserving the original text alpha without `saveLayer`.
  /// 淡化数字缓存 16 档颜色和段落，避免逐帧排版及额外合成层。
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
      drawCenteredText(canvas, _digitText(value), textStyle, digitCache, cx, cy);
    } else {
      drawCenteredText(canvas, _digitText(value), _fadedStyle(alpha), digitCache, cx, cy);
    }

    if (scaled) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FlipCardPainter oldDelegate) => true;
}
