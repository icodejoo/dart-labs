import 'dart:math';

import 'package:flutter/material.dart';
import 'package:luckdraw/grid.dart';

import 'official_demo.dart';
import 'official_stage.dart';

/// 官方完整示例中的八个九宫格，顺序对应 more_06 至 more_13。
final List<OfficialDemo> moreGridDemos = [
  OfficialDemo(
      id: 'more-grid-dy',
      title: '仿抖音九宫格抽奖',
      refAsset: 'more_06',
      builder: (_) => OfficialGrid(
          stopIndex: () => 0,
          overlay: (_, __, start) => Stack(children: [
                Positioned(
                    left: 150,
                    top: 150,
                    width: 84,
                    height: 84,
                    child: FractionalTranslation(
                        translation: const Offset(-0.5, -0.53),
                        child: GestureDetector(
                            onTap: start,
                            child: Image(
                                image: officialImage('dy/btn.gif'),
                                semanticLabel: '开始抽奖')))),
              ]),
          config: GridConfig(
              blocks: [
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(10),
                    background: fill('#006bff'),
                    borderRadius: 10),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(1),
                    background: fill('#000000'),
                    borderRadius: 10),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(5),
                    background: fill('#1551c1'),
                    borderRadius: 10),
              ],
              prizes: _perimeterPrizes((x, y, index) => GridPrize(
                  x: x,
                  y: y,
                  images: [_fullCellImage('dy/$index.png', top: px(1))])),
              style: const GridStyle(
                  cell: LuckyCellStyle(
                      background: LuckyFill.color(Colors.transparent),
                      borderRadius: 5)),
              activeStyle: LuckyCellStyle(background: fill('#27c2b0'))))),
  OfficialDemo(
      id: 'more-grid-wyyx',
      title: '仿网易严选九宫格',
      refAsset: 'more_07',
      builder: (_) => OfficialGrid(
          height: 310,
          stopIndex: _randomEight,
          stopDelay: const Duration(seconds: 2),
          config: GridConfig(
              blocks: [
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(1),
                    background: fill('#e2cea3'),
                    borderRadius: 13),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.symmetric(vertical: 5),
                    background: fill('#f3ecdc'),
                    borderRadius: 13),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(1),
                    background: fill('#e2cea3'),
                    borderRadius: 8),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(10),
                    background: fill('#fffcf5'),
                    borderRadius: 8),
              ],
              prizes: _perimeterPrizes((x, y, index) => GridPrize(
                      x: x,
                      y: y,
                      images: [
                        _fullCellImage('yx/default-$index.png',
                            activeSource: 'yx/active-$index.png')
                      ])),
              buttons: [
                GridButton(x: 1, y: 1, style: _transparentCell, images: [
                  GridImage(officialImage('yx/btn.png'),
                      width: pct(90), top: pct(5))
                ])
              ],
              style: GridStyle(
                  cell: LuckyCellStyle(
                      background: fill('#ffefd6'), borderRadius: 5),
                  text: LuckyTextDefaults(
                      color: hex('#755c28'), fontSize: 10, lineHeight: 12)),
              activeStyle: LuckyCellStyle(
                  background: fill('#de7247'),
                  text: LuckyTextOverride(color: hex('#ffefd6')))))),
  OfficialDemo(
      id: 'more-grid-wyyyx',
      title: '仿网易云游戏九宫格',
      refAsset: 'more_08',
      builder: (_) => OfficialGrid(
          stopIndex: _randomEight,
          stopDelay: const Duration(seconds: 2),
          config: GridConfig(
              blocks: [
                _domBackdrop('yyx/bg.png'),
                const LuckyBoxBlock(
                    padding: LuckyEdgeInsets.all(10),
                    background: LuckyFill.color(Colors.transparent),
                    borderRadius: 10),
              ],
              prizes: _cloudGamePrizes(),
              buttons: [
                GridButton(x: 1, y: 1, style: _transparentCell, texts: [
                  LuckyText('剩余次数:???次', color: hex('#ca620d'), top: pct(75))
                ], images: [
                  GridImage(officialImage('yyx/btn.png'),
                      width: pct(100), top: px(0))
                ])
              ],
              style: GridStyle(
                  text: LuckyTextDefaults(
                      color: hex('#AFFFD7'),
                      fontSize: 10,
                      lineHeight: 13,
                      wordWrap: false)),
              activeStyle: LuckyCellStyle(
                  background: const GridConfig().activeStyle.background,
                  text: LuckyTextOverride(color: hex('#fff')))))),
  OfficialDemo(
      id: 'more-grid-xdf',
      title: '仿新东方小程序抽奖',
      refAsset: 'more_09',
      builder: (_) => OfficialGrid(
          stopIndex: _randomEight,
          config: GridConfig(
              blocks: [
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(3),
                    background: fill('#92c53a'),
                    borderRadius: 8),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(2),
                    background: fill('#bdd333'),
                    borderRadius: 8),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(7),
                    background: fill('#0D6630'),
                    borderRadius: 8),
              ],
              prizes: _xdfPrizes(),
              buttons: [
                GridButton(
                    x: 1,
                    y: 1,
                    // 官方 shadow: '' 按兼容映射回退到默认阴影。
                    style: const LuckyCellStyle(),
                    images: [
                      GridImage(officialImage('xdf/button.png'),
                          width: pct(100), height: pct(112))
                    ])
              ],
              options: const GridOptions(gutter: 8),
              style: GridStyle(
                  cell: LuckyCellStyle(
                      background: fill('#f4f7cc'),
                      borderRadius: 13,
                      shadow: LuckyShadow(
                          offsetY: 9,
                          blur: 0.1,
                          color: hex('#E9E967'),
                          blurSpace: LuckyShadowBlurSpace.device)),
                  text: LuckyTextDefaults(color: hex('#d55a07'), fontSize: 11)),
              activeStyle: LuckyCellStyle(
                  background: fill('#e9e967'),
                  shadow: LuckyShadow(
                      offsetY: 9,
                      blur: 0.1,
                      color: hex('#E1E13B'),
                      blurSpace: LuckyShadowBlurSpace.device))))),
  OfficialDemo(
      id: 'more-grid-xq',
      title: '仿雪球九宫格抽奖',
      refAsset: 'more_10',
      builder: (_) => OfficialGrid(
          stopIndex: _randomEight,
          stopDelay: const Duration(seconds: 2),
          config: GridConfig(
              blocks: [
                _domBackdrop('xq/bg.png'),
                const LuckyBoxBlock(padding: LuckyEdgeInsets.all(15)),
              ],
              prizes: _perimeterPrizes((x, y, index) => GridPrize(
                      x: x,
                      y: y,
                      images: [
                        _fullCellImage('xq/$index.png',
                            activeSource: 'xq/a$index.png')
                      ])),
              buttons: [
                GridButton(
                    x: 1,
                    y: 1,
                    style: _transparentCell,
                    images: [_fullCellImage('xq/btn.png')])
              ],
              options: const GridOptions(gutter: 10)))),
  OfficialDemo(
      id: 'more-grid-hwl',
      title: '仿好未来九宫格抽奖',
      refAsset: 'more_11',
      builder: (_) => OfficialGrid(
          stopIndex: _randomEight,
          stopDelay: const Duration(seconds: 2),
          config: GridConfig(
              blocks: [
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(10),
                    background: fill('#faeecb')),
                LuckyBoxBlock(
                    padding: const LuckyEdgeInsets.all(10),
                    background: fill('#eec578')),
              ],
              prizes: _hwlPrizes(),
              buttons: [
                GridButton(
                    x: 1,
                    y: 1,
                    style: _transparentCell,
                    images: [_fullCellImage('hwl/btn.png')])
              ],
              style: GridStyle(
                  text: LuckyTextDefaults(
                      color: hex('#ac804f'), fontSize: 10))))),
  // 差异：官方 60×60 配合默认 gutter=5 产生负基础格宽高，luckdraw 不支持；示例等价换算为无缝整数细网格。
  OfficialDemo(
      id: 'more-grid-round',
      title: '仿咸鱼游戏圆形九宫格',
      refAsset: 'more_12',
      builder: (_) => OfficialGrid(
          // 官方虽有十二个奖品，停止回调仍只随机选取前八个。
          stopIndex: _randomEight,
          stopDelay: const Duration(seconds: 2),
          config: _roundGridConfig())),
  OfficialDemo(
      id: 'more-grid-yqs',
      title: '仿艺气山九宫格抽奖',
      refAsset: 'more_13',
      builder: (_) => OfficialGrid(
          stopIndex: _randomEight,
          stopDelay: const Duration(seconds: 2),
          config: GridConfig(
              blocks: [
                LuckyBoxBlock(padding: const LuckyEdgeInsets.all(15), images: [
                  LuckyImage(officialImage('yqs/bg.png'),
                      width: pct(100), height: pct(100))
                ])
              ],
              prizes: _perimeterPrizes((x, y, index) => GridPrize(
                      x: x,
                      y: y,
                      images: [
                        _fullCellImage('yqs/prize$index.png',
                            activeSource: 'yqs/prize$index-on.png')
                      ])),
              buttons: [
                GridButton(
                    x: 1,
                    y: 1,
                    style: _transparentCell,
                    images: [_fullCellImage('yqs/start-btn.png')])
              ],
              options: const GridOptions(gutter: -15),
              activeStyle: _transparentCell))),
];

