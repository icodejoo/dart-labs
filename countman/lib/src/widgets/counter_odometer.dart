import 'package:flutter/widgets.dart';
import 'package:odometer/odometer.dart' show OdometerNumber, OdometerTransition;

import 'package:countman/src/counter/plugin.dart';
import 'package:countman/src/counter/types.dart';

import 'reduce_motion.dart';

/// A count-up widget that renders each digit with a vertical slide transition,
/// driven by the shared [Countman] ticker.
///
/// Option A: constructs [OdometerNumber] directly from the raw animated float
/// each frame — individual digit progress is derived from the fractional part,
/// so the ones digit slides smoothly while higher digits tick on integer carry.
/// Digit count matches the current value with no leading-zero padding.
///
/// ```dart
/// CounterOdometer(to: 9999)
/// CounterOdometer(from: 9999, to: 100)  // decreasing — no leading zeros
/// ```
class CounterOdometer extends StatefulWidget {
  const CounterOdometer({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    this.allowNegative = false,
    this.letterWidth = 20,
    this.numberTextStyle,
    this.verticalOffset = 20,
    this.groupSeparator,
    this.prefix,
    this.suffix,
    this.prefixWidget,
    this.suffixWidget,
    this.onComplete,
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// When `false` (default) the value never goes below 0. Set `true` to
  /// display negative values with a leading minus sign.
  final bool allowNegative;

  /// Fixed width per digit slot — prevents layout jitter when digits change.
  final double letterWidth;
  final TextStyle? numberTextStyle;

  /// Vertical slide distance in logical pixels.
  final double verticalOffset;

  /// Optional widget inserted every 3 digits (e.g. `Text(',')`).
  final Widget? groupSeparator;

  /// Plain-text prefix. Ignored when [prefixWidget] is provided.
  final String? prefix;

  /// Plain-text suffix. Ignored when [suffixWidget] is provided.
  final String? suffix;

  /// Widget placed before the digits. Takes precedence over [prefix].
  final Widget? prefixWidget;

  /// Widget placed after the digits. Takes precedence over [suffix].
  final Widget? suffixWidget;

  final void Function(double value)? onComplete;

  @override
  State<CounterOdometer> createState() => _CounterOdometerState();
}

class _CounterOdometerState extends State<CounterOdometer> {
  late final _LiveOdometerAnimation _animation;
  double _currentValue = 0;
  bool _showMinus = false;
  CounterHandle? _handle;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.from ?? 0;
    _showMinus = widget.allowNegative && _currentValue < 0;
    _animation = _LiveOdometerAnimation(_odometerOf(_currentValue));
    _startTask(from: _currentValue);
  }

  // Odometer digits are non-negative; negativity is shown via a leading minus.
  OdometerNumber _odometerOf(double v) =>
      _fromFloat(widget.allowNegative ? v.abs() : v);

  void _startTask({required double from}) {
    _handle?.cancel();
    _handle = counter(CounterOptions(
      from: from,
      to: widget.to,
      duration: motionDuration(widget.duration),
      curve: widget.curve,
      allowNegative: widget.allowNegative,
      onUpdate: (v) {
        _currentValue = v;
        _animation.value = _odometerOf(v);
        final neg = widget.allowNegative && v < 0;
        if (neg != _showMinus) setState(() => _showMinus = neg);
      },
      onComplete: (_) => widget.onComplete?.call(widget.to),
    ));
  }

  @override
  void didUpdateWidget(CounterOdometer old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve) {
      _startTask(from: _currentValue);
    }
  }

  @override
  void dispose() {
    _handle?.cancel();
    _animation.dispose();
    super.dispose();
  }

  // Builds one digit column without Opacity widget.
  // Opacity widget triggers saveLayer for every fractional alpha frame.
  // Using color alpha avoids the saveLayer entirely.
  Widget _digit(int value, int place, double opacity, double offsetY) {
    // Inherit the ambient DefaultTextStyle (theme text color etc.) so digits
    // are visible without an explicit color, instead of defaulting to white.
    final style = DefaultTextStyle.of(context).style.merge(widget.numberTextStyle);
    final base = style.color ?? const Color(0xFF000000);
    final color = base.withValues(alpha: (base.a * opacity).clamp(0.0, 1.0));
    Widget child = SizedBox(
      width: widget.letterWidth,
      child: Text('$value',
          textAlign: TextAlign.center,
          style: style.copyWith(color: color)),
    );
    // Insert thousand separator every 3 integer places (place 4, 7, 10…)
    if (widget.groupSeparator != null && (place - 1) > 0 && (place - 1) % 3 == 0) {
      child = Row(mainAxisSize: MainAxisSize.min,
          children: [child, widget.groupSeparator!]);
    }
    return Transform.translate(offset: Offset(0, offsetY), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final vo = widget.verticalOffset;
    final digits = OdometerTransition(
      odometerAnimation: _animation,
      // Incoming digit: slides from -vo → 0, fades in
      transitionIn: (value, place, p) => _digit(value, place, p,       vo * p - vo),
      // Outgoing digit: slides from 0 → +vo, fades out
      transitionOut:(value, place, p) => _digit(value, place, 1.0 - p, vo * p),
    );

    // Leading minus for negative values (only when allowNegative).
    final Widget numberPart = _showMinus
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Text('-', style: widget.numberTextStyle),
            digits,
          ])
        : digits;

    final hasPrefix = widget.prefixWidget != null || widget.prefix != null;
    final hasSuffix = widget.suffixWidget != null || widget.suffix != null;
    if (!hasPrefix && !hasSuffix) return numberPart;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (widget.prefixWidget != null)
          widget.prefixWidget!
        else if (widget.prefix != null)
          Text(widget.prefix!, style: widget.numberTextStyle),
        numberPart,
        if (widget.suffixWidget != null)
          widget.suffixWidget!
        else if (widget.suffix != null)
          Text(widget.suffix!, style: widget.numberTextStyle),
      ],
    );
  }
}

/// Constructs an [OdometerNumber] directly from a raw float value.
///
/// The fractional part of [v] becomes the ones-digit slide progress.
/// Higher digits carry only at integer boundaries — no leading zeros when
/// the digit count shrinks (e.g. 9999 → 100).
OdometerNumber _fromFloat(double v) {
  if (v <= 0) return OdometerNumber(0);
  final floor = v.floor();
  final frac = v - floor;
  var val = floor;
  var place = 1;
  final digits = <int, double>{};
  while (val > 0) {
    digits[place] = val.toDouble() + (place == 1 ? frac : 0.0);
    val = val ~/ 10;
    place++;
  }
  if (digits.isEmpty) digits[1] = frac;
  return OdometerNumber.fromDigits(digits);
}

/// A minimal [Animation<OdometerNumber>] backed by [ChangeNotifier].
/// Setting [value] notifies [OdometerTransition] (an [AnimatedWidget]) to
/// rebuild — no [AnimationController] needed.
class _LiveOdometerAnimation extends ChangeNotifier
    implements Animation<OdometerNumber> {
  _LiveOdometerAnimation(OdometerNumber initial) : _value = initial;

  OdometerNumber _value;

  @override
  OdometerNumber get value => _value;

  set value(OdometerNumber v) {
    _value = v;
    notifyListeners();
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  bool get isForwardOrCompleted => true;

  @override
  bool get isCompleted => false;

  @override
  bool get isDismissed => false;

  @override
  bool get isAnimating => true;

  @override
  String toStringDetails() => 'live';

  @override
  Animation<U> drive<U>(Animatable<U> child) =>
      throw UnsupportedError('_LiveOdometerAnimation does not support drive()');

  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}
}
