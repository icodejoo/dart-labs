import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/grid.dart';

import '../support/grid_fixtures.dart';

/// 单格测试配置。
const GridConfig _single =
    GridConfig(rows: 1, cols: 1, prizes: [GridPrize(x: 0, y: 0)]);

/// 阴影测试颜色。
const Color _black = Color(0xFF000000);

/// 阴影测试配置。
const LuckyShadow _shadow =
    LuckyShadow(offsetX: 12, offsetY: -8, color: _black);

/// 布局和模型契约断言。
void main() {
  group('computeGridLayout', () {
    test('prize area shrinks by each block padding', () {
      final layout = gridLayout(_single.copyWith(blocks: const [
        LuckyBoxBlock(padding: LuckyEdgeInsets.all(10)),
        LuckyBoxBlock(
            padding: LuckyEdgeInsets.only(top: 2, left: 3, right: 4, bottom: 5))
      ]));
      expect(layout.prizeArea, const Rect.fromLTWH(13, 12, 273, 273));
      expect(layout.blocks[1].rect, const Rect.fromLTWH(10, 10, 280, 280));
      expect(layout.blocks.first.block.background, isNull);
    });
    test('cell size subtracts gutters', () {
      final layout = gridLayout(const GridConfig());
      expect(layout.cellWidth, (300 - 5 * 2) / 3);
      expect(layout.cellHeight, layout.cellWidth);
    });
    test('cell geometry supports col and row spans', () {
      final layout = gridLayout(
          const GridConfig(prizes: [GridPrize(x: 1, y: 0, col: 2, row: 2)]));
      final w = layout.cellWidth;
      expect(layout.hitRect(0), Rect.fromLTWH(w + 5, 0, w * 2 + 5, w * 2 + 5));
    });
    test('shadow shrinks the cell rect by its offsets like upstream', () {
      final layout = gridLayout(_single.copyWith(
          style: const GridStyle(
              cell: LuckyCellStyle(
                  background: gridNormalFill, shadow: _shadow))));
      expect(
          layout.cells.single.normal.rect, const Rect.fromLTWH(0, 8, 288, 292));
      expect(layout.hitRect(0), const Rect.fromLTWH(0, 0, 300, 300));
    });
    test('shadow applies only when the cell has a background', () {
      final noFill = gridLayout(_single.copyWith(
          style: const GridStyle(cell: LuckyCellStyle(shadow: _shadow))));
      expect(noFill.cells.single.normal.rect, noFill.hitRect(0));
      final transparent = gridLayout(_single.copyWith(
          style: const GridStyle(
              cell: LuckyCellStyle(
                  background: LuckyFill.color(Color(0x00000000)),
                  shadow: _shadow))));
      expect(transparent.cells.single.normal.rect.width, 288);
    });
    test(
        'active style replaces background and shadow and overrides text fields',
        () {
      final config = _single.copyWith(
          prizes: const [
            GridPrize(x: 0, y: 0, texts: [LuckyText('A', color: _black)])
          ],
          style: const GridStyle(
              cell:
                  LuckyCellStyle(background: gridNormalFill, shadow: _shadow)),
          activeStyle: const LuckyCellStyle(
              text: LuckyTextOverride(fontSize: 30, color: Color(0xFFFFFFFF))));
      final cell = gridLayout(config).cells.single;
      expect(cell.active.background, isNull);
      expect(cell.active.shadow, isNull);
      expect(cell.active.rect, cell.hitRect);
      expect(cell.active.texts.single.style.fontSize, 30);
      expect(cell.active.texts.single.style.color, const Color(0xFFFFFFFF));
    });
    test('active line height ignores the active fontSize like upstream', () {
      final layout = gridLayout(_single.copyWith(
          prizes: const [
            GridPrize(
                x: 0,
                y: 0,
                texts: [LuckyText('A\nB', fontSize: 12, wordWrap: false)])
          ],
          activeStyle:
              const LuckyCellStyle(text: LuckyTextOverride(fontSize: 40))));
      expect(layout.cells.single.active.texts.map((line) => line.baselineY),
          [12, 24]);
    });
    test('cell borderRadius zero is honored in the typed API', () {
      final layout = gridLayout(_single.copyWith(prizes: const [
        GridPrize(x: 0, y: 0, style: LuckyCellStyle(borderRadius: 0))
      ]));
      expect(layout.cells.single.normal.borderRadius, 0);
      expect(layout.cells.single.active.borderRadius, 0);
    });
    test('texts wrap to lengthLimit of the cell width and keep empty lines',
        () {
      final layout = gridLayout(_single.copyWith(prizes: const [
        GridPrize(x: 0, y: 0, texts: [
          LuckyText('ABCDE', lengthLimit: LuckyLength.px(1)),
          LuckyText('A\n\nB', wordWrap: false)
        ])
      ]));
      expect(layout.cells.single.normal.texts.map((line) => line.text),
          ['', 'A', 'B', 'C', 'D', 'E', 'A', '', 'B']);
    });
    test('activeImage is used only when active and the base image is loaded',
        () {
      const image =
          GridImage(AssetImage('base'), activeImage: AssetImage('active'));
      final layout = gridLayout(_single.copyWith(prizes: const [
        GridPrize(x: 0, y: 0, images: [image])
      ]));
      expect(layout.cells.single.normal.images.single.slot.active, isFalse);
      expect(layout.cells.single.active.images.single.slot.active, isTrue);
      expect(layout.cells.single.active.images.single.image, image);
      // 图片未到达不能参与布局；普通图门控另由 painter 测试验证。
    });
    test('zero rows cols or size does not throw', () {
      final invalidConfigs = [
        _single.copyWith(rows: 0),
        _single.copyWith(cols: -1),
        _single
      ];
      for (final config in invalidConfigs) {
        final layout = gridLayout(config, size: Size.zero);
        expect(layout.isEmpty, isTrue);
        expect(layout.cellWidth, 0);
        expect(layout.cellHeight, 0);
      }
      expect(
          gridLayout(_single.copyWith(blocks: const [
            LuckyBoxBlock(padding: LuckyEdgeInsets.all(1000))
          ])).isEmpty,
          isTrue);
    });
    test(
        'border and foreground are laid out for normal and active styles (#304 #347)',
        () {
      const border = LuckyBorder(width: 2, color: _black);
      final cell = gridLayout(_single.copyWith(
              style: const GridStyle(
                  cell: LuckyCellStyle(
                      border: border, foreground: gridNormalFill)),
              activeStyle: const LuckyCellStyle(
                  border: border, foreground: gridNormalFill, borderRadius: 3)))
          .cells
          .single;
      expect(cell.normal.border, border);
      expect(cell.normal.foreground, gridNormalFill);
      expect(cell.active.border, border);
      expect(cell.active.foreground, gridNormalFill);
      expect(cell.active.borderRadius, 3);
    });
  });
  test('Grid models > copies preserve values and compare every field', () {
    const config = gridFixture;
    expect(config.copyWith(), config);
    expect(config.copyWith().hashCode, config.hashCode);
    expect(
        config.copyWith(
            rows: 2,
            cols: 4,
            blocks: const [],
            prizes: const [],
            buttons: const [],
            options: const GridOptions(gutter: 0),
            style: const GridStyle(),
            activeStyle: const LuckyCellStyle()),
        isNot(config));
    const options = GridOptions();
    expect(options.copyWith(), options);
    expect(options.copyWith().hashCode, options.hashCode);
    expect(
        options.copyWith(gutter: 2, motion: const LuckyMotionOptions(speed: 1)),
        isNot(options));
    const style = GridStyle();
    expect(style.copyWith(), style);
    expect(style.copyWith().hashCode, style.hashCode);
    expect(
        style.copyWith(
            cell: const LuckyCellStyle(),
            text: const LuckyTextDefaults(fontSize: 10)),
        isNot(style));
    final prize = config.prizes.first;
    expect(prize.copyWith(), prize);
    expect(prize.copyWith().hashCode, prize.hashCode);
    expect(
        prize.copyWith(
            x: 1,
            y: 2,
            col: 2,
            row: 2,
            style: const LuckyCellStyle(),
            texts: const [],
            images: const [],
            weight: 3,
            disabled: true,
            painter: _paint),
        isNot(prize));
    final button = config.buttons.first;
    expect(button.copyWith(), button);
    expect(button.copyWith().hashCode, button.hashCode);
    expect(
        button.copyWith(
            x: 0,
            y: 0,
            col: 2,
            row: 2,
            style: const LuckyCellStyle(),
            texts: const [],
            images: const [],
            painter: _paint),
        isNot(button));
    const image =
        GridImage(AssetImage('base'), activeImage: AssetImage('active'));
    expect(image.copyWith(), image);
    expect(image.copyWith().hashCode, image.hashCode);
    expect(
        image.copyWith(
            image: const AssetImage('other'),
            top: const LuckyLength.px(1),
            left: const LuckyLength.px(1),
            width: const LuckyLength.px(5),
            height: const LuckyLength.px(5),
            formatter: (source) => source,
            borderRadius: 2,
            opacity: 0.5,
            fallback: const AssetImage('fallback'),
            semanticLabel: '图',
            activeImage: const AssetImage('another')),
        isNot(image));
  });
}

/// 测试自定义绘制回调。
void _paint(Canvas canvas, Rect rect, bool active) {}