/// 官方 rgba(0, 0, 0, 0) 的透明格子背景。
const LuckyCellStyle _transparentCell =
    LuckyCellStyle(background: LuckyFill.color(Colors.transparent));

/// 官方八格顺时针排列，从左上角开始。
const List<(int, int)> _perimeter = [
  (0, 0),
  (1, 0),
  (2, 0),
  (2, 1),
  (2, 2),
  (1, 2),
  (0, 2),
  (0, 1),
];

/// 对应官方 Math.random() * 8 >> 0。
int _randomEight() => Random().nextInt(8);

/// 按官方顺时针坐标生成八个奖品。
List<GridPrize> _perimeterPrizes(
        GridPrize Function(int x, int y, int index) build) =>
    [
      for (var i = 0; i < _perimeter.length; i++)
        build(_perimeter[i].$1, _perimeter[i].$2, i),
    ];

/// 铺满格子的图片，激活态仍使用同一组尺寸与偏移。
GridImage _fullCellImage(String source,
        {String? activeSource, LuckyLength? top}) =>
    GridImage(officialImage(source),
        activeImage: activeSource == null ? null : officialImage(activeSource),
        width: pct(100),
        height: pct(100),
        top: top);

/// 将官方外层 DOM 的底色、圆角和背景图放入零内边距的底层块。
LuckyBoxBlock _domBackdrop(String source) =>
    LuckyBoxBlock(background: fill('#132122'), borderRadius: 8, images: [
      LuckyImage(officialImage(source),
          width: pct(100), height: pct(100), borderRadius: 8)
    ]);

