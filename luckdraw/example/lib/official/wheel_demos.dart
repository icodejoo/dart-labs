import 'package:flutter/material.dart';
import 'package:luckdraw/wheel.dart';

import 'official_demo.dart';
import 'official_stage.dart';

/// 官方「大转盘抽奖」页 19 个示例，顺序、标题与官方一致；`refAsset` 为 wheel_01…wheel_19。
final List<OfficialDemo> wheelDemos = [
  OfficialDemo(
      id: 'wheel-block-padding',
      title: '通过padding挤出边框',
      refAsset: 'wheel_01',
      builder: (_) => OfficialWheel(
              config: WheelConfig(blocks: [
            WheelBlock(padding: 10, background: fill('#617df2')),
            WheelBlock(padding: 10, background: fill('#869cfa')),
            WheelBlock(padding: 10, background: fill('#afc8ff')),
            WheelBlock(padding: 10, background: fill('#e9e8fe')),
          ]))),
  OfficialDemo(
      id: 'wheel-block-img',
      title: '使用图片作为背景',
      refAsset: 'wheel_02',
      builder: (_) => OfficialWheel(
              config: WheelConfig(blocks: [
            WheelBlock(images: [
              WheelBlockImage(officialImage('wheel-bg.png'),
                  width: pct(100), height: pct(100))
            ])
          ]))),
  OfficialDemo(
      id: 'wheel-block-border',
      title: '使用图片作为边框',
      refAsset: 'wheel_03',
      builder: (_) => OfficialWheel(
              config: WheelConfig(blocks: [
            _imageBlock('wheel-border.jpg', padding: 12),
            _imageBlock('wheel-bg.png'),
          ]))),
  OfficialDemo(
      id: 'wheel-block-borders',
      title: '设置多个图片作为边框',
      refAsset: 'wheel_04',
      builder: (_) => OfficialWheel(
              config: WheelConfig(blocks: [
            _imageBlock('wheel-border.jpg', padding: 12),
            _imageBlock('wheel-border.png', padding: 10),
            _imageBlock('wheel-bg.png'),
          ]))),
  // 差异：WheelPrize 没有 JS 自定义 title 元数据字段，改用 semanticsLabel 保存编号，不绘制文字。
  OfficialDemo(
      id: 'wheel-block-rotate',
      title: '设置背景图片跟随旋转',
      refAsset: 'wheel_05',
      builder: (_) => OfficialWheel(
          width: 240,
          height: 240,
          autoPlay: true,
          config: WheelConfig(
              blocks: [
                const WheelBlock(padding: 20),
                WheelBlock(padding: 20, images: [
                  WheelBlockImage(officialImage('block-img.png'),
                      width: pct(100), rotate: true),
                ]),
              ],
              prizes: [
                for (var i = 0; i < 8; i++) WheelPrize(semanticsLabel: '$i'),
              ],
              options:
                  const WheelOptions(motion: LuckyMotionOptions(speed: 1))))),
  OfficialDemo(
      id: 'wheel-prize-background',
      title: '设置扇形区域的背景颜色',
      refAsset: 'wheel_06',
      builder: (_) => OfficialWheel(
          config: WheelConfig(
              blocks: [_border()],
              prizes: _alternatingPrizes(
                  evenColor: '#afc8ff', oddColor: '#fff7a2')))),
  OfficialDemo(
      id: 'wheel-prize-font',
      title: '设置奖品文字',
      refAsset: 'wheel_07',
      builder: (_) => OfficialWheel(
          config: WheelConfig(
              blocks: [_border()],
              prizes: _alternatingPrizes(numbered: true, textTop: pct(10))))),
  OfficialDemo(
      id: 'wheel-prize-fonts',
      title: '设置多行奖品文字',
      refAsset: 'wheel_08',
      builder: (_) => OfficialWheel(
          width: 300,
          height: 300,
          config: WheelConfig(
              blocks: [
                _border()
              ],
              prizes: [
                WheelPrize(texts: [
                  LuckyText('洗碗机', top: pct(10), fontSize: 24),
                  LuckyText('剩余23', top: pct(40)),
                ]),
                _thanksPrize(),
                WheelPrize(texts: [
                  LuckyText('特斯拉',
                      top: pct(10),
                      fontSize: 24,
                      color: hex('#ff0000'),
                      fontWeight: FontWeight.w700),
                  LuckyText('剩余1', top: pct(40)),
                ]),
                _thanksPrize(),
                WheelPrize(texts: [
                  LuckyText('颐和园门票', top: pct(10), fontSize: 20),
                  LuckyText('剩余99', top: pct(40)),
                ]),
                _thanksPrize(),
              ],
              style: WheelStyle(background: fill('#e9e8fe')),
              options: const WheelOptions(gutter: 2)))),
  OfficialDemo(
      id: 'wheel-prize-wordWrap',
      title: '设置奖品文字换行',
      refAsset: 'wheel_09',
      builder: (_) => OfficialWheel(
              config: WheelConfig(
                  blocks: [
                _border()
              ],
                  prizes: [
                WheelPrize(background: fill('#e9e8fe'), texts: [
                  LuckyText('当文字超长之后就会自动进行换行', top: px(10)),
                ]),
                WheelPrize(background: fill('#b8c5f2')),
                WheelPrize(background: fill('#e9e8fe'), texts: [
                  LuckyText('这段文字则不会自动换行', top: px(10), wordWrap: false),
                ]),
                WheelPrize(background: fill('#b8c5f2')),
              ],
                  style: WheelStyle(
                      text: LuckyTextDefaults(lengthLimit: pct(80)))))),
  OfficialDemo(
      id: 'wheel-prize-lineClamp',
      title: '设置奖品文字溢出隐藏',
      refAsset: 'wheel_10',
      builder: (_) => OfficialWheel(
              config: WheelConfig(
                  blocks: [
                _border()
              ],
                  prizes: [
                WheelPrize(background: fill('#e9e8fe'), texts: [
                  LuckyText('设置文字超出3行自动隐藏', top: px(10), lineClamp: 3),
                ]),
                WheelPrize(background: fill('#b8c5f2'), texts: [
                  LuckyText('设置文字超出2行自动隐藏', top: px(10), lineClamp: 2),
                ]),
                WheelPrize(background: fill('#e9e8fe'), texts: [
                  LuckyText('设置文字超出1行自动隐藏', top: px(10), lineClamp: 1),
                ]),
                WheelPrize(background: fill('#b8c5f2'), texts: [
                  LuckyText('默认情况下不会自动隐藏', top: px(10)),
                ]),
              ],
                  style: WheelStyle(
                      text: LuckyTextDefaults(lengthLimit: pct(80)))))),
  OfficialDemo(
      id: 'wheel-prize-img',
      title: '设置奖品图片',
      refAsset: 'wheel_11',
      builder: (_) => OfficialWheel(
          config: WheelConfig(
              blocks: [_border()],
              prizes: _alternatingPrizes(images: [
                LuckyImage(officialImage('prize.png'),
                    width: pct(40), top: pct(10)),
              ])))),
  OfficialDemo(
      id: 'wheel-default-gutter',
      title: '设置扇形之间的缝隙',
      refAsset: 'wheel_12',
      builder: (_) => OfficialWheel(
          config: WheelConfig(
              blocks: [_border('#617df2')],
              prizes: _alternatingPrizes(),
              options: const WheelOptions(gutter: 5)))),
  OfficialDemo(
      id: 'wheel-btn-radius',
      title: '设置抽奖按钮',
      refAsset: 'wheel_13',
      builder: (_) => OfficialWheel(
          stopIndex: () => 0,
          config: WheelConfig(
              blocks: [_border('#617df2')],
              prizes: _alternatingPrizes(),
              buttons: _layeredButtons()))),
  OfficialDemo(
      id: 'wheel-btn-pointer',
      title: '带指针的抽奖按钮',
      refAsset: 'wheel_14',
      builder: (_) => OfficialWheel(
          stopIndex: () => 0,
          config: WheelConfig(
              blocks: [_border('#617df2')],
              prizes: _alternatingPrizes(),
              buttons: _layeredButtons(pointer: true)))),
  OfficialDemo(
      id: 'wheel-btn-img',
      title: '使用图片作为抽奖按钮',
      refAsset: 'wheel_15',
      builder: (_) => OfficialWheel(
          stopIndex: () => 0,
          config: WheelConfig(
              blocks: [_border('#617df2')],
              prizes: _alternatingPrizes(),
              buttons: [
                WheelButton(radius: pct(45), images: [
                  LuckyImage(officialImage('wheel-btn.png'),
                      width: pct(100), top: pct(-130)),
                ]),
              ]))),
  OfficialDemo(
      id: 'wheel-btn-dom',
      title: '使用Dom作为抽奖按钮',
      refAsset: 'wheel_16',
      builder: (_) => OfficialWheel(
          stopIndex: () => 0,
          config: WheelConfig(
              blocks: [_border('#617df2')], prizes: _alternatingPrizes()),
          overlay: (_, __, start) => Center(
              child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                      onTap: start,
                      child: Container(
                          width: 50,
                          height: 50,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: hex('#6a5acd'),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Text('开始',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  height: 1)))))))),
  OfficialDemo(
      id: 'wheel-default-stopRange',
      title: '指针在扇形50%区域内随机停止',
      refAsset: 'wheel_17',
      builder: (_) => OfficialWheel(
          stopIndex: () => 0,
          stopDelay: const Duration(seconds: 1),
          config: WheelConfig(
              blocks: [_border()],
              prizes: _alternatingPrizes(numbered: true),
              options: const WheelOptions(stopRange: 0.8)),
          controls: (_, __, start) => officialButtons([('开始', start)]))),
  OfficialDemo(
      id: 'wheel-default-speed',
      title: '设置抽奖的旋转速度',
      refAsset: 'wheel_18',
      builder: (_) => OfficialWheel(
          autoPlay: true,
          config: WheelConfig(
              blocks: [_border()],
              prizes: _alternatingPrizes(),
              options:
                  const WheelOptions(motion: LuckyMotionOptions(speed: 8))))),
  OfficialDemo(
      id: 'wheel-demo',
      title: '控制游戏的开始和结束',
      refAsset: 'wheel_19',
      builder: (_) => OfficialWheel(
          stopIndex: () => 0,
          stopDelay: const Duration(seconds: 1),
          config: WheelConfig(
              blocks: [_border()],
              prizes: _alternatingPrizes(numbered: true),
              buttons: [
                WheelButton(radius: pct(40), background: fill('#617df2')),
                WheelButton(radius: pct(35), background: fill('#afc8ff')),
                WheelButton(
                    radius: pct(30),
                    background: fill('#869cfa'),
                    pointer: true,
                    texts: [LuckyText('开始', top: px(-10))]),
              ]))),
];

