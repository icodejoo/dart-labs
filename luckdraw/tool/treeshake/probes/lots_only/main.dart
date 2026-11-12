import 'package:flutter/widgets.dart';
import 'package:luckdraw/lots.dart';

/// 仅使用 lots 入口，保留实际 Widget 与配置。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: const LuckyLots(
              config: LotsConfig(sticks: [LotsStick(label: '上签')])))));
}
