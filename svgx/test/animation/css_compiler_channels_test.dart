import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_animation_values.dart';
import 'package:svgx/src/animation/css_keyframes_compiler.dart';
import 'package:svgx/src/animation/css_stylesheet.dart';
import 'package:svgx/src/animation/smil_animation.dart';

/// 四种通道的属性名。
const _motion = 'offset-distance',
    _color = 'fill',
    _path = 'd',
    _list = 'stroke-dasharray';

/// 各通道合法的起止值及静态基准。
const _values = {
  _motion: ['0%', '100%', '20%'],
  _color: ['#000', '#fff', '#ff000080'],
  _path: ['path("M0 0 L0 10")', 'path("M10 0 L10 10")', 'M2 0 L2 10'],
  _list: ['10', '20 40', '2px, 4'],
};

/// 各通道所需的静态运动属性。
const _motionProperties = {'offset-path': 'path("M0 0 L100 0")'};

/// 默认动画与常用时间，避免依赖 CSS 默认缓动。
const _animation = 'a 1s linear',
    _half = Duration(milliseconds: 500),
    _quarter = Duration(milliseconds: 250);

/// 颜色字节与数值采样的误差界限。
const _tolerance = 1e-5, _black = 0xff000000, _white = 0xffffffff;

/// 返回线性假采样表，只验证编译映射，不依赖图形运行时。
List<SmilMotionSample> _samplePath(String path, String rotate) => const [
  SmilMotionSample(0, 0, 0),
  SmilMotionSample(100, 0, 90),
];

/// 为每帧建立同宽假变形数据，测试只采样位置编码。
PathMorphData _morph(List<String> frames) => PathMorphData(
  ops: const [kMorphMove],
  frames: [
    for (var i = 0; i < frames.length; i++)
      Float64List.fromList([i.toDouble(), 0]),
  ],
);

/// 可用的纯 Dart 假钩子。
final _hooks = CssCompileHooks(
  sampleMotionPath: _samplePath,
  buildPathMorph: _morph,
);

/// 从 CSS 解析入口编译，参数可覆盖时序、静态值、额外动画和钩子。
CssCompileResult _compile(
  String frames, {
  String animation = _animation,
  Map<String, String> attributes = const {},
  Map<String, String> properties = _motionProperties,
  CssCompileHooks? hooks,
  String extra = '',
}) => compileCssAnimations(
  animations: parseCssAnimations(parseCssDeclarations('animation: $animation')),
  keyframes: parseCssStylesheet('@keyframes a {$frames} $extra').keyframes,
  attributes: attributes,
  cssProperties: properties,
  hooks: hooks ?? _hooks,
);

/// 构造一个属性的完整起止关键帧。
String _frames(String property) =>
    'from {$property: ${_values[property]![0]}} to {$property: ${_values[property]![1]}}';

/// 检查恰好一个属性失败且诊断带动画名。
void _skip(CssCompileResult r, CssCompileSkipReason reason, String property) {
  expect(r.skipped, hasLength(1));
  expect(r.skipped.single.reason, reason);
  expect(r.skipped.single.animationName, 'a');
  expect(r.skipped.single.property, property);
}

/// 从四个不同类型轨道读取共有时序字段供参数化测试使用。
dynamic _track(CssCompileResult r, String property) => switch (property) {
  _motion => r.motion.single,
  _color => r.color.single,
  _path => r.paths.single,
  _ => r.lists.single,
};

/// 根据 CSS 手算结果检查四通道相同进度下的值。
void _progress(CssCompileResult r, String property, Duration time, double p) {
  switch (property) {
    case _motion:
      expect(r.motion.single.sample(time)!.x, closeTo(100 * p, _tolerance));
    case _color:
      final byte = (255 * p).round();
      expect(
        r.color.single.sample(time),
        0xff000000 | byte << 16 | byte << 8 | byte,
      );
    case _path:
      expect(r.paths.single.sample(time), closeTo(p, _tolerance));
    default:
      expect(r.lists.single.sample(time)![0], closeTo(10 + 10 * p, _tolerance));
      expect(r.lists.single.sample(time)![1], closeTo(10 + 30 * p, _tolerance));
  }
}

