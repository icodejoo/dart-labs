import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/slot.dart';

/// 验证老虎机列与 has 圆角语义。
void main() {
  group('slotFromLuckyCanvasConfig', () {
    test('maps slots order speed direction and mode', () {
      expect(slotFromLuckyCanvasConfig({}).config, const SlotConfig());
      final r = slotFromLuckyCanvasConfig({
        'width': '180px',
        'height': 200,
        'blocks': [
          {'padding': '5'}
        ],
        'prizes': [
          {
            'background': 'red',
            'fonts': [
              {'text': 'A'}
            ],
            'imgs': [
              {'src': 'a'}
            ]
          }
        ],
        'slots': [
          {
            'order': [2, 0, 1],
            'speed': 12,
            'direction': -1
          },
          <String, Object?>{}
        ],
        'defaultConfig': {
          'mode': 'horizontal',
          'direction': -1,
          'rowSpacing': '2px',
          'colSpacing': '3px',
          'speed': 10,
          'accelerationTime': 800,
          'decelerationTime': 900
        },
        'defaultStyle': {
          'background': 'blue',
          'borderRadius': '8px',
          'fontSize': 24
        }
      });
      final c = r.config;
      expect(r.warnings, isEmpty);
      expect([r.width, r.height], [180, 200]);
      expect(c.reels.first,
          const SlotReel(order: [2, 0, 1], speed: 12, direction: -1));
      expect(c.reels.last, const SlotReel());
      expect(c.options.mode, SlotMode.horizontal);
      expect(c.options.direction, -1);
      expect(c.options.rowSpacing, 2);
      expect(c.options.colSpacing, 3);
      expect(c.options.motion.speed, 10);
      expect(c.style.cell.borderRadius, 8);
      expect(c.prizes.single.texts.single.text, 'A');
      expect(
          slotFromLuckyCanvasConfig({
            'slots': [
              {'order': null}
            ]
          }).config.reels.single.order,
          isNull);
    });
    test('slot prize borderRadius 0 is kept like has()', () {
      final r = slotFromLuckyCanvasConfig({
        'prizes': [
          {'borderRadius': 0},
          <String, Object?>{}
        ],
        'defaultStyle': {'borderRadius': 12}
      });
      expect(r.config.prizes.first.borderRadius, 0);
      expect(r.config.prizes.last.borderRadius, isNull);
      expect(r.config.style.cell.borderRadius, 12);
    });
    test('zero speed or direction falls back to defaults', () {
      final r = slotFromLuckyCanvasConfig({
        'slots': [
          {'speed': 0, 'direction': 0}
        ],
        'defaultConfig': {'speed': 30, 'direction': -1}
      });
      expect(r.config.reels.single.speed, isNull);
      expect(r.config.reels.single.direction, isNull);
      expect(r.config.options.motion.speed, 30);
      expect(r.config.options.direction, -1);
    });
  });
}
