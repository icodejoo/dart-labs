import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';
import 'countdown_card_provider.dart';
import 'countdown_card_types.dart';
import 'painter/flip_card_painter.dart';
import 'reduce_motion.dart';
import 'style_support.dart';
import 'providers.dart';

export 'countdown_card_provider.dart';
export 'countdown_card_types.dart';
export 'painter/flip_card_painter.dart';

const _defaultDuration = Duration(milliseconds: 450);
const _defaultCardWidth = 56.0;
const _defaultCardHeight = 76.0;
const _defaultDigitGap = 4.0;
const _defaultUnitGap = 8.0;
const _defaultCardColor = Color(0xFF212121);
const _defaultScaleFactor = 1.5;
const _defaultTransitionType = CountdownType.calendar;
const _defaultTranslateEffect = SlideEffect.none;
const _defaultPerspective = 0.006;

/// Visual style for [CountdownCard].
///
/// Aggregates card geometry, colors, per-digit transition look, and container
/// [decoration]/[padding]. All fields nullable; unset fields fall back to the
/// deprecated loose params, then an ancestor [CountdownCardProvider], then a
/// hardcoded default.
///
/// [CountdownCard] 的视觉样式。聚合卡片几何、颜色、逐位过渡外观、容器
/// [decoration]/[padding]。所有字段可空；未设置的字段回退到弃用松散参数，再到
/// 祖先 [CountdownCardProvider]，最后到硬编码默认值。
@immutable
class CountdownCardStyle with BoxStyleFields, StyleProps {
  /// Creates a [CountdownCard] style. All fields optional.
  ///
  /// 创建 [CountdownCard] 样式。所有字段可选。
  const CountdownCardStyle({
    this.splitDigits,
    this.cardWidth,
    this.cardHeight,
    this.digitGap,
    this.unitGap,
    this.cardColor,
    this.transitionType,
    this.scaleEffect,
    this.scaleFactor,
    this.opacityEffect,
    this.perspective,
    this.textStyle,
    this.labelStyle,
    this.separatorStyle,
    this.padding,
    this.decoration,
  });

  /// When true each digit gets its own card; when false each unit is one card.
  final bool? splitDigits;

  /// Width of one card.
  final double? cardWidth;

  /// Height of one card.
  final double? cardHeight;

  /// Gap between digit cards when [splitDigits] is true.
  final double? digitGap;

  /// Horizontal space on each side of the separator.
  final double? unitGap;

  /// Card background color.
  final Color? cardColor;

  /// Per-digit change transition.
  final CountdownType? transitionType;

  /// Scale behavior for slide/flip transitions.
  final SlideEffect? scaleEffect;

  /// Scale magnitude used by [scaleEffect].
  final double? scaleFactor;

  /// Opacity behavior for slide/flip transitions.
  final SlideEffect? opacityEffect;

  /// Perspective coefficient for flip's 3D rotation.
  final double? perspective;

  /// Digit number text style.
  final TextStyle? textStyle;

  /// Unit-label text style.
  final TextStyle? labelStyle;

  /// Separator-character text style.
  final TextStyle? separatorStyle;

  @override
  final EdgeInsetsGeometry? padding;
  @override
  final Decoration? decoration;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回替换了给定字段的副本。
  CountdownCardStyle copyWith({
    bool? splitDigits,
    double? cardWidth,
    double? cardHeight,
    double? digitGap,
    double? unitGap,
    Color? cardColor,
    CountdownType? transitionType,
    SlideEffect? scaleEffect,
    double? scaleFactor,
    SlideEffect? opacityEffect,
    double? perspective,
    TextStyle? textStyle,
    TextStyle? labelStyle,
    TextStyle? separatorStyle,
    EdgeInsetsGeometry? padding,
    Decoration? decoration,
  }) =>
      CountdownCardStyle(
        splitDigits: splitDigits ?? this.splitDigits,
        cardWidth: cardWidth ?? this.cardWidth,
        cardHeight: cardHeight ?? this.cardHeight,
        digitGap: digitGap ?? this.digitGap,
        unitGap: unitGap ?? this.unitGap,
        cardColor: cardColor ?? this.cardColor,
        transitionType: transitionType ?? this.transitionType,
        scaleEffect: scaleEffect ?? this.scaleEffect,
        scaleFactor: scaleFactor ?? this.scaleFactor,
        opacityEffect: opacityEffect ?? this.opacityEffect,
        perspective: perspective ?? this.perspective,
        textStyle: textStyle ?? this.textStyle,
        labelStyle: labelStyle ?? this.labelStyle,
        separatorStyle: separatorStyle ?? this.separatorStyle,
        padding: padding ?? this.padding,
        decoration: decoration ?? this.decoration,
      );

