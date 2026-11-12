import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:luckdraw/slot.dart';

import 'official_demo.dart';
import 'official_stage.dart';

/// 官方「老虎机抽奖」的 17 个基础示例，顺序及标题与官方页面一致。
final List<OfficialDemo> slotDemos = [
  OfficialDemo(
      id: 'slot-block-padding',
      title: '通过padding挤出边框',
      refAsset: 'slot_01',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(blocks: [
            for (final color in ['#617df2', '#869cfa', '#afc8ff', '#e9e8fe'])
              LuckyBoxBlock(
                  padding: const LuckyEdgeInsets.all(10),
                  background: fill(color)),
          ]))),
  OfficialDemo(
      id: 'slot-block-borderRadius',
      title: '设置边框圆角',
      refAsset: 'slot_02',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(blocks: [
            for (final (color, radius) in [
              ('#617df2', 10.0),
              ('#869cfa', 30.0),
              ('#afc8ff', 50.0),
              ('#e9e8fe', double.infinity),
            ])
              LuckyBoxBlock(
                  padding: const LuckyEdgeInsets.all(10),
                  background: fill(color),
                  borderRadius: radius),
          ]))),
  OfficialDemo(
      id: 'slot-block-img',
      title: '使用图片作为背景',
      refAsset: 'slot_03',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(blocks: [
            LuckyBoxBlock(images: [
              LuckyImage(officialImage('slot-bg.png'),
                  width: pct(100), height: pct(100)),
            ]),
          ]))),
  OfficialDemo(
      id: 'slot-prize-borderRadius',
      title: '设置格子圆角',
      refAsset: 'slot_04',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotCyclicOrders,
              prizes: [
                for (final radius in [0.0, 20.0, double.infinity])
                  SlotPrize(background: fill('#bac5ee'), borderRadius: radius),
              ],
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-prize-background',
      title: '设置格子背景颜色',
      refAsset: 'slot_05',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotCyclicOrders,
              prizes: [
                for (final color in ['#b6c8f6', '#8c9eed', '#6980e3'])
                  SlotPrize(background: fill(color), borderRadius: 10),
              ],
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-prize-font',
      title: '设置奖品文字',
      refAsset: 'slot_06',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [
                SlotReel(order: [1, 0, 1]),
                SlotReel(order: [1, 0, 1]),
                SlotReel(order: [0, 1, 0]),
              ],
              prizes: [
                for (final text in ['6', '9'])
                  SlotPrize(texts: [LuckyText(text, top: pct(15))]),
              ],
              style: _slotNumberStyle(),
              options: const SlotOptions(rowSpacing: 25, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-prize-wordWrap',
      title: '设置奖品文字换行',
      refAsset: 'slot_07',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotSingleOrders,
              prizes: const [
                SlotPrize(texts: [LuckyText('自动换行')]),
                SlotPrize(texts: [LuckyText('手动\n换行', wordWrap: false)]),
                SlotPrize(texts: [LuckyText('不换行', wordWrap: false)]),
              ],
              style:
                  SlotStyle(cell: LuckyCellStyle(background: fill('#b8c5f2'))),
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-prize-lineClamp',
      title: '设置奖品文字溢出隐藏',
      refAsset: 'slot_08',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotSingleOrders,
              prizes: const [
                SlotPrize(texts: [LuckyText('超出2行自动隐藏', lineClamp: 2)]),
                SlotPrize(texts: [LuckyText('超出1行自动隐藏', lineClamp: 1)]),
                SlotPrize(texts: [LuckyText('不会自动隐藏')]),
              ],
              style:
                  SlotStyle(cell: LuckyCellStyle(background: fill('#b8c5f2'))),
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-prize-img',
      title: '设置奖品图片',
      refAsset: 'slot_09',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotDifferentSpeeds,
              prizes: [
                for (final image in ['prize.png', 'active.png'])
                  SlotPrize(
                      background: fill('#bac5ee'),
                      borderRadius: 10,
                      images: [
                        LuckyImage(officialImage(image),
                            width: pct(60), top: pct(20)),
                      ]),
              ],
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-prize-bgImg',
      title: '设置格子的背景图片',
      refAsset: 'slot_10',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotDifferentSpeeds,
              prizes: [
                for (final image in ['prize.png', 'active.png'])
                  SlotPrize(images: [
                    LuckyImage(officialImage('cell-80.png'),
                        width: pct(100), height: pct(100)),
                    LuckyImage(officialImage(image),
                        width: pct(60), top: pct(20)),
                  ]),
              ],
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-slot-speed',
      title: '设置不同插槽的转速',
      refAsset: 'slot_11',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          autoPlay: true,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: _slotDifferentSpeeds,
              prizes: _slotPlainPrizes(),
              options: const SlotOptions(rowSpacing: 20, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-slot-direction',
      title: '设置不同插槽的旋转方向',
      refAsset: 'slot_12',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          autoPlay: true,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [
                SlotReel(speed: 3, direction: 1),
                SlotReel(speed: 3, direction: -1),
                SlotReel(speed: 3, direction: 1),
              ],
              prizes: _slotPlainPrizes(),
              options: const SlotOptions(rowSpacing: 20, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-slot-length',
      title: '设置5列插槽',
      refAsset: 'slot_13',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          autoPlay: true,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [
                SlotReel(speed: 1),
                SlotReel(speed: 2),
                SlotReel(speed: 3),
                SlotReel(speed: 2),
                SlotReel(speed: 1),
              ],
              prizes: _slotPlainPrizes(),
              options: const SlotOptions(rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-defaultConfig-rowSpacing',
      title: '设置奖品的行间距',
      refAsset: 'slot_14',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [SlotReel(), SlotReel(), SlotReel()],
              prizes: _slotPlainPrizes(),
              options: const SlotOptions(rowSpacing: 30)))),
  OfficialDemo(
      id: 'slot-defaultConfig-colSpacing',
      title: '设置奖品的列间距',
      refAsset: 'slot_15',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          autoPlay: true,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [SlotReel(), SlotReel(), SlotReel()],
              prizes: _slotPlainPrizes(),
              options: const SlotOptions(rowSpacing: 5, colSpacing: 40)))),
  OfficialDemo(
      id: 'slot-defaultConfig-mode',
      title: '设置为横向旋转模式',
      refAsset: 'slot_16',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          autoPlay: true,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [
                SlotReel(speed: 5),
                SlotReel(speed: 1),
                SlotReel(speed: 5),
              ],
              prizes: _slotPlainPrizes(),
              options: const SlotOptions(
                  mode: SlotMode.horizontal, rowSpacing: 10, colSpacing: 10)))),
  OfficialDemo(
      id: 'slot-demo',
      title: '控制游戏的开始和结束',
      refAsset: 'slot_17',
      builder: (_) => OfficialSlot(
          width: 240,
          height: 180,
          config: SlotConfig(
              blocks: _slotBlocks(),
              reels: const [
                SlotReel(order: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], direction: 1),
                SlotReel(order: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0], direction: -1),
                SlotReel(order: [2, 3, 4, 5, 6, 7, 8, 9, 0, 1], direction: 1),
              ],
              prizes: [
                for (var index = 0; index < 10; index++)
                  SlotPrize(texts: [LuckyText('$index', top: pct(15))]),
              ],
              style: _slotNumberStyle(),
              options: const SlotOptions(rowSpacing: 20, colSpacing: 10)),
          controls: (_, controller, start) =>
              _SlotDemoLoop(controller: controller, start: start))),
];

