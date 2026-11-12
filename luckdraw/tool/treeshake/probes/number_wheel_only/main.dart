import 'package:flutter/widgets.dart';
import 'package:luckdraw/number_wheel.dart';

/// 仅使用 number_wheel 入口，保留实际 Widget 与配置。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: LuckyNumberWheel(config: NumberWheelConfig.range(0, 9)))));
}
