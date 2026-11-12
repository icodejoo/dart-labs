import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/wheel.dart';

/// 验证转盘迁移契约与上游默认值。
void main() {
  group('wheelFromLuckyCanvasConfig', () {
    test(
        'maps blocks prizes buttons defaultConfig and defaultStyle with upstream defaults',
        () {
      final empty = wheelFromLuckyCanvasConfig({});
      expect(empty.config, const WheelConfig());
      expect(empty.warnings, isEmpty);
      final result = wheelFromLuckyCanvasConfig({
        'width': '12rem',
        'height': 300,
        'blocks': [
          {
            'padding': '10%',
            'background': 'red',
            'imgs': [
              {
                'src': 'ring.png',
                'rotate': true,
                'top': '10%',
                'left': 1,
                'width': 20,
                'height': 30
              }
            ]
          }
        ],
        'prizes': [
          {
            'range': 2,
            'background': 'blue',
            'fonts': [
              {
                'text': 7,
                'top': '20%',
                'left': 0,
                'fontColor': 'red',
                'fontSize': '19.9px',
                'fontStyle': 'Roboto, serif',
                'fontWeight': 'bold',
                'lineHeight': '21px',
                'wordWrap': false,
                'lengthLimit': '80%',
                'lineClamp': 2
              },
              {'text': '', 'fontSize': 0, 'fontWeight': '', 'lineHeight': 0}
            ],
            'imgs': [
              {'src': 'prize.png'}
            ]
          }
        ],
        'buttons': [
          {
            'radius': '25%',
            'pointer': true,
            'background': 'white',
            'fonts': [
              {'text': 'GO'}
            ],
            'imgs': [
              {'src': 'button.png'}
            ]
          }
        ],
        'defaultConfig': {
          'gutter': '2px',
          'offsetDegree': 30,
          'speed': 10,
          'stopRange': 0.8,
          'accelerationTime': 1000.125,
          'decelerationTime': 1200
        },
        'defaultStyle': {
          'background': 'yellow',
          'fontColor': 'blue',
          'fontSize': '24px',
          'fontStyle': 'Roboto, serif',
          'fontWeight': '700',
          'lineHeight': '26px',
          'wordWrap': false,
          'lengthLimit': '75%',
          'lineClamp': 3
        }
      });
      final c = result.config;
      expect(result.width, 192);
      expect(result.height, 300);
      expect(result.warnings, isEmpty);
      expect(c.blocks.single.padding, 0.1);
      expect(c.blocks.single.images.single.rotate, isTrue);
      expect(c.blocks.single.images.single.width, const LuckyLength.px(20));
      expect(c.prizes.single.weight, 2);
      expect(
          c.prizes.single.texts.first,
          const LuckyText('7',
              top: LuckyLength.percent(20),
              left: LuckyLength.px(0),
              color: Color(0xFFFF0000),
              fontSize: 19.9,
              fontFamily: 'Roboto',
              fontFamilyFallback: ['serif'],
              fontWeight: FontWeight.w700,
              lineHeight: 21,
              wordWrap: false,
              lengthLimit: LuckyLength.percent(80),
              lineClamp: 2));
      expect(c.prizes.single.texts.last.fontSize, isNull);
      expect(c.buttons.single.radius, const LuckyLength.percent(25));
      expect(c.buttons.single.pointer, isTrue);
      expect(c.options.gutter, 2);
      expect(c.options.offsetDegree, 30);
      expect(c.options.stopRange, 0.8);
      expect(c.options.motion.speed, 10);
      expect(c.options.motion.accelerationTime.inMicroseconds, 1000125);
      expect(c.options.motion.decelerationTime.inMilliseconds, 1200);
      expect(c.style.text.fontSize, 24);
      expect(c.style.text.lineClamp, 3);
      expect(c.style.text.fontFamilyFallback, ['serif']);
      expect(() => c.prizes.clear(), throwsUnsupportedError);
      expect(() => result.warnings.clear(), throwsUnsupportedError);
    });
    test('speedFunction is ignored unless honorSpeedFunction is set', () {
      const data = {
        'defaultConfig': {'speedFunction': 'cubic'}
      };
      expect(
          wheelFromLuckyCanvasConfig(data)
              .config
              .options
              .motion
              .accelerationEasing,
          LuckyEasings.quad);
      final c = wheelFromLuckyCanvasConfig(data,
              options: const LuckyCanvasCompatOptions(honorSpeedFunction: true))
          .config;
      expect(c.options.motion.accelerationEasing, LuckyEasings.cubic);
      expect(c.options.motion.decelerationEasing, LuckyEasings.cubic);
      final bad = wheelFromLuckyCanvasConfig({
        'defaultConfig': {'speedFunction': 'bad'}
      }, options: const LuckyCanvasCompatOptions(honorSpeedFunction: true));
      expect(bad.warnings.single.path, 'defaultConfig.speedFunction');
    });
    test('strictUpstream selects frame timebase and upstream solver', () {
      final c = wheelFromLuckyCanvasConfig({},
              options: LuckyCanvasCompatOptions.strictUpstream())
          .config;
      expect(c.options.motion.timebase, LuckyTimebase.frame);
      expect(c.options.motion.stopSolver, isA<UpstreamStopSolver>());
      expect(wheelFromLuckyCanvasConfig({}).config.options.motion.timebase,
          LuckyTimebase.time);
    });
    test('unknown keys and callbacks produce warnings not errors', () {
      final r = wheelFromLuckyCanvasConfig({
        'start': 'callback',
        'unknown': true,
        'width': '50%',
        'height': 'bad!',
        'blocks': [
          {
            'padding': 'bad!',
            'background': 1,
            'imgs': [
              {'src': ''}
            ]
          }
        ],
        'prizes': [
          {
            'range': 'bad',
            'fonts': [
              {'text': null, 'fontColor': 'bad'}
            ],
            'imgs': [
              {'src': 'a', 'formatter': true},
              4
            ]
          }
        ],
        'buttons': [
          {'pointer': 'yes'}
        ],
        'defaultConfig': {'speedFunction': 1},
        'defaultStyle': {
          'fontColor': 'bad',
          'fontSize': 'bad!',
          'fontWeight': 'bad'
        }
      });
      expect(r.width, isNull);
      expect(r.height, isNull);
      final paths = r.warnings.map((w) => w.path);
      expect(
          paths,
          containsAll([
            'start',
            'unknown',
            'width',
            'height',
            'blocks[0].padding',
            'blocks[0].background',
            'blocks[0].imgs[0].src',
            'prizes[0].range',
            'prizes[0].imgs[0].formatter',
            'prizes[0].imgs[1]',
            'buttons[0].pointer',
            'defaultConfig.speedFunction',
            'defaultStyle.fontColor'
          ]));
      expect(r.config.style.text.fontSize, 18);
      expect(r.config.prizes.single.texts.single.text, 'null');
    });
    test('block padding uses only the first token', () {
      final r = wheelFromLuckyCanvasConfig({
        'blocks': [
          {'padding': '2px 100px 200px'}
        ]
      });
      expect(r.config.blocks.single.padding, 2);
      expect(r.warnings, isEmpty);
    });
    test('kLuckyCanvasEasingNames covers all seven upstream easings', () {
      expect(kLuckyCanvasEasingNames, {
        'quad': LuckyEasings.quad,
        'cubic': LuckyEasings.cubic,
        'quart': LuckyEasings.quart,
        'quint': LuckyEasings.quint,
        'sine': LuckyEasings.sine,
        'expo': LuckyEasings.expo,
        'circ': LuckyEasings.circ
      });
    });
  });
}
