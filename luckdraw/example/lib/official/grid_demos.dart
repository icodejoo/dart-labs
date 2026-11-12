import 'package:flutter/material.dart';
import 'package:luckdraw/grid.dart';

import 'official_demo.dart';
import 'official_stage.dart';

/// 官方九宫格的 25 个基础示例，顺序对应 grid_01 至 grid_25。
final List<OfficialDemo> gridDemos = [
  OfficialDemo(
      id: 'grid-block-padding',
      title: '通过padding挤出边框',
      refAsset: 'grid_01',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: GridConfig(blocks: [
            for (final color in ['#617df2', '#869cfa', '#afc8ff', '#e9e8fe'])
              LuckyBoxBlock(
                  padding: const LuckyEdgeInsets.all(10),
                  background: fill(color)),
          ]))),
  OfficialDemo(
      id: 'grid-block-borderRadius',
      title: '设置边框圆角',
      refAsset: 'grid_02',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: GridConfig(blocks: [
            for (final (color, radius) in <(String, double)>[
              ('#617df2', 10),
              ('#869cfa', 30),
              ('#afc8ff', 50),
              ('#e9e8fe', double.infinity),
            ])
              LuckyBoxBlock(
                  padding: const LuckyEdgeInsets.all(10),
                  background: fill(color),
                  borderRadius: radius),
          ]))),
  OfficialDemo(
      id: 'grid-block-img',
      title: '使用图片作为背景',
      refAsset: 'grid_03',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: GridConfig(blocks: [
            LuckyBoxBlock(padding: const LuckyEdgeInsets.all(20), images: [
              LuckyImage(officialImage('grid-bg.png'),
                  width: pct(100), height: pct(100)),
            ]),
          ]))),
  OfficialDemo(
      id: 'grid-prize-borderRadius',
      title: '设置格子圆角',
      refAsset: 'grid_04',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: [
            for (var i = 0; i < _perimeter.length; i++)
              GridPrize(
                  x: _perimeter[i].$1,
                  y: _perimeter[i].$2,
                  style: LuckyCellStyle(
                      borderRadius: const <double>[
                    0,
                    15,
                    double.infinity,
                    15,
                    0,
                    15,
                    double.infinity,
                    15,
                  ][i])),
          ]))),
  OfficialDemo(
      id: 'grid-prize-font',
      title: '设置奖品文字',
      refAsset: 'grid_05',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: [
            for (var i = 0; i < 3; i++)
              GridPrize(x: 1, y: i, texts: [LuckyText('$i', top: px(15))]),
          ]))),
  OfficialDemo(
      id: 'grid-prize-wordWrap',
      title: '设置奖品文字换行',
      refAsset: 'grid_06',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: const [
            GridPrize(x: 1, y: 0, texts: [LuckyText('自动换行')]),
            GridPrize(
                x: 1, y: 1, texts: [LuckyText('需要\n手动换行', wordWrap: false)]),
            GridPrize(
                x: 1, y: 2, texts: [LuckyText('当前格子不换行', wordWrap: false)]),
          ]))),
  OfficialDemo(
      id: 'grid-prize-lineClamp',
      title: '设置奖品文字溢出隐藏',
      refAsset: 'grid_07',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: const [
            GridPrize(x: 1, y: 0, texts: [LuckyText('超过2行自动隐藏', lineClamp: 2)]),
            GridPrize(x: 1, y: 1, texts: [LuckyText('超过1行自动隐藏', lineClamp: 1)]),
            GridPrize(x: 1, y: 2, texts: [LuckyText('不会自动隐藏')]),
          ]))),
  OfficialDemo(
      id: 'grid-prize-background',
      title: '设置格子的背景颜色',
      refAsset: 'grid_08',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: [
            for (final (x, y, color) in [
              (0, 0, '#b3c8fa'),
              (1, 0, '#899df3'),
              (2, 0, '#657fea'),
              (0, 2, '#9c9dd8'),
              (1, 2, '#888bf2'),
              (2, 2, '#7074f6'),
            ])
              GridPrize(
                  x: x, y: y, style: LuckyCellStyle(background: fill(color))),
          ]))),
  OfficialDemo(
      id: 'grid-prize-img',
      title: '设置奖品图片',
      refAsset: 'grid_09',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: _imagePrizes()))),
  OfficialDemo(
      id: 'grid-prize-bgImg',
      title: '设置格子的背景图片',
      refAsset: 'grid_10',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: GridConfig(
              blocks: _gridBlocks(),
              prizes: _imagePrizes(cellBackground: true)))),
  OfficialDemo(
      id: 'grid-prize-activeSrc',
      title: '中奖标识滑过替换图片',
      refAsset: 'grid_11',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          autoPlay: true,
          config: _gridConfig(
              rows: 2,
              cols: 2,
              prizes: _imagePrizes(active: true, positions: _clockwiseFour),
              activeStyle: LuckyCellStyle(background: fill('#869cfa')),
              options:
                  const GridOptions(motion: LuckyMotionOptions(speed: 1))))),
  OfficialDemo(
      id: 'grid-activeStyle',
      title: '设置中奖标记样式',
      refAsset: 'grid_12',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          autoPlay: true,
          config: _gridConfig(
              rows: 2,
              cols: 2,
              prizes: [
                for (var i = 0; i < _clockwiseFour.length; i++)
                  GridPrize(
                      x: _clockwiseFour[i].$1,
                      y: _clockwiseFour[i].$2,
                      texts: [
                        LuckyText(['恭', '喜', '发', '财'][i], top: pct(25))
                      ]),
              ],
              style: GridStyle(
                  cell: _gridStyle.cell,
                  text: LuckyTextDefaults(
                      fontSize: 30,
                      color: hex('#ff6b61'),
                      fontWeight: FontWeight.w700)),
              activeStyle: LuckyCellStyle(
                  background: fill('#9c9cdd'),
                  text: LuckyTextOverride(color: hex('#f9bdbd'))),
              options:
                  const GridOptions(motion: LuckyMotionOptions(speed: 1))))),
  OfficialDemo(
      id: 'grid-prize-index',
      title: '设置抽奖的旋转方向',
      refAsset: 'grid_13',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          autoPlay: true,
          config: _gridConfig(
              rows: 2,
              cols: 2,
              prizes: _positionPrizes(const [(0, 0), (0, 1), (1, 1), (1, 0)]),
              activeStyle: LuckyCellStyle(background: fill('#9c9cdd')),
              options:
                  const GridOptions(motion: LuckyMotionOptions(speed: 1))))),
  OfficialDemo(
      id: 'grid-btn',
      title: '设置抽奖按钮',
      refAsset: 'grid_14',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          stopIndex: () => 0,
          stopDelay: const Duration(milliseconds: 3000),
          config: _gridConfig(buttons: [_startButton('#9c9dd8')]))),
  OfficialDemo(
      id: 'grid-btn-img',
      title: '使用图片作为抽奖按钮',
      refAsset: 'grid_15',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          stopIndex: () => 0,
          stopDelay: const Duration(milliseconds: 3000),
          config: _gridConfig(buttons: [
            GridButton(
                x: 1,
                y: 1,
                style: const LuckyCellStyle(
                    background: LuckyFill.color(Colors.transparent)),
                images: [
                  GridImage(officialImage('grid-btn.png'),
                      width: pct(100), height: pct(100)),
                ]),
          ]))),
  OfficialDemo(
      id: 'grid-btn-dom',
      title: '使用Dom作为抽奖按钮',
      refAsset: 'grid_16',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 150,
          stopIndex: () => 0,
          stopDelay: const Duration(milliseconds: 3000),
          controls: (_, __, start) => _domButton(start),
          config: _gridConfig(
              rows: 2,
              cols: 3,
              prizes: _positionPrizes(
                  const [(0, 0), (1, 0), (2, 0), (2, 1), (1, 1), (0, 1)])))),
  // 差异：GridButton 不保存 JS callback，OfficialGrid 未暴露按钮下标；同位置叠层分别展示按钮提示。
  OfficialDemo(
      id: 'grid-btns',
      title: '设置多个抽奖按钮',
      refAsset: 'grid_17',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          overlay: (context, _, __) => _multipleButtonsOverlay(context),
          config: _gridConfig(
              rows: 3,
              cols: 4,
              prizes: _positionPrizes(const [
                (0, 0),
                (1, 0),
                (2, 0),
                (3, 0),
                (3, 1),
                (2, 1),
                (1, 1),
                (0, 1),
              ]),
              buttons: [
                for (final (x, text) in [(0, '单抽'), (2, '十连抽')])
                  GridButton(
                      x: x,
                      y: 2,
                      col: 2,
                      style: LuckyCellStyle(background: fill('#7f95d1')),
                      texts: [LuckyText(text, top: pct(25))]),
              ]))),
  OfficialDemo(
      id: 'grid-default-gutter',
      title: '设置格子之间的缝隙',
      refAsset: 'grid_18',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(options: const GridOptions(gutter: 20)))),
  OfficialDemo(
      id: 'grid-default-speed',
      title: '设置抽奖的旋转速度',
      refAsset: 'grid_19',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          autoPlay: true,
          config: _gridConfig(
              options:
                  const GridOptions(motion: LuckyMotionOptions(speed: 10))))),
  OfficialDemo(
      id: 'grid-layout-10',
      title: '十宫格布局',
      refAsset: 'grid_20',
      builder: (_) => OfficialGrid(
          width: 240,
          height: 200,
          config: _gridConfig(
              rows: 3, cols: 4, prizes: _numberedPerimeter(4, 3, 25)))),
  OfficialDemo(
      id: 'grid-layout-12',
      title: '十二宫格布局',
      refAsset: 'grid_21',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(
              rows: 4, cols: 4, prizes: _numberedPerimeter(4, 4, 20)))),
  OfficialDemo(
      id: 'grid-layout-16',
      title: '十六宫格布局',
      refAsset: 'grid_22',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(
              rows: 5, cols: 5, prizes: _numberedPerimeter(5, 5, 10)))),
  // 差异：原生格子坐标/跨度只接受整数，且会截断负基础格宽；将原 60×60 布局等价换算为无缝整数细网格，缝隙计入跨度，保留小数按钮的像素位置与大小。
  OfficialDemo(
      id: 'grid-layout-round',
      title: '圆形宫格布局',
      refAsset: 'grid_23',
      builder: (_) => OfficialGrid(
          width: 300,
          height: 300,
          stopIndex: () => 0,
          stopDelay: const Duration(milliseconds: 2000),
          config: _roundGridConfig())),
  OfficialDemo(
      id: 'grid-row-col',
      title: '横向/纵向合并格子',
      refAsset: 'grid_24',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          config: _gridConfig(prizes: const [
            GridPrize(x: 0, y: 0, col: 2),
            GridPrize(x: 2, y: 0, row: 2),
            GridPrize(x: 1, y: 2, col: 2),
            GridPrize(x: 0, y: 1, row: 2),
          ]))),
  OfficialDemo(
      id: 'grid-demo',
      title: '控制游戏的开始和结束',
      refAsset: 'grid_25',
      builder: (_) => OfficialGrid(
          width: 200,
          height: 200,
          stopIndex: () => 0,
          stopDelay: const Duration(milliseconds: 1000),
          config: _gridConfig(
              prizes: _numberedPerimeter(3, 3, 25),
              buttons: [_startButton('#7f95d1')]))),
];

