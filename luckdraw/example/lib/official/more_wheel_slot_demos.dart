import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/wheel.dart';

import 'official_demo.dart';
import 'official_stage.dart';

/// 官方完整示例中的五个转盘与两个老虎机，保持官方卡片顺序。
final List<OfficialDemo> moreWheelSlotDemos = [
  OfficialDemo(
    id: 'more-wheel-zo',
    title: '仿中欧基金大转盘',
    refAsset: 'more_01',
    builder: (_) => OfficialWheel(
      width: 300,
      height: 300,
      stopIndex: () => 3,
      config: WheelConfig(
        blocks: [
          WheelBlock(images: [
            WheelBlockImage(officialImage('zo/bg3.png'),
                width: pct(100), rotate: true),
          ]),
        ],
        prizes: [
          for (final (text, image) in const [
            ('5888元', '0'),
            (' 20元', '4'),
            ('季卡', '5'),
            ('5元', '1'),
            ('10000元', '2'),
            (' 30天', '6'),
          ])
            WheelPrize(
              texts: [LuckyText(text, top: pct(36))],
              images: [
                LuckyImage(officialImage('zo/$image.png'),
                    width: pct(50), top: pct(55)),
              ],
            ),
        ],
        buttons: [
          WheelButton(
            radius: pct(25),
            texts: [
              LuckyText('立即\n抽奖',
                  color: hex('#fff'), top: pct(-50), fontSize: 16),
            ],
            images: [
              LuckyImage(officialImage('zo/btn2.png'),
                  width: pct(120), top: pct(-125)),
            ],
          ),
        ],
        style: WheelStyle(
            text: LuckyTextDefaults(
                color: hex('#913229'),
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        options: const WheelOptions(offsetDegree: -30),
      ),
    ),
  ),
  OfficialDemo(
    id: 'more-wheel-pdmm',
    title: '仿潘德妈妈大转盘',
    refAsset: 'more_02',
    builder: (_) => OfficialWheel(
      width: 300,
      height: 300,
      stopIndex: () => 0,
      stopDelay: const Duration(seconds: 2),
      config: WheelConfig(
        blocks: [
          WheelBlock(padding: 30, images: [
            WheelBlockImage(officialImage('pdmm/bg.png'),
                width: pct(100), height: pct(100), top: px(6)),
          ]),
          WheelBlock(padding: 3, background: fill('#a70c1b')),
        ],
        prizes: [
          for (var i = 0; i < 8; i++)
            WheelPrize(
              semanticsLabel: const ['谢谢参与', '红包', '抽奖次数+3', '礼物'][i % 4],
              background: fill(i.isEven ? '#ffd099' : '#fff'),
              texts: [
                LuckyText(const ['谢谢参与', '红包', '抽奖次数+3', '礼物'][i % 4],
                    top: pct(8)),
              ],
              images: [
                LuckyImage(officialImage('pdmm/0${i % 4 + 1}.png'),
                    width: pct(30), top: pct(30)),
              ],
            ),
        ],
        buttons: [
          WheelButton(radius: px(45), images: [
            LuckyImage(officialImage('pdmm/btn.png'),
                width: pct(102), top: pct(-127)),
          ]),
        ],
        style: WheelStyle(
            text: LuckyTextDefaults(color: hex('#a70c1b'), fontSize: 10)),
      ),
    ),
  ),
  OfficialDemo(
    id: 'more-wheel-jd',
    title: '仿京东大转盘抽京豆',
    refAsset: 'more_03',
    builder: (_) => OfficialWheel(
      width: 260,
      height: 260,
      stopIndex: () => Random().nextInt(8),
      stopDelay: const Duration(seconds: 2),
      config: WheelConfig(
        prizes: [
          for (var i = 0; i < 8; i++)
            WheelPrize(
              semanticsLabel: const ['10个京豆', '5个京豆', '1个京豆', '谢谢参与'][i % 4],
              background: fill(i.isEven ? '#F8DEF8' : '#FEF3FC'),
              texts: [
                LuckyText(const ['10个京豆', '5个京豆', '1个京豆', '谢谢参与'][i % 4],
                    top: pct(12)),
              ],
              images: [
                LuckyImage(officialImage('jd/${i % 4 == 3 ? 0 : 1}.png'),
                    width: pct(45), top: pct(35)),
              ],
            ),
        ],
        buttons: [
          WheelButton(radius: px(40), images: [
            LuckyImage(officialImage('jd/button.png'),
                width: pct(140), top: pct(-135)),
          ]),
        ],
        style: WheelStyle(
            text: LuckyTextDefaults(
                color: hex('#000'), fontSize: 13, fontFamily: 'SimHei')),
        options: const WheelOptions(offsetDegree: 22.5),
      ),
    ),
  ),
  OfficialDemo(
    id: 'more-wheel-xc',
    title: '仿携程转盘抽奖',
    refAsset: 'more_04',
    builder: (_) => OfficialWheel(
      width: 300,
      height: 300,
      stopIndex: () => Random().nextInt(6),
      config: WheelConfig(
        blocks: [
          WheelBlock(images: [
            WheelBlockImage(officialImage('xc/bg.png'),
                width: pct(100), rotate: true),
          ]),
        ],
        prizes: [
          for (final name in const [
            '免费住酒店',
            '房型升级',
            '免费取消',
            '延迟退房',
            '免费早餐',
            '明天再来',
          ])
            WheelPrize(semanticsLabel: name),
        ],
        buttons: [
          WheelButton(
            radius: pct(25),
            texts: [
              LuckyText('开始\n抽奖',
                  color: hex('#fff'), top: pct(-50), fontSize: 16),
            ],
            images: [
              LuckyImage(officialImage('xc/btn.png'),
                  width: pct(120), top: pct(-175)),
            ],
          ),
        ],
        options: const WheelOptions(offsetDegree: 0),
      ),
    ),
  ),
  OfficialDemo(
    id: 'more-wheel-bili',
    title: '仿bilibili抽奖',
    refAsset: 'more_05',
    builder: (_) => OfficialWheel(
      width: 300,
      height: 300,
      stopIndex: () => 5,
      config: WheelConfig(
        blocks: [
          WheelBlock(padding: 40, images: [
            WheelBlockImage(officialImage('bili/bg.png'), width: pct(100)),
          ]),
          WheelBlock(images: [
            WheelBlockImage(officialImage('bili/prize.png'),
                width: pct(100), rotate: true),
          ]),
          WheelBlock(images: [
            WheelBlockImage(officialImage('bili/point.png'),
                width: px(20), top: px(-25)),
          ]),
        ],
        prizes: [for (var i = 0; i < 6; i++) WheelPrize(semanticsLabel: '$i')],
        buttons: [
          WheelButton(radius: pct(48), images: [
            LuckyImage(officialImage('bili/btn.png'),
                width: pct(100), top: pct(-100)),
            LuckyImage(officialImage('bili/logo.png'),
                width: pct(70), top: pct(-70)),
          ]),
        ],
        options: const WheelOptions(
            offsetDegree: -30, motion: LuckyMotionOptions(speed: 10)),
      ),
    ),
  ),
  OfficialDemo(
    id: 'more-slot-dy',
    title: '仿抖音抽盲盒(老虎机)',
    refAsset: 'more_14',
    builder: (_) => OfficialSlot(
      width: 360,
      height: 260,
      autoPlay: true,
      config: SlotConfig(
        blocks: [
          LuckyBoxBlock(
            padding: const LuckyEdgeInsets.only(
                top: 108, right: 61, bottom: 52, left: 61),
            images: [
              LuckyImage(officialImage('dy/bgImg.png'), width: pct(100)),
            ],
          ),
        ],
        reels: const [
          SlotReel(order: [1, 2, 0, 3, 4, 5], speed: 1)
        ],
        prizes: [
          for (var i = 0; i < 6; i++)
            SlotPrize(images: [
              LuckyImage(officialImage('dy/prize.png'),
                  height: pct(100), formatter: (source) => _dySlice(source, i)),
            ]),
        ],
        options: const SlotOptions(
            mode: SlotMode.horizontal, rowSpacing: 0, colSpacing: -41),
      ),
      controls: (_, controller, start) =>
          _DyControls(controller: controller, start: start),
    ),
  ),
  OfficialDemo(
    id: 'more-slot-didi',
    title: '仿滴滴老虎机抽奖',
    refAsset: 'more_15',
    builder: (_) => OfficialSlot(
      width: 350,
      height: 250,
      stopIndex: () => 0,
      config: SlotConfig(
        blocks: [
          LuckyBoxBlock(images: [
            LuckyImage(officialImage('didi/area.png'),
                width: pct(71), height: px(110), top: pct(17)),
          ]),
          LuckyBoxBlock(
            padding: const LuckyEdgeInsets.only(
                top: 45, right: 55, bottom: 100, left: 55),
            images: [
              LuckyImage(officialImage('didi/bg.png'),
                  left: px(3), width: pct(100), height: pct(130), top: px(-35)),
            ],
          ),
        ],
        reels: const [
          SlotReel(order: [0, 1, 2], speed: 15),
          SlotReel(order: [2, 0, 1], speed: 15, direction: -1),
          SlotReel(order: [1, 2, 0], speed: 20),
        ],
        prizes: [
          for (var i = 0; i < 3; i++)
            SlotPrize(images: [
              LuckyImage(officialImage('didi/cell.png'),
                  width: pct(100), height: pct(100)),
              LuckyImage(officialImage('didi/$i.png'),
                  width: pct(i == 1 ? 70 : 80), top: pct(i == 1 ? 12 : 20)),
            ]),
        ],
        options: const SlotOptions(rowSpacing: 1, colSpacing: 6.5),
      ),
      overlay: (_, __, start) => _didiOverlay(start),
    ),
  ),
];

/// 按官方 Canvas formatter 将盲盒横向精灵图裁成六份。
Future<ui.Image> _dySlice(ui.Image source, int index) async {
  final sliceWidth = source.width / 6;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(source, ui.Offset(-sliceWidth * index, 0), ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(sliceWidth.toInt(), source.height);
  } finally {
    picture.dispose();
  }
}

/// 按滴滴 Vue 中按钮及文字的绝对定位坐标还原叠层。
Widget _didiOverlay(VoidCallback start) => Stack(children: [
      Positioned(
        left: 350 * .25,
        top: 250 * .70,
        width: 180,
        child: LayoutBuilder(builder: (_, constraints) {
          // 官方按钮素材为 340 × 79，文字百分比以按钮盒子的高度为基准。
          final height = constraints.maxWidth * 79 / 340;
          return SizedBox(
            height: height,
            child: Stack(children: [
              Image(image: officialImage('didi/btn.png'), width: 180),
              Positioned(
                left: 180 * .14,
                top: height * .17,
                child: GestureDetector(
                  onTap: start,
                  child: const Text('???\u2002\u2003开始抽奖',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          );
        }),
      ),
    ]);

/// 暴露抖音示例的 play、stop 方法及 isPlay 控制状态。
class _DyControls extends StatefulWidget {
  /// 创建控制区；自动播放不改变原始 isPlay 的初值。
  const _DyControls({required this.controller, required this.start});

  /// 舞台持有的老虎机控制器。
  final SlotController controller;

  /// 调用舞台的开始流程。
  final VoidCallback start;

  /// 创建控制状态。
  @override
  State<_DyControls> createState() => _DyControlsState();
}

/// 保存 Vue 的 isPlay，停止作废或游戏结束时复位。
class _DyControlsState extends State<_DyControls> {
  /// 与官方 data 中的 isPlay 初值一致。
  bool _isPlay = false;

  /// 监听结束阶段，对应官方 endCallback。
  @override
  void initState() {
    super.initState();
    widget.controller.phase.addListener(_onPhase);
  }

  /// 控制器替换时同步阶段监听。
  @override
  void didUpdateWidget(covariant _DyControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.phase.removeListener(_onPhase);
    widget.controller.phase.addListener(_onPhase);
  }

  /// 正常结束时恢复开始按钮，取消由 stop(-1) 立即恢复。
  void _onPhase() {
    if (widget.controller.phase.value == LuckyPhase.settled && _isPlay) {
      setState(() => _isPlay = false);
    }
  }

  /// 对应 play 方法：调用 play 后将 isPlay 设为 true。
  void _play() {
    widget.start();
    setState(() => _isPlay = true);
  }

  /// 对应 stop 方法，只有 -1 会立即清除 isPlay。
  void _stop(int index) {
    if (index == -1) setState(() => _isPlay = false);
    widget.controller.stop(index);
  }

  /// 将快照中的方法接到画布下方的外部控制按钮。
  @override
  Widget build(BuildContext context) => officialButtons([
        if (!_isPlay) ('开始', _play),
        if (_isPlay) ...[
          for (var i = 0; i < 6; i++) ('停止($i)', () => _stop(i)),
          ('取消', () => _stop(-1)),
        ],
      ]);

  /// 释放对舞台控制器的监听。
  @override
  void dispose() {
    widget.controller.phase.removeListener(_onPhase);
    super.dispose();
  }
}