  /// Merges with lower-priority [other]: this object's non-null fields win.
  ///
  /// 与更低优先级的 [other] 合并：本对象非空字段优先。
  CountdownCardStyle merge(CountdownCardStyle? other) => other == null
      ? this
      : CountdownCardStyle(
          splitDigits: splitDigits ?? other.splitDigits,
          cardWidth: cardWidth ?? other.cardWidth,
          cardHeight: cardHeight ?? other.cardHeight,
          digitGap: digitGap ?? other.digitGap,
          unitGap: unitGap ?? other.unitGap,
          cardColor: cardColor ?? other.cardColor,
          transitionType: transitionType ?? other.transitionType,
          scaleEffect: scaleEffect ?? other.scaleEffect,
          scaleFactor: scaleFactor ?? other.scaleFactor,
          opacityEffect: opacityEffect ?? other.opacityEffect,
          perspective: perspective ?? other.perspective,
          textStyle: textStyle ?? other.textStyle,
          labelStyle: labelStyle ?? other.labelStyle,
          separatorStyle: separatorStyle ?? other.separatorStyle,
          padding: padding ?? other.padding,
          decoration: decoration ?? other.decoration,
        );

  @override
  List<Object?> get props => [
        splitDigits,
        cardWidth,
        cardHeight,
        digitGap,
        unitGap,
        cardColor,
        transitionType,
        scaleEffect,
        scaleFactor,
        opacityEffect,
        perspective,
        textStyle,
        labelStyle,
        separatorStyle,
        padding,
        decoration,
      ];
}

/// A flip-card countdown display. Each time unit (H / M / S) is rendered as
/// a card that animates when the digit changes.
///
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// ```dart
/// CountdownCard(to: const Duration(minutes: 5))
/// CountdownCard(to: DateTime(2025, 12, 31), splitDigits: true)
/// ```
///
/// Rendering is a single [CustomPainter] driven by one shared
/// [AnimationController] per card instance — dense grids of concurrent
/// [CountdownCard]s cost one [Ticker] each, not one per digit, and digit
/// changes never rebuild the widget tree (only `markNeedsPaint`).
///
/// [cardColor]/[textStyle]/[labelStyle]/[separatorStyle]/[duration]/
/// [cardWidth]/[cardHeight]/[digitGap]/[unitGap] fall back to an ancestor
/// [CountdownCardProvider] when left unset, then to a hardcoded default.
/// Digit/separator/label glyphs are cached per-card so repeated digits
/// (0-9) aren't re-laid-out every frame; for whichever of [textStyle] /
/// [labelStyle] / [separatorStyle] are inherited from a provider (not set
/// on this card), that cache is also shared across every card in the
/// provider's scope.
class CountdownCard extends StatefulWidget {
  const CountdownCard({
    super.key,
    required this.to,
    this.style,
    this.showHours,
    this.labels = const ['H', 'M', 'S'],
    this.separator = ':',
    this.duration,
    this.curve,
    this.repaintBoundary = true,
    this.plugin,
    this.controller,
    this.onComplete,
    this.onTick,
    this.threshold,
    this.onThreshold,
  });

  /// Visual style. Merged over the ancestor [CountdownCardProvider], then
  /// defaults.
  ///
  /// **Two provider paths, by design.** Card visuals resolve as:
  /// `style` > enclosing [CountdownProvider]'s `countdownCardStyle`
  /// (a [CountdownCardStyle]) > ancestor [CountdownCardProvider] (which also
  /// owns the shared glyph cache) > hardcoded default. [CountdownCardProvider]
  /// stays separate because it carries stateful, card-specific [TextPainter]
  /// glyph caches that don't belong on the general scope.
  ///
  /// 视觉样式。叠加在祖先 [CountdownCardProvider] 之上，再到默认值。
  ///
  /// **两条 provider 路径（有意为之）。** 卡片视觉解析顺序：`style` > 所在
  /// [CountdownProvider] 的 `countdownCardStyle`（[CountdownCardStyle]）> 祖先
  /// [CountdownCardProvider]（同时持有共享字形缓存）> 硬编码默认值。
  /// [CountdownCardProvider] 保持独立，因为它承载有状态、卡片专属的 [TextPainter]
  /// 字形缓存，不宜并入通用 scope。
  final CountdownCardStyle? style;

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final Object to;

