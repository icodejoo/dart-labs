import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_animation_values.dart';
import 'package:svgx/src/animation/css_keyframes_compiler.dart';
import 'package:svgx/src/animation/css_stylesheet.dart';
import 'package:svgx/src/animation/smil_animation.dart';

/// 通用数值关键帧，供时间映射测试复用。
const _numericFrames = 'from { opacity: 0 } to { opacity: 10 }';

/// 通用变换关键帧，供时间映射测试复用。
const _transformFrames =
    'from { transform: translate(0px, 0px) } '
    'to { transform: translate(10px, 20px) }';

/// 默认动画声明，避免测试依赖 CSS 默认缓动。
const _defaultAnimation = 'a 1s linear';

/// 常用采样误差上限。
const _tolerance = 1e-5;

/// 从真实解析入口编译单个或多个动画。
CssCompileResult _compile(
  String frames, {
  String animation = _defaultAnimation,
  Map<String, String> attributes = const {},
  Map<String, String> cssProperties = const {},
  String extra = '',
}) => compileCssAnimations(
  animations: parseCssAnimations(parseCssDeclarations('animation: $animation')),
  keyframes: parseCssStylesheet('@keyframes a {$frames} $extra').keyframes,
  attributes: attributes,
  cssProperties: cssProperties,
);

/// 在毫秒时刻采样数值轨道。
double? _sample(SmilAnimation track, int milliseconds) =>
    track.sample(Duration(milliseconds: milliseconds));

/// 断言恰好一个属性被诊断，且其他属性仍可编译。
void _expectSkip(
  CssCompileResult result,
  CssCompileSkipReason reason, [
  String? property,
]) {
  expect(result.skipped, hasLength(1));
  expect(result.skipped.single.animationName, 'a');
  expect(result.skipped.single.reason, reason);
  expect(result.skipped.single.property, property);
}

