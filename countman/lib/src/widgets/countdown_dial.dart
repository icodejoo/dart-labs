import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'countdown_builder.dart';
import 'providers.dart';
import 'style_support.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public colour vocabulary
// ─────────────────────────────────────────────────────────────────────────────

/// The five zone colours that drive tick / arc / digit tinting.
///
/// Mirrors the `IRingColors` interface from ring.ts.
@immutable
class DialColors with StyleProps {
  const DialColors({
    this.normal = const Color(0xFFFF6A5A),
    this.green = const Color(0xFF37D67A),
    this.yellow = const Color(0xFFFFCF3A),
    this.red = const Color(0xFFFF3B30),
    this.off = const Color(0xFF3A2730),
  });

  /// Main colour used when minutes > 0 (not in final minute).
  final Color normal;

  /// Final-minute colour when sec >= yellowAt (safe zone).
  final Color green;

  /// Final-minute colour when redAt <= sec < yellowAt (caution zone).
  final Color yellow;

  /// Final-minute colour when sec < redAt (danger zone).
  final Color red;

  /// Colour of unlit tick marks.
  final Color off;

  /// Returns the zone colour for a given second index.
  Color zoneColor(int sec, {int redAt = 3, int yellowAt = 10}) {
    if (sec < redAt) return red;
    if (sec < yellowAt) return yellow;
    return green;
  }

  DialColors copyWith({
    Color? normal,
    Color? green,
    Color? yellow,
    Color? red,
    Color? off,
  }) =>
      DialColors(
        normal: normal ?? this.normal,
        green: green ?? this.green,
        yellow: yellow ?? this.yellow,
        red: red ?? this.red,
        off: off ?? this.off,
      );

  @override
  List<Object?> get props => [normal, green, yellow, red, off];
}

// ─────────────────────────────────────────────────────────────────────────────
// Tick ring configuration
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for the outermost tick ring.
///
/// Mirrors `IRingTicks` from ring.ts.
///
/// The SVG coordinate space in ring.ts uses a 100×100 viewBox with centre
/// (50, 50).  The Flutter painter maps these proportionally to the widget's
/// logical pixel size, so every dimension here is in that normalised [0, 100]
/// space (i.e., a fraction of the widget's half-width).
@immutable
class DialTicksConfig with StyleProps {
  const DialTicksConfig({
    this.count = 60,
    this.radius = 46.5,
    this.width = 2.6,
    this.length = 8.5,
    this.majorEvery = 5,
    this.majorLengthFactor = 1.5,
    this.majorWidthFactor = 1.3,
    this.showLabels = false,
    this.labelStyle,
  });

  /// Total number of tick marks (one per second for a 60-second ring).
  final int count;

  /// Outer tip radius in normalised units.
  final double radius;

  /// Width of a minor tick in normalised units.
  final double width;

  /// Length of a minor tick in normalised units.
  final double length;

  /// Every Nth tick is drawn as a "major" tick (longer + wider).
  final int majorEvery;

  /// How much longer a major tick is vs a minor tick (multiplier).
  final double majorLengthFactor;

  /// How much wider a major tick is vs a minor tick (multiplier).
  final double majorWidthFactor;

  /// Draw text labels on major ticks (e.g. 0, 5, 10, �?.
  final bool showLabels;

  /// Text style for major-tick labels (defaults to a small white font).
  final TextStyle? labelStyle;