/// 验证四通道映射、诊断、端点及编译产物的实际采样行为。
void main() {
  for (final property in _values.keys) {
    group(property, () {
      test('基本编译、关键帧位置和线性手算采样', () {
        final r = _compile(_frames(property));
        final dynamic track = _track(r, property);
        expect(r.skipped, isEmpty);
        expect(r.approximations, isEmpty);
        expect(track.keyTimes, [0, 1]);
        expect(track.calcMode, SmilCalcMode.linear);
        expect(track.keySplines, isNull);
        _progress(r, property, _half, .5);
      });

      for (final endpoints in ['start', 'end', 'both']) {
        test('缺少 $endpoints 端点使用静态基准', () {
          final v = _values[property]!;
          final frames =
              '${endpoints == 'end' ? 'from {$property:${v[0]}}' : ''}'
              '50% {$property:${v[1]}} '
              '${endpoints == 'start' ? 'to {$property:${v[0]}}' : ''}';
          final r = _compile(
            frames,
            attributes: {property: v[2]},
            properties: {..._motionProperties, _motion: _values[_motion]![2]},
          );
          final dynamic t = _track(r, property);
          expect(t.keyTimes, [0, .5, 1]);
          final dynamic actual = switch (property) {
            _motion => r.motion.single.keyPoints,
            _path => r.paths.single.frames,
            _color => r.color.single.values,
            _ => r.lists.single.values,
          };
          final dynamic base = switch (property) {
            _motion => .2,
            _color => 0x80ff0000,
            _path => v[2],
            _ => [2.0, 4.0],
          };
          if (endpoints != 'end') expect(actual.first, base);
          if (endpoints != 'start') expect(actual.last, base);
        });
      }

      test('无效中间值及其缓动忽略，合法 stop 保留', () {
        final r = _compile(
          '${_frames(property)} 30% {$property: garbage; '
          'animation-timing-function: step-start}',
        );
        expect((_track(r, property)).keyTimes, [0, 1]);
        expect((_track(r, property)).keySplines, isNull);
        _progress(r, property, _half, .5);
      });

      test('全无效报告 noValidValue，数值属性继续编译', () {
        final r = _compile(
          'from {$property: garbage; opacity:0} '
          'to {$property: invalid; opacity:1}',
        );
        _skip(r, CssCompileSkipReason.noValidValue, property);
        expect(r.numeric.single.values, [0, 1]);
      });

      test('重要声明不进入通道', () {
        final r = _compile(
          '${_frames(property)} 30% {$property: garbage !important}',
        );
        expect(r.skipped, isEmpty);
        expect((_track(r, property)).keyTimes, [0, 1]);
      });

      test('逐段 steps、贝塞尔和全局缓动回退', () {
        final v = _values[property]!;
        final r = _compile(
          'from {$property:${v[0]}; animation-timing-function:linear} '
          '25% {$property:${v[0]}; animation-timing-function:steps(2,end)} '
          '75% {$property:${v[1]}} to {$property:${v[1]}; '
          'animation-timing-function:step-start}',
          animation: 'a 1s ease-in',
        );
        final dynamic t = _track(r, property);
        expect(t.keyTimes, [0, .25, .75, 1]);
        expect(t.calcMode, SmilCalcMode.spline);
        expect(t.keySplines, hasLength(3));
        expect(t.keySplines[0], isA<CubicBezier>());
        expect(t.keySplines[1], isA<SmilStepsEasing>());
        expect((t.keySplines[2] as CubicBezier).x1, .42);
        if (property != _path) {
          _progress(r, property, const Duration(milliseconds: 374), 0);
          _progress(r, property, const Duration(milliseconds: 501), .5);
        } else {
          expect(r.paths.single.sample(const Duration(milliseconds: 374)), 1);
          expect(r.paths.single.sample(const Duration(milliseconds: 501)), 1.5);
        }
      });

      test('全局贝塞尔实际采样', () {
        final r = _compile(
          _frames(property),
          animation: 'a 1s cubic-bezier(0,0,1,0)',
        );
        _progress(r, property, _half, .125);
      });

      for (final direction in {
        'normal': SmilDirection.normal,
        'reverse': SmilDirection.reverse,
        'alternate': SmilDirection.alternate,
        'alternate-reverse': SmilDirection.alternateReverse,
      }.entries) {
        test('方向 ${direction.key} 保留并采样第二轮', () {
          final r = _compile(
            _frames(property),
            animation: 'a 1s linear 3 ${direction.key}',
          );
          expect((_track(r, property)).direction, direction.value);
          final p = direction.key == 'reverse' || direction.key == 'alternate'
              ? .75
              : .25;
          _progress(r, property, const Duration(milliseconds: 1250), p);
        });
      }

      for (final delay in [-250, 250]) {
        test('延迟 $delay 同时写 begin 和 beginSpec', () {
          final r = _compile(
            _frames(property),
            animation: 'a 1s linear ${delay}ms',
          );
          final dynamic t = _track(r, property);
          expect(t.begin, Duration(milliseconds: delay));
          expect(t.beginSpec.offset, t.begin);
          _progress(r, property, Duration(milliseconds: delay + 500), .5);
        });
      }

      for (final repeat in ['infinite', '2.5']) {
        test('重复次数 $repeat', () {
          final r = _compile(
            _frames(property),
            animation: 'a 1s linear $repeat forwards',
          );
          final dynamic t = _track(r, property);
          expect(t.repeatCount.indefinite, repeat == 'infinite');
          if (repeat != 'infinite') expect(t.repeatCount.count, 2.5);
          _progress(r, property, const Duration(milliseconds: 2500), .5);
        });
      }

      for (final fill in ['none', 'forwards', 'backwards', 'both']) {
        test('填充 $fill 与结束后采样', () {
          final r = _compile(_frames(property), animation: 'a 1s linear $fill');
          final dynamic t = _track(r, property);
          final freeze = fill == 'forwards' || fill == 'both';
          expect(t.fillFreeze, freeze);
          if (freeze) {
            _progress(r, property, const Duration(seconds: 2), 1);
          } else {
            expect(t.sample(const Duration(seconds: 2)), isNull);
          }
        });
        test('零时长 $fill 规则', () {
          final r = _compile(
            _frames(property),
            animation: 'a 0s linear infinite $fill',
          );
          if (fill == 'forwards' || fill == 'both') {
            final dynamic t = _track(r, property);
            expect(t.repeatCount.indefinite, isFalse);
            expect(t.repeatCount.count, 1);
            _progress(r, property, Duration.zero, 1);
          } else {
            expect(
              r.skipped.single.reason,
              CssCompileSkipReason.zeroDurationWithoutForwards,
            );
          }
        });
      }

      for (final entry in {
        'paused': CssCompileSkipReason.paused,
        '0': CssCompileSkipReason.iterationCountZero,
      }.entries) {
        test('整条时序跳过 ${entry.key}', () {
          final r = _compile(_frames(property), animation: 'a 1s ${entry.key}');
          expect(r.skipped.single.reason, entry.value);
          expect(r.skipped.single.property, isNull);
        });
      }
    });
  }

  group('运动路径细节', () {
    for (final entry in <String?, String>{
      null: 'auto',
      'auto': 'auto',
      'reverse': 'auto-reverse',
      '0deg': '0',
      '45deg': '45',
      '12.5deg': '12.5',
      '100grad': '90',
      '${pi}rad': '180',
      '.25turn': '90',
      '0': '0',
      '-0deg': '0',
    }.entries) {
      test('旋转 ${entry.key} 转为 ${entry.value}', () {
        var calls = 0;
        final r = _compile(
          _frames(_motion),
          properties: {
            ..._motionProperties,
            if (entry.key != null) 'offset-rotate': entry.key!,
          },
          hooks: CssCompileHooks(
            sampleMotionPath: (path, rotate) {
              calls++;
              expect(path, 'M0 0 L100 0');
              expect(rotate, entry.value);
              return _samplePath(path, rotate);
            },
          ),
        );
        expect(calls, 1);
        expect(
          r.motion.single.interpolateAngle,
          entry.value == 'auto' || entry.value == 'auto-reverse',
        );
        expect(
          r.motion.single.sample(_half)!.angleDegrees,
          r.motion.single.interpolateAngle ? 45 : 0,
        );
      });
    }
    for (final rotate in [
      'auto 10deg',
      'reverse 20deg',
      'auto-reverse',
      '12px',
      '1',
      '1e308turn',
      'NaNdeg',
    ]) {
      test('不支持旋转 $rotate', () {
        _skip(
          _compile(
            _frames(_motion),
            properties: {..._motionProperties, 'offset-rotate': rotate},
          ),
          CssCompileSkipReason.unsupportedMotion,
          _motion,
        );
      });
    }
    test('缺路径、非 path 路径独立诊断', () {
      _skip(
        _compile(_frames(_motion), properties: const {}),
        CssCompileSkipReason.motionPathMissing,
        _motion,
      );
      for (final path in ['none', 'ray(45deg)', 'circle(10px)', 'path("")']) {
        _skip(
          _compile(_frames(_motion), properties: {'offset-path': path}),
          CssCompileSkipReason.unsupportedMotion,
          _motion,
        );
      }
    });
    test('px 距离被忽略，全无效返回 noValidValue', () {
      final r = _compile('${_frames(_motion)} 50% {$_motion:25px}');
      expect(r.motion.single.keyPoints, [0, 1]);
      _skip(
        _compile('from {$_motion:0px} to {$_motion:100px}'),
        CssCompileSkipReason.noValidValue,
        _motion,
      );
    });
    test('默认静态距离零，非法静态距离不能补端点', () {
      expect(_compile('50% {$_motion:50%}').motion.single.keyPoints, [
        0,
        .5,
        0,
      ]);
      _skip(
        _compile(
          '50% {$_motion:50%}',
          properties: {..._motionProperties, _motion: '2px'},
        ),
        CssCompileSkipReason.impliedEndpointUnavailable,
        _motion,
      );
    });
    test('没有钩子、钩子失败及采样表过短', () {
      for (final hooks in [
        const CssCompileHooks(),
        CssCompileHooks(sampleMotionPath: (_, _) => null),
        CssCompileHooks(sampleMotionPath: (_, _) => []),
        CssCompileHooks(
          sampleMotionPath: (_, _) => const [SmilMotionSample(0, 0, 0)],
        ),
      ]) {
        _skip(
          _compile(_frames(_motion), hooks: hooks),
          CssCompileSkipReason.hookUnavailable,
          _motion,
        );
      }
    });
    test('动画内路径与旋转声明不支持', () {
      final r = _compile(
        'from {offset-path:path("M0 0 L1 1");offset-rotate:auto}',
      );
      expect(r.skipped.map((s) => s.property), [
        'offset-path',
        'offset-rotate',
      ]);
      expect(
        r.skipped.every(
          (s) => s.reason == CssCompileSkipReason.unsupportedProperty,
        ),
        isTrue,
      );
    });
    test('超出路径的百分比保留，采样钳制', () {
      final r = _compile('from {$_motion:-50%} to {$_motion:150%}');
      expect(r.motion.single.keyPoints, [-.5, 1.5]);
      expect(r.motion.single.sample(const Duration(milliseconds: 1))!.x, 0);
      expect(r.motion.single.sample(const Duration(milliseconds: 999))!.x, 100);
    });
  });

  group('颜色细节', () {
    for (final prop in [_color, 'stroke', 'stop-color']) {
      test('$prop 混合颜色语法和 none 哨兵', () {
        final r = _compile(
          'from {$prop:#f80} 25% {$prop:#ff8800} '
          '50% {$prop:rgb(255,136,0)} 75% {$prop: NoNe } to {$prop:transparent}',
        );
        expect(r.color.single.attributeName, prop);
        expect(r.color.single.values, [
          0xffff8800,
          0xffff8800,
          0xffff8800,
          kSmilColorNone,
          0,
        ]);
      });
    }
    test('短长含 alpha 十六进制与 rgba', () {
      final r = _compile(
        'from {fill:#f008} 50% {fill:#ff000088} '
        'to {fill:rgba(255,0,0,0.5)}',
      );
      expect(r.color.single.values, [0x88ff0000, 0x88ff0000, 0x80ff0000]);
    });
    test('不猜继承，静态 none 可以补端点，静态 CSS 表不冒充 attributes', () {
      for (final attrs in [
        const <String, String>{},
        {_color: 'currentColor'},
        {_color: 'red'},
        {_color: 'url(#g)'},
      ]) {
        _skip(
          _compile(
            '50% {fill:#fff}',
            attributes: attrs,
            properties: const {_color: '#000'},
          ),
          CssCompileSkipReason.impliedEndpointUnavailable,
          _color,
        );
      }
      expect(
        _compile(
          '50% {fill:#fff}',
          attributes: const {_color: 'NONE'},
        ).color.single.values,
        [kSmilColorNone, _white, kSmilColorNone],
      );
    });
    test('具名、hsl、currentColor、url 均忽略', () {
      final r = _compile(
        '${_frames(_color)} 10% {fill:red} 20% {fill:hsl(0,0%,0%)} '
        '30% {fill:currentColor} 40% {fill:url(#g)}',
      );
      expect(r.color.single.values, [_black, _white]);
    });
    test('225 颜色到 none 平台再到颜色的翻转点', () {
      const orange = 0xffdd753d;
      final t = _compile(
        'from {fill:#dd753d} 25% {fill:none} '
        '75% {fill:none} to {fill:#dd753d}',
      ).color.single;
      for (final entry in {
        124: orange,
        125: kSmilColorNone,
        126: kSmilColorNone,
        500: kSmilColorNone,
        874: kSmilColorNone,
        875: orange,
        876: orange,
      }.entries) {
        expect(t.sample(Duration(milliseconds: entry.key)), entry.value);
      }
    });
    test('哨兵按缓动后的段进度翻转', () {
      final t = _compile(
        'from {fill:#dd753d} to {fill:none}',
        animation: 'a 1s steps(2,start)',
      ).color.single;
      expect(t.sample(const Duration(milliseconds: 1)), kSmilColorNone);
    });
  });

  group('路径细节', () {
    test('提取路径文本后传入构建钩子，静态 d 为裸路径', () {
      final r = _compile(
        '50% {d:path("M1 1 L2 2")}',
        attributes: const {_path: 'M0 0 L1 1'},
        hooks: CssCompileHooks(
          buildPathMorph: (frames) {
            expect(frames, ['M0 0 L1 1', 'M1 1 L2 2', 'M0 0 L1 1']);
            return _morph(frames);
          },
        ),
      );
      expect(r.paths.single.interpolates, isTrue);
      expect(r.paths.single.sample(_quarter), .5);
    });
    test('无钩子跳过，不兼容编译为离散且记近似', () {
      _skip(
        _compile(_frames(_path), hooks: const CssCompileHooks()),
        CssCompileSkipReason.hookUnavailable,
        _path,
      );
      final r = _compile(
        _frames(_path),
        hooks: CssCompileHooks(buildPathMorph: (_) => null),
      );
      expect(r.skipped, isEmpty);
      expect(r.paths.single.morph, isNull);
      expect(r.paths.single.calcMode, SmilCalcMode.discrete);
      expect(r.paths.single.sample(_half), 0);
      expect(r.approximations.single.animationName, 'a');
      expect(r.approximations.single.property, _path);
      expect(
        r.approximations.single.reason,
        CssCompileApproximationReason.pathIncompatibleDiscrete,
      );
    });
    test('路径缺少或空静态端点不猜测', () {
      for (final attrs in [
        const <String, String>{},
        {_path: '   '},
      ]) {
        _skip(
          _compile('50% {d:path("M0 0")}', attributes: attrs),
          CssCompileSkipReason.impliedEndpointUnavailable,
          _path,
        );
      }
    });
    test('单个首帧通过静态路径补成两帧', () {
      final r = _compile(
        'from {d:path("M0 0")}',
        attributes: const {_path: 'M1 1'},
      );
      expect(r.paths.single.frames, ['M0 0', 'M1 1']);
    });
  });

  group('列表细节', () {
    test('一项与两项补齐，中点为 15、25', () {
      final t = _compile(_frames(_list)).lists.single;
      expect(t.values, [
        [10, 10],
        [20, 40],
      ]);
      expect(t.sample(_half), [15, 25]);
    });
    test('三项和两项补为六项', () {
      final t = _compile('from {$_list:1 2 3} to {$_list:4px, 5px}')
          .lists
          .single;
      expect(t.values, [
        [1, 2, 3, 1, 2, 3],
        [4, 5, 4, 5, 4, 5],
      ]);
    });
    test('奇数列表不翻倍', () {
      final t = _compile('from {$_list:1 2 3} to {$_list:4 5 6}').lists.single;
      expect(t.width, 3);
    });
    test('静态端点长度也参与公共倍数，上限含 32', () {
      final r = _compile(
        '50% {$_list:1 2 3}',
        attributes: const {_list: '4 5'},
      );
      expect(r.lists.single.width, 6);
      final list32 = List.filled(32, '1').join(' ');
      expect(
        _compile('from {$_list:1} to {$_list:$list32}').lists.single.width,
        32,
      );
      for (final lengths in [
        [5, 7],
        [33, 1],
      ]) {
        final a = List.filled(lengths[0], '1').join(' ');
        final b = List.filled(lengths[1], '2').join(' ');
        _skip(
          _compile('from {$_list:$a} to {$_list:$b}'),
          CssCompileSkipReason.listTooLong,
          _list,
        );
      }
      _skip(
        _compile(
          '50% {$_list:1 2 3 4 5}',
          attributes: {_list: '1 2 3 4 5 6 7'},
        ),
        CssCompileSkipReason.listTooLong,
        _list,
      );
    });
    for (final value in [
      'none',
      '1em 2',
      '10%',
      '1,,2',
      ',1',
      '1,',
      'NaN',
      'Infinity',
      '1e999',
    ]) {
      test('非法列表 $value 整个 stop 忽略', () {
        final r = _compile('${_frames(_list)} 50% {$_list:$value}');
        expect(r.lists.single.keyTimes, [0, 1]);
      });
    }
    test('列表静态端点不可用', () {
      for (final attrs in [
        const <String, String>{},
        {_list: 'none'},
        {_list: '2em'},
      ]) {
        _skip(
          _compile('50% {$_list:2 4}', attributes: attrs),
          CssCompileSkipReason.impliedEndpointUnavailable,
          _list,
        );
      }
    });
  });

  test('同块共享 keyTimes 和逐段缓动，多个动画按列表顺序追加', () {
    final start = [for (final e in _values.entries) '${e.key}:${e.value[0]}']
        .join(';');
    final end = [for (final e in _values.entries) '${e.key}:${e.value[1]}']
        .join(';');
    final r = _compile(
      'from {$start} to {$end}',
      animation: 'a 1s ease-in, b 2s linear',
      extra: '@keyframes b {from {$start} to {$end}}',
    );
    expect(r.skipped, isEmpty);
    final first = r.motion.first;
    for (final dynamic t in [r.color.first, r.paths.first, r.lists.first]) {
      expect(identical(t.keyTimes, first.keyTimes), isTrue);
      expect(identical(t.keySplines, first.keySplines), isTrue);
    }
    for (final tracks in [r.motion, r.color, r.paths, r.lists]) {
      expect(tracks.map((t) => t.duration), [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    }
  });

  test('空结果新字段均为空且不产出 deferredProperty', () {
    const r = CssCompileResult.empty;
    expect(
      [
        r.motion,
        r.color,
        r.paths,
        r.lists,
        r.approximations,
      ].every((e) => e.isEmpty),
      isTrue,
    );
    expect(kCssDeferredProperties, isEmpty);
  });

  test('固定种子随机畸形 stop 字符串不抛异常', () {
    final random = Random(4205);
    const alphabet = 'abcXYZ0123456789#%(),.+- /\\\'";{}[]';
    for (var n = 0; n < 300; n++) {
      final value = String.fromCharCodes(
        List.generate(
          random.nextInt(60),
          (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ),
      );
      final frames = [
        for (final p in _values.keys)
          'from {$p:$value} 50% {$p:$value} to {$p:$value}',
      ].join(' ');
      expect(
        () => _compile(frames),
        returnsNormally,
        reason: '随机输入 $n: $value',
      );
    }
  });
}