/// 验证编译产物、错误隔离及与引擎采样的一致性。
void main() {
  group('缓动', () {
    test('全线性与对角线贝塞尔均不分配样条', () {
      for (final timing in ['linear', 'cubic-bezier(.2,.2,.8,.8)']) {
        final r = _compile(_numericFrames, animation: 'a 1s $timing');
        expect(r.numeric.single.calcMode, SmilCalcMode.linear);
        expect(r.numeric.single.keySplines, isNull);
        expect(r.numeric.single.keyTimes, [0, 1]);
        expect(identical(r.skipped, const <CssCompileSkip>[]), isTrue);
      }
    });

    test('混合缓动逐段编译并回退全局缓动，末点缓动不参与', () {
      final track = _compile('''
        from { opacity: 0; animation-timing-function: linear }
        20% { opacity: 2; animation-timing-function: cubic-bezier(.3,.1,.7,.9) }
        60% { opacity: 6 }
        to { opacity: 10; animation-timing-function: step-start }
      ''', animation: 'a 1s steps(3,end)').numeric.single;
      expect(track.keyTimes, [0, .2, .6, 1]);
      expect(track.calcMode, SmilCalcMode.spline);
      final curves = track.keySplines!;
      expect(curves, hasLength(3));
      final linear = curves[0] as CubicBezier;
      expect([linear.x1, linear.y1, linear.x2, linear.y2], [0, 0, 1, 1]);
      final cubic = curves[1] as CubicBezier;
      expect([cubic.x1, cubic.y1, cubic.x2, cubic.y2], [.3, .1, .7, .9]);
      expect((curves[2] as SmilStepsEasing).count, 3);
    });

    test('最后一个合法缓动适用于同点全部属性，非法与重要缓动被忽略', () {
      final r = _compile('''
        from {
          opacity: 0; stroke-width: 1;
          animation-timing-function: ease-in;
          animation-timing-function: steps(2,start);
          animation-timing-function: bad;
          animation-timing-function: linear !important;
        }
        to { opacity: 1; stroke-width: 2 }
      ''');
      for (final track in r.numeric) {
        final easing = track.keySplines!.single as SmilStepsEasing;
        expect(easing.count, 2);
        expect(easing.position, SmilStepPosition.start);
      }
    });

    test('只有末个点包含非线性缓动仍为线性', () {
      final track = _compile('''
        from { opacity: 0 }
        to { opacity: 1; animation-timing-function: ease }
      ''').numeric.single;
      expect(track.keySplines, isNull);
    });

    final cases = <String, (int, SmilStepPosition)>{
      'step-end': (1, SmilStepPosition.end),
      'step-start': (1, SmilStepPosition.start),
      'steps(3,end)': (3, SmilStepPosition.end),
      'steps(2,start)': (2, SmilStepPosition.start),
      'steps(4,jump-none)': (4, SmilStepPosition.jumpNone),
      'steps(3,jump-both)': (3, SmilStepPosition.jumpBoth),
      'steps(2,jump-start)': (2, SmilStepPosition.start),
      'steps(2,jump-end)': (2, SmilStepPosition.end),
    };
    for (final entry in cases.entries) {
      test('阶跃映射 ${entry.key}', () {
        final track = _compile(
          _numericFrames,
          animation: 'a 1s ${entry.key}',
        ).numeric.single;
        final easing = track.keySplines!.single as SmilStepsEasing;
        expect(easing.count, entry.value.$1);
        expect(easing.position, entry.value.$2);
      });
    }
  });

  group('时间', () {
    for (final delay in [250, -250]) {
      test('delay=$delay 同时保存在 begin 与 beginSpec，解析后不变', () {
        final r = _compile(
          '$_numericFrames $_transformFrames',
          animation: 'a 1s linear ${delay}ms',
        );
        final all = <SmilTimed>[...r.numeric, ...r.transforms];
        expect(all, hasLength(2));
        for (final track in all) {
          expect(track.begin, Duration(milliseconds: delay));
          expect(track.beginSpec.offset, track.begin);
          expect(track.beginSpec.syncbaseId, isNull);
          expect(track.elementId, isNull);
        }
        resolveSmilBeginTimes(all);
        for (final track in all) {
          expect(track.begin, Duration(milliseconds: delay));
        }
        expect(_sample(r.numeric.single, 0), delay > 0 ? isNull : 2.5);
      });
    }

    for (final count in ['infinite', '1', '3', '2.5']) {
      test('迭代次数 $count 原样映射', () {
        final r = _compile(
          '$_numericFrames $_transformFrames',
          animation: 'a 1s linear $count forwards',
        );
        for (final track in <SmilTimed>[...r.numeric, ...r.transforms]) {
          expect(track.duration, const Duration(seconds: 1));
          expect(track.repeatCount.indefinite, count == 'infinite');
          if (count != 'infinite') {
            expect(track.repeatCount.count, double.parse(count));
          }
        }
        if (count == '2.5') expect(_sample(r.numeric.single, 2601), 5);
      });
    }

    test('零次与暂停整条跳过', () {
      _expectSkip(
        _compile(_numericFrames, animation: 'a 1s 0 forwards'),
        CssCompileSkipReason.iterationCountZero,
      );
      _expectSkip(
        _compile(_numericFrames, animation: 'a 1s paused'),
        CssCompileSkipReason.paused,
      );
    });

    for (final fill in ['none', 'forwards', 'backwards', 'both']) {
      test('填充方式 $fill 仅处理结束后冻结', () {
        final r = _compile(
          '$_numericFrames $_transformFrames',
          animation: 'a 1s linear 200ms $fill',
        );
        final freeze = fill == 'forwards' || fill == 'both';
        expect(r.numeric.single.fillFreeze, freeze);
        expect(r.transforms.single.fillFreeze, freeze);
        expect(_sample(r.numeric.single, 199), isNull);
        expect(
          r.transforms.single.sample(const Duration(milliseconds: 199)),
          isNull,
        );
        expect(_sample(r.numeric.single, 1201), freeze ? 10 : isNull);
        expect(
          r.transforms.single.sample(const Duration(milliseconds: 1201)),
          freeze ? [10, 20, 0] : isNull,
        );
      });

      test('零时长 $fill，保留时强制一次且有限', () {
        final r = _compile(
          '$_numericFrames $_transformFrames',
          animation: 'a 0s linear infinite $fill',
        );
        if (fill == 'forwards' || fill == 'both') {
          for (final track in <SmilTimed>[...r.numeric, ...r.transforms]) {
            expect(track.repeatCount.indefinite, isFalse);
            expect(track.repeatCount.count, 1);
          }
          expect(_sample(r.numeric.single, 1), 10);
        } else {
          _expectSkip(r, CssCompileSkipReason.zeroDurationWithoutForwards);
          expect(r.numeric, isEmpty);
          expect(r.transforms, isEmpty);
        }
      });
    }

    final directions = <String, SmilDirection>{
      'normal': SmilDirection.normal,
      'reverse': SmilDirection.reverse,
      'alternate': SmilDirection.alternate,
      'alternate-reverse': SmilDirection.alternateReverse,
    };
    for (final entry in directions.entries) {
      test('方向 ${entry.key} 同时应用于数值和变换', () {
        final r = _compile(
          '$_numericFrames $_transformFrames',
          animation: 'a 1s linear 3 ${entry.key}',
        );
        expect(r.numeric.single.direction, entry.value);
        expect(r.transforms.single.direction, entry.value);
        final reversed = entry.key == 'reverse' || entry.key == 'alternate';
        final expected = reversed ? 7.49 : 2.51;
        expect(_sample(r.numeric.single, 1251), closeTo(expected, _tolerance));
        expect(
          r.transforms.single.sample(const Duration(milliseconds: 1251))![0],
          closeTo(expected, _tolerance),
        );
      });
    }
  });

  group('数值与隐式端点', () {
    test('rx/ry 多属性块共用时间点和区间缓动', () {
      final r = _compile('''
        from {rx: 2px; ry: 3px}
        40% {rx: 4px; ry: 5px; animation-timing-function: steps(2,end)}
        to {rx: 8px; ry: 9px}
      ''', animation: 'a 1s ease-in');
      final x = r.numeric[0], y = r.numeric[1];
      expect(x.values, [2, 4, 8]);
      expect(y.values, [3, 5, 9]);
      expect(identical(x.keyTimes, y.keyTimes), isTrue);
      expect(identical(x.keySplines, y.keySplines), isTrue);
    });

    test('全部白名单可编译，px 去单位，输入静态表不变', () {
      const properties = [
        'opacity',
        'fill-opacity',
        'stroke-opacity',
        'stroke-width',
        'stroke-dashoffset',
        'rx',
        'ry',
        'r',
        'cx',
        'cy',
        'x',
        'y',
        'width',
        'height',
      ];
      final start = [for (final p in properties) '$p: 2px'].join(';');
      final end = [for (final p in properties) '$p: 8px'].join(';');
      final attrs = {'width': '4px'};
      final r = _compile('from {$start} to {$end}', attributes: attrs);
      expect(r.numeric.map((t) => t.attributeName), properties);
      for (final track in r.numeric) {
        expect(track.values, [2, 8]);
      }
      expect(attrs, {'width': '4px'});
    });

    test('百分比和其他单位被视为未写，保留合法 stop 的缓动', () {
      final track = _compile('''
        from { opacity: 0 }
        20% { opacity: 30%; animation-timing-function: step-start }
        40% { opacity: 3em }
        60% { opacity: 6; animation-timing-function: ease-in }
        to { opacity: 10 }
      ''').numeric.single;
      expect(track.keyTimes, [0, .6, 1]);
      expect(track.values, [0, 6, 10]);
      expect(track.keySplines, hasLength(2));
      expect(track.keySplines!.first, isA<CubicBezier>());
      expect((track.keySplines!.last as CubicBezier).x1, .42);
    });

    test('同点后写覆盖，重要声明与控制声明忽略', () {
      final r = _compile('''
        from { opacity: 2; opacity: 3; opacity: 8 !important;
          transform: scale(3) !important; animation-name: ignored;
          animation: ignored; transition: opacity 1s; transition-duration: 2s }
        to { opacity: 9; fill: red !important }
      ''');
      expect(r.numeric.single.values, [3, 9]);
      expect(r.skipped, isEmpty);
      expect(r.transforms, isEmpty);
    });

    test('所有 stop 无效时诊断，其他属性继续', () {
      final r = _compile('''
        from { opacity: 0%; width: 2px }
        to { opacity: 2em; width: 4px }
      ''');
      _expectSkip(r, CssCompileSkipReason.noValidValue, 'opacity');
      expect(r.numeric.single.attributeName, 'width');
    });

    for (final missing in ['start', 'end', 'both']) {
      test('缺端点 $missing 使用静态值，补点缓动回退全局', () {
        final frames = switch (missing) {
          'start' => '50% {opacity: 5} to {opacity: 10}',
          'end' => 'from {opacity: 0} 50% {opacity: 5}',
          _ => '50% {opacity: 5}',
        };
        final track = _compile(
          frames,
          animation: 'a 1s ease-in',
          attributes: const {'opacity': '2px'},
        ).numeric.single;
        expect(track.keyTimes, [0, .5, 1]);
        expect(track.values, switch (missing) {
          'start' => [2, 5, 10],
          'end' => [0, 5, 2],
          _ => [2, 5, 2],
        });
        expect(track.keySplines, hasLength(2));
        expect((track.keySplines!.first as CubicBezier).x1, .42);
      });
    }

    test('属性按自己的 stop 序列插值，忽略其他属性位置', () {
      final r = _compile('''
        from {opacity: 0; width: 2}
        30% {width: 5}
        70% {opacity: 7}
        to {opacity: 10; width: 9}
      ''');
      expect(r.numeric[0].keyTimes, [0, .7, 1]);
      expect(r.numeric[1].keyTimes, [0, .3, 1]);
      expect(_sample(r.numeric[0], 301), closeTo(3.01, _tolerance));
    });

    const defaults = {
      'opacity': 1.0,
      'fill-opacity': 1.0,
      'stroke-opacity': 1.0,
      'stroke-width': 1.0,
      'stroke-dashoffset': 0.0,
    };
    for (final entry in defaults.entries) {
      test('${entry.key} 缺端点使用默认值', () {
        final r = _compile('50% {${entry.key}: 5}');
        expect(r.numeric.single.values, [entry.value, 5, entry.value]);
      });
    }

    for (final property in [
      'rx',
      'ry',
      'r',
      'cx',
      'cy',
      'x',
      'y',
      'width',
      'height',
    ]) {
      test('$property 无默认值则跳过，提供静态值则补齐', () {
        final frames = '50% {$property: 5}';
        _expectSkip(
          _compile(frames),
          CssCompileSkipReason.impliedEndpointUnavailable,
          property,
        );
        expect(
          _compile(frames, attributes: {property: '3px'}).numeric.single.values,
          [3, 5, 3],
        );
      });
    }

    test('仅在首点或末点出现也能补成两个值', () {
      for (final point in ['from', 'to']) {
        final track = _compile('$point {opacity: 4}').numeric.single;
        expect(track.keyTimes, [0, 1]);
        expect(track.values, point == 'from' ? [4, 1] : [1, 4]);
      }
    });
  });

  group('变换', () {
    test('多槽位布局、函数顺序和共享时间缓动', () {
      final r = _compile('''
        from {transform: translate(2px,3px) scale(2,4) rotate(0deg) skewX(5deg) skewY(6deg)}
        30% {transform: translate(8px,9px) scale(3,5) rotate(216deg) skewX(8deg) skewY(9deg)}
        to {transform: translate(12px,13px) scale(4,6) rotate(720deg) skewX(15deg) skewY(16deg)}
      ''', animation: 'a 1s ease-in');
      expect(r.transforms.map((t) => t.type), SmilTransformType.values);
      expect(r.transforms[0].values.first, [2, 3, 0]);
      expect(r.transforms[1].values.first, [2, 4, 0]);
      expect(r.transforms[2].values.last, [720, 0, 0]);
      expect(r.transforms[3].values.first, [5, 0, 0]);
      expect(r.transforms[4].values.last, [16, 0, 0]);
      for (final track in r.transforms) {
        expect(track.replacesStaticTransform, isTrue);
        expect(track.keyTimes, [0, .3, 1]);
        expect(identical(track.keyTimes, r.transforms.first.keyTimes), isTrue);
        expect(
          identical(track.keySplines, r.transforms.first.keySplines),
          isTrue,
        );
        expect(track.keySplines, hasLength(2));
        expect(track.calcMode, SmilCalcMode.spline);
      }
      expect(r.skipped, isEmpty);
    });

    test('rotate 保留圈数，0 到 720 中点为 360', () {
      final track = _compile('''
        from {transform: rotate(0deg)} to {transform: rotate(720deg)}
      ''').transforms.single;
      expect(track.sample(const Duration(milliseconds: 500)), [360, 0, 0]);
    });

    final bad = <String, CssCompileSkipReason>{
      'from {transform: scale(2)} to {transform: rotate(3deg)}':
          CssCompileSkipReason.transformSignatureMismatch,
      'from {transform: scale(2)} to {transform: scale(3) rotate(3deg)}':
          CssCompileSkipReason.transformSignatureMismatch,
      'from {transform: rotate(0deg) scale(1)} to {transform: scale(2) rotate(3deg)}':
          CssCompileSkipReason.transformSignatureMismatch,
      'from {transform: matrix(1,0,0,1,2,3)} to {transform: scale(2)}':
          CssCompileSkipReason.transformUnsupportedFunction,
      'from {transform: skew(2deg,3deg)} to {transform: scale(2)}':
          CssCompileSkipReason.transformUnsupportedFunction,
      'from {transform: none} to {transform: none}':
          CssCompileSkipReason.transformAllNone,
      'from {transform: translate(2em)} to {transform: bad}':
          CssCompileSkipReason.noValidValue,
    };
    var index = 0;
    for (final entry in bad.entries) {
      test('非法变换 ${index++} 只隔离变换属性', () {
        final r = _compile('${entry.key} $_numericFrames');
        _expectSkip(r, entry.value, 'transform');
        expect(r.transforms, isEmpty);
        expect(r.numeric, hasLength(1));
      });
    }

    test('none 补为签名同形的单位变换', () {
      final r = _compile('''
        from {transform: none}
        to {transform: translate(4px,6px) scale(3,5) rotate(720deg) skewX(8deg) skewY(10deg)}
      ''');
      expect(r.transforms.map((t) => t.values.first), [
        [0, 0, 0],
        [1, 1, 0],
        [0, 0, 0],
        [0, 0, 0],
        [0, 0, 0],
      ]);
      expect(r.transforms[1].sample(const Duration(milliseconds: 500)), [
        2,
        3,
        0,
      ]);
    });

    test('无静态变换时，隐式首尾都用单位变换', () {
      final track = _compile('50% {transform: scale(4,6)}').transforms.single;
      expect(track.keyTimes, [0, .5, 1]);
      expect(track.values, [
        [1, 1, 0],
        [4, 6, 0],
        [1, 1, 0],
      ]);
    });

    test('只有 SVG 静态变换时缺端点必须跳过', () {
      _expectSkip(
        _compile(
          '50% {transform: translate(4px,6px)}',
          attributes: const {'transform': 'translate(2 3)'},
        ),
        CssCompileSkipReason.impliedEndpointUnavailable,
        'transform',
      );
    });

    test('CSS 静态变换优先，补齐首尾且不借用首个动画值', () {
      final props = {'transform': 'translate(2px,3px)'};
      final track = _compile(
        '50% {transform: translate(4px,6px)}',
        attributes: const {'transform': 'translate(9 10)'},
        cssProperties: props,
      ).transforms.single;
      expect(track.values, [
        [2, 3, 0],
        [4, 6, 0],
        [2, 3, 0],
      ]);
      expect(props, {'transform': 'translate(2px,3px)'});
    });

    test('CSS 静态 none 覆盖 SVG 静态值并扩展为单位变换', () {
      final track = _compile(
        '50% {transform: scale(3)}',
        attributes: const {'transform': 'scale(9)'},
        cssProperties: const {'transform': 'none'},
      ).transforms.single;
      expect(track.values, [
        [1, 1, 0],
        [3, 3, 0],
        [1, 1, 0],
      ]);
    });

    for (final base in ['bad', 'rotate(5deg)', 'matrix(1,0,0,1,0,0)']) {
      test('无法逐函数插值的静态 CSS 基准 $base 安静跳过', () {
        _expectSkip(
          _compile(
            '50% {transform: scale(3)}',
            cssProperties: {'transform': base},
          ),
          CssCompileSkipReason.impliedEndpointUnavailable,
          'transform',
        );
      });
    }

    test('端点完整不需要解析静态基准，非法中间 stop 视为未写', () {
      final track = _compile(
        '''
        $_transformFrames 30% {transform: translate(3em)}
      ''',
        attributes: const {'transform': 'translate(9 10)'},
      ).transforms.single;
      expect(track.keyTimes, [0, 1]);
    });
  });

  group('多动画与诊断', () {
    test('数值按列表顺序保留，不同属性独立', () {
      final r = _compile(
        _numericFrames,
        animation: 'a 1s linear, b 2s linear, c 3s linear',
        extra: '''
            @keyframes b {from {width: 2} to {width: 4}}
            @keyframes c {from {opacity: 5} to {opacity: 8}}
          ''',
      );
      expect(r.numeric.map((t) => t.attributeName), [
        'opacity',
        'width',
        'opacity',
      ]);
      expect(r.numeric.map((t) => t.values), [
        [0, 10],
        [2, 4],
        [5, 8],
      ]);
      expect(r.skipped, isEmpty);
    });

    test('仅保留最后一个关键帧含变换的动画，早先数值仍编译', () {
      final r = _compile(
        '$_numericFrames $_transformFrames',
        animation: 'a 1s, b 2s',
        extra: '''
            @keyframes b {from {transform: scale(2)} to {transform: scale(4)}}
          ''',
      );
      _expectSkip(
        r,
        CssCompileSkipReason.overriddenByLaterAnimation,
        'transform',
      );
      expect(r.numeric, hasLength(1));
      expect(r.transforms.single.type, SmilTransformType.scale);
    });

    test('最后含变换动画即使暂停也覆盖前者，不回退早先轨道', () {
      final r = _compile(
        _transformFrames,
        animation: 'a 1s, b 2s paused',
        extra: '''
            @keyframes b {from {transform: scale(2)} to {transform: scale(4)}}
          ''',
      );
      expect(r.transforms, isEmpty);
      expect(r.skipped.map((s) => s.reason), [
        CssCompileSkipReason.overriddenByLaterAnimation,
        CssCompileSkipReason.paused,
      ]);
    });

    test('只有重要变换声明的后者不覆盖前者', () {
      final r = _compile(
        _transformFrames,
        animation: 'a 1s, b 2s',
        extra: '''
            @keyframes b {to {transform: scale(4) !important}}
          ''',
      );
      expect(r.transforms.single.type, SmilTransformType.translate);
      expect(r.skipped, isEmpty);
    });

    test('未知关键帧安静跳过且不影响其他动画', () {
      final r = _compile(_numericFrames, animation: 'missing 1s, a 1s');
      expect(r.skipped.single.animationName, 'missing');
      expect(r.skipped.single.reason, CssCompileSkipReason.unknownKeyframes);
      expect(r.skipped.single.property, isNull);
      expect(r.numeric, hasLength(1));
    });

    test('全部后续属性及未知属性有独立诊断，控制声明不诊断', () {
      final r = _compile(
        'from {fill:#000; stroke:#000; stop-color:#000; '
        'offset-distance:0%; d:path("M0 0"); stroke-dasharray:10; '
        'offset-path:path("M0 0"); offset-rotate:auto; visibility:hidden; '
        'animation-name:b; transition-delay:1s} '
        'to {fill:#fff; stroke:#fff; stop-color:#fff; '
        'offset-distance:100%; d:path("M1 1"); stroke-dasharray:20}',
        cssProperties: const {'offset-path': 'path("M0 0 L1 1")'},
      );
      expect(kCssDeferredProperties, isEmpty);
      expect(r.color.map((t) => t.attributeName), [
        'fill',
        'stroke',
        'stop-color',
      ]);
      expect(r.lists.single.values, [
        [10],
        [20],
      ]);
      expect(r.skipped.map((s) => s.property), [
        'offset-distance',
        'd',
        'offset-path',
        'offset-rotate',
        'visibility',
      ]);
      expect(r.skipped.map((s) => s.reason), [
        CssCompileSkipReason.hookUnavailable,
        CssCompileSkipReason.hookUnavailable,
        CssCompileSkipReason.unsupportedProperty,
        CssCompileSkipReason.unsupportedProperty,
        CssCompileSkipReason.unsupportedProperty,
      ]);
    });

    test('空动画返回共享结果', () {
      expect(
        identical(
          compileCssAnimations(animations: const [], keyframes: const {}),
          CssCompileResult.empty,
        ),
        isTrue,
      );
    });
  });

  group('按 CSS 语义手算采样', () {
    test('对称贝塞尔中点及其两侧，数值与变换一致', () {
      final r = _compile(
        '$_numericFrames $_transformFrames',
        animation: 'a 1s cubic-bezier(.42,0,.58,1)',
      );
      expect(_sample(r.numeric.single, 500), closeTo(5, _tolerance));
      expect(
        _sample(r.numeric.single, 499)! + _sample(r.numeric.single, 501)!,
        closeTo(10, _tolerance),
      );
      expect(r.transforms.single.sample(const Duration(milliseconds: 500)), [
        5,
        10,
        0,
      ]);
    });

    test('非线性区间保留超出单位范围的缓动值', () {
      final r = _compile(
        _numericFrames,
        animation: 'a 1s cubic-bezier(.25,2,.75,2)',
      );
      // 参数中点的 x=.5，y=1.625。
      expect(_sample(r.numeric.single, 500), closeTo(16.25, _tolerance));
    });

    test('steps 在跳变点两侧与手算值一致', () {
      final track = _compile(
        _numericFrames,
        animation: 'a 1s steps(4,end)',
      ).numeric.single;
      expect(_sample(track, 249), 0);
      expect(_sample(track, 251), 2.5);
      expect(_sample(track, 749), 5);
      expect(_sample(track, 751), 7.5);
    });

    test('alternate 反向时也反向采样原始非线性缓动', () {
      final r = _compile(
        '$_numericFrames $_transformFrames',
        animation: 'a 1s cubic-bezier(0,0,1,0) 3 alternate',
      );
      // x(.5)=.5、y(.5)=.125，第二轮中点仍得 1.25。
      expect(_sample(r.numeric.single, 1500), closeTo(1.25, _tolerance));
      expect(
        r.transforms.single.sample(const Duration(milliseconds: 1500))![0],
        closeTo(1.25, _tolerance),
      );
      expect(_sample(r.numeric.single, 1249), _sample(r.numeric.single, 751));
    });

    test('逐段缓动在关键帧两侧切换而不使用末点缓动', () {
      final track = _compile('''
        from {opacity: 0; animation-timing-function: linear}
        50% {opacity: 5; animation-timing-function: steps(2,end)}
        to {opacity: 10; animation-timing-function: step-start}
      ''').numeric.single;
      expect(_sample(track, 499), closeTo(4.99, _tolerance));
      expect(_sample(track, 501), 5);
      expect(_sample(track, 751), 7.5);
    });
  });

  group('畸形输入不抛异常', () {
    for (final value in [
      'NaN',
      'Infinity',
      '-Infinity',
      '1e999',
      '1e300',
      '-1e300',
    ]) {
      test('数值与变换字符串 $value', () {
        late CssCompileResult r;
        expect(
          () => r = _compile('''
          from {opacity: $value; transform: translate(${value}px)}
          to {opacity: 1; transform: translate(2px)}
        '''),
          returnsNormally,
        );
        expect(r.numeric.single.values.every((v) => v.isFinite), isTrue);
        expect(
          r.transforms.single.values.expand((v) => v).every((v) => v.isFinite),
          isTrue,
        );
      });
    }

    test('空 stop 集合无产物，单 stop 自动补端点', () {
      final empty = _compile('');
      expect(empty.numeric, isEmpty);
      expect(empty.transforms, isEmpty);
      expect(empty.skipped, isEmpty);
      expect(
        () => _compile('50% {opacity: 2; transform: scale(3)}'),
        returnsNormally,
      );
      expect(_compile('50% {opacity: 2}').numeric.single.keyTimes, [0, .5, 1]);
    });
  });
}