/// 铺满所在圆环的背景图片，可用内边距露出边框。
WheelBlock _imageBlock(String name, {double padding = 0}) =>
    WheelBlock(padding: padding, images: [
      WheelBlockImage(officialImage(name), width: pct(100), height: pct(100)),
    ]);

/// 基础示例共用的十像素纯色外边框。
WheelBlock _border([String color = '#869cfa']) =>
    WheelBlock(padding: 10, background: fill(color));

/// 六个交替背景色奖品，按需附加编号或同一张奖品图片。
List<WheelPrize> _alternatingPrizes(
        {String evenColor = '#e9e8fe',
        String oddColor = '#b8c5f2',
        bool numbered = false,
        LuckyLength? textTop,
        List<LuckyImage> images = const []}) =>
    [
      for (var i = 0; i < 6; i++)
        WheelPrize(
            background: fill(i.isEven ? evenColor : oddColor),
            texts: [if (numbered) LuckyText('$i', top: textTop)],
            images: images),
    ];

/// 多行奖品示例中重复出现的灰色「谢谢参与」。
WheelPrize _thanksPrize() => WheelPrize(texts: [
      LuckyText('谢谢参与', top: pct(10), fontSize: 24, color: hex('#aaa')),
    ]);

/// 半径依次为奖品区 50%、45%、40% 的三层按钮。
List<WheelButton> _layeredButtons({bool pointer = false}) => [
      WheelButton(radius: pct(50), background: fill('#617df2')),
      WheelButton(radius: pct(45), background: fill('#afc8ff')),
      WheelButton(
          radius: pct(40),
          background: fill('#869cfa'),
          pointer: pointer,
          texts: [LuckyText('开始\n抽奖', top: px(-20))]),
    ];
