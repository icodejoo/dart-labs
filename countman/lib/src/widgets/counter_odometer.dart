// CounterOdometer — sliding-digit counter driven by a persistent CustomPainter.
//
// Replaced the external `odometer` package with a painter that is updated
// in-place each frame via markNeedsPaint(). Zero widget rebuilds per frame.
//
// Visual behaviour:
//   • Ones digit transitions smoothly (fractional progress).
//   • Higher digits snap at integer carry boundaries.
//   • Increasing: old digit exits downward, new arrives from above.
//   • Decreasing: old exits upward, new arrives from below.
//   • Optional bounce: each ones-digit transition briefly overshoots the target
//     then springs back, direction-aware.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';

import 'reduce_motion.dart';
import 'style_support.dart';
import 'providers.dart';

/// Visual style for [CounterOdometer].
///
/// Groups digit text style, slot geometry, per-affix styling, and container
/// [decoration]/[padding]. All fields nullable; unset fields fall back to the
/// deprecated loose params then framework defaults.
///
/// [CounterOdometer] 的视觉样式。聚合数字文本样式、槽位几何、前后缀样式、容器
/// [decoration]/[padding]。所有字段可空；未设置回退到弃用松散参数再到框架默认值。
@immutable
class CounterOdometerStyle with BoxStyleFields, StyleProps {
  /// Creates a [CounterOdometer] style. All fields optional.
  ///
  /// 创建 [CounterOdometer] 样式。所有字段可选。
  const CounterOdometerStyle({
    this.numberTextStyle,
    this.letterWidth,
    this.verticalOffset,
    this.fadeEnabled,
    this.digitAlignment,
    this.crossAxisAlignment,
    this.prefixStyle,
    this.suffixStyle,
    this.padding,
    this.decoration,
  });

  /// Text style for the digits.
  final TextStyle? numberTextStyle;

  /// Fixed width per digit slot.
  final double? letterWidth;

  /// Vertical slide distance in logical pixels.
  final double? verticalOffset;

  /// Cross-fade incoming/outgoing digits.
  final bool? fadeEnabled;

  /// Alignment of each digit within its slot.
  final Alignment? digitAlignment;

  /// Cross-axis alignment of the number row (and prefix/suffix).
  final CrossAxisAlignment? crossAxisAlignment;

  /// Text style for the prefix string (falls back to [numberTextStyle]).
  final TextStyle? prefixStyle;

  /// Text style for the suffix string (falls back to [numberTextStyle]).
  final TextStyle? suffixStyle;

  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  CounterOdometerStyle copyWith({
    TextStyle? numberTextStyle,
    double? letterWidth,
    double? verticalOffset,
    bool? fadeEnabled,
    Alignment? digitAlignment,
    CrossAxisAlignment? crossAxisAlignment,
    TextStyle? prefixStyle,
    TextStyle? suffixStyle,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
  }) =>
      CounterOdometerStyle(
        numberTextStyle: numberTextStyle ?? this.numberTextStyle,
        letterWidth: letterWidth ?? this.letterWidth,
        verticalOffset: verticalOffset ?? this.verticalOffset,
        fadeEnabled: fadeEnabled ?? this.fadeEnabled,
        digitAlignment: digitAlignment ?? this.digitAlignment,
        crossAxisAlignment: crossAxisAlignment ?? this.crossAxisAlignment,
        prefixStyle: prefixStyle ?? this.prefixStyle,
        suffixStyle: suffixStyle ?? this.suffixStyle,
        padding: padding ?? this.padding,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  CounterOdometerStyle merge(CounterOdometerStyle? other) => other == null
      ? this
      : CounterOdometerStyle(
          numberTextStyle: numberTextStyle ?? other.numberTextStyle,
          letterWidth: letterWidth ?? other.letterWidth,
          verticalOffset: verticalOffset ?? other.verticalOffset,
          fadeEnabled: fadeEnabled ?? other.fadeEnabled,
          digitAlignment: digitAlignment ?? other.digitAlignment,
          crossAxisAlignment: crossAxisAlignment ?? other.crossAxisAlignment,
          prefixStyle: prefixStyle ?? other.prefixStyle,
          suffixStyle: suffixStyle ?? other.suffixStyle,
          padding: padding ?? other.padding,
          decoration: decoration ?? other.decoration,
        );

  @override
  List<Object?> get props => [
        numberTextStyle,
        letterWidth,
        verticalOffset,
        fadeEnabled,
        digitAlignment,
        crossAxisAlignment,
        prefixStyle,
        suffixStyle,
        padding,
        decoration,
      ];
}

class CounterOdometer extends StatefulWidget {
  const CounterOdometer({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.plugin,
    this.controller,
    this.style,
    this.slideCurve,
    this.groupSeparator,
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.onUpdate,
    this.onComplete,
    this.onReady,
    this.onStart,
    this.onCancel,
    this.bounceOvershoot = 0.0,
    this.bounceElasticity = 4.0,
  }) : assert(bounceOvershoot >= 0.0),
       assert(bounceElasticity >= 1.0);

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default) the value never goes below 0.
  final bool allowNegative;