/// 官方多数示例共用的两层十像素边框。
List<LuckyBoxBlock> _slotBlocks() => [
      for (final color in ['#869cfa', '#e9e8fe'])
        LuckyBoxBlock(
            padding: const LuckyEdgeInsets.all(10), background: fill(color)),
    ];

/// 圆角和底色示例中三列各自的奖品顺序。
const List<SlotReel> _slotCyclicOrders = [
  SlotReel(order: [0, 1, 2]),
  SlotReel(order: [2, 0, 1]),
  SlotReel(order: [1, 2, 0]),
];

/// 换行和行数限制示例中每列仅有一个奖品。
const List<SlotReel> _slotSingleOrders = [
  SlotReel(order: [0]),
  SlotReel(order: [1]),
  SlotReel(order: [2]),
];

/// 图片和转速示例的三个原始速度。
const List<SlotReel> _slotDifferentSpeeds = [
  SlotReel(speed: 1),
  SlotReel(speed: 4),
  SlotReel(speed: 20),
];

/// 运动和间距示例共用的两个浅蓝色圆角格子。
List<SlotPrize> _slotPlainPrizes() => [
      for (var index = 0; index < 2; index++)
        SlotPrize(background: fill('#bac5ee'), borderRadius: 10),
    ];

/// 数字奖品共用的圆形底色和三十二像素深灰文字。
SlotStyle _slotNumberStyle() => SlotStyle(
    cell: LuckyCellStyle(
        background: fill('#bac5ee'), borderRadius: double.infinity),
    text: LuckyTextDefaults(fontSize: 32, color: hex('#333')));

/// 在舞台控制区复现官方末项的自动开始、逐列停止和六秒循环。
class _SlotDemoLoop extends StatefulWidget {
  /// 使用舞台提供的控制器和开始回调。
  const _SlotDemoLoop({required this.controller, required this.start});

  /// 舞台持有的老虎机控制器。
  final SlotController controller;

  /// 舞台的开始回调。
  final VoidCallback start;

  /// 创建随控制区销毁的循环状态。
  @override
  State<_SlotDemoLoop> createState() => _SlotDemoLoopState();
}

/// 以帧时钟实现网页的定时演示，离开条目时一并释放。
class _SlotDemoLoopState extends State<_SlotDemoLoop>
    with SingleTickerProviderStateMixin {
  /// 官方随机选择的四组结果，顺序及数值保持不变。
  static const List<List<int>> _results = [
    [9, 9, 6],
    [0, 0, 7],
    [6, 6, 6],
    [8, 8, 8],
  ];

  /// 模拟 Math.random 的随机源。
  final Random _random = Random();

  /// 负责五百毫秒停止及六秒重播的帧时钟。
  late final Ticker _ticker;

  /// 下一次开始的时间点。
  Duration _nextPlay = const Duration(seconds: 6);

  /// 当前局的停止时间点；停止后清空。
  Duration? _stopAt = const Duration(milliseconds: 500);

  /// 等舞台挂接控制器后立即开始首轮演示。
  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.start();
      _ticker.start();
    });
  }

  /// 按官方间隔开始游戏，延时后随机选择一组三列目标。
  void _tick(Duration elapsed) {
    if (elapsed >= _nextPlay) {
      widget.start();
      _nextPlay = elapsed + const Duration(seconds: 6);
      _stopAt = elapsed + const Duration(milliseconds: 500);
    }
    final stopAt = _stopAt;
    if (stopAt != null && elapsed >= stopAt) {
      widget.controller.stopEach(_results[_random.nextInt(4)]);
      _stopAt = null;
    }
  }

  /// 官方此项没有外部 DOM 按钮，控制区仅承载循环行为。
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  /// 离开条目时停止并释放演示时钟。
  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
