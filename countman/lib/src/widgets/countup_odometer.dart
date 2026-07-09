import 'package:flutter/widgets.dart';
import 'package:odometer/odometer.dart';

import 'package:countman/src/count_up/plugin.dart';
import 'package:countman/src/count_up/types.dart';

/// A count-up widget that renders each digit with a vertical slide transition,
/// driven by the shared [Countman] ticker.
///
/// Internally uses [OdometerNumber.lerp] to compute per-digit fractional
/// progress each frame — no [AnimationController] per instance.
///
/// ```dart
/// CountupOdometer(to: 9999)
/// CountupOdometer(
///   to: 9999,
///   duration: Duration(milliseconds: 1500),
///   letterWidth: 24,
///   numberTextStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
/// )
/// ```
class CountupOdometer extends StatefulWidget {
  const CountupOdometer({
    super.key,
    this.from,
    required this.to,
    this.duration = const Duration(milliseconds: 1000),
    this.curve = Curves.easeOut,
    /// Width of each digit slot in logical pixels.
    /// Should match your [numberTextStyle] font size roughly.
    this.letterWidth = 20,
    this.numberTextStyle,
    this.verticalOffset = 20,
    this.groupSeparator,
    this.onDone,
  });

  final double? from;
  final double to;
  final Duration duration;
  final Curve curve;

  /// Fixed width per digit slot — prevents layout jitter when digits change.
  final double letterWidth;
  final TextStyle? numberTextStyle;

  /// Vertical slide distance in logical pixels.
  final double verticalOffset;

  /// Optional widget inserted every 3 digits (e.g. `Text(',')`).
  final Widget? groupSeparator;

  final void Function(double value)? onDone;

  @override
  State<CountupOdometer> createState() => _CountupOdometerState();
}

class _CountupOdometerState extends State<CountupOdometer> {
  late final _LiveOdometerAnimation _animation;
  late OdometerNumber _fromOdo;
  late OdometerNumber _toOdo;
  CountupHandle? _handle;

  @override
  void initState() {
    super.initState();
    _fromOdo = OdometerNumber((widget.from ?? 0).round());
    _toOdo = OdometerNumber(widget.to.round());
    _animation = _LiveOdometerAnimation(_fromOdo);
    _startTask();
  }

  void _startTask() {
    _handle?.cancel();
    final fromSnap = _fromOdo;
    final toSnap = _toOdo;
    _handle = countup(CountupOptions(
      from: 0,
      to: 1, // t: 0 → 1; curve is applied by CountupPlugin
      duration: widget.duration,
      curve: widget.curve,
      onUpdate: (t) {
        _animation.value = OdometerNumber.lerp(fromSnap, toSnap, t.clamp(0.0, 1.0));
      },
      onDone: (_) => widget.onDone?.call(widget.to),
    ));
  }

  @override
  void didUpdateWidget(CountupOdometer old) {
    super.didUpdateWidget(old);
    if (widget.to != old.to ||
        widget.duration != old.duration ||
        widget.curve != old.curve) {
      _fromOdo = OdometerNumber(_animation.value.number);
      _toOdo = OdometerNumber(widget.to.round());
      _startTask();
    }
  }

  @override
  void dispose() {
    _handle?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideOdometerTransition(
      odometerAnimation: _animation,
      letterWidth: widget.letterWidth,
      numberTextStyle: widget.numberTextStyle,
      verticalOffset: widget.verticalOffset,
      groupSeparator: widget.groupSeparator,
    );
  }
}

/// A minimal [Animation<OdometerNumber>] backed by [ChangeNotifier].
///
/// [AnimatedWidget] (which [OdometerTransition] extends) calls [addListener],
/// routing to [ChangeNotifier]. Setting [value] calls [notifyListeners],
/// which triggers [AnimatedWidget.markNeedsBuild] — no [AnimationController].
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
