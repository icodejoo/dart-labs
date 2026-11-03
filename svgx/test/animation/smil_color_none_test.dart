import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';

/// 测试用的不透明红色。
const _red = 0xFFFF0000;

/// 测试用的不透明蓝色。
const _blue = 0xFF0000FF;

/// 单次迭代时长（毫秒），采样点按千分之一进度取整。
const _durationMs = 1000;

/// 构造两帧（或多帧）颜色动画，进度即毫秒数 / 1000。
SmilColorAnimation _color(
  List<int> values, {
  SmilCalcMode mode = SmilCalcMode.linear,
  List<SmilSegmentEasing>? splines,
  List<double>? keyTimes,
  SmilDirection direction = SmilDirection.normal,
  String attributeName = 'fill',
}) => SmilColorAnimation(
  values: values,
  duration: const Duration(milliseconds: _durationMs),
  begin: Duration.zero,
  fillFreeze: true,
  calcMode: mode,
  keySplines: splines,
  keyTimes: keyTimes,
  direction: direction,
  attributeName: attributeName,
);

/// 取千分之 [permille] 进度处的颜色。
int? _at(SmilColorAnimation a, int permille) =>
    a.sample(Duration(milliseconds: permille));

/// 验证颜色与 `none` 哨兵之间的离散翻转规则。
void main() {
  test('哨兵常量位于颜色值域之外', () {
    expect(kSmilColorNone, -1);
    expect(kSmilColorNone, lessThan(0));
  });

  test('attributeName 默认 stop-color，可覆盖', () {
    expect(
      SmilColorAnimation(
        values: const [_red, _blue],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: false,
      ).attributeName,
      'stop-color',
    );
    expect(_color(const [_red, _blue]).attributeName, 'fill');
  });

  group('线性缓动下的翻转点', () {
    // (值, 进度千分比, 期望)
    final cases = <(String, List<int>, int, int)>[
      ('color→none 0.49', [_red, kSmilColorNone], 490, _red),
      ('color→none 0.50', [_red, kSmilColorNone], 500, kSmilColorNone),
      ('color→none 0.51', [_red, kSmilColorNone], 510, kSmilColorNone),
      ('none→color 0.49', [kSmilColorNone, _blue], 490, kSmilColorNone),
      ('none→color 0.50', [kSmilColorNone, _blue], 500, _blue),
      ('none→color 0.51', [kSmilColorNone, _blue], 510, _blue),
      ('none→none 0.49', [kSmilColorNone, kSmilColorNone], 490, kSmilColorNone),
      ('none→none 0.50', [kSmilColorNone, kSmilColorNone], 500, kSmilColorNone),
      ('none→none 0.51', [kSmilColorNone, kSmilColorNone], 510, kSmilColorNone),
    ];
    for (final (name, values, permille, expected) in cases) {
      test(name, () => expect(_at(_color(values), permille), expected));
    }

    test('起点与定格终点', () {
      expect(_at(_color([_red, kSmilColorNone]), 0), _red);
      expect(_at(_color([_red, kSmilColorNone]), 5000), kSmilColorNone);
      expect(_at(_color([kSmilColorNone, _blue]), 0), kSmilColorNone);
      expect(_at(_color([kSmilColorNone, _blue]), 5000), _blue);
    });
  });

  test('缓动后进度决定翻转：回弹曲线提前翻转', () {
    // ease-out-back 风格曲线在 20% 处缓动后已超过 0.5。
    const bounce = CubicBezier(0.175, 0.885, 0.32, 1.275);
    final a = _color(
      const [_red, kSmilColorNone],
      mode: SmilCalcMode.spline,
      splines: const [bounce],
    );
    final linear = _color(const [_red, kSmilColorNone]);
    expect(bounce.transform(0.2), greaterThan(0.5));
    expect(_at(a, 200), kSmilColorNone);
    expect(_at(linear, 200), _red);
    // 极早的时刻缓动后进度仍小于 0.5。
    expect(bounce.transform(0.01), lessThan(0.5));
    expect(_at(a, 10), _red);
  });

  test('缓动后进度延后翻转：ease-in 在 0.5 处仍未翻', () {
    const easeIn = CubicBezier(0.42, 0, 1, 1);
    final a = _color(
      const [_red, kSmilColorNone],
      mode: SmilCalcMode.spline,
      splines: const [easeIn],
    );
    expect(easeIn.transform(0.5), lessThan(0.5));
    expect(_at(a, 500), _red);
    expect(_at(a, 800), kSmilColorNone);
  });

  group('discrete 模式', () {
    test('值表可含哨兵，直接取段起点值', () {
      final a = _color(const [
        _red,
        kSmilColorNone,
        _blue,
      ], mode: SmilCalcMode.discrete);
      expect(_at(a, 100), _red);
      expect(_at(a, 400), _red);
      expect(_at(a, 600), kSmilColorNone);
      expect(_at(a, 900), kSmilColorNone);
    });

    test('keyTimes 控制切换点', () {
      final a = _color(
        const [kSmilColorNone, _blue, kSmilColorNone, _red],
        mode: SmilCalcMode.discrete,
        keyTimes: const [0, 0.2, 0.6, 1],
      );
      expect(_at(a, 100), kSmilColorNone);
      expect(_at(a, 300), _blue);
      expect(_at(a, 700), kSmilColorNone);
    });
  });

  group('与阶跃缓动组合', () {
    test('steps(2, end)：输出 0 与 0.5，0.5 处翻转', () {
      final a = _color(
        const [_red, kSmilColorNone],
        mode: SmilCalcMode.spline,
        splines: const [SmilStepsEasing(2)],
      );
      // 前半段阶跃输出 0，后半段输出 0.5，>= 0.5 即翻转。
      expect(_at(a, 400), _red);
      expect(_at(a, 600), kSmilColorNone);
    });

    test('steps(2, start)：整段输出 0.5 与 1，开头即翻转', () {
      final a = _color(
        const [_red, kSmilColorNone],
        mode: SmilCalcMode.spline,
        splines: const [SmilStepsEasing(2, SmilStepPosition.start)],
      );
      expect(_at(a, 100), kSmilColorNone);
      expect(_at(a, 900), kSmilColorNone);
    });

    test('steps(3, end)：输出 0、1/3、2/3，只在 1/3 到 2/3 之间越过 0.5', () {
      final a = _color(
        const [_red, kSmilColorNone],
        mode: SmilCalcMode.spline,
        splines: const [SmilStepsEasing(3)],
      );
      expect(_at(a, 200), _red);
      expect(_at(a, 400), _red); // 输出 1/3，仍小于 0.5
      expect(_at(a, 700), kSmilColorNone); // 输出 2/3
    });
  });

  test('多段：color→none→color 各段独立判定', () {
    final a = _color(const [_red, kSmilColorNone, _blue]);
    // 第一段 0..0.5：翻转点在 0.25；第二段 0.5..1：翻转点在 0.75。
    expect(_at(a, 240), _red);
    expect(_at(a, 260), kSmilColorNone);
    expect(_at(a, 740), kSmilColorNone);
    expect(_at(a, 760), _blue);
  });

  test('direction 反向时按有向进度翻转', () {
    final a = _color(const [
      _red,
      kSmilColorNone,
    ], direction: SmilDirection.reverse);
    // 反向后有向进度 = 1 - p：p=0.2 对应 0.8，已翻。
    expect(_at(a, 200), kSmilColorNone);
    expect(_at(a, 800), _red);
  });

  test('不含哨兵时仍是逐通道插值', () {
    final a = _color(const [0xFF000000, 0xFFFFFFFF]);
    expect(_at(a, 500), 0xFF808080);
  });
}