/// 官方三行三列奖品的顺时针位置。
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

/// 官方两行两列奖品的顺时针位置。
const List<(int, int)> _clockwiseFour = [(0, 0), (1, 0), (1, 1), (0, 1)];

/// 通用淡蓝格子样式，继承官方默认圆角。
final GridStyle _gridStyle = GridStyle(
    cell: const GridStyle().cell.copyWith(background: fill('#b8c5f2')));

/// 两层各十像素的官方边框，可指定圆角。
List<LuckyBoxBlock> _gridBlocks({double radius = 0}) => [
      for (final color in ['#869cfa', '#e9e8fe'])
        LuckyBoxBlock(
            padding: const LuckyEdgeInsets.all(10),
            background: fill(color),
            borderRadius: radius),
    ];

/// 汇集重复的官方边框、格子默认色与默认三行三列配置。
GridConfig _gridConfig({
  int rows = 3,
  int cols = 3,
  List<GridPrize>? prizes,
  List<GridButton> buttons = const [],
  GridOptions options = const GridOptions(),
  GridStyle? style,
  LuckyCellStyle? activeStyle,
}) =>
    GridConfig(
        rows: rows,
        cols: cols,
        blocks: _gridBlocks(),
        prizes: prizes ?? _positionPrizes(_perimeter),
        buttons: buttons,
        options: options,
        style: style ?? _gridStyle,
        activeStyle: activeStyle ?? const GridConfig().activeStyle);

