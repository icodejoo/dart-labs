import 'package:flutter/material.dart';
import 'package:luckdraw/grid.dart';

import '../demo_shell.dart';
import '../theme/demo_theme.dart';
import '../theme/prize_art.dart';

/// 九宫格示例；例如 `const GridPage()`。
class GridPage extends StatefulWidget {
  /// 创建九宫格页。
  const GridPage({super.key});

  /// 创建状态。
  @override
  State<GridPage> createState() => GridPageState();
}

/// 九宫格页的业务状态。
class GridPageState extends State<GridPage> {
  /// 页面持有的控制器，例如 `controller.lastResult`。
  final GridController controller = GridController();

  /// 按顺时针排列的八个奖品。
  static const GridConfig config = GridConfig(
      rows: 3,
      cols: 3,
      blocks: [
        LuckyBoxBlock(
            padding: LuckyEdgeInsets.all(12),
            borderRadius: 22,
            background: LuckyFill.gradient(LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [DemoPalette.blue, DemoPalette.primary])))
      ],
      prizes: [
        GridPrize(
            x: 0,
            y: 0,
            painter: paintGridPrize,
            texts: [LuckyText('A · 礼盒', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 1,
            y: 0,
            painter: paintGridPrize,
            texts: [LuckyText('B · 大奖', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 2,
            y: 0,
            painter: paintGridPrize,
            texts: [LuckyText('C · 好礼', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 2,
            y: 1,
            painter: paintGridPrize,
            texts: [LuckyText('D · 惊喜', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 2,
            y: 2,
            painter: paintGridPrize,
            texts: [LuckyText('E · 幸运', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 1,
            y: 2,
            painter: paintGridPrize,
            texts: [LuckyText('F · 元气', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 0,
            y: 2,
            painter: paintGridPrize,
            texts: [LuckyText('G · 心意', top: LuckyLength.percent(68))]),
        GridPrize(
            x: 0,
            y: 1,
            painter: paintGridPrize,
            texts: [LuckyText('H · 福气', top: LuckyLength.percent(68))]),
      ],
      buttons: [
        GridButton(
            x: 1,
            y: 1,
            style: LuckyCellStyle(
                background: LuckyFill.color(DemoPalette.gold),
                shadow: LuckyShadow(offsetY: 3, color: Color(0xFFCCA35F))),
            texts: [
              LuckyText('开始',
                  top: LuckyLength.percent(33),
                  fontSize: 18,
                  fontWeight: FontWeight.w700)
            ])
      ],
      style: GridStyle(
          cell: LuckyCellStyle(
              background: LuckyFill.color(DemoPalette.cream),
              borderRadius: 12,
              shadow: LuckyShadow(offsetY: 3, color: Color(0xFF394FAF))),
          text: LuckyTextDefaults(
              color: DemoPalette.ink,
              fontSize: 11,
              fontFamily: 'Roboto',
              fontFamilyFallback: demoFontFallback)),
      // 高亮只加红色边框：背景、圆角、阴影与普通格一致，避免几何和颜色跳变。
      activeStyle: LuckyCellStyle(
          background: LuckyFill.color(DemoPalette.cream),
          borderRadius: 12,
          border: LuckyBorder(width: 3, color: Color(0xFFE53935)),
          shadow: LuckyShadow(offsetY: 3, color: Color(0xFF394FAF))),
      options: GridOptions(gutter: 8, motion: demoMotion));

  /// 结果文本。
  String _result = '';

  /// 展示高亮循环及目标结果。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: '九宫格',
      phase: controller.phase,
      result: _result,
      reset: () {
        controller.reset();
        setState(() => _result = '');
      },
      start: () {
        controller.play();
      },
      serverResult: () {
        controller.stop(demoTarget);
      },
      game: LuckyGrid(
          config: config,
          controller: controller,
          width: demoSide,
          height: demoSide,
          onStart: () {
            controller.play();
          },
          onEnd: (result) => setState(() => _result = '奖品：${result.index}')));

  /// 释放控制器。
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