/// 网易云游戏的八个奖品，保留重复图片和两处换行。
List<GridPrize> _cloudGamePrizes() {
  const names = [
    'steam游戏任选\n(限款)',
    '百元京东卡',
    '暴雪游戏30点数',
    '云币2888',
    '手游月卡',
    '连续3日\n手游时长+1h',
    '手游时长+30min',
    '端游时长+1h',
  ];
  const imageNumbers = [1, 2, 3, 4, 5, 6, 6, 7];
  return _perimeterPrizes((x, y, index) => GridPrize(x: x, y: y, texts: [
        LuckyText(names[index], top: pct(index == 0 || index == 5 ? 60 : 69))
      ], images: [
        _fullCellImage('yyx/cell.png', activeSource: 'yyx/active.png'),
        GridImage(officialImage('yyx/${imageNumbers[index]}.png'),
            width: pct(70), top: pct(3)),
      ]));
}

/// 新东方重复两轮的四种奖品。
List<GridPrize> _xdfPrizes() {
  const names = ['谢谢参与', '1个星球币', '5个星球币', '10个星球币'];
  return _perimeterPrizes((x, y, index) => GridPrize(x: x, y: y, texts: [
        LuckyText(names[index % 4], top: pct(68))
      ], images: [
        GridImage(officialImage('xdf/${index % 4 == 0 ? 0 : 1}.png'),
            width: pct(50), top: pct(12))
      ]));
}

