import 'package:flutter/widgets.dart';
import 'package:luckdraw/capsule.dart';

/// 仅使用 capsule 入口，保留实际 Widget 与配置。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: const LuckyCapsuleMachine(
              config: CapsuleConfig(prizes: [
        CapsulePrize(
            topFill: LuckyFill.color(Color(0xFFE53935)),
            bottomFill: LuckyFill.color(Color(0xFFFFEB3B)))
      ])))));
}
