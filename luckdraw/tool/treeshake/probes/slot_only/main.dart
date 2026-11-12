import 'package:flutter/widgets.dart';
import 'package:luckdraw/slot.dart';

/// 仅使用 slot 入口，保留实际 Widget 与配置。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: const LuckySlotMachine(
              config:
                  SlotConfig(prizes: [SlotPrize()], reels: [SlotReel()])))));
}
