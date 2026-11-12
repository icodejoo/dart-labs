import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 独立小图层逐帧移动，不重建或重绘被测组件。
class BenchmarkFrameDriver extends StatefulWidget {
  const BenchmarkFrameDriver({super.key});

  @override
  State<BenchmarkFrameDriver> createState() => _BenchmarkFrameDriverState();
}

class _BenchmarkFrameDriverState extends State<BenchmarkFrameDriver>
    with SingleTickerProviderStateMixin {
  final _position = ValueNotifier<int>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _position.value = (_position.value + 1) % 32;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(36, 4),
      painter: _PulsePainter(_position),
    ),
  );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.position) : super(repaint: position);

  final ValueNotifier<int> position;
  final _paint = Paint()..color = Colors.cyan;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(position.value.toDouble(), 1, 2, 2), _paint);
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.position != position;
}