  final Counter? plugin;
  final CounterValueController? controller;

  /// Visual style. Merged over the enclosing [CounterProvider]'s odometer
  /// style, then the built-in defaults.
  ///
  /// 视觉样式。叠加在所在 [CounterProvider] 的 odometer 样式之上，再到内建默认值。
  final CounterOdometerStyle? style;

  /// Optional easing applied to the per-digit slide/fade progress.
  final Curve? slideCurve;

  /// Text drawn between every 3 digits (e.g. `','`).
  /// Replaces the former `Widget?` parameter; the painter renders it as text.
  final String? groupSeparator;

  final String? prefix;
  final String? suffix;
  final Widget? prefixWidget;
  final Widget? suffixWidget;

  final void Function(double value)? onUpdate;
  final void Function(double value)? onComplete;
  final VoidCallback? onReady;
  final VoidCallback? onStart;
  final VoidCallback? onCancel;

  /// How far each ones-digit transition overshoots its target before snapping
  /// back. `0.0` (default) disables the effect.
  ///
  /// The overshoot direction follows the animation:
  ///   • Increasing → briefly shows the digit ABOVE the target (e.g. 6→7→6).
  ///   • Decreasing → briefly shows the digit BELOW the target (e.g. 6→5→6).
  final double bounceOvershoot;

  /// Controls timing of the overshoot peak within each transition.
  /// Higher values push the peak closer to the end (stiffer spring). Must be ≥ 1.
  ///
  /// Peak occurs at `frac = 0.5^(1/bounceElasticity)`:
  ///   `4.0` (default) → peak at frac ≈ 0.84 (balanced).
  ///   `8.0`           → peak at frac ≈ 0.92 (very late, snappy).
  final double bounceElasticity;

  @override
  State<CounterOdometer> createState() => _CounterOdometerState();
}

// ── state ─────────────────────────────────────────────────────────────────────

class _CounterOdometerState extends State<CounterOdometer> {
  double _currentValue = 0;
  bool _showMinus = false;
  bool _increasing = true;
  CounterHandle? _handle;

  // Stable abs-value endpoints for this animation segment.
  // Passed to the painter so each digit column interpolates fromDigit→toDigit
  // independently, giving the slot-machine "all digits move" effect while
  // always landing on an exact integer digit at t=0 and t=1.
  double _fromAbsVal = 0;
  double _toAbsVal   = 0;

