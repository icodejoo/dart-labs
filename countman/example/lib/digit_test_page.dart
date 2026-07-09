import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:countman/countman.dart';

class DigitTestPage extends StatefulWidget {
  const DigitTestPage({super.key});
  @override
  State<DigitTestPage> createState() => _DigitTestPageState();
}

class _DigitTestPageState extends State<DigitTestPage> {
  double _value = 0;
  bool _decreasing = false;
  final _logs = <String>[];
  int _frameCount = 0;
  static const _maxLog = 30;

  void _start() {
    setState(() {
      _value = 99;
      _decreasing = false;
      _logs.clear();
      _frameCount = 0;
    });
  }

  void _reset() {
    setState(() {
      _value = 0;
      _decreasing = true;
      _logs.clear();
      _frameCount = 0;
    });
  }

  void _onUpdate(double raw) {
    if (_frameCount >= _maxLog) return;
    _frameCount++;

    // Decompose into digit values (same logic as _updateCurrentDigitValues)
    // from: 0, to: 999999999
    const from = 0.0, to = 999999999.0;
    final t = ((raw - from) / (to - from)).clamp(0.0, 1.0);

    final fromDigits = _getDigits(0);
    final toDigits   = _getDigits(999999999);
    final maxN = math.max(fromDigits.length, toDigits.length);
    final oldD = [...List<double>.filled(maxN - fromDigits.length, 0.0), ...fromDigits];
    final tarD = [...List<double>.filled(maxN - toDigits.length,   0.0), ...toDigits];

    final cur = <String>[];
    for (int i = 0; i < maxN; i++) {
      final v = oldD[i] + (tarD[i] - oldD[i]) * t;
      final digit    = v.truncate() % 10;
      final progress = (v - v.truncate());
      final rnd      = v.round();
      cur.add('[$i]v=${v.toStringAsFixed(2)} d=$digit p=${progress.toStringAsFixed(2)} rnd=$rnd');
    }

    final line = 'f$_frameCount raw=${raw.toStringAsFixed(0)} t=${t.toStringAsFixed(4)}\n'
        '  visible from idx=${_firstVisible(oldD, tarD, t, maxN)}\n'
        '  ${cur.join(' ')}';

    if (mounted) {
      setState(() => _logs.add(line));
    }
  }

  int _firstVisible(List<double> oldD, List<double> tarD, double t, int n) {
    for (int i = 0; i < n; i++) {
      final v = oldD[i] + (tarD[i] - oldD[i]) * t;
      if (v.round() != 0) return i;
    }
    return n - 1;
  }

  List<double> _getDigits(int val) {
    if (val == 0) return [0.0];
    final d = <double>[];
    int v = val.abs();
    while (v > 0) { d.add(v.toDouble()); v ~/= 10; }
    return d.reversed.toList();
  }

  static const _style = TextStyle(fontSize: 40, fontWeight: FontWeight.bold, fontFamily: 'monospace');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Digit Debug  0 → 999,999,999')),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Text(_decreasing ? '↓ Decreasing' : '↑ Increasing',
              style: TextStyle(
                  color: _decreasing ? Colors.red : Colors.green,
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // CountupPlus — direction handled automatically inside widget
          CountupPlus(
            value: _value,
            duration: const Duration(seconds: 3),
            thousandSeparator: ',',
            textStyle: _style,
          ),
          const SizedBox(height: 16),
          // CountupBuilder to tap into raw values
          CountupBuilder(
            to: _value,
            duration: const Duration(seconds: 3),
            onUpdate: _onUpdate,
            builder: (_, v) => Text(
              v.toInt().toString(),
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(onPressed: _start, child: const Text('Start')),
              const SizedBox(width: 16),
              OutlinedButton(onPressed: _reset, child: const Text('Reset')),
            ],
          ),
          const Divider(),
          // Frame log
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (_, i) => Text(
                _logs[i],
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
