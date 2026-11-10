import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:luckdraw/extend.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/src/grid/layout/grid_layout.dart'
    show computeGridLayout;

/// 金色普通格子背景。
const LuckyFill gridNormalFill = LuckyFill.color(Color(0xFFFFE8AF));

/// Golden 使用全局加载的 Roboto，避免系统缺少默认字体时显示 Ahem 方块。
const LuckyTextDefaults gridTextDefaults =
    LuckyTextDefaults(fontFamily: 'Roboto');

/// 九宫格标准三行三列配置，奖品沿外圈顺时针巡游。
const GridConfig gridFixture = GridConfig(
  blocks: [
    LuckyBoxBlock(
        padding: LuckyEdgeInsets.all(10),
        background: LuckyFill.color(Color(0xFF7055BB)),
        borderRadius: 18)
  ],
  style: GridStyle(
      text: gridTextDefaults,
      cell: LuckyCellStyle(background: gridNormalFill, borderRadius: 12)),
  prizes: [
    GridPrize(x: 0, y: 0, weight: 1, texts: [LuckyText('A')]),
    GridPrize(x: 1, y: 0, weight: 1, texts: [LuckyText('B')]),
    GridPrize(x: 2, y: 0, weight: 1, texts: [LuckyText('C')]),
    GridPrize(x: 2, y: 1, weight: 1, texts: [LuckyText('D')]),
    GridPrize(x: 2, y: 2, weight: 1, texts: [LuckyText('E')]),
    GridPrize(x: 1, y: 2, weight: 1, texts: [LuckyText('F')]),
    GridPrize(x: 0, y: 2, weight: 1, texts: [LuckyText('G')]),
    GridPrize(x: 0, y: 1, weight: 1, texts: [LuckyText('H')]),
  ],
  buttons: [
    GridButton(
        x: 1,
        y: 1,
        style: LuckyCellStyle(background: LuckyFill.color(Color(0xFFAD8EFF))),
        texts: [LuckyText('GO')])
  ],
);

/// 计算测试布局并释放测量器；默认使用 300 像素盒子。
GridLayout gridLayout(GridConfig config, {Size size = const Size(300, 300)}) {
  final input = LuckyLayoutInput.headless(size);
  try {
    return computeGridLayout(config, input);
  } finally {
    input.measurer.dispose();
  }
}

/// 创建单像素内存图用于格子绘制；调用者负责释放返回图片。
Future<ui.Image> createGridTestImage({required Color color}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1, 1);
  } finally {
    picture.dispose();
  }
}
