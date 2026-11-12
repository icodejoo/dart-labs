import 'package:flutter/widgets.dart';
import 'package:luckdraw/grid.dart';

/// 仅使用 grid 入口，保留实际 Widget 与配置。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: const LuckyGrid(
              config: GridConfig(prizes: [GridPrize(x: 0, y: 0)])))));
}