/// 好未来的奖品底图、激活图、文字及前景图片。
List<GridPrize> _hwlPrizes() {
  const names = [
    '二次元时钟',
    '航天计时器',
    '航天钥匙链',
    '航天勋章',
    '谢谢参与',
    '10金币',
    '小猴毛绒玩具',
    '神秘大礼',
  ];
  return _perimeterPrizes((x, y, index) => GridPrize(x: x, y: y, texts: [
        LuckyText(names[index], top: pct(67))
      ], images: [
        _fullCellImage('hwl/cell.png', activeSource: 'hwl/active.png'),
        GridImage(officialImage('hwl/$index.png'),
            width: pct(50), top: pct(15)),
      ]));
}

/// 将官方圆周奖品和中央按钮等价换算到无缝整数细网格。
GridConfig _roundGridConfig() {
  /// 官方网格的行列数。
  const divisions = 60;

  /// 三百像素画布扣除两侧各四十五像素内边距后的边长。
  const area = 300 - 2 * 45;

  /// 官方未显式配置的默认间隙。
  const gutter = 5;

  // 官方基础格宽高 w = (210 - 5 * 59) / 60 = -85 / 60。
  // 坐标步长 w + gutter = (area + gutter) / divisions = 215 / 60。
  // 新网格行列数 = area * divisions = 12600，gutter=0，每单位 1/60px。
  // 原 x、y 分别乘 215：45 + x' / 60 = 45 + x * (w + gutter)，y 同理。
  /// 将官方横纵坐标换算为整数细网格坐标。
  int coordinate(int value) => value * (area + gutter);

  // 原 col、row 分别换算为 n' = n * 215 - 5 * 60：
  // n' / 60 = n * (w + gutter) - gutter = n * w + (n - 1) * gutter。
  // 奖品跨度 12 → 2280 单位，即 38px；按钮跨度 36 → 7440 单位，即 124px。
  // 按钮原坐标 (12,12) → (2580,2580)，加上内边距后左上角仍为 (88,88)。
  /// 将官方合并格跨度连同末端间隙换算为整数细网格跨度。
  int span(int value) => value * (area + gutter) - gutter * divisions;

  const positions = [
    (24, 0),
    (36, 3),
    (45, 12),
    (48, 24),
    (45, 36),
    (36, 45),
    (24, 48),
    (12, 45),
    (3, 36),
    (0, 24),
    (3, 12),
    (12, 3),
  ];
  return GridConfig(
      rows: area * divisions,
      cols: area * divisions,
      blocks: [
        LuckyBoxBlock(padding: const LuckyEdgeInsets.all(45), images: [
          LuckyImage(officialImage('round/bg.png'),
              width: pct(100), height: pct(100))
        ])
      ],
      prizes: [
        for (var i = 0; i < positions.length; i++)
          GridPrize(
              x: coordinate(positions[i].$1),
              y: coordinate(positions[i].$2),
              col: span(12),
              row: span(12),
              images: [
                _fullCellImage('round/cell.png',
                    activeSource: 'round/active.png'),
                GridImage(officialImage('round/$i.png'),
                    width: pct(80), top: pct(i == 6 ? -20 : 10)),
              ])
      ],
      buttons: [
        GridButton(
            x: coordinate(12),
            y: coordinate(12),
            col: span(36),
            row: span(36),
            texts: [
              LuckyText('', top: pct(43))
            ],
            images: [
              GridImage(officialImage('round/btn.png'), width: pct(100))
            ])
      ],
      options: const GridOptions(gutter: 0),
      style:
          GridStyle(text: LuckyTextDefaults(color: hex('#fff'), fontSize: 8)));
}
