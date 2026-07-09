import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';

/// A flip-card countdown display. Each time unit (H / M / S) is rendered as
/// a split-flap card that animates when the digit changes.
///
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// ```dart
/// CountdownCard(to: const Duration(minutes: 5))
/// CountdownCard(to: DateTime(2025, 12, 31), splitDigits: true)
/// ```
///
/// For large numbers of concurrent instances set [repaintBoundary] = false.
class CountdownCard extends StatefulWidget {
  const CountdownCard({
    super.key,
    required this.to,
    this.splitDigits = false,
    this.showHours,
    this.labels = const ['H', 'M', 'S'],
    this.separator = ':',
    this.flipDuration = const Duration(milliseconds: 450),
    this.cardWidth = 56.0,
    this.cardHeight = 76.0,
    this.digitGap = 4.0,
    this.unitGap = 8.0,
    this.cardColor = const Color(0xFF212121),
    this.textStyle,
    this.labelStyle,
    this.separatorStyle,
    this.repaintBoundary = true,
    this.plugin,
    this.controller,
    this.onDone,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final dynamic to;

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

  final Duration flipDuration;

  final double cardWidth;
  final double cardHeight;

  /// Gap between digit cards when [splitDigits] is true.
  final double digitGap;

  /// Horizontal space on each side of the separator.
  final double unitGap;

  final Color cardColor;

  /// Text style for the digit numbers. Defaults to bold white scaled to [cardHeight].
  final TextStyle? textStyle;

  /// Text style for unit labels below each card.
  final TextStyle? labelStyle;

  /// Text style for the separator character.
  final TextStyle? separatorStyle;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onDone;

  @override
  State<CountdownCard> createState() => _CountdownCardState();
}

class _CountdownCardState extends State<CountdownCard> {
  late final ValueNotifier<Duration> _remaining;
  CountdownHandle? _handle;

  @override
  void initState() {
    super.initState();
    _remaining = ValueNotifier(Duration.zero);
    _start();
  }

  void _start() {
    _handle?.cancel();
    final r = remainingUntil(widget.to);
    _remaining.value = r;
    _handle = (widget.plugin ?? defaultCountdown).add(CountdownOptions(
      duration: r,
      onUpdate: (r) => _remaining.value = r,
      onDone: widget.onDone,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CountdownCard old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to) {
      widget.controller?.detach();
      _start();
    }
  }

  @override
  void dispose() {
    widget.controller?.detach();
    _handle?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inner = ValueListenableBuilder<Duration>(
      valueListenable: _remaining,
      builder: (_, r, __) => _CardLayout(
        remaining: r,
        splitDigits: widget.splitDigits,
        showHours: widget.showHours,
        labels: widget.labels,
        separator: widget.separator,
        flipDuration: widget.flipDuration,
        cardWidth: widget.cardWidth,
        cardHeight: widget.cardHeight,
        digitGap: widget.digitGap,
        unitGap: widget.unitGap,
        cardColor: widget.cardColor,
        textStyle: widget.textStyle,
        labelStyle: widget.labelStyle,
        separatorStyle: widget.separatorStyle,
      ),
    );
    return widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
  }
}

// ── Layout ────────────────────────────────────────────────────────────────────

class _CardLayout extends StatelessWidget {
  const _CardLayout({
    required this.remaining,
    required this.splitDigits,
    required this.showHours,
    required this.labels,
    required this.separator,
    required this.flipDuration,
    required this.cardWidth,
    required this.cardHeight,
    required this.digitGap,
    required this.unitGap,
    required this.cardColor,
    required this.textStyle,
    required this.labelStyle,
    required this.separatorStyle,
  });

  final Duration remaining;
  final bool splitDigits;
  final bool? showHours;
  final List<String>? labels;
  final String separator;
  final Duration flipDuration;
  final double cardWidth;
  final double cardHeight;
  final double digitGap;
  final double unitGap;
  final Color cardColor;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final TextStyle? separatorStyle;

  bool get _showHours => showHours ?? remaining.inHours >= 1;

  TextStyle get _effectiveText => textStyle ??
      TextStyle(
        fontSize: cardHeight * 0.48,
        fontWeight: FontWeight.bold,
        color: const Color(0xFFFFFFFF),
      );

  TextStyle get _effectiveLabel => labelStyle ??
      TextStyle(
        fontSize: 11,
        color: const Color(0xFF9E9E9E),
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      );

  TextStyle get _effectiveSep => separatorStyle ??
      TextStyle(
        fontSize: cardHeight * 0.38,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF757575),
      );

  @override
  Widget build(BuildContext context) {
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final s = remaining.inSeconds % 60;

    final children = <Widget>[];

    if (_showHours) {
      children.add(_unit(h, labels?[0]));
      children.add(_sep());
    }
    children.add(_unit(m, labels?[1]));
    children.add(_sep());
    children.add(_unit(s, labels?[2]));

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }

  Widget _sep() => Padding(
        padding: EdgeInsets.symmetric(horizontal: unitGap),
        child: Text(separator, style: _effectiveSep),
      );

  Widget _unit(int value, String? label) {
    final cards = splitDigits
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _digit(value ~/ 10, pad: false),
              SizedBox(width: digitGap),
              _digit(value % 10, pad: false),
            ],
          )
        : _digit(value, pad: true);

    if (label == null) return cards;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        cards,
        const SizedBox(height: 4),
        Text(label, style: _effectiveLabel),
      ],
    );
  }

  Widget _digit(int value, {required bool pad}) => _FlipDigit(
        value: value,
        pad: pad,
        cardWidth: cardWidth,
        cardHeight: cardHeight,
        cardColor: cardColor,
        flipDuration: flipDuration,
        textStyle: _effectiveText,
      );
}

