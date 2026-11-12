@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只记录 Canvas 调用，不测耗时，也不影响桌面基准。
class _P5PaintProbe implements Canvas {
  /// 分开统计背景、文字、中缝与裁剪，避免把 clip 误作 GPU draw call。
  final counts = <String, int>{
    'drawRRect': 0,
    'drawParagraph': 0,
    'drawRect': 0,
    'clipRect': 0,
  };

  /// 每次圆角背景调用计一次。
  @override
  void drawRRect(RRect rrect, Paint paint) =>
      counts['drawRRect'] = counts['drawRRect']! + 1;

  /// 每次段落提交计一次，包含分隔符。
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      counts['drawParagraph'] = counts['drawParagraph']! + 1;

  /// 每次数位中缝调用计一次。
  @override
  void drawRect(Rect rect, Paint paint) =>
      counts['drawRect'] = counts['drawRect']! + 1;

  /// 记录逻辑裁剪次数；不假定它等于实际 GPU 提交数。
  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => counts['clipRect'] = counts['clipRect']! + 1;

  /// 忽略 save、transform 等不在旧模型计数口径内的操作。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// 与桌面页相同的 MM:SS 拆位；预热后按 15 个整秒变化枚举。
List<int> _digits(int seconds) => [
  seconds ~/ 600 % 10,
  seconds ~/ 60 % 10,
  seconds ~/ 10 % 6,
  seconds % 10,
];

/// 直接使用生产画笔，保持四个半卡、一个分隔符且无标签。
FlipCardPainter _painter(AnimationController controller, String variant) {
  final cache = CardGlyphCache();
  const textStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  return FlipCardPainter(
    repaint: controller,
    controller: controller,
    model: CardModel(_digits(240)),
    geom: const CardGeometry(
      size: Size(80, 40),
      cells: [
        Cell(0, 15, 0, BorderRadius.horizontal(left: Radius.circular(4))),
        Cell(15, 15, 1, BorderRadius.horizontal(right: Radius.circular(4))),
        Cell(50, 15, 2, BorderRadius.horizontal(left: Radius.circular(4))),
        Cell(65, 15, 3, BorderRadius.horizontal(right: Radius.circular(4))),
      ],
      separatorCenters: [40],
      unitLabelCenters: [],
      unitLabelText: [],
    ),
    transitionType: switch (variant) {
      'countmanCardDefault' => CountdownType.calendar,
      'cardFlipDefault' => CountdownType.flip,
      _ => CountdownType.slide,
    },
    scaleEffect: variant == 'cardSlideScale'
        ? SlideEffect.both
        : SlideEffect.none,
    opacityEffect: variant == 'cardSlideOpacity'
        ? SlideEffect.both
        : SlideEffect.none,
    scaleFactor: 1.5,
    perspective: 0.006,
    cardHeight: 40,
    cardColor: const Color(0xFF212121),
    textStyle: textStyle,
    labelStyle: const TextStyle(fontSize: 11),
    separatorStyle: const TextStyle(
      fontSize: 15.2,
      fontWeight: FontWeight.bold,
      color: Color(0xFF757575),
    ),
    separator: ':',
    digitCache: cache,
    sepCache: cache,
    labelCache: cache,
  );
}

/// 对变化中和提交后两种帧分别计数，结果保存为可复算 JSON。
void main() {
  testWidgets('P5 桌面 MM:SS 绘制调用归因', (tester) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 450),
    );
    final results = <String, Object>{};
    for (final variant in [
      'countmanCardFair',
      'cardSlideScale',
      'cardSlideOpacity',
      'cardFlipDefault',
      'countmanCardDefault',
    ]) {
      final painter = _painter(controller, variant);
      final active = _P5PaintProbe();
      final committed = _P5PaintProbe();
      var samples = 0;
      var changedDigits = 0;
      for (var second = 3; second < 18; second++) {
        for (var i = 0; i < 50; i++) {
          final initial = (4 + i % 5) * 60 + i % 60;
          final from = _digits(initial - second);
          final to = _digits(initial - second - 1);
          painter.model.committed = from;
          painter.model.target = to;
          painter.model.changedMask = [
            for (var d = 0; d < 4; d++) from[d] != to[d],
          ];
          changedDigits += painter.model.changedMask!.where((v) => v).length;
          for (final progress in [0.25, 0.5, 0.75]) {
            controller.value = progress;
            for (final reverse in [false, true]) {
              painter.model.reversePhase = reverse;
              painter.paint(active, painter.geom.size);
              samples++;
            }
          }
          painter.model.target = null;
          painter.model.committed = to;
          painter.paint(committed, painter.geom.size);
        }
      }
      final means = {
        for (final entry in active.counts.entries)
          entry.key: entry.value / samples,
      };
      final terminal = {
        for (final entry in committed.counts.entries)
          entry.key: entry.value / 750,
      };
      final k = changedDigits / 750;
      final expected = variant == 'countmanCardDefault'
          ? 13 + 10 * k
          : variant == 'cardFlipDefault'
          ? 9.0
          : 9 + 2 * k;
      expect(means.values.reduce((a, b) => a + b), closeTo(expected, 1e-9));
      results[variant] = {
        'samples': samples,
        'changedDigitsMean': k,
        'active': means,
        'terminal': terminal,
      };
      painter.digitCache.clear();
    }
    controller.dispose();
    final output = const JsonEncoder.withIndent('  ').convert(results);
    File('build/perf/p5-draw-counts.json').writeAsStringSync(output);
    // ignore: avoid_print
    print(output);
  });
}