/// 按配置顺序创建没有附加内容的奖品。
List<GridPrize> _positionPrizes(List<(int, int)> positions) => [
      for (final (x, y) in positions) GridPrize(x: x, y: y),
    ];

/// 创建含奖品图、可选格子背景图和激活图的奖品列表。
List<GridPrize> _imagePrizes({
  bool cellBackground = false,
  bool active = false,
  List<(int, int)> positions = _perimeter,
}) =>
    [
      for (final (x, y) in positions)
        GridPrize(x: x, y: y, images: [
          if (cellBackground)
            GridImage(officialImage('cell-80.png'),
                width: pct(100), height: pct(100)),
          GridImage(officialImage('prize.png'),
              activeImage: active ? officialImage('active.png') : null,
              width: pct(50),
              top: pct(25)),
        ]),
    ];

/// 从左上角开始沿外围顺时针编号，保留每种布局的文字偏移。
List<GridPrize> _numberedPerimeter(int cols, int rows, double top) {
  final positions = <(int, int)>[
    for (var x = 0; x < cols; x++) (x, 0),
    for (var y = 1; y < rows; y++) (cols - 1, y),
    for (var x = cols - 2; x >= 0; x--) (x, rows - 1),
    for (var y = rows - 2; y > 0; y--) (0, y),
  ];
  return [
    for (var i = 0; i < positions.length; i++)
      GridPrize(
          x: positions[i].$1,
          y: positions[i].$2,
          texts: [LuckyText('$i', top: pct(top))]),
  ];
}