  final _repaintTrigger = ValueNotifier<int>(0);
  _OdometerPainter? _painter;
  TextStyle? _lastStyle;
  Size? _protoSize;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.from ?? 0;
    _showMinus    = widget.allowNegative && _currentValue < 0;
    _increasing   = (widget.from ?? 0) <= widget.to;
    _fromAbsVal   = _currentValue.abs();
    _toAbsVal     = widget.to.abs();
    _startTask(from: _currentValue);
  }

  void _startTask({required double from}) {
    _handle?.cancel();
    _increasing = from <= widget.to;
    _fromAbsVal = from.abs();
    _toAbsVal   = widget.to.abs();
    _handle = (widget.plugin ?? defaultCounter).add(CounterOptions(
      from: from,
      to: widget.to,
      duration: motionDuration(widget.duration),
      curve: widget.curve,
      allowNegative: widget.allowNegative,
      onUpdate: (v) {
        _currentValue = v;
        widget.controller?.latestValue = v;
        widget.onUpdate?.call(v);
        _painter?.update(v, _increasing, _fromAbsVal, _toAbsVal);
        _repaintTrigger.value++;

        final neg = widget.allowNegative && v < 0;
        if (neg != _showMinus) {
          _showMinus = neg;
          if (mounted) setState(() {});
        }
      },
      onComplete: (_) => widget.onComplete?.call(widget.to),
      onReady: widget.onReady,
      onStart: widget.onStart,
      onCancel: widget.onCancel,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CounterOdometer old) {
    super.didUpdateWidget(old);
    if (widget.controller != old.controller) old.controller?.detach();
    if (widget.to       != old.to       ||
        widget.duration != old.duration  ||
        widget.curve    != old.curve     ||
        widget.plugin   != old.plugin    ||
        widget.controller != old.controller) {
      _startTask(from: _currentValue);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _handle?.cancel();
    _painter?.disposeCache();
    _repaintTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve style: widget.style over the provider default, then built-in
    // defaults for any field still unset.
    //
    // 解析样式：widget.style 叠加在 provider 默认之上，仍未设的字段用内建默认值。
    final scope = CountmanScope.maybeOf<Counter>(context);
    final st = widget.style?.merge(scope?.counterOdometerStyle) ?? scope?.counterOdometerStyle;
    final effNumberTextStyle = st?.numberTextStyle;
    final effLetterWidth = st?.letterWidth ?? 20.0;
    final effVerticalOffset = st?.verticalOffset ?? 20.0;
    final effFadeEnabled = st?.fadeEnabled ?? true;
    final effDigitAlignment = st?.digitAlignment ?? Alignment.center;
    final effCrossAxisAlignment = st?.crossAxisAlignment ?? CrossAxisAlignment.baseline;
    final effPrefixStyle = st?.prefixStyle ?? effNumberTextStyle;
    final effSuffixStyle = st?.suffixStyle ?? effNumberTextStyle;

    final style      = DefaultTextStyle.of(context).style.merge(effNumberTextStyle);
    final textScaler = MediaQuery.textScalerOf(context);

    // ── prototype measurement (once per style) ─────────────────────────────
    if (_protoSize == null || style != _lastStyle) {
      final tp = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      _protoSize = tp.size;
      tp.dispose();

      _painter?.disposeCache();
      _painter = _OdometerPainter(
        repaint: _repaintTrigger,
        value: _currentValue,
        fromAbsVal: _fromAbsVal,
        toAbsVal: _toAbsVal,
        increasing: _increasing,
        textStyle: style,
        digitH: _protoSize!.height,
        letterWidth: effLetterWidth,
        verticalOffset: effVerticalOffset,
        slideCurve: widget.slideCurve,
        fadeEnabled: effFadeEnabled,
        digitAlignment: effDigitAlignment,
        groupSeparator: widget.groupSeparator,
        bounceOvershoot: widget.bounceOvershoot,
        bounceElasticity: widget.bounceElasticity,
      );
      _lastStyle = style;
    } else {
      _painter!.update(_currentValue, _increasing, _fromAbsVal, _toAbsVal);
    }

    // SizedBox sized from max(from, to) — stable throughout animation.
    final totalW = _painter!.computeFullWidth();
    final Widget digitBox = SizedBox(
      width: totalW,
      height: _protoSize!.height,
      child: CustomPaint(painter: _painter),
    );

    // ── decoration Row ─────────────────────────────────────────────────────
    final needsRow = _showMinus ||
        widget.prefix      != null || widget.prefixWidget  != null ||
        widget.suffix      != null || widget.suffixWidget  != null;

    final Widget content = !needsRow
        ? digitBox
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: effCrossAxisAlignment,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (_showMinus) Text('-', style: effNumberTextStyle),
              if (widget.prefixWidget != null)
                widget.prefixWidget!
              else if (widget.prefix != null)
                Text(widget.prefix!, style: effPrefixStyle),
              digitBox,
              if (widget.suffixWidget != null)
                widget.suffixWidget!
              else if (widget.suffix != null)
                Text(widget.suffix!, style: effSuffixStyle),
            ],
          );
    return applyBoxStyle(content, padding: st?.padding, decoration: st?.decoration);
  }
}