  /// Whether to show the hours unit.
  /// null = auto: shown only when remaining ≥ 1 hour.
  final bool? showHours;

  /// Labels shown below each unit card. Supply null to hide labels.
  /// Order: [hours, minutes, seconds].
  final List<String>? labels;

  final String separator;

  /// Total transition duration, shared by every transition type. Falls back
  /// to [CountdownCardProvider.duration], then 450ms.
  final Duration? duration;

  /// Easing curve for the per-digit transition. Falls back to
  /// [CountdownCardProvider.curve], then [Curves.linear].
  ///
  /// 逐位过渡的缓动曲线。回退到 [CountdownCardProvider.curve]，再到 [Curves.linear]。
  final Curve? curve;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onComplete;

  /// Called every tick with the current remaining [TimeParts].
  ///
  /// 每 tick 以当前剩余 [TimeParts] 回调。
  final void Function(TimeParts parts)? onTick;

  /// When remaining first drops to or below this, [onThreshold] fires once.
  /// null (default) disables the check.
  final Duration? threshold;

  /// Called once when remaining crosses [threshold].
  final void Function()? onThreshold;

  @override
  State<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<CountdownCard>
    with SingleTickerProviderStateMixin {
  CountdownHandle? _handle;
  late final AnimationController _ctrl;
  late bool _showHours;
  late CardModel _model;
  Duration _lastRemaining = Duration.zero;

  // Resolved once per build() (widget ?? provider ?? default) — the
  // AnimationController's status listener is created once in initState and
  // can't safely query CountdownCardProvider itself, so it reads this field
  // instead of `widget.transitionType` directly.
  CountdownType _transitionType = _defaultTransitionType;

  // Per-card glyph cache. Used for any style this card resolves itself
  // (explicit override, or no ancestor provider) — never shared with other
  // cards. Bounded: at most ~10 digits + separator + label strings.
  final _localCache = <(String, TextStyle), TextPainter>{};

  @override
  void initState() {
    super.initState();
    _transitionType = widget.style?.transitionType ?? _defaultTransitionType;
    _ctrl = AnimationController(vsync: this, duration: motionDuration(widget.duration ?? _defaultDuration))
      ..addStatusListener((status) {
        // calendar is two legs (forward then auto-reverse) over the same
        // duration; slide/flip are a single forward pass — they commit at
        // `completed` instead of waiting for a `dismissed` that never comes.
        final isCalendar = _transitionType == CountdownType.calendar;
        if (isCalendar && status == AnimationStatus.completed) {
          _model.reversePhase = true;
          _ctrl.reverse();
          return;
        }
        final isEnd = isCalendar ? status == AnimationStatus.dismissed : status == AnimationStatus.completed;
        if (isEnd) {
          if (_model.target != null) _model.committed = _model.target!;
          _model.target = null;
          _model.reversePhase = false;
        }
      });
    final r = remainingUntil(widget.to);
    _showHours = widget.showHours ?? r.inHours >= 1;
    _model = CardModel(_digitsFor(r, _showHours));
    _start();
  }

  void _start() {
    _handle?.cancel();
    _handle = (widget.plugin ?? defaultCountdown).add(CountdownOptions(
      duration: remainingUntil(widget.to),
      onUpdate: _onTick,
      onComplete: widget.onComplete,
      threshold: widget.threshold,
      onThreshold: widget.onThreshold,
    ));
    widget.controller?.attach(_handle!);
  }

  List<int> _digitsFor(Duration r, bool showHours) {
    final units = showHours
        ? [r.inHours, r.inMinutes % 60, r.inSeconds % 60]
        : [r.inMinutes % 60, r.inSeconds % 60];
    return [for (final u in units) ...[u ~/ 10, u % 10]];
  }

  void _onTick(TimeParts parts) {
    widget.onTick?.call(parts);
    final remaining = parts.value;
    _lastRemaining = remaining;
    final showHours = widget.showHours ?? remaining.inHours >= 1;
    if (showHours != _showHours) {
      // Rare event (crossing the 1h boundary): the unit count itself
      // changes, which needs a real layout pass. Snap instead of animating —
      // a transition here would need to reconcile two different cell counts
      // mid-flight, which isn't worth the complexity for a once-per-run edge.
      setState(() {
        _showHours = showHours;
        _model = CardModel(_digitsFor(remaining, showHours));
      });
      return;
    }

    final next = _digitsFor(remaining, _showHours);
    final changed = List.generate(next.length, (i) => next[i] != _model.committed[i]);
    if (!changed.contains(true)) return;

    if (_ctrl.isAnimating && _model.target != null) {
      _model.committed = _model.target!; // finish the previous batch instantly
    }
    _model.target = next;
    _model.changedMask = changed;
    _model.reversePhase = false;
    _ctrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(CountdownCard old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to) {
      widget.controller?.detach();
      _ctrl.stop();
      _ctrl.value = 0;
      final r = remainingUntil(widget.to);
      _showHours = widget.showHours ?? r.inHours >= 1;
      _model = CardModel(_digitsFor(r, _showHours));
      _start();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _handle?.cancel();
    _ctrl.dispose();
    for (final tp in _localCache.values) {
      tp.dispose(); // release cached native paragraphs
    }
    _localCache.clear();
    super.dispose();
  }

  CardGeometry _measure({
    required double cardWidth,
    required double cardHeight,
    required double digitGap,
    required double unitGap,
    required TextStyle separatorStyle,
    required TextStyle labelStyle,
    required Map<(String, TextStyle), TextPainter> sepCache,
    required Map<(String, TextStyle), TextPainter> labelCache,
    required bool splitDigits,
  }) {
    final unitsCount = _showHours ? 3 : 2;
    final labelOffset = _showHours ? 0 : 1; // labels are always [hours, minutes, seconds]
    final sepPainter = sepCache.putIfAbsent(
        (widget.separator, separatorStyle),
        () => TextPainter(text: TextSpan(text: widget.separator, style: separatorStyle), textDirection: TextDirection.ltr)
          ..layout());

    var x = 0.0;
    final cells = <Cell>[];
    final sepCenters = <double>[];
    final unitLabelCenters = <double>[];
    final unitLabelText = <String?>[];
    var digitIndex = 0;

    for (var u = 0; u < unitsCount; u++) {
      final unitStart = x;
      if (splitDigits) {
        cells.add(Cell(x, cardWidth, digitIndex++, _fullRadius));
        x += cardWidth + digitGap;
        cells.add(Cell(x, cardWidth, digitIndex++, _fullRadius));
        x += cardWidth;
      } else {
        final half = cardWidth / 2;
        cells.add(Cell(x, half, digitIndex++, _leftRadius));
        x += half;
        cells.add(Cell(x, half, digitIndex++, _rightRadius));
        x += half;
      }
      unitLabelCenters.add((unitStart + x) / 2);
      unitLabelText.add(widget.labels?[u + labelOffset]);

      if (u != unitsCount - 1) {
        x += unitGap;
        sepCenters.add(x + sepPainter.width / 2);
        x += sepPainter.width + unitGap;
      }
    }

    final hasLabels = widget.labels != null;
    final labelHeight = hasLabels
        ? labelCache
            .putIfAbsent(('X', labelStyle),
                () => TextPainter(text: TextSpan(text: 'X', style: labelStyle), textDirection: TextDirection.ltr)..layout())
            .height
        : 0.0;
    final extraHeight = hasLabels ? 4 + labelHeight : 0.0;

    return CardGeometry(
      size: Size(x, cardHeight + extraHeight),
      cells: cells,
      separatorCenters: sepCenters,
      unitLabelCenters: unitLabelCenters,
      unitLabelText: unitLabelText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = CountdownCardProvider.of(context);

    // Resolution order per field: widget.style > enclosing CountdownProvider's
    // countdownCardStyle > ancestor CountdownCardProvider > hardcoded default.
    //
    // 每个字段的解析顺序：widget.style > 所在 CountdownProvider 的 countdownCardStyle
    // > 祖先 CountdownCardProvider > 硬编码默认值。
    final ccStyle = CountmanScope.maybeOf<Countdown>(context)?.countdownCardStyle;
    final st = widget.style?.merge(ccStyle) ?? ccStyle;
    final cardWidth = st?.cardWidth ?? provider?.cardWidth ?? _defaultCardWidth;
    final cardHeight = st?.cardHeight ?? provider?.cardHeight ?? _defaultCardHeight;
    final digitGap = st?.digitGap ?? provider?.digitGap ?? _defaultDigitGap;
    final unitGap = st?.unitGap ?? provider?.unitGap ?? _defaultUnitGap;
    final cardColor = st?.cardColor ?? provider?.cardColor ?? _defaultCardColor;
    final duration = widget.duration ?? provider?.duration ?? _defaultDuration;
    if (_ctrl.duration != duration) _ctrl.duration = duration;
    final effCurve = widget.curve ?? provider?.curve ?? Curves.linear;
    final splitDigits = st?.splitDigits ?? false;

    _transitionType = st?.transitionType ?? provider?.transitionType ?? _defaultTransitionType;
    final scaleEffect = st?.scaleEffect ?? provider?.scaleEffect ?? _defaultTranslateEffect;
    final scaleFactor = st?.scaleFactor ?? provider?.scaleFactor ?? _defaultScaleFactor;
    final opacityEffect = st?.opacityEffect ?? provider?.opacityEffect ?? _defaultTranslateEffect;
    final perspective = st?.perspective ?? provider?.perspective ?? _defaultPerspective;

    final resolvedTextStyle = st?.textStyle;
    final resolvedLabelStyle = st?.labelStyle;
    final resolvedSeparatorStyle = st?.separatorStyle;

    final textStyle = resolvedTextStyle ??
        provider?.textStyle ??
        TextStyle(fontSize: cardHeight * 0.48, fontWeight: FontWeight.bold, color: const Color(0xFFFFFFFF));
    final labelStyle = resolvedLabelStyle ??
        provider?.labelStyle ??
        const TextStyle(
            fontSize: 11, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w500, letterSpacing: 0.5);
    final separatorStyle = resolvedSeparatorStyle ??
        provider?.separatorStyle ??
        TextStyle(fontSize: cardHeight * 0.38, fontWeight: FontWeight.bold, color: const Color(0xFF757575));

    // A style is only shared via the provider's cache when this card is
    // actually inheriting it (left unset) — an explicit override always
    // uses this card's own local cache, so it never pollutes the shared one.
    final digitCache = (resolvedTextStyle == null && provider != null) ? provider.cache : _localCache;
    final sepCache = (resolvedSeparatorStyle == null && provider != null) ? provider.cache : _localCache;
    final labelCache = (resolvedLabelStyle == null && provider != null) ? provider.cache : _localCache;

    final geom = _measure(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      digitGap: digitGap,
      unitGap: unitGap,
      separatorStyle: separatorStyle,
      labelStyle: labelStyle,
      sepCache: sepCache,
      labelCache: labelCache,
      splitDigits: splitDigits,
    );

    final inner = CustomPaint(
      size: geom.size,
      painter: FlipCardPainter(
        repaint: _ctrl,
        controller: _ctrl,
        model: _model,
        geom: geom,
        transitionType: _transitionType,
        scaleEffect: scaleEffect,
        scaleFactor: scaleFactor,
        opacityEffect: opacityEffect,
        perspective: perspective,
        curve: effCurve,
        cardHeight: cardHeight,
        cardColor: cardColor,
        textStyle: textStyle,
        labelStyle: labelStyle,
        separatorStyle: separatorStyle,
        separator: widget.separator,
        digitCache: digitCache,
        sepCache: sepCache,
        labelCache: labelCache,
      ),
    );
    // The card paints digits straight to the canvas, so it has no text node
    // for a screen reader. Expose the remaining time via Semantics.
    final semantic = Semantics(
      container: true,
      label: 'Countdown',
      value: CountdownFormat.hms(TimeParts.of(_lastRemaining)),
      child: inner,
    );
    final decorated = applyBoxStyle(semantic, padding: st?.padding, decoration: st?.decoration);
    return widget.repaintBoundary
        ? RepaintBoundary(child: decorated)
        : decorated;
  }
}

// ── geometry ───────────────────────────────────────────────────────────────────────────

const _fullRadius = BorderRadius.all(Radius.circular(4));
const _leftRadius = BorderRadius.horizontal(left: Radius.circular(4));
const _rightRadius = BorderRadius.horizontal(right: Radius.circular(4));
