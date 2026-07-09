import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';
import 'countdown_card_provider.dart';
import 'countdown_card_types.dart';
import 'painter/flip_card_painter.dart';
import 'reduce_motion.dart';

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
    this.splitDigits = false,
    this.showHours,
    this.labels = const ['H', 'M', 'S'],
    this.separator = ':',
    this.transitionType,
    this.scaleEffect,
    this.scaleFactor,
    this.opacityEffect,
    this.perspective,
    this.duration,
    this.cardWidth,
    this.cardHeight,
    this.digitGap,
    this.unitGap,
    this.cardColor,
    this.textStyle,
    this.labelStyle,
    this.separatorStyle,
    this.repaintBoundary = true,
    this.plugin,
    this.controller,
    this.onComplete,
    this.threshold,
    this.onThreshold,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final Object to;

  /// When true each individual digit (0-9) gets its own card;
  /// when false each unit (00-59) is one card.
  final bool splitDigits;

  /// Whether to show the hours unit.
  /// null = auto: shown only when remaining ≥ 1 hour.
  final bool? showHours;

  /// Labels shown below each unit card. Supply null to hide labels.
  /// Order: [hours, minutes, seconds].
  final List<String>? labels;

  final String separator;

  /// Per-digit change animation. Falls back to
  /// [CountdownCardProvider.transitionType], then [CountdownType.calendar].
  final CountdownType? transitionType;

  /// Scale behavior for [CountdownType.slide]/[CountdownType.flip]
  /// digits: the entering digit shrinks from [scaleFactor] down to its
  /// normal size ("enter"/"both"), the exiting digit shrinks from normal
  /// size down to `1 / scaleFactor` ("exit"/"both"). No effect for
  /// [CountdownType.calendar]. Falls back to
  /// [CountdownCardProvider.scaleEffect], then [SlideEffect.none] (no
  /// scaling).
  final SlideEffect? scaleEffect;

  /// Magnitude used by [scaleEffect]. Must be > 1 for "enter" to look like
  /// it's shrinking in and "exit" to look like it's shrinking out — enter
  /// animates `scaleFactor → 1.0`, exit animates `1.0 → 1/scaleFactor`. Falls
  /// back to [CountdownCardProvider.scaleFactor], then 1.5.
  final double? scaleFactor;

  /// Opacity behavior for [CountdownType.slide]/[CountdownType.flip]
  /// digits: the entering digit fades in from transparent ("enter"/"both"),
  /// the exiting digit fades out to transparent ("exit"/"both"). No effect
  /// for [CountdownType.calendar]. Falls back to
  /// [CountdownCardProvider.opacityEffect], then [SlideEffect.none]
  /// (fully opaque throughout).
  final SlideEffect? opacityEffect;

  /// Perspective coefficient for [CountdownType.flip]'s 3D
  /// rotation — larger values exaggerate the foreshortening (the card looks
  /// like it's leaning further out of the screen as it turns). No effect for
  /// [CountdownType.calendar]/[CountdownType.slide]. Falls
  /// back to [CountdownCardProvider.perspective], then 0.006.
  final double? perspective;

  /// Total transition duration, shared by every [transitionType]. Falls back
  /// to [CountdownCardProvider.duration], then 450ms.
  final Duration? duration;

  /// Falls back to [CountdownCardProvider.cardWidth], then 56.
  final double? cardWidth;

  /// Falls back to [CountdownCardProvider.cardHeight], then 76.
  final double? cardHeight;

  /// Gap between digit cards when [splitDigits] is true.
  /// Falls back to [CountdownCardProvider.digitGap], then 4.
  final double? digitGap;

  /// Horizontal space on each side of the separator.
  /// Falls back to [CountdownCardProvider.unitGap], then 8.
  final double? unitGap;

  /// Falls back to [CountdownCardProvider.cardColor], then a dark grey.
  final Color? cardColor;

  /// Text style for the digit numbers. Falls back to
  /// [CountdownCardProvider.textStyle], then bold white scaled to the
  /// resolved card height.
  final TextStyle? textStyle;

  /// Text style for unit labels below each card. Falls back to
  /// [CountdownCardProvider.labelStyle], then a small grey label style.
  final TextStyle? labelStyle;

  /// Text style for the separator character. Falls back to
  /// [CountdownCardProvider.separatorStyle], then a mid-grey style scaled
  /// to the resolved card height.
  final TextStyle? separatorStyle;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onComplete;

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
    _transitionType = widget.transitionType ?? _defaultTransitionType;
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
      if (widget.splitDigits) {
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

    final cardWidth = widget.cardWidth ?? provider?.cardWidth ?? _defaultCardWidth;
    final cardHeight = widget.cardHeight ?? provider?.cardHeight ?? _defaultCardHeight;
    final digitGap = widget.digitGap ?? provider?.digitGap ?? _defaultDigitGap;
    final unitGap = widget.unitGap ?? provider?.unitGap ?? _defaultUnitGap;
    final cardColor = widget.cardColor ?? provider?.cardColor ?? _defaultCardColor;
    final duration = widget.duration ?? provider?.duration ?? _defaultDuration;
    if (_ctrl.duration != duration) _ctrl.duration = duration;

    _transitionType = widget.transitionType ?? provider?.transitionType ?? _defaultTransitionType;
    final scaleEffect = widget.scaleEffect ?? provider?.scaleEffect ?? _defaultTranslateEffect;
    final scaleFactor = widget.scaleFactor ?? provider?.scaleFactor ?? _defaultScaleFactor;
    final opacityEffect = widget.opacityEffect ?? provider?.opacityEffect ?? _defaultTranslateEffect;
    final perspective = widget.perspective ?? provider?.perspective ?? _defaultPerspective;

    final textStyle = widget.textStyle ??
        provider?.textStyle ??
        TextStyle(fontSize: cardHeight * 0.48, fontWeight: FontWeight.bold, color: const Color(0xFFFFFFFF));
    final labelStyle = widget.labelStyle ??
        provider?.labelStyle ??
        const TextStyle(
            fontSize: 11, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w500, letterSpacing: 0.5);
    final separatorStyle = widget.separatorStyle ??
        provider?.separatorStyle ??
        TextStyle(fontSize: cardHeight * 0.38, fontWeight: FontWeight.bold, color: const Color(0xFF757575));

    // A style is only shared via the provider's cache when this card is
    // actually inheriting it (left unset) — an explicit override always
    // uses this card's own local cache, so it never pollutes the shared one.
    final digitCache = (widget.textStyle == null && provider != null) ? provider.cache : _localCache;
    final sepCache = (widget.separatorStyle == null && provider != null) ? provider.cache : _localCache;
    final labelCache = (widget.labelStyle == null && provider != null) ? provider.cache : _localCache;

    final geom = _measure(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      digitGap: digitGap,
      unitGap: unitGap,
      separatorStyle: separatorStyle,
      labelStyle: labelStyle,
      sepCache: sepCache,
      labelCache: labelCache,
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
    return widget.repaintBoundary
        ? RepaintBoundary(child: semantic)
        : semantic;
  }
}

// ── geometry ───────────────────────────────────────────────────────────────────────────

const _fullRadius = BorderRadius.all(Radius.circular(4));
const _leftRadius = BorderRadius.horizontal(left: Radius.circular(4));
const _rightRadius = BorderRadius.horizontal(right: Radius.circular(4));
