import 'package:flutter/widgets.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/wheel.dart';

/// 同时使用全部玩法与拉杆版本，作为完整玩法的体积对照。
void main() {
  runApp(Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
          child: Column(children: [
        SizedBox(
            width: _side,
            height: _side,
            child:
                LuckyWheel(config: const WheelConfig(prizes: [WheelPrize()]))),
        SizedBox(
            width: _side,
            height: _side,
            child: const LuckyGrid(
                config: GridConfig(prizes: [GridPrize(x: 0, y: 0)]))),
        SizedBox(
            width: _side,
            height: _side,
            child: const LuckySlotMachine(
                config:
                    SlotConfig(prizes: [SlotPrize()], reels: [SlotReel()]))),
        SizedBox(
            width: _side,
            height: _side,
            child: const LuckyCapsuleMachine(
                config: CapsuleConfig(prizes: [
              CapsulePrize(
                  topFill: LuckyFill.color(Color(0xFFE53935)),
                  bottomFill: LuckyFill.color(Color(0xFFFFEB3B)))
            ]))),
        SizedBox(
            width: _side,
            height: _side,
            child: LuckyNumberWheel(config: NumberWheelConfig.range(0, 9))),
        SizedBox(
            width: _side,
            height: _side,
            child: const LuckyLots(
                config: LotsConfig(sticks: [LotsStick(label: '上签')]))),
        SizedBox(
            width: _side,
            height: _side,
            child: LuckyLotto(config: LottoConfig.superLotto())),
        const SizedBox(
            width: _side,
            height: _side,
            child: LuckyLeverSlotMachine(
                config:
                    SlotConfig(prizes: [SlotPrize()], reels: [SlotReel()]))),
      ]))));
}

/// 每个探针玩法的有界边长。
const double _side = 240;
