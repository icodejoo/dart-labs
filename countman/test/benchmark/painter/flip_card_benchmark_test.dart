@Tags(['benchmark'])
library;

import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'paint_probe.dart';

/// 固定预热、批次数与采样数，使改动前后使用同一测量口径。
const _warmup = 2000;
const _iterations = 1000;
const _samples = 11;
const _digitCount = 6;
const _cardHeight = 50.0;
const _cellWidth = 24.0;
const _size = Size(200, 70);
const _duration = Duration(milliseconds: 450);
const _textStyle = TextStyle(fontSize: 24, color: Colors.white);
/// 固定组名同时用于报告与各过渡的段落数量断言。
const _slideBoth = 'slide-both';
const _slideNone = 'slide-none';
const _calendar = 'calendar';
const _flip = 'flip';
/// 两个分隔符和三个标签每帧各绘制一次。
const _decorationCount = 5;

/// 每帧创建并释放真实 Picture，仅计录制时间。
void _paintFrame(FlipCardPainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), _size);
  recorder.endRecording().dispose();
}

/// 遍历全部透明度档和两个翻页阶段，避免只测单帧的缓存命中。
void _prepareFrame(FlipCardPainter painter, int frame) {
  const phases = 32;
  (painter.controller as AnimationController).value = (frame % phases + 0.5) / phases;
  painter.model.reversePhase = frame.isOdd;
}

/// 预热后交错采样，报告中位数并检查段落数和缓存平台期。
void _measure(Map<String, FlipCardPainter> painters) {
  final lengths = <String, int>{};
  for (final entry in painters.entries) {
    for (var i = 0; i < _warmup; i++) {
      _prepareFrame(entry.value, i);
      _paintFrame(entry.value);
    }
    lengths[entry.key] = entry.value.digitCache.length;
  }
  final results = {for (final name in painters.keys) name: <double>[]};
  final entries = painters.entries.toList();
  for (var batch = 0; batch < _samples; batch++) {
    for (final entry in batch.isEven ? entries : entries.reversed) {
      final timer = Stopwatch()..start();
      for (var i = 0; i < _iterations; i++) {
        _prepareFrame(entry.value, i);
        _paintFrame(entry.value);
      }
      timer.stop();
      results[entry.key]!.add(timer.elapsedMicroseconds / _iterations);
    }
  }
  for (final entry in painters.entries) {
    final samples = results[entry.key]!;
    final sorted = [...samples]..sort();
    final probe = PaintProbe();
    entry.value.paint(probe, _size);
    final expectedDigits = switch (entry.key) {
      _calendar => _digitCount * 4,
      _flip => _digitCount,
      _ => _digitCount * 2,
    };
    expect(probe.paragraphs, expectedDigits + _decorationCount, reason: entry.key);
    expect(entry.value.digitCache.length, lengths[entry.key], reason: entry.key);
    // ignore: avoid_print
    print('${entry.key}: median=${sorted[sorted.length ~/ 2].toStringAsFixed(3)} '
        'us/frame samples=${samples.map((v) => v.toStringAsFixed(3)).join(",")} '
        'drawParagraph=${probe.paragraphs} cache=${entry.value.digitCache.length}');
  }
}

/// 构造六位全部变化且带三标签、两分隔符的常驻画笔。
FlipCardPainter _painter(AnimationController controller, CountdownType type,
    SlideEffect effect) {
  final cache = CardGlyphCache();
  return FlipCardPainter(
    repaint: controller,
    controller: controller,
    model: CardModel(List.generate(_digitCount, (i) => i))
      ..target = List.generate(_digitCount, (i) => i + 1)
      ..changedMask = List.filled(_digitCount, true),
    geom: CardGeometry(
      size: _size,
      cells: List.generate(_digitCount,
          (i) => Cell(i * _cellWidth, _cellWidth, i, BorderRadius.zero)),
      separatorCenters: const [48, 96],
      unitLabelCenters: const [24, 72, 120],
      unitLabelText: const ['H', 'M', 'S'],
    ),
    transitionType: type,
    scaleEffect: effect,
    scaleFactor: 1.5,
    opacityEffect: effect,
    perspective: 0.002,
    cardHeight: _cardHeight,
    cardColor: Colors.black,
    textStyle: _textStyle,
    labelStyle: const TextStyle(fontSize: 11),
    separatorStyle: const TextStyle(fontSize: 18),
    separator: ':',
    digitCache: cache,
    sepCache: cache,
    labelCache: cache,
  );
}

/// 显式启用 benchmark 标签后运行四种过渡的相同工作负载。
void main() {
  testWidgets('FlipCard 真实画布基准与绘制次数', (tester) async {
    final controller = AnimationController(vsync: tester, duration: _duration);
    final painters = {
      _slideBoth: _painter(controller, CountdownType.slide, SlideEffect.both),
      _slideNone: _painter(controller, CountdownType.slide, SlideEffect.none),
      _calendar: _painter(controller, CountdownType.calendar, SlideEffect.none),
      _flip: _painter(controller, CountdownType.flip, SlideEffect.none),
    };
    try {
      _measure(painters);
    } finally {
      for (final painter in painters.values) {
        painter.digitCache.clear();
      }
      controller.dispose();
    }
  });
}
