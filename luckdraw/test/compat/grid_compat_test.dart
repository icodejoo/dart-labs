import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/grid.dart';

/// 验证九宫格迁移及旧按钮兼容。
void main() {
  group('gridFromLuckyCanvasConfig', () {
    test('maps rows cols cells activeStyle and the legacy button field', () {
      final empty = gridFromLuckyCanvasConfig({});
      expect(empty.config.rows, 3);
      expect(empty.config.cols, 3);
      final r = gridFromLuckyCanvasConfig({
        'width': 300,
        'height': '20rem',
        'rows': '4',
        'cols': 0,
        'blocks': [
          {
            'padding': '1 2 3 4',
            'borderRadius': '6px',
            'background': 'red',
            'imgs': [
              {'src': 'block'}
            ]
          }
        ],
        'prizes': [
          {
            'x': '2',
            'y': 1,
            'col': 2,
            'row': 0,
            'range': 3,
            'background': 'blue',
            'shadow': '1 2 3 red',
            'fonts': [
              {'text': 'A'}
            ],
            'imgs': [
              {'src': 'normal', 'activeSrc': 'active', 'width': '50%'}
            ]
          }
        ],
        'buttons': [
          {'x': 0, 'y': 0}
        ],
        'button': {'x': 1, 'y': 2},
        'defaultConfig': {'gutter': '8px', 'speed': 30},
        'defaultStyle': {'background': 'yellow', 'borderRadius': '10px'},
        'activeStyle': {
          'background': 'white',
          'shadow': '2 3 4 red',
          'fontColor': 'red',
          'fontSize': '22px',
          'fontStyle': 'Roboto',
          'fontWeight': 'bold',
          'lineHeight': '25px'
        }
      });
      final c = r.config;
      expect(r.warnings, isEmpty);
      expect([r.width, r.height, c.rows, c.cols], [300, 320, 4, 3]);
      expect(c.blocks.single.padding,
          const LuckyEdgeInsets.only(top: 1, bottom: 2, left: 3, right: 4));
      expect(c.blocks.single.images.single.image, const AssetImage('block'));
      expect([
        c.prizes.single.x,
        c.prizes.single.y,
        c.prizes.single.col,
        c.prizes.single.row
      ], [
        2,
        1,
        2,
        1
      ]);
      expect(c.prizes.single.weight, 3);
      expect(c.prizes.single.images.single.activeImage,
          const AssetImage('active'));
      expect(c.buttons.map((b) => b.x), [0, 1]);
      expect(c.options.gutter, 8);
      expect(c.options.motion.speed, 30);
      expect(c.style.cell.borderRadius, 10);
      expect(c.activeStyle.text!.fontSize, 22);
      expect(c.activeStyle.text!.lineHeight, 25);
      expect(c.activeStyle.shadow!.offsetX, 2);
      expect(gridFromLuckyCanvasConfig({'rows': 'bad'}).config.rows, 3);
    });
    test('cell borderRadius 0 falls back to the default like upstream', () {
      final r = gridFromLuckyCanvasConfig({
        'prizes': [
          {'x': false, 'y': '', 'borderRadius': 0},
          {'x': true, 'y': 0, 'borderRadius': '0px'}
        ]
      });
      expect(r.config.prizes.first.style!.borderRadius, isNull);
      expect(r.config.prizes.last.style!.borderRadius, 0);
      expect(r.config.prizes.last.x, 1);
      expect(r.config.style.cell.borderRadius, 20);
    });
    test('disabled is ignored unless honorDisabled is set', () {
      const data = {
        'prizes': [
          {'x': 0, 'y': 0, 'disabled': true}
        ]
      };
      expect(gridFromLuckyCanvasConfig(data).config.prizes.single.disabled,
          isFalse);
      expect(
          gridFromLuckyCanvasConfig(data,
                  options: const LuckyCanvasCompatOptions(honorDisabled: true))
              .config
              .prizes
              .single
              .disabled,
          isTrue);
    });
    test('button callbacks are dropped with a warning', () {
      final r = gridFromLuckyCanvasConfig({
        'button': {
          'callback': 'callback',
          'x': 'bad',
          'y': 0,
          'borderRadius': 1,
          'imgs': [
            {'src': '', 'activeSrc': ''}
          ]
        },
        'activeStyle': {'bad': 1},
        'blocks': [
          {'paddingTop': 2, 'padding': false}
        ]
      });
      expect(
          r.warnings.map((w) => w.path),
          containsAll([
            'button.callback',
            'button.x',
            'button.imgs[0].src',
            'activeStyle.bad',
            'blocks[0].paddingTop',
            'blocks[0].padding'
          ]));
      expect(r.config.buttons.single.x, 0);
      expect(r.config.buttons.single.images, isEmpty);
    });
  });
}