// ── painter ───────────────────────────────────────────────────────────────────

class _OdometerPainter extends CustomPainter {
  _OdometerPainter({
    required Listenable repaint,
    required double value,
    required double fromAbsVal,
    required double toAbsVal,
    required bool increasing,
    required this.textStyle,
    required this.digitH,
    required this.letterWidth,
    required this.verticalOffset,
    this.slideCurve,
    this.fadeEnabled = true,
    this.digitAlignment = Alignment.center,
    this.groupSeparator,
    this.bounceOvershoot = 0.0,
    this.bounceElasticity = 4.0,
  })  : _value      = value,
        _fromAbsVal = fromAbsVal,
        _toAbsVal   = toAbsVal,
        _increasing  = increasing,
        _color       = textStyle.color ?? const Color(0xFF000000),
        super(repaint: repaint);

  double _value;
  double _fromAbsVal;
  double _toAbsVal;
  bool   _increasing;

  void update(double value, bool increasing, double fromAbsVal, double toAbsVal) {
    _value      = value;
    _increasing  = increasing;
    _fromAbsVal = fromAbsVal;
    _toAbsVal   = toAbsVal;
  }

  final TextStyle textStyle;
  final double    digitH;       // height of one digit (from TextPainter)
  final double    letterWidth;
  final double    verticalOffset;
  final Curve?    slideCurve;
  final bool      fadeEnabled;
  final Alignment digitAlignment;
  final String?   groupSeparator;
  final double    bounceOvershoot;
  final double    bounceElasticity;
  final Color     _color;

  // ── paragraph cache ───────────────────────────────────────────────────────
  // Key: digit * 256 + alpha_byte  →  pre-laid-out Paragraph
  final Map<int, ui.Paragraph> _cache = {};