// ── Flip digit ────────────────────────────────────────────────────────────────

class _FlipDigit extends StatefulWidget {
  const _FlipDigit({
    required this.value,
    required this.pad,
    required this.cardWidth,
    required this.cardHeight,
    required this.cardColor,
    required this.flipDuration,
    required this.textStyle,
  });

  final int value;
  final bool pad;
  final double cardWidth;
  final double cardHeight;
  final Color cardColor;
  final Duration flipDuration;
  final TextStyle textStyle;

  @override
  State<_FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<_FlipDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _prev = 0;
  int _curr = 0;

  @override
  void initState() {
    super.initState();
    _prev = _curr = widget.value;
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.flipDuration,
    );
  }

  @override
  void didUpdateWidget(_FlipDigit old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _prev = old.value;
      _curr = widget.value;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(int v) =>
      widget.pad ? v.toString().padLeft(2, '0') : v.toString();

  // Full card face with text centered.
  Widget _face(int value) => Container(
        width: widget.cardWidth,
        height: widget.cardHeight,
        decoration: BoxDecoration(
          color: widget.cardColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: Text(_fmt(value), style: widget.textStyle)),
      );

  // Top half of a card face (clips lower 50%).
  Widget _topHalf(int value) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 0.5,
          child: _face(value),
        ),
      );

  // Bottom half of a card face (clips upper 50%).
  Widget _bottomHalf(int value) => Align(
        alignment: Alignment.bottomCenter,
        child: ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 0.5,
            child: _face(value),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;

        // Idle — render static card.
        if (t == 0 || t == 1) return _face(_curr);

        final inPhase1 = t < 0.5;
        final t1 = (t * 2).clamp(0.0, 1.0);
        final t2 = ((t - 0.5) * 2).clamp(0.0, 1.0);

        // Phase 1: old top falls forward  (0 → -π/2)
        // Phase 2: new top rises from behind (π/2 → 0)
        final angle = inPhase1
            ? -(t1 * math.pi / 2)
            : (1 - t2) * math.pi / 2;

        final staticTopValue = inPhase1 ? _prev : _curr;
        final animTopValue   = inPhase1 ? _prev : _curr;

        return SizedBox(
          width: widget.cardWidth,
          height: widget.cardHeight,
          child: Stack(
            children: [
              // Bottom half always shows new value.
              _bottomHalf(_curr),
              // Static top half (provides background for the animated flap).
              _topHalf(staticTopValue),
              // Animated flap rotating around the center divider.
              Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // perspective
                  ..rotateX(angle),
                child: _topHalf(animTopValue),
              ),
              // Divider line at card center.
              Positioned(
                top: widget.cardHeight / 2 - 0.5,
                left: 0,
                right: 0,
                child: ColoredBox(
                  color: const Color(0x28000000),
                  child: SizedBox(height: 1, width: widget.cardWidth),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
