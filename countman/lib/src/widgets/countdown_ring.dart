import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:countman/src/count_down/plugin.dart';
import 'package:countman/src/count_down/types.dart';

/// A circular arc countdown display.
///
/// The ring depletes clockwise from the top as time elapses.
/// Progress = remaining / total, where [total] defaults to the initial
/// remaining duration at widget creation.
///
/// [to] accepts [DateTime], [Duration], [int] (ms epoch), or ISO-8601 [String].
///
/// ```dart
/// CountdownRing(
///   to: const Duration(minutes: 5),
///   size: 80,
///   center: CountdownText(to: const Duration(minutes: 5)),
/// )
/// ```
///
/// For large numbers of concurrent instances set [repaintBoundary] = false.
class CountdownRing extends StatefulWidget {
  const CountdownRing({
    super.key,
    required this.to,
    this.size = 80.0,
    this.strokeWidth = 8.0,
    this.color = const Color(0xFF2196F3),
    this.trackColor = const Color(0xFFE0E0E0),
    this.center,
    this.clockwise = true,
    this.repaintBoundary = true,
    this.plugin,
    this.controller,
    this.onDone,
  });

  /// Countdown target. Accepts [DateTime], [Duration], [int] (ms epoch),
  /// or ISO-8601 [String].
  final dynamic to;

  final double size;
  final double strokeWidth;

  /// Arc color. Defaults to blue.
  final Color color;

  /// Track (background circle) color.
  final Color trackColor;

  /// Optional widget rendered in the center of the ring.
  final Widget? center;

  /// Arc direction. True = clockwise (default).
  final bool clockwise;

  /// Wraps in [RepaintBoundary]. Disable when displaying many instances.
  final bool repaintBoundary;

  final Countdown? plugin;
  final CountdownController? controller;
  final void Function()? onDone;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  late final ValueNotifier<Duration> _remaining;
  late Duration _total;
  CountdownHandle? _handle;

  @override
  void initState() {
    super.initState();
    _total = Duration.zero;
    _remaining = ValueNotifier(Duration.zero);
    _start();
  }

  void _start() {
    _handle?.cancel();
    final r = remainingUntil(widget.to); // single call
    _total = r;
    _remaining.value = r;
    _handle = (widget.plugin ?? defaultCountdown).add(CountdownOptions(
      duration: r,
      onUpdate: (v) => _remaining.value = v,
      onDone: widget.onDone,
    ));
    widget.controller?.attach(_handle!);
  }

  @override
  void didUpdateWidget(CountdownRing old) {
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
      builder: (_, r, __) {
        final progress = _total.inMicroseconds > 0
            ? (r.inMicroseconds / _total.inMicroseconds).clamp(0.0, 1.0)
            : 0.0;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _RingPainter(
            progress: progress,
            color: widget.color,
            trackColor: widget.trackColor,
            strokeWidth: widget.strokeWidth,
            clockwise: widget.clockwise,
          ),
          child: widget.center != null
              ? SizedBox.square(
                  dimension: widget.size,
                  child: Center(child: widget.center),
                )
              : null,
        );
      },
    );
    return widget.repaintBoundary ? RepaintBoundary(child: inner) : inner;
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.clockwise,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final bool clockwise;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Track circle.
    paint.color = trackColor;
    canvas.drawCircle(center, radius, paint);

    // Arc representing remaining progress.
    if (progress > 0) {
      paint.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // start at 12 o'clock
        2 * math.pi * progress * (clockwise ? 1 : -1),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