  @override
  List<Object?> get props => [
        count,
        radius,
        width,
        length,
        majorEvery,
        majorLengthFactor,
        majorWidthFactor,
        showLabels,
        labelStyle,
      ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Decorative arc configuration
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for one decorative segmented arc ring.
///
/// Mirrors `IRingArc` from ring.ts.
@immutable
class DialArcConfig with StyleProps {
  const DialArcConfig({
    required this.radius,
    required this.strokeWidth,
    this.segments = 3,
    this.spanDegrees = 60.0,
  });

  /// Ring radius in normalised units.
  final double radius;

  /// Stroke width in normalised units.
  final double strokeWidth;

  /// Number of arc segments evenly distributed around the circle.
  final int segments;

  /// Angular span of each segment in degrees.
  final double spanDegrees;

  @override
  List<Object?> get props => [radius, strokeWidth, segments, spanDegrees];
}

// ─────────────────────────────────────────────────────────────────────────────
// Inner progress ring configuration
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for the innermost progress ring.
///
/// Mirrors `IRingInner` from ring.ts.
@immutable
class DialInnerConfig with StyleProps {
  const DialInnerConfig({
    this.radius = 27.5,
    this.strokeWidth = 2.8,
    this.trackColor = const Color(0x38968C94),
  });

  /// Ring radius in normalised units.
  final double radius;

  /// Stroke width in normalised units.
  final double strokeWidth;

  /// Grey background track colour.
  final Color trackColor;

  @override
  List<Object?> get props => [radius, strokeWidth, trackColor];
}

// ─────────────────────────────────────────────────────────────────────────────
// CountdownDial widget
// ─────────────────────────────────────────────────────────────────────────────

/// A circular dial countdown display that replicates the ring.ts renderer in
/// Flutter using [CustomPainter].
///
/// Four concentric rings (outermost �?innermost):
///
/// 1. **Tick ring** �?60 radial tick marks; remaining-second ticks are lit in
///    the current zone colour, elapsed ticks are drawn in the dim [DialColors.off]
///    colour.  In the final minute the lit ticks cycle through red �?yellow �?///    green as the second climbs from 0.
/// 2. **Arc A (outer)** �?three decorative arc segments that rotate
///    *counter-clockwise* one tick per elapsed second (mirrors the clockwise
///    countdown direction).
/// 3. **Arc B (inner)** �?a second, thinner set of decorative arc segments
///    that rotate *clockwise*, converging with arc A at zero.
/// 4. **Progress ring** �?a grey track with a coloured overlay that drains
///    from full to empty.  The overlay is split into per-minute segments plus
///    the final-minute red/yellow/green sub-arcs.
///
/// A [CountdownBuilder] drives all animations; [builder] provides the centre
/// display (time text, custom widget, etc.).
///
/// ```dart
/// CountdownDial(
///   to: const Duration(minutes: 5),
///   size: 200,
///   builder: (context, parts) => Text(
///     '${parts.minutes.toString().padLeft(2, '0')}:'
///     '${parts.seconds.toString().padLeft(2, '0')}',
///     style: const TextStyle(color: Colors.white, fontSize: 28),
///   ),
/// )
/// ```
///
/// All ring geometry uses a normalised 100×100 coordinate space to stay
/// faithful to the original SVG viewBox (0 0 100 100) from ring.ts.
/// Visual style for [CountdownDial].
///
/// Aggregates the dial's geometry, zone colors, tick/arc/inner ring configs
/// (with explicit `show*` flags — clearer than the old "pass null to hide"),
/// glow, and container [decoration]/[padding]. All fields nullable; unset
/// fields fall back to the dial's built-in defaults.
///
/// [CountdownDial] 的视觉样式。聚合表盘几何、区域配色、刻度/弧/内圈配置（用显式
/// `show*` 开关——比旧的"传 null 隐藏"更清晰）、辉光、容器 [decoration]/[padding]。
/// 所有字段可空；未设置的字段回退到表盘内建默认值。
@immutable
class CountdownDialStyle with BoxStyleFields, StyleProps {
  /// Creates a [CountdownDial] style. All fields optional.
  ///
  /// 创建 [CountdownDial] 样式。所有字段可选。
  const CountdownDialStyle({
    this.size,
    this.clockwise,
    this.redAt,
    this.yellowAt,
    this.colors,
    this.ticks,
    this.arcA,
    this.arcB,
    this.inner,
    this.glow,
    this.showTicks,
    this.showArcA,
    this.showArcB,
    this.showInner,
    this.centerAlignment,
    this.padding,
    this.decoration,
  });

  /// Logical pixel size (square).
  final double? size;

  /// Tick/drain direction; true = clockwise.
  final bool? clockwise;

  /// Seconds-remaining threshold below which ticks turn red.
  final int? redAt;

  /// Seconds-remaining threshold below which ticks turn yellow.
  final int? yellowAt;

  /// Zone color palette.
  final DialColors? colors;

  /// Outer tick ring config (used when [showTicks] != false).
  final DialTicksConfig? ticks;

  /// Outer decorative arc config (used when [showArcA] != false).
  final DialArcConfig? arcA;

  /// Inner decorative arc config (used when [showArcB] != false).
  final DialArcConfig? arcB;

  /// Innermost progress ring config (used when [showInner] != false).
  final DialInnerConfig? inner;

  /// Drop-shadow glow on lit elements.
  final bool? glow;

  /// Whether the tick ring is drawn. Default true.
  final bool? showTicks;

  /// Whether outer arc A is drawn. Default true.
  final bool? showArcA;

  /// Whether inner arc B is drawn. Default true.
  final bool? showArcB;

  /// Whether the innermost progress ring is drawn. Default true.
  final bool? showInner;

  /// Alignment of the center [CountdownDial.builder] child. Default center.
  final AlignmentGeometry? centerAlignment;

  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  CountdownDialStyle copyWith({
    double? size,
    bool? clockwise,
    int? redAt,
    int? yellowAt,
    DialColors? colors,
    DialTicksConfig? ticks,
    DialArcConfig? arcA,
    DialArcConfig? arcB,
    DialInnerConfig? inner,
    bool? glow,
    bool? showTicks,
    bool? showArcA,
    bool? showArcB,
    bool? showInner,
    AlignmentGeometry? centerAlignment,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
  }) =>
      CountdownDialStyle(
        size: size ?? this.size,
        clockwise: clockwise ?? this.clockwise,
        redAt: redAt ?? this.redAt,
        yellowAt: yellowAt ?? this.yellowAt,
        colors: colors ?? this.colors,
        ticks: ticks ?? this.ticks,
        arcA: arcA ?? this.arcA,
        arcB: arcB ?? this.arcB,
        inner: inner ?? this.inner,
        glow: glow ?? this.glow,
        showTicks: showTicks ?? this.showTicks,
        showArcA: showArcA ?? this.showArcA,
        showArcB: showArcB ?? this.showArcB,
        showInner: showInner ?? this.showInner,
        centerAlignment: centerAlignment ?? this.centerAlignment,
        padding: padding ?? this.padding,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  CountdownDialStyle merge(CountdownDialStyle? other) => other == null
      ? this
      : CountdownDialStyle(
          size: size ?? other.size,
          clockwise: clockwise ?? other.clockwise,
          redAt: redAt ?? other.redAt,
          yellowAt: yellowAt ?? other.yellowAt,
          colors: colors ?? other.colors,
          ticks: ticks ?? other.ticks,
          arcA: arcA ?? other.arcA,
          arcB: arcB ?? other.arcB,
          inner: inner ?? other.inner,
          glow: glow ?? other.glow,
          showTicks: showTicks ?? other.showTicks,
          showArcA: showArcA ?? other.showArcA,
          showArcB: showArcB ?? other.showArcB,
          showInner: showInner ?? other.showInner,
          centerAlignment: centerAlignment ?? other.centerAlignment,
          padding: padding ?? other.padding,
          decoration: decoration ?? other.decoration,
        );

  @override
  List<Object?> get props => [
        size,
        clockwise,
        redAt,
        yellowAt,
        colors,
        ticks,
        arcA,
        arcB,
        inner,
        glow,
        showTicks,
        showArcA,
        showArcB,
        showInner,
        centerAlignment,
        padding,
        decoration,
      ];
}

class CountdownDial extends StatelessWidget {
  const CountdownDial({
    super.key,
    required this.to,
    this.style,
    this.repaintBoundary,
    this.painterBuilder,
    this.builder,
    this.plugin,
    this.controller,
    this.onComplete,
    this.onTick,
    this.threshold,
    this.onThreshold,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.onPause,
    this.onResume,
  });

  /// Visual style. Merged over the enclosing [CountdownProvider]'s defaults.
  ///
  /// 视觉样式。叠加在所在 [CountdownProvider] 的默认值之上。
  final CountdownDialStyle? style;

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch), or
  /// ISO-8601 [String].
  final Object to;

  /// Wraps in [RepaintBoundary].  Falls back to the provider then `true`.
  final bool? repaintBoundary;

  /// Supplies a fully custom painter given the current [TimeParts], replacing
  /// the built-in dial painter. All [style] visuals are ignored then.
  ///
  /// 依据当前 [TimeParts] 提供完全自定义的画笔，替换内建表盘画笔。此时所有 [style]
  /// 视觉项被忽略。
  final CustomPainter Function(BuildContext context, TimeParts parts)? painterBuilder;

  /// Optional widget rendered in the centre of the dial.
  /// Receives [TimeParts] each tick.  When null, the centre is empty.
  final Widget Function(BuildContext context, TimeParts parts)? builder;

  // ── Countman integration ──────────────────────────────────────────────────

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onComplete;

  /// Called every tick with the current remaining [TimeParts].
  ///
  /// 每 tick 以当前剩余 [TimeParts] 回调。
  final void Function(TimeParts parts)? onTick;

  final Duration? threshold;
  final void Function()? onThreshold;
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final scope = CountmanScope.maybeOf<Countdown>(context);
    final effRepaint = repaintBoundary ?? scope?.repaintBoundary ?? true;

    // Widget style layered over the enclosing provider's dial style.
    //
    // widget 样式叠加在所在 provider 的表盘样式之上。
    final s = (style ?? const CountdownDialStyle()).merge(scope?.countdownDialStyle);
    final effSize = s.size ?? 200.0;
    final effTicks = (s.showTicks ?? true) ? (s.ticks ?? const DialTicksConfig()) : null;
    final effArcA = (s.showArcA ?? true)
        ? (s.arcA ?? const DialArcConfig(radius: 35.5, strokeWidth: 2.4))
        : null;
    final effArcB = (s.showArcB ?? true)
        ? (s.arcB ??
            const DialArcConfig(radius: 31.5, strokeWidth: 1.3, segments: 3, spanDegrees: 60))
        : null;
    final effInner = (s.showInner ?? true) ? (s.inner ?? const DialInnerConfig()) : null;

    return CountdownBuilder(
      to: to,
      plugin: plugin ?? scope?.plugin,
      controller: controller,
      onComplete: onComplete,
      onTick: onTick,
      threshold: threshold,
      onThreshold: onThreshold,
      onReady: onReady,
      onStart: onStart,
      onCancel: onCancel,
      onPause: onPause,
      onResume: onResume,
      builder: (ctx, parts, _) {
        final dial = Semantics(
          container: true,
          label: 'Countdown',
          value: '${(parts.progress * 100).round()}%',
          child: CustomPaint(
            size: Size.square(effSize),
            painter: painterBuilder != null
                ? painterBuilder!(ctx, parts)
                : _DialPainter(
                    parts: parts,
                    clockwise: s.clockwise ?? true,
                    redAt: s.redAt ?? 3,
                    yellowAt: s.yellowAt ?? 10,
                    colors: s.colors ?? const DialColors(),
                    ticks: effTicks,
                    arcA: effArcA,
                    arcB: effArcB,
                    inner: effInner,
                    glow: s.glow ?? false,
                  ),
            child: builder != null
                ? SizedBox.square(
                    dimension: effSize,
                    child: Align(
                      alignment: s.centerAlignment ?? Alignment.center,
                      child: builder!(ctx, parts),
                    ),
                  )
                : null,
          ),
        );
        final decorated = applyBoxStyle(dial, padding: s.padding, decoration: s.decoration);
        return effRepaint ? RepaintBoundary(child: decorated) : decorated;
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DialPainter �?the CustomPainter that draws all four concentric rings
// ─────────────────────────────────────────────────────────────────────────────

/// Internal painter.  All geometry is computed in a normalised 100×100
/// coordinate space (matching the SVG `viewBox="0 0 100 100"` from ring.ts)
/// and then scaled to [size] via [_scale].
class _DialPainter extends CustomPainter {
  const _DialPainter({
    required this.parts,
    required this.clockwise,
    required this.redAt,
    required this.yellowAt,
    required this.colors,
    required this.ticks,
    required this.arcA,
    required this.arcB,
    required this.inner,
    required this.glow,
  });

  final TimeParts parts;
  final bool clockwise;
  final int redAt;
  final int yellowAt;
  final DialColors colors;
  final DialTicksConfig? ticks;
  final DialArcConfig? arcA;
  final DialArcConfig? arcB;
  final DialInnerConfig? inner;
  final bool glow;

  // ── Coordinate helpers ────────────────────────────────────────────────────

  /// Scale factor: logical pixels per normalised unit.
  double _scale(Size size) => size.shortestSide / 100.0;

  /// Canvas centre in logical pixels.
  Offset _centre(Size size) => Offset(size.width / 2, size.height / 2);

  // ── Derived state ─────────────────────────────────────────────────────────

  /// Remaining milliseconds rounded up to the nearest whole second (same
  /// quantisation as ring.ts's `Math.ceil(remaining / 1000) * 1000`).
  int _remMs() {
    final ms = parts.value.inMilliseconds;
    return ms <= 0 ? 0 : ((ms + 999) ~/ 1000) * 1000;
  }

  /// Integer remaining seconds (quantised).
  int _remSec() => _remMs() ~/ 1000;

  /// Whole minutes remaining (= remSec ÷ 60, integer part).
  int _totalMin() => _remSec() ~/ 60;

  /// Seconds within the current minute (0�?9).
  int _sec() => _remSec() % 60;

  /// True when we are in the final minute (totalMin == 0).
  bool _finalMin() => _totalMin() == 0;

  /// Current zone colour (used for arcs and digits):
  ///   - final minute: red / yellow / green based on _sec().
  ///   - otherwise: normal.
  Color _themeColor() {
    if (_finalMin()) return colors.zoneColor(_sec(), redAt: redAt, yellowAt: yellowAt);
    return colors.normal;
  }

  // ── Main paint entry ──────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final sc = _scale(size);
    final c = _centre(size);

    // Layer order (back �?front), matching ring.ts build() insertion order:
    //   1. innermost progress ring  (inserted first in SVG, so it's behind arcs)
    //   2. arc A + arc B            (drawn on top of inner ring)
    //   3. outermost tick ring      (topmost ring layer)
    //   4. centre content           (handled by the child widget, not the painter)
    //
    // Note: ring.ts inserts ticks first, then inner, then arcs in the SVG.
    // SVG paints in source order (later = on top), so the visual stack is:
    //   ticks �?inner �?arcs, with arcs on top.
    // We replicate that exact order here.

    _paintTicks(canvas, c, sc);
    _paintInner(canvas, c, sc);
    _paintArc(canvas, c, sc, arcA, -_dirSign()); // arc A: counter-clockwise
    _paintArc(canvas, c, sc, arcB, _dirSign());  // arc B: clockwise
  }

  /// +1 if clockwise, -1 if counter-clockwise (the "cw" scalar from ring.ts).
  double _dirSign() => clockwise ? 1.0 : -1.0;

  // ──────────────────────────────────────────────────────────────────────────
  // Layer 1 �?outermost tick ring
  // ──────────────────────────────────────────────────────────────────────────

  /// Draws the outermost ring of radial tick marks.
  ///
  /// ring.ts logic (paint section, tick loop):
  ///   lit  = min(tickCfg.count, sec)   -- number of bright ticks
  ///   i < lit  �?"on" (lit)
  ///   i >= lit �?"off" (dim)
  ///   zone for lit ticks in finalMin: zoneColor(i) (so tick 0 is always red,
  ///   tick 1..redAt-1 red, redAt..yellowAt-1 yellow, yellowAt.. green).
  ///
  /// Geometry from ring.ts:
  ///   Each tick is a rect with:
  ///     x = 50 - width/2, y = 50 - radius,
  ///     width = tickWidth, height = tickLength
  ///   rotated by -(cw * i * step) around (50, 50).
  ///   rx = width * 0.42  (rounded end caps)
  ///
  /// Flutter equivalent: rotate the canvas, draw a rounded RRect, restore.
  void _paintTicks(Canvas canvas, Offset centre, double sc) {
    final cfg = ticks;
    if (cfg == null) return;

    final count = cfg.count;
    // _sec() returns remSec % 60, which is 0 at exact minute boundaries
    // (e.g. 60 s or 120 s remaining).  At those boundaries all ticks should be
    // lit, so treat sec == 0 with remaining time as a full count.
    final rawSec = _sec();
    final sec = (rawSec == 0 && parts.value.inMilliseconds > 0) ? count : rawSec;
    final lit = parts.value.inMilliseconds <= 0 ? 0 : math.min(count, sec);
    final finalMin = _finalMin();
    final step = (2 * math.pi) / count; // radians per tick

    for (int i = 0; i < count; i++) {
      final on = i < lit;
      final isMajor = cfg.majorEvery > 0 && (i % cfg.majorEvery == 0);

      // Tick dimensions in normalised units.
      final tickLen =
          (isMajor ? cfg.length * cfg.majorLengthFactor : cfg.length) * sc;
      final tickW =
          (isMajor ? cfg.width * cfg.majorWidthFactor : cfg.width) * sc;
      final tickR = cfg.radius * sc; // outer tip radius from centre

      // Colour for this tick.
      Color tickColor;
      if (!on) {
        tickColor = colors.off;
      } else if (finalMin) {
        tickColor = colors.zoneColor(i, redAt: redAt, yellowAt: yellowAt);
      } else {
        tickColor = colors.normal;
      }

      // The angle for tick i, measured from 12 o'clock (−π/2), increasing
      // clockwise (ring.ts uses rotate(−cw * i * step °) around SVG centre,
      // which for cw=1 steps clockwise from the top).
      final angle = -math.pi / 2 + _dirSign() * i * step;

      // Tick tip point (at radius from centre) and root point (inward by tickLen).
      final tipX = centre.dx + tickR * math.cos(angle);
      final tipY = centre.dy + tickR * math.sin(angle);
      final rootX = centre.dx + (tickR - tickLen) * math.cos(angle);
      final rootY = centre.dy + (tickR - tickLen) * math.sin(angle);

      // Draw as a stroked line with rounded caps (matches the rx-rounded rect
      // of ring.ts without requiring canvas matrix saves).
      final tickPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tickW
        ..strokeCap = StrokeCap.round
        ..color = tickColor
        ..isAntiAlias = true;
      if (on && glow) {
        tickPaint.maskFilter =
            const MaskFilter.blur(BlurStyle.outer, 1.5);
      }
      canvas.drawLine(Offset(tipX, tipY), Offset(rootX, rootY), tickPaint);

      // Optional labels on major ticks.
      if (cfg.showLabels && isMajor) {
        _paintTickLabel(canvas, centre, angle, tickR, tickLen, i, cfg, sc);
      }
    }
  }

  /// Draws a text label just inside the tick root for major tick [i].
  void _paintTickLabel(
    Canvas canvas,
    Offset centre,
    double angle,
    double tickR,
    double tickLen,
    int i,
    DialTicksConfig cfg,
    double sc,
  ) {
    final style = cfg.labelStyle ??
        TextStyle(
          color: colors.off,
          fontSize: 7.0 * sc,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    final tp = TextPainter(
      text: TextSpan(text: '$i', style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    // Position just inside the tick root, centred on the radius direction.
    final labelR = tickR - tickLen - 3.0 * sc;
    final lx = centre.dx + labelR * math.cos(angle) - tp.width / 2;
    final ly = centre.dy + labelR * math.sin(angle) - tp.height / 2;
    tp.paint(canvas, Offset(lx, ly));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Layer 2 �?decorative segmented arc rings (arc A and arc B)
  // ──────────────────────────────────────────────────────────────────────────

  /// Draws one decorative segmented arc ring (either arc A or arc B).
  ///
  /// ring.ts logic (paintArc):
  ///   rotation = dir * secRem * 6   (degrees; 6°/sec = full turn in 60 s)
  ///   Arc A: dir = −cw  �?rotates counter-clockwise as time decreases.
  ///   Arc B: dir = +cw  �?rotates clockwise (opposite to arc A).
  ///   At remaining=0 both are at 0° rotation �?they converge at the base pos.
  ///
  ///   Each segment is drawn as an open arc path (no fill, rounded linecap,
  ///   vector-effect: non-scaling-stroke).
  ///
  ///   Geometry:
  ///     N segments evenly spaced by 2π/segments.
  ///     Segment k is centred at angle (TOP + k * pitch).
  ///     Span (half either side of centre) = spanDegrees/2 in radians.
  ///     The whole group is then rotated by `rotation` degrees around (50,50).
  ///
  /// Flutter: rotate canvas by [dir * secRem * 6°], draw N arcs.
  void _paintArc(
    Canvas canvas,
    Offset centre,
    double sc,
    DialArcConfig? cfg,
    double dir,
  ) {
    if (cfg == null) return;

    final secRem = _remSec();
    final rotationRad = dir * secRem * 6.0 * (math.pi / 180.0);
    final color = _themeColor();

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = cfg.strokeWidth * sc
      ..strokeCap = StrokeCap.round
      ..color = color
      ..isAntiAlias = true;

    if (glow) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.outer, 2.0);
    }

    final radius = cfg.radius * sc;
    final spanRad = cfg.spanDegrees * (math.pi / 180.0);
    final pitch = 2 * math.pi / cfg.segments;

    canvas.save();
    // Rotate the whole arc group around the dial centre.
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(rotationRad);
    canvas.translate(-centre.dx, -centre.dy);

    for (int k = 0; k < cfg.segments; k++) {
      // Segment centre angle: start at 12 o'clock (−π/2), step by pitch.
      final mid = -math.pi / 2 + k * pitch;
      final startA = mid - spanRad / 2;
      final sweepA = spanRad;

      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        startA,
        sweepA,
        false,
        paint,
      );
    }

    canvas.restore();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Layer 3 �?innermost progress ring
  // ──────────────────────────────────────────────────────────────────────────

  /// Draws the innermost progress ring: grey track + coloured drain overlay.
  ///
  /// ring.ts logic (inner section of paint()):
  ///   total = state.total (the initial duration in ms, captured at mount).
  ///   The ring drains from full �?empty.  "Full" = TOP (12 o'clock).
  ///   angleAt(ms) = TOP �?cw * (ms / total) * 2π
  ///   �?at ms=total the angle is TOP (full).
  ///   �?at ms=0     the angle is TOP (empty �?swept arc length is 0).
  ///
  ///   Segments:
  ///     For each whole minute j (1 �?N-1):
  ///       from = j*60000, to = min((j+1)*60000, total)
  ///       drawn in `normal` colour (or per-minute colorAt override).
  ///     Final minute (last 60 s) split into three sub-arcs:
  ///       [0, redAt*1000)           �?red
  ///       [redAt*1000, yellowAt*1000) �?yellow
  ///       [yellowAt*1000, 60000)      �?green
  ///
  ///   Each arc: from angleAt(t0) to angleAt(min(t1, remaining)).
  ///   When remaining < t0 the arc is empty; when remaining > t1 the arc is
  ///   fully drawn.
  ///
  ///   Flutter: compute totalMs from parts.total; replicate the same math.
  void _paintInner(Canvas canvas, Offset centre, double sc) {
    final cfg = inner;
    if (cfg == null) return;

    final radius = cfg.radius * sc;
    final strokeWidth = cfg.strokeWidth * sc;

    // ── Track (grey background circle) ───────────────────────────────────

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = cfg.trackColor
      ..isAntiAlias = true;
    canvas.drawCircle(centre, radius, trackPaint);

    // ── Progress arcs ──────────────────────────────────────────────────

    final totalMs = parts.total?.inMilliseconds ?? 0;
    if (totalMs <= 0) return; // no total �?can't compute proportions

    final remMs = _remMs().toDouble();
    final rem = math.max(0.0, math.min(remMs, totalMs.toDouble()));

    // Converts a millisecond value to an angle on the canvas.
    // TOP = −π/2 (12 o'clock). Full arc clockwise for cw=true.
    // Formula mirrors ring.ts: angleAt(ms) = TOP �?cw * (ms/total) * 2π
    // where `ms` counts from 0 (elapsed) to totalMs (full ring at start).
    double angleAt(double ms) =>
        -math.pi / 2 - _dirSign() * (ms / totalMs) * 2 * math.pi;

    // Draw one arc segment from t0 ms to min(t1, rem) ms (both anchored at 0).
    void drawSeg(Canvas canvas, double t0, double t1, Color color) {
      final hi = math.min(t1, rem);
      if (hi <= t0) return; // nothing to draw

      final a0 = angleAt(t0);
      final a1 = angleAt(hi);

      // sweep is always the same sign as dirSign, magnitude = a1-a0 difference.
      // Because angleAt decreases as ms increases (we're draining), we use the
      // delta directly (a1 - a0 is negative for cw, positive for ccw).
      final sweep = a1 - a0;
      if (sweep.abs() < 1e-6) return;

      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color
        ..isAntiAlias = true;

      if (glow) {
        arcPaint.maskFilter =
            const MaskFilter.blur(BlurStyle.outer, 2.0);
      }

      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        a0,
        sweep,
        false,
        arcPaint,
      );
    }

    // Per-minute segments (index 1 �?N-1, where index 0 = final minute).
    final n = math.max(1, (totalMs / 60000).ceil());
    for (int j = 1; j < n; j++) {
      final from = j * 60000.0;
      final to = math.min((j + 1) * 60000.0, totalMs.toDouble());
      drawSeg(canvas, from, to, colors.normal);
    }

    // Final-minute sub-arcs (green �?yellow �?red, outermost time first).
    drawSeg(canvas, yellowAt * 1000.0, 60000.0, colors.green);
    drawSeg(canvas, redAt * 1000.0, yellowAt * 1000.0, colors.yellow);
    drawSeg(canvas, 0.0, redAt * 1000.0, colors.red);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // shouldRepaint
  // ──────────────────────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(_DialPainter old) {
    // TimeParts is mutated in place (same object reference every rebuild), so
    // reference comparison or value comparison both return false — the old value
    // is already overwritten by the time shouldRepaint runs.  Simply return true:
    // the painter is only triggered once per second by CountdownBuilder's _rev
    // notifier, so the per-repaint cost is negligible.
    return true;
  }
}
