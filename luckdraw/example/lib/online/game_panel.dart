import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:luckdraw/luckdraw.dart';

import '../demo_kit/demo_kit.dart';

/// 卡片内画布的逻辑尺寸，等比缩放而不改变玩法布局。
const _stageWidth = 300.0;

/// 线上紧凑画布的高度。
const _stageHeight = 196.0;

/// 纵向玩法的绘制高度。
const _tallHeight = 400.0;

/// 纵向玩法的预览高度。
const _tallPreviewHeight = 260.0;

/// 所有示例使用的结果文字分隔符。
const _resultSeparator = '：';

/// 控制器各阶段的双语名称。
const _phases = {
  LuckyPhase.idle: ('Ready', '就绪'),
  LuckyPhase.idleSpinning: ('Idle spin', '待机慢转'),
  LuckyPhase.accelerating: ('Accelerating', '加速中'),
  LuckyPhase.cruising: ('Spinning', '运行中'),
  LuckyPhase.decelerating: ('Stopping', '减速中'),
  LuckyPhase.settled: ('Settled', '已开奖'),
};

/// 把既有独立玩法嵌入统一卡片，控制器仍由原页面管理并释放。
class GamePanel extends StatelessWidget {
  /// 创建带开始、服务端返回与阶段反馈的演示主体。
  const GamePanel(
      {super.key,
      required this.game,
      required this.phase,
      required this.result,
      required this.start,
      required this.stop,
      this.tall = false});

  /// 是否使用纵向画布比例。
  final bool tall;

  /// 原页面创建的玩法画布。
  final Widget game;

  /// 当前控制器阶段。
  final ValueListenable<LuckyPhase> phase;

  /// 原页面记录的结果。
  final String result;

  /// 开始一轮演示。
  final VoidCallback start;

  /// 注入确定的模拟服务端结果。
  final VoidCallback stop;

  /// 显示操作反馈，阶段条件来自当前公开 API。
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: tall ? _tallPreviewHeight : _stageHeight,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                  width: _stageWidth,
                  height: tall ? _tallHeight : _stageWidth,
                  child: Center(child: game)),
            ),
          ),
          const SizedBox(height: DemoTokens.smallGap),
          ValueListenableBuilder<LuckyPhase>(
            valueListenable: phase,
            builder: (context, value, _) {
              final label = _phases[value];
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        spacing: DemoTokens.smallGap,
                        runSpacing: DemoTokens.smallGap,
                        children: [
                          FilledButton(
                              style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: DemoTokens.gap)),
                              onPressed: value.canPlay ? start : null,
                              child: Text(tr(context, 'Start', '开始'))),
                          OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: DemoTokens.gap)),
                              onPressed: value.canStop ? stop : null,
                              child:
                                  Text(tr(context, 'Server result', '服务端返回'))),
                        ]),
                    const SizedBox(height: DemoTokens.smallGap),
                    Semantics(
                        liveRegion: true,
                        child: Text(
                          result.trim().isNotEmpty &&
                                  value == LuckyPhase.settled
                              ? '${tr(context, 'Result: ', '结果：')}${result.split('\n').first.split(_resultSeparator).last}'
                              : tr(context, label?.$1 ?? value.name,
                                  label?.$2 ?? value.name),
                          style: Theme.of(context).textTheme.bodySmall,
                        )),
                  ]);
            },
          ),
        ],
      );
}
