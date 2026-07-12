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
  required CounterTransition transition,
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
    required this.transition,
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
    bool fast = false,
    List<int> fastFrom = const <int>[],
    List<int> fastTo = const <int>[],
    List<double> targets = const <double>[],
    List<double> bounceOffsets = const <double>[],
  })  : _digitValues = List<double>.of(digitValues),
        _increasing = increasing,
        _fast = fast,
        _fastFrom = fastFrom,
        _fastTo = fastTo,
        _targets = targets,
        _bounceOffsets = bounceOffsets,
        color = style.color ?? const Color(0xFFFFFFFF),
        super(repaint: repaint);

  // ── mutable state updated each frame ──────────────────────────────────────
  List<double> _digitValues;
  bool _increasing;

  /// Fast mode: each column is a SINGLE step from [_fastFrom]`[i]` to
  /// [_fastTo]`[i]`, with `_digitValues[i]` carrying the 0–1 progress (instead
  /// of a continuous odometer position). Off: the normal cascading roll.
  ///
  /// 快速模式：每列从 [_fastFrom]`[i]` 单步到 [_fastTo]`[i]`，`_digitValues[i]`
  /// 携带 0–1 进度（而非连续里程表位置）。关闭：普通级联滚动。
  bool _fast;
  List<int> _fastFrom;
  List<int> _fastTo;

  /// Per-column cumulative TARGET place value (value / 10^place), used only in
  /// normal mode for ghost-prevention: a place that already shows its target
  /// digit and is within one digit-step of its target stops rolling. Empty in
  /// fast mode and for [painterBuilder] custom painters that don't supply it.
  ///
  /// 每列的累计目标位值（值 / 10^位），仅普通模式用于防幻影：已显示目标数位且距目标
  /// 不足一个数位步长的列停止滚动。fast 模式及未提供该值的 [painterBuilder] 自定义
  /// painter 下为空。
  List<double> _targets;

  /// Per-column post-animation bounce nudge, each a fraction of digit height
  /// (empty / 0 = none). The digits stay pinned to their target (progress 0)
  /// and each slides by its fraction in the motion direction, then back — no
  /// adjacent digit shown. Per-column so a staggered roll gets a bounce wave.
  ///
  /// 逐列的动画后回弹轻推，各为数位高度的比例（空 / 0 = 无）。数位仍钉在目标
  ///（进度 0），各自沿运动方向滑动其比例再返回——不显示相邻数位。逐列使错峰滚动
  /// 得到回弹波。
  List<double> _bounceOffsets;

  void update(
    List<double> values,
    bool increasing, {
    bool? fast,
    List<int>? fastFrom,
    List<int>? fastTo,
    List<double>? targets,
    List<double>? bounceOffsets,
  }) {
    _digitValues   = values;
    _increasing    = increasing;
    if (bounceOffsets != null) _bounceOffsets = bounceOffsets;
    if (fast != null) _fast = fast;
    if (fastFrom != null) _fastFrom = fastFrom;
    if (fastTo != null) _fastTo = fastTo;
    if (targets != null) _targets = targets;
  }

  List<double> get digitValues => _digitValues;
  bool get increasing => _increasing;

  // ── immutable config ───────────────────────────────────────────────────────
  final TextStyle style;
  final Size digitSize;
  final CounterTransition transition;
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

  /// Below this cumulative place value a normal-mode leading column counts as
  /// "not yet reached" and is dropped from layout; above it the column is
  /// included and its opacity ramps `cum → 1` for a fade-in.
  ///
  /// 低于此累计位值，普通模式的前导列视为"尚未到达"并从布局中剔除；高于则纳入，
  /// 其不透明度按 `cum → 1` 渐变实现淡入。
  static const double _revealEps = 1e-3;

  // ── paragraph cache ────────────────────────────────────────────────────────
  // Keyed digit × 16 alpha buckets → at most 10·16 = 160 laid-out paragraphs
  // for a fading counter (was 10·256 = 2560). 16 opacity levels are visually
  // indistinguishable in a sub-second cross-fade.
  //
  // 键为 数位 × 16 个 alpha 桶 → 淡入计数器最多缓存 10·16 = 160 个已排版段落
  //（原 10·256 = 2560）。亚秒交叉淡入下 16 级不透明度肉眼无差。
  static const int _alphaBuckets = 16;
  final Map<int, ui.Paragraph> _cache = {};

  /// Reused each column each frame by [_resolveColumnPhaseInto] so the paint
  /// hot path stays allocation-free.
  ///
  /// 由 [_resolveColumnPhaseInto] 逐列逐帧复用，使绘制热路径零分配。
  final DigitPhase _phase = DigitPhase();

  /// Builds (or reuses) a laid-out [ui.Paragraph] for [digit] at [alpha]
  /// (quantized to [_alphaBuckets] levels to bound the cache).
  ui.Paragraph paragraphFor(int digit, double alpha) {
    final bucket = (alpha.clamp(0.0, 1.0) * (_alphaBuckets - 1)).round();
    final key = digit * _alphaBuckets + bucket;
    return _cache.putIfAbsent(key, () {
      final str = numeralMapper != null
          ? numeralMapper!(digit)
          : (numeralSystemDigits[numeralSystem]?[digit] ?? '$digit');
      final c = color.withValues(alpha: bucket / (_alphaBuckets - 1));
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
      if (_fast) {
        // Fast columns carry progress, not magnitude → decide from the endpoint
        // digits (old OR new non-zero keeps the column through its single step).
        //
        // 快速列携带进度而非幅值 → 用端点数位判断（旧或新非零则该列在单步期间保留）。
        firstVisible = -1;
        for (int i = 0; i < n; i++) {
          final f = i < _fastFrom.length ? _fastFrom[i] : 0;
          final t = i < _fastTo.length ? _fastTo[i] : 0;
          if (f != 0 || t != 0) { firstVisible = i; break; }
        }
      } else {
        // Normal columns carry the cumulative place value: a place is present
        // once the number has grown into it. Using the LIVE value (not the old
        // endpoint) means leading zeros are hidden at rest — e.g. after
        // 1000 → 7 the thousands/hundreds/tens drop away, leaving "7". A place
        // in its fade-in window (0 < cum < 1) is still included; paint() ramps
        // its opacity so it fades in rather than popping.
        //
        // 普通列携带累计位值：数字增长到某位后该位才出现。用实时值（而非旧端点）
        // 意味着静止时正确隐藏前导零——如 1000 → 7 后千/百/十位消失，只留 "7"。
        // 处于淡入窗口（0 < cum < 1）的位仍会纳入；paint() 会渐变其不透明度，实现淡入而非突现。
        firstVisible = _digitValues.indexWhere((v) => v > _revealEps);
      }
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
      cols.add(DigitColumnLayout(index: i, x: x, hasSeparator: addSep));
      x += dw;
    }
    return cols;
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

      _resolveColumnPhaseInto(col.index);
      final int cur = _phase.cur;
      final int nxt = _phase.nxt;
      final double p = _phase.p;

      // Fade-in ONLY for leading integer places (index < units) still growing
      // into view (cum 0→1). The units place and any fraction digits are never
      // leading zeros → always full opacity, so a value of 0 shows "0" instead
      // of a blank. Full opacity too in fast mode and when leading zeros aren't
      // hidden.
      //
      // 仅对仍在淡入的前导整数位（index < 个位，cum 0→1）渐显。个位与小数位永远不是
      // 前导零 → 恒为全不透明，故值为 0 时显示 "0" 而非空白。fast 模式与不隐藏前导零时
      // 也为全不透明。
      final int unitsIdx = _digitValues.length - fractionDigits - 1;
      final double reveal = (hideLeadingZeroes && !_fast && col.index < unitsIdx)
          ? _digitValues[col.index].clamp(0.0, 1.0)
          : 1.0;

      canvas.save();
      canvas.clipRect(Rect.fromLTWH(col.x, 0, dw, dh));
      // Bounce nudge: slide this column's (target) digit in the motion
      // direction within its clipped slot, then back. exitDirection() gives the
      // sign (increase → up, decrease → down). Progress is 0 during bounce, so
      // only the target digit is drawn — the nudge just repositions it.
      // Per-column offset → a staggered roll produces a bounce wave.
      //
      // 回弹轻推：在裁剪槽内沿运动方向滑动本列（目标）数位再返回。exitDirection()
      // 给出符号（递增→上，递减→下）。回弹期间进度为 0，故只画目标数位，轻推仅重定位它。
      // 逐列偏移 → 错峰滚动产生回弹波。
      final double bounceOff =
          col.index < _bounceOffsets.length ? _bounceOffsets[col.index] : 0.0;
      if (bounceOff != 0.0) {
        canvas.translate(0, bounceOff * dh * exitDirection());
      }
      if (reveal < 1.0) {
        // saveLayer scales the whole column's alpha — only on the ≤1 fading
        // edge column, so the zero-build fast path is untouched at rest.
        //
        // saveLayer 整体缩放该列 alpha——仅作用于至多 1 个正在淡入的边缘列，
        // 静止时不影响零构建快路径。
        canvas.saveLayer(
          Rect.fromLTWH(col.x, 0, dw, dh),
          Paint()..color = Color.fromRGBO(0, 0, 0, reveal),
        );
        paintTransition(canvas, cur, nxt, p, col.x, dh, dw);
        canvas.restore();
      } else {
        paintTransition(canvas, cur, nxt, p, col.x, dh, dw);
      }
      canvas.restore();

      if (col.hasSeparator) {
        drawSeparator(canvas, col.x - separatorWidth(), dh);
      }
    }
  }

  /// Resolves the triple a column renders THIS frame: `cur` = the digit being
  /// left, `nxt` = the digit arriving, `p` = the 0–1 roll phase from cur → nxt.
  ///
  /// Fast mode: a single step [_fastFrom]`[i]` → [_fastTo]`[i]`, progress from
  /// `_digitValues[i]` (a static column returns p = 0). Normal mode: the value
  /// trajectory is monotonic in the global [_increasing] direction (fixed
  /// before the animation runs), so `cur` is `floor` (up) or `ceil` (down) of
  /// the position and `nxt` is ±1 (mod 10). Reading it this way keeps the roll
  /// phase correct across the 0/9 wrap and for the negative positions a wrapped
  /// decrease produces (e.g. digit 1 → −1 ≡ 9), instead of flashing a phantom
  /// digit.
  ///
  /// 解析某列本帧渲染的三元组：`cur` = 正在离开的位，`nxt` = 正在到来的位，
  /// `p` = 从 cur → nxt 的 0–1 滚动相位。
  ///
  /// 快速模式：从 [_fastFrom]`[i]` 单步到 [_fastTo]`[i]`，进度取自 `_digitValues[i]`
  /// （静止列返回 p = 0）。普通模式：值轨迹沿全局 [_increasing] 方向单调（在动画运行前
  /// 定好），故 `cur` 取位置的 floor（向上）或 ceil（向下），`nxt` 为 ±1（对 10 取模）。
  /// 如此读取可在跨 0/9 环绕及递减环绕产生的负位置（如数位 1 → −1 ≡ 9）时保持滚动
  /// 相位正确，而非闪出幻影数位。
  ///
  /// @param columnIndex Index into [digitValues] (0 = most significant).
  ///
  ///   [digitValues] 的下标（0 = 最高位）。
  ///
  /// @returns Record `(cur, nxt, p)` — the two digits and the roll phase.
  ///
  ///   记录 `(cur, nxt, p)` —— 两个数位与滚动相位。
  /// Fills [_phase] for [columnIndex] this frame. Hot path — no allocation.
  ///
  /// 为本帧的 [columnIndex] 填充 [_phase]。热路径——零分配。
  void _resolveColumnPhaseInto(int columnIndex) {
    // Ghost-prevention needs this place's target digit + value; off in fast
    // mode and for custom painters / unit tests that don't supply them.
    //
    // 防幻影需要本位的目标数位与目标值；fast 模式及未提供的自定义 painter / 单测下关闭。
    final bool hasTarget = !_fast &&
        columnIndex < _fastTo.length &&
        columnIndex < _targets.length;
    resolveDigitPhase(
      _phase,
      fast: _fast,
      fastFrom: columnIndex < _fastFrom.length ? _fastFrom[columnIndex] : 0,
      fastTo: columnIndex < _fastTo.length ? _fastTo[columnIndex] : 0,
      position: _digitValues[columnIndex],
      increasing: _increasing,
      targetDigit: hasTarget ? _fastTo[columnIndex] : -1,
      target: hasTarget ? _targets[columnIndex] : 0.0,
      hasTarget: hasTarget,
      eps: _revealEps,
    );
  }

  @visibleForTesting
  (int cur, int nxt, double p) resolveColumnPhase(int columnIndex) {
    _resolveColumnPhaseInto(columnIndex);
    return (_phase.cur, _phase.nxt, _phase.p);
  }

  /// Renders the transition by composing [CounterTransition]: an optional
  /// motion-blur layer wrapping the [CounterMotion] movement plus the
  /// scale/fade modifiers. Override to customize or add an effect.
  ///
  /// 按 [CounterTransition] 组合渲染过渡：可选的运动模糊层包裹 [CounterMotion] 运动，
  /// 再叠加 scale/fade 修饰。可覆写以定制或新增效果。
  void paintTransition(Canvas canvas, int cur, int nxt, double p, double x, double h, double w) {
    if (transition.blur) {
      final sigma = (0.5 - (p - 0.5).abs()) * 8.0;
      if (sigma >= 0.1) {
        canvas.saveLayer(
          Rect.fromLTWH(x, 0, w, h),
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        );
        _paintMotion(canvas, cur, nxt, p, x, h, w);
        canvas.restore();
        return;
      }
    }
    _paintMotion(canvas, cur, nxt, p, x, h, w);
  }

  /// Draws the outgoing [cur] and incoming [nxt] digits for the current
  /// [CounterMotion]. Flip is single-sided (one face at a time); the others
  /// draw both digits (the scale/fade modifiers separate/blend them).
  ///
  /// 为当前 [CounterMotion] 绘制离场 [cur] 与入场 [nxt] 数位。flip 单面（同一时刻一面）；
  /// 其余绘制两位（由 scale/fade 修饰分离/混合）。
  void _paintMotion(Canvas c, int cur, int nxt, double p, double x, double h, double w) {
    if (transition.motion == CounterMotion.flip) {
      final showCur = p < 0.5;
      _drawDigit(c, showCur ? cur : nxt, leaving: showCur, p: p, x: x, h: h, w: w);
      return;
    }
    _drawDigit(c, cur, leaving: true,  p: p, x: x, h: h, w: w);
    _drawDigit(c, nxt, leaving: false, p: p, x: x, h: h, w: w);
  }

  /// Draws one digit at progress [p], composing scale + motion + fade.
  /// [leaving] = outgoing (at rest as p→0); else incoming (at rest as p→1).
  ///
  /// 在进度 [p] 绘制一个数位，组合 scale + 运动 + fade。[leaving] = 离场（p→0 归位）；
  /// 否则入场（p→1 归位）。
  void _drawDigit(Canvas c, int digit,
      {required bool leaving,
      required double p,
      required double x,
      required double h,
      required double w}) {
    final double away = leaving ? p : (1 - p); // 0 = at rest, 1 = fully displaced
    final double alpha = transition.fade ? (1 - away) : 1.0;
    if (alpha <= 0.001) return;

    // Only scale + rotate mutate the canvas transform here; slide bakes its
    // offset into the draw Offset and flip's applyRotateX self-saves/restores.
    // So the default slide/none look (the hot path) skips the save/restore pair
    // entirely, and flip only needs the outer restore if scale added a save.
    //
    // 此处仅 scale 与 rotate 会改动画布变换；slide 把偏移写入 draw 的 Offset，
    // flip 的 applyRotateX 自带 save/restore。故默认 slide/none（热路径）完全跳过
    // 这对 save/restore，flip 也仅在 scale 已 save 时才需外层 restore。
    final bool needsRestore =
        transition.scale || transition.motion == CounterMotion.rotate;
    if (needsRestore) c.save();

    // Scale about the cell center (shrinks the leaving / grows the arriving).
    if (transition.scale) {
      final double s = (1 - away).clamp(0.0, 1.0);
      if (s <= 0) {
        c.restore(); // needsRestore is true here — scale set the save.
        return;
      }
      final double cx = x + w / 2;
      final double cy = h / 2;
      c.translate(cx, cy);
      c.scale(s, s);
      c.translate(-cx, -cy);
    }

    double dy = 0;
    switch (transition.motion) {
      case CounterMotion.none:
        break;
      case CounterMotion.slide:
        {
          final double d = exitDirection();
          dy = (leaving ? away : -away) * h * d;
        }
      case CounterMotion.rotate:
        {
          final double cx = x + w / 2;
          final double cy = h / 2;
          final double ang = (leaving ? -away : away) * math.pi / 2;
          c.translate(cx, cy);
          c.rotate(ang);
          c.translate(-cx, -cy);
        }
      case CounterMotion.flip:
        {
          // ⚠️ perspective rotateX (setEntry 3,2) → GPU compositing layer.
          final double cx = x + w / 2;
          final double cy = h / 2;
          final double ang = leaving ? -p * math.pi : (1 - p) * math.pi;
          applyRotateX(c, Offset(cx, cy), ang, 0.002, () {
            c.drawParagraph(paragraphFor(digit, alpha), Offset(x, topY(h)));
          });
          if (needsRestore) c.restore(); // only when scale added a save
          return;
        }
    }

    c.drawParagraph(paragraphFor(digit, alpha), Offset(x, topY(h) + dy));
    if (needsRestore) c.restore();
  }

  double topY(double h) => (h - digitSize.height) / 2;

  double exitDirection() {
    final base = (flipDirection == AxisDirection.up || flipDirection == AxisDirection.right) ? -1.0 : 1.0;
    return _increasing ? base : -base;
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
    this.hasSeparator = false,
  });
  final int index;
  final double x;
  /// True when a thousand-separator was placed immediately before this column.
  final bool hasSeparator;
}
