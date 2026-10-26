@Tags(['benchmark'])
library;

import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inner_reference.dart';
import 'paint_probe.dart';

const _warmup = 2000;
const _iterations = 1000;
const _samples = 11;

/// 报告批次中位数和均值，不把受机器状态影响的耗时写成断言。
void _report(String name, List<double> samples) {
  final sorted = [...samples]..sort();
  final mean = samples.reduce((a, b) => a + b) / samples.length;
  // ignore: avoid_print
  print('$name: median=${sorted[sorted.length ~/ 2].toStringAsFixed(3)} '
      'mean=${mean.toStringAsFixed(3)} us/frame '
      'samples=${samples.map((v) => v.toStringAsFixed(3)).join(",")}');
}

/// 每帧创建并释放真实 Picture，包含录制开销，不含栅格化与 GPU 时间。
void _paintFrame(CustomPainter painter, Size size) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
}

/// 预热后交错测量各实现，降低运行顺序和 JIT 对比较的影响。
void _measure(Map<String, CustomPainter> painters, Size size) {
  for (final painter in painters.values) {
    for (var i = 0; i < _warmup; i++) {
      _paintFrame(painter, size);
    }
  }
  final results = {for (final name in painters.keys) name: <double>[]};
  for (var batch = 0; batch < _samples; batch++) {
    final entries = painters.entries.toList();
    for (final entry in batch.isEven ? entries : entries.reversed) {
      final timer = Stopwatch()..start();
      for (var i = 0; i < _iterations; i++) {
        _paintFrame(entry.value, size);
      }
      timer.stop();
      results[entry.key]!.add(timer.elapsedMicroseconds / _iterations);
    }
  }
  results.forEach(_report);
  for (final entry in painters.entries) {
    final probe = PaintProbe();
    entry.value.paint(probe, size);
    // 身份集合只能观察实际使用的 Paint，不代表完整的 VM 堆分配量。
    // ignore: avoid_print
    print('${entry.key}: observed Paint=${probe.paints.length}, '
        'drawArc=${probe.arcs.length}, paragraphs=${probe.paragraphs}');
  }
}

/// 创建带分组与小数点、所有列处于滚动中的多列 Counter。
CounterPainter _counter(ChangeNotifier repaint, int columns) => CounterPainter(
      repaint: repaint,
      digitValues: List.generate(columns, (i) => i % 10 + 0.375),
      style: const TextStyle(fontSize: 24, color: Colors.white),
      digitSize: const Size(18, 30),
      transition: CounterTransition.slide,
      flipDirection: AxisDirection.up,
      increasing: true,
      fractionDigits: 2,
      groupingPattern: const [3],
      hideLeadingZeroes: false,
      numeralSystem: NumeralSystem.latin,
      thousandSeparator: ',',
    );

/// 记录中心实际进入绘制的次数，验证分层确实隔离了重绘。
class _PaintCounter extends CustomPainter {
  int calls = 0;

  /// 不增加绘制命令，仅记录框架是否重画了中心内容。
  @override
  void paint(Canvas canvas, Size size) => calls++;

  /// 保持夹具的中心绘制配置固定。
  @override
  bool shouldRepaint(_PaintCounter oldDelegate) => false;
}

/// 只在显式启用时运行性能测试，计时不含 widget 创建。
void main() {
  tearDown(Countman.destroy);

  testWidgets('Dial 与 Counter 真实画布基准', (tester) async {
    final painters = <String, CustomPainter>{};
    for (final entry in {
      'Dial inner 60': const DialCountdownStyle(
          showTicks: false, showArcA: false, showArcB: false),
      'Dial full 60': const DialCountdownStyle(),
      'Dial labels 60':
          const DialCountdownStyle(ticks: DialTicksConfig(showLabels: true)),
    }.entries) {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: DialCountdown(to: const Duration(hours: 1), style: entry.value),
      ));
      painters[entry.key] = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter != null)
          .painter!;
    }
    _measure(painters, const Size.square(200));
    _measure({
      'Reference inner 60': const InnerReference(),
      'Merged candidate inner 60': const InnerReference(merged: true),
    }, const Size.square(200));
    final repaint = ChangeNotifier();
    final counters = {
      'Counter 6': _counter(repaint, 6),
      'Counter 12': _counter(repaint, 12),
      'Counter 24': _counter(repaint, 24),
    };
    try {
      _measure(counters, const Size(600, 30));
    } finally {
      for (final painter in counters.values) {
        painter.disposeCache();
      }
      repaint.dispose();
    }
  });

  testWidgets('中心文字分层的实际重绘基准', (tester) async {
    for (final dynamicCenter in [false, true]) {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: DialCountdown(to: Duration(hours: 1)),
      ));
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter != null)
          .painter!;
      const label = Text('60:00', style: TextStyle(fontSize: 28));
      final keys = [UniqueKey(), UniqueKey()];
      final centerKeys = [UniqueKey(), UniqueKey()];
      final counts = [_PaintCounter(), _PaintCounter()];
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var index = 0; index < 2; index++)
            RepaintBoundary(
                child: CustomPaint(
              key: keys[index],
              painter: painter,
              child: SizedBox.square(
                  dimension: 200,
                  child: Center(
                    child: index == 1
                        ? RepaintBoundary(
                            child: CustomPaint(
                                key: centerKeys[index],
                                painter: counts[index],
                                child: label))
                        : CustomPaint(
                            key: centerKeys[index],
                            painter: counts[index],
                            child: label),
                  )),
            )),
        ])),
      ));
      final renders = [
        for (final key in keys)
          tester.renderObject<RenderCustomPaint>(find.byKey(key))
      ];
      final centers = [
        for (final key in centerKeys)
          tester.renderObject<RenderCustomPaint>(find.byKey(key))
      ];

      /// 只测脏标记与 flushPaint，避免测试框架 pump 开销掩盖分层差异。
      void frame(int index) {
        if (dynamicCenter) centers[index].markNeedsPaint();
        renders[index].markNeedsPaint();
        tester.binding.rootPipelineOwner.flushPaint();
      }

      for (var i = 0; i < _warmup; i++) {
        frame(0);
        frame(1);
      }
      final samples = [<double>[], <double>[]];
      for (var batch = 0; batch < _samples; batch++) {
        for (final index in batch.isEven ? [0, 1] : [1, 0]) {
          final timer = Stopwatch()..start();
          for (var i = 0; i < _iterations; i++) {
            frame(index);
          }
          timer.stop();
          samples[index].add(timer.elapsedMicroseconds / _iterations);
        }
      }
      for (var index = 0; index < 2; index++) {
        _report('Center dynamic=$dynamicCenter boundary=${index == 1}',
            samples[index]);
        // ignore: avoid_print
        print('center paint calls=${counts[index].calls}');
      }
    }
  });
}