  ui.Paragraph _paragraph(int digit, double alpha) {
    final key = digit * 256 + (alpha * 255).round().clamp(0, 255);
    return _cache.putIfAbsent(key, () {
      final c = _color.withValues(alpha: alpha.clamp(0.0, 1.0));
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          fontSize: textStyle.fontSize,
          fontWeight: textStyle.fontWeight,
          fontFamily: textStyle.fontFamily,
        ),
      )
        ..pushStyle(ui.TextStyle(
          color: c,
          fontSize: textStyle.fontSize,
          fontWeight: textStyle.fontWeight,
          fontFamily: textStyle.fontFamily,
        ))
        ..addText('$digit');
      return pb.build()
        ..layout(ui.ParagraphConstraints(width: letterWidth));
    });
  }

  ui.Paragraph? _sepCache;
  ui.Paragraph _separatorParagraph() {
    return _sepCache ??= () {
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: textStyle.fontSize, fontFamily: textStyle.fontFamily),
      )
        ..pushStyle(ui.TextStyle(
          color: _color,
          fontSize: textStyle.fontSize,
          fontFamily: textStyle.fontFamily,
        ))
        ..addText(groupSeparator!);
      return pb.build()
        ..layout(ui.ParagraphConstraints(width: _separatorWidth() + 4));
    }();
  }

  double? _sepWidthCache;
  double _separatorWidth() {
    if (groupSeparator == null) return 0;
    return _sepWidthCache ??= () {
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(fontSize: textStyle.fontSize, fontFamily: textStyle.fontFamily),
      )
        ..pushStyle(ui.TextStyle(
          color: _color, fontSize: textStyle.fontSize, fontFamily: textStyle.fontFamily,
        ))
        ..addText(groupSeparator!);
      final p = pb.build()..layout(const ui.ParagraphConstraints(width: 200));
      final w = p.maxIntrinsicWidth;
      p.dispose();
      return w;
    }();
  }

  // ── digit layout ──────────────────────────────────────────────────────────

  /// Integer power of 10 (avoids floating-point drift in math.pow).
  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) r *= 10;
    return r;
  }

  /// Real cascading odometer layout.
  ///
  /// Each digit column uses `absVal / 10^p` to derive its current position,
  /// so higher-place digits scroll proportionally slower (ones is 10× faster
  /// than tens, etc.). This is the physically correct odometer behaviour the
  /// user expects — different digits move at different speeds rather than all
  /// cycling 0→9 in lockstep.
  ///
  /// Ghost prevention: at t=0 and t=1 (endpoints) digits are snapped to the
  /// exact integer digits of _fromAbsVal / _toAbsVal, ensuring frac=0 and no
  /// semi-transparent overlap at rest.
  List<(double x, int cur, int nxt, double frac)> _buildLayout(int numDigits) {
    final double t;
    if (_fromAbsVal == _toAbsVal) {
      t = 1.0;
    } else {
      t = ((_value.abs() - _fromAbsVal) / (_toAbsVal - _fromAbsVal))
          .clamp(0.0, 1.0);
    }

    final bool snapStart = t <= 1e-9;
    final bool snapEnd   = t >= 1.0 - 1e-9;

    final raw = <(int cur, int nxt, double frac)>[];

    for (int place = 0; place < numDigits; place++) {
      final p10  = _pow10(place);
      final p10f = p10.toDouble();

      int    cur;
      double frac;
      int    nxt;

      if (snapStart) {
        // Exact integer digits at animation start — no ghost.
        cur  = (_fromAbsVal.round() ~/ p10) % 10;
        frac = 0.0;
        nxt  = _increasing ? (cur + 1) % 10 : (cur - 1 + 10) % 10;
      } else if (snapEnd) {
        // Exact integer digits at animation end — no ghost.
        cur  = (_toAbsVal.round() ~/ p10) % 10;
        frac = 0.0;
        nxt  = _increasing ? (cur + 1) % 10 : (cur - 1 + 10) % 10;
      } else if (_increasing) {
        // Increasing: floor gives the "from" digit, frac is decimal portion.
        final scaled  = _value.abs() / p10f;
        final intPart = scaled.floor();
        frac = scaled - intPart;
        if (frac < 0.005) frac = 0.0;
        cur  = intPart % 10;
        nxt  = (cur + 1) % 10;

        // Ghost prevention: when this digit has entered its final cycle
        // (within one place-value step of target) and already shows the
        // target digit, stop animating — prevents a "9→0" ghost at the end.
        final int targetDigit = (_toAbsVal.round() ~/ p10) % 10;
        if (cur == targetDigit && _value.abs() >= _toAbsVal - p10f) {
          frac = 0.0;
        }
      } else {
        // Decreasing: ceil gives the digit we're leaving; frac is progress
        // toward the lower digit.
        final scaled  = _value.abs() / p10f;
        final intCeil = scaled.ceil();
        frac = (intCeil - scaled).clamp(0.0, 1.0);
        if (frac < 0.005) frac = 0.0;
        cur  = intCeil % 10;
        nxt  = (cur - 1 + 10) % 10;

        // Ghost prevention for decreasing: within one cycle of target.
        final int targetDigit = (_toAbsVal.round() ~/ p10) % 10;
        if (cur == targetDigit && _value.abs() <= _toAbsVal + p10f) {
          frac = 0.0;
        }
      }

      raw.add((cur, nxt, frac));
    }

    // Build left-to-right (most significant first).
    final n    = raw.length;
    final sepW = _separatorWidth();
    final result = <(double x, int cur, int nxt, double frac)>[];
    double x = 0;

    for (var i = n - 1; i >= 0; i--) {
      final fromRight = i + 1;
      if (groupSeparator != null && fromRight % 3 == 0 && fromRight < n) {
        x += sepW;
      }
      final (c, nt, fr) = raw[i];
      result.add((x, c, nt, fr));
      x += letterWidth;
    }
    return result;
  }

  /// Stable SizedBox width based on max(fromAbsVal, toAbsVal) digit count —
  /// never changes mid-animation.
  double computeFullWidth() {
    final maxAbsVal = math.max(_fromAbsVal, _toAbsVal);
    final intFloor  = maxAbsVal.floor();
    final numDigits = intFloor == 0 ? 1 : intFloor.toString().length;
    final sepW = _separatorWidth();
    var x = 0.0;
    for (var i = numDigits - 1; i >= 0; i--) {
      final fromRight = i + 1;
      if (groupSeparator != null && fromRight % 3 == 0 && fromRight < numDigits) {
        x += sepW;
      }
      x += letterWidth;
    }
    return x == 0 ? letterWidth : x;
  }

  // ── paint ─────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final h        = size.height;
    final maxAbsVal = math.max(_fromAbsVal, _toAbsVal);
    final intFloor  = maxAbsVal.floor();
    final numDigits = math.max(1, intFloor == 0 ? 1 : intFloor.toString().length);
    final layout    = _buildLayout(numDigits);
    final dir    = _increasing ? 1.0 : -1.0;
    final sepW   = _separatorWidth();
    // Use the CELL HEIGHT as slide distance so digits fully clear the clip
    // boundary at any frac value, preventing semi-transparent ghost overlap.
    // Using a smaller verticalOffset than digitH would leave the incoming
    // digit permanently peeking into the visible window.
    final vo     = h;

    // Vertical baseline within the slot, accounting for digitAlignment.
    final baseY = (h - digitH) * (digitAlignment.y + 1) / 2;

    for (int i = 0; i < layout.length; i++) {
      final (x, cur, nxt, frac) = layout[i];

      // Draw separator left of this column when carry-based layout inserted one.
      if (groupSeparator != null) {
        final fromRight = layout.length - i;
        if (fromRight % 3 == 0 && fromRight < layout.length) {
          canvas.drawParagraph(_separatorParagraph(), Offset(x - sepW, baseY));
        }
      }

      // ── easing + bounce ─────────────────────────────────────────────────
      // Fast path: bounceOvershoot=0 (default) → skip all sin/pow math.
      // Slow path: apply bounce bump after easing. bump peaks near frac=0.84
      // (e=4) and returns to 0 at both frac=0 and frac=1 (sin(π·frac^e)).
      // effectiveE can exceed 1.0, triggering the 3-digit overshoot render.
      final rawE = (slideCurve?.transform(frac.clamp(0, 1)) ?? frac).clamp(0.0, 1.0);
      final effectiveE = (bounceOvershoot > 0 && frac > 0 && frac < 1)
          ? rawE + bounceOvershoot * math.sin(math.pi * math.pow(frac, bounceElasticity))
          : rawE;

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(x, 0, letterWidth, h));

      if (effectiveE <= 1.0) {
        // ── normal: two digits ─────────────────────────────────────────────
        final e = effectiveE;
        canvas.drawParagraph(
          _paragraph(cur, fadeEnabled ? 1.0 - e : 1.0),
          Offset(x, baseY + e * vo * dir),
        );
        canvas.drawParagraph(
          _paragraph(nxt, fadeEnabled ? e : 1.0),
          Offset(x, baseY + (e - 1.0) * vo * dir),
        );
      } else {
        // ── overshoot: three digits ────────────────────────────────────────
        // effectiveE ∈ (1, 1+bounceOvershoot]: treat as a secondary transition
        // where `nxt` (the target digit) plays the role of the exiting digit
        // and `over` (one step further in the animation direction) briefly
        // appears, then everything returns as effectiveE falls back to 1.0.
        final eFrac = effectiveE - 1.0; // 0 → bounceOvershoot → 0
        final over  = _increasing ? (nxt + 1) % 10 : (nxt - 1 + 10) % 10;

        // cur: fully exited — nothing to draw (clipped).

        // nxt (target): slides past center, fades out slightly.
        canvas.drawParagraph(
          _paragraph(nxt, fadeEnabled ? (1.0 - eFrac).clamp(0, 1) : 1.0),
          Offset(x, baseY + (effectiveE - 1.0) * vo * dir),
        );

        // over (overshoot digit): arrives from the far side, fades in briefly.
        canvas.drawParagraph(
          _paragraph(over, fadeEnabled ? eFrac.clamp(0, 1) : 1.0),
          Offset(x, baseY + (effectiveE - 2.0) * vo * dir),
        );
      }

      canvas.restore();
    }
  }

  void disposeCache() {
    for (final p in _cache.values) { p.dispose(); }
    _cache.clear();
    _sepCache?.dispose();
    _sepCache = null;
  }

  @override
  bool shouldRepaint(_OdometerPainter old) => false;
}