/// 创建居中的官方文字开始按钮。
GridButton _startButton(String color) => GridButton(
    x: 1,
    y: 1,
    style: LuckyCellStyle(background: fill(color)),
    texts: [LuckyText('开始', top: pct(25))]);

/// 还原画布下方的 DOM 按钮盒模型。
Widget _domButton(VoidCallback start) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
            onTap: start,
            child: Container(
                width: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: hex('#7f95d1'),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('开始游戏',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.black, fontSize: 16, height: 1.5))))));

/// 在两个按钮的实际命中区域分别处理官方 alert，不启动原例未启动的抽奖。
Widget _multipleButtonsOverlay(BuildContext context) => Stack(children: [
      for (final (left, label, message) in [
        (20.0, '单抽', 'hello'),
        (102.5, '十连抽', 'world'),
      ])
        Positioned(
            left: left,
            top: 130,
            width: 77.5,
            height: 50,
            child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await _showGridAlert(context, message);
                      if (context.mounted) {
                        await _showGridAlert(context, '你点击了$label');
                      }
                    }))),
    ]);

/// 用原生对话框依次还原按钮 callback 和 start 的提示。
Future<void> _showGridAlert(BuildContext context, String message) async {
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(content: Text(message), actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('确定')),
          ]));
}

/// 将圆形示例的原始小数网格换算成像素位置完全相同的整数细网格。
GridConfig _roundGridConfig() {
  /// 官方网格细分数。
  const z = 60;

  /// 官方奖品格跨度。
  const s = 12;

  /// 官方纵轴偏移量。
  const m = 18;

  /// 官方横轴偏移量。
  const n = 9;

  /// 官方按钮放大倍数。
  const k = 2.8;

  /// 三百像素画布扣除两层边框后的内容边长。
  const area = 300 - 2 * (10 + 10);

  /// 官方默认五像素格子缝隙。
  const gutter = 5;
  // 原坐标步长是 (area + gutter) / z，合并格尺寸再扣除一份 gutter。
  // 新网格每单位为 1 / z 像素，允许精确表达 13.2 和 33.6 等原始值。
  /// 把原坐标换算为整数网格坐标。
  int coordinate(double value) => (value * (area + gutter)).round();

  /// 把原跨度及其末端缝隙换算为整数网格跨度。
  int span(double value) => (value * (area + gutter) - gutter * z).round();

  final positions = <(double, double)>[
    (z / 2 - s / 2, 0),
    (z - m - s / 2, n - s / 2),
    (z - n - s / 2, m - s / 2),
    (z - s.toDouble(), z / 2 - s / 2),
    (z - n - s / 2, z - m - s / 2),
    (z - m - s / 2, z - n - s / 2),
    (z / 2 - s / 2, z - s.toDouble()),
    (m - s / 2, z - n - s / 2),
    (n - s / 2, z - m - s / 2),
    (0, z / 2 - s / 2),
    (n - s / 2, m - s / 2),
    (m - s / 2, n - s / 2),
  ];
  return GridConfig(
      rows: z * area,
      cols: z * area,
      blocks: _gridBlocks(radius: double.infinity),
      options: const GridOptions(gutter: 0),
      prizes: [
        for (final (x, y) in positions)
          GridPrize(
              x: coordinate(x),
              y: coordinate(y),
              col: span(s.toDouble()),
              row: span(s.toDouble())),
      ],
      buttons: [
        GridButton(
            x: coordinate(z / 2 - s / 2 * k),
            y: coordinate(z / 2 - s / 2 * k),
            col: span(s * k),
            row: span(s * k),
            texts: [LuckyText('开始', top: pct(43))]),
      ],
      style: GridStyle(
          cell: LuckyCellStyle(
              borderRadius: double.infinity, background: fill('#bac5ee'))),
      activeStyle: LuckyCellStyle(background: fill('#f7cf9f')));
}
